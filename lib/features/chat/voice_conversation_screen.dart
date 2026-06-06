import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/api/audio_api.dart';
import '../../core/api/chat_api.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';

/// Voice Conversation Mode — full-screen, continuous voice loop.
///
/// State machine:
///   idle → listening → transcribing → thinking → speaking → listening
///
/// VAD (Voice Activity Detection):
///   - Amplitude stream từ record package
///   - Buffer rolling 1.5s, nếu avg amplitude < threshold → silence detected
///   - threshold = -30dB (record package trả dBFS, 0=loud, -∞=silent)
///
/// Reuse infrastructure đã có:
///   - VoiceRecorder (record audio)
///   - AudioApi.speechToTextFromBytes / speechToText (Whisper STT)
///   - ChatApi.sendStream (LLM streaming với contract enforcement)
///   - AudioApi.textToSpeech (gTTS)
///   - AudioPlayerService (play TTS bytes)
///
/// Defense angle (Chương 4):
///   "Contract enforcement vẫn áp dụng trong voice mode. User nói off-scope
///   query qua mic → AI refuse bằng GIỌNG NÓI đúng ngôn ngữ session.
///   Khác ChatGPT Voice: chậm hơn (~4-7s vs ~1-2s) nhưng OFFLINE + free +
///   có 3 lớp guard."
class VoiceConversationScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String languageCode;
  final String sessionTitle;
  const VoiceConversationScreen({
    super.key,
    required this.sessionId,
    required this.languageCode,
    required this.sessionTitle,
  });

  @override
  ConsumerState<VoiceConversationScreen> createState() =>
      _VoiceConversationScreenState();
}

enum _VoiceState { idle, listening, transcribing, thinking, speaking, error }

class _VoiceConversationScreenState
    extends ConsumerState<VoiceConversationScreen>
    with TickerProviderStateMixin {
  _VoiceState _state = _VoiceState.idle;
  String _userTranscript = '';
  String _aiText = '';
  String? _errorMsg;

  // Conversation history hiển thị trên màn
  final List<_VoiceTurn> _turns = [];

  // VAD settings
  static const _silenceThresholdDb = -35.0;     // dBFS — dưới này coi là im lặng
  static const _silenceDuration = Duration(milliseconds: 1500);
  static const _maxRecordDuration = Duration(seconds: 30);

  StreamSubscription<Amplitude>? _ampSub;
  Timer? _silenceTimer;
  DateTime? _recordStartedAt;
  bool _userHasSpoken = false;
  bool _exiting = false;
  // Re-entry guard cho _stopAndProcess — tránh trigger 2 lần liên tiếp khi
  // amplitude listener vẫn còn fire trong lúc state đang transition.
  bool _processingTurn = false;

  late final AnimationController _pulseCtrl;

  // Theo dõi duration cuộc gọi. Dùng ValueNotifier thay vì Timer +
  // setState để CHỈ widget hiển thị duration rebuild — không phải toàn
  // screen (tránh kéo theo 44 waveform bars rebuild mỗi giây).
  late final DateTime _callStartedAt;
  final ValueNotifier<int> _elapsedSeconds = ValueNotifier(0);
  Timer? _callTimer;

  @override
  void initState() {
    super.initState();
    ref.watch;  // ensure ref accessible
    // KHÔNG auto-repeat. Chỉ chạy khi state=listening hoặc speaking để
    // tránh waveform AnimatedBuilder ticks 60fps liên tục (gây lag toàn app).
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Track call duration. Update ValueNotifier mỗi giây — CHỈ widget bind
    // vào _elapsedSeconds rebuild (duration text), không phải toàn screen.
    _callStartedAt = DateTime.now();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _elapsedSeconds.value =
          DateTime.now().difference(_callStartedAt).inSeconds;
    });
    // Bắt đầu listening ngay
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    // Set flag NGAY để mọi async callback đang treo biết "exit, đừng làm gì nữa"
    _exiting = true;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _ampSub?.cancel();
    _ampSub = null;
    _callTimer?.cancel();
    _callTimer = null;
    _elapsedSeconds.dispose();
    _pulseCtrl.dispose();
    // Fire-and-forget — không await vì dispose phải sync trả về
    final rec = ref.read(voiceRecorderProvider);
    if (rec.isRecording) {
      rec.cancel().catchError((_) {});
    }
    ref.read(audioPlayerServiceProvider).stop().catchError((_) {});
    super.dispose();
  }

  // ==========================================================
  // Pulse animation chỉ chạy khi listening/speaking — tránh AnimatedBuilder
  // rebuild waveform 60fps liên tục khi UI idle (root cause lag toàn app).
  // ==========================================================
  void _syncPulse() {
    final shouldRun = _state == _VoiceState.listening ||
        _state == _VoiceState.speaking;
    if (shouldRun) {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
    } else {
      if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
    }
  }

  // ==========================================================
  // State machine actions
  // ==========================================================
  Future<void> _startListening() async {
    if (_exiting) return;
    // Cleanup state cũ trước khi start mới — tránh stale subscriptions / timer
    _silenceTimer?.cancel();
    _silenceTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;

    if (!mounted || _exiting) return;
    setState(() {
      _state = _VoiceState.listening;
      _userTranscript = '';
      _aiText = '';
      _errorMsg = null;
      _userHasSpoken = false;
    });
    _syncPulse();

    final rec = ref.read(voiceRecorderProvider);
    // Phòng trường hợp record cũ còn chạy
    if (rec.isRecording) {
      try {
        await rec.cancel();
      } catch (_) {}
    }
    try {
      // Timeout 5s — nếu getUserMedia hang trên web thì recover thay vì stuck
      await rec.start().timeout(const Duration(seconds: 5));
      _recordStartedAt = DateTime.now();
    } on TimeoutException {
      _setError('Mic không phản hồi. Bấm "Thử lại" để khởi động lại.');
      return;
    } catch (e) {
      _setError('Không khởi động được microphone: $e');
      return;
    }

    // Subscribe amplitude stream cho VAD
    _ampSub = rec.amplitudeStream().listen((amp) {
      if (_state != _VoiceState.listening) return;
      // amp.current là dBFS — 0 = loud, -∞ = silent
      final isSilent = amp.current < _silenceThresholdDb;

      // Max duration safeguard — tránh record vô hạn nếu mic lỗi
      if (_recordStartedAt != null &&
          DateTime.now().difference(_recordStartedAt!) > _maxRecordDuration) {
        _stopAndProcess();
        return;
      }

      if (!isSilent) {
        // Có speech → reset silence timer + mark user has spoken
        _userHasSpoken = true;
        _silenceTimer?.cancel();
        _silenceTimer = null;
        return;
      }

      // Đang silent — start timer nếu user đã nói trước đó
      if (_userHasSpoken && _silenceTimer == null) {
        _silenceTimer = Timer(_silenceDuration, _stopAndProcess);
      }
    });
  }

  Future<void> _stopAndProcess() async {
    if (_state != _VoiceState.listening) return;
    if (_processingTurn) return; // guard tránh re-entry
    _processingTurn = true;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;

    if (!mounted || _exiting) {
      _processingTurn = false;
      return;
    }
    setState(() => _state = _VoiceState.transcribing);
    _syncPulse();

    final rec = ref.read(voiceRecorderProvider);
    final api = ref.read(audioApiProvider);
    final chatApi = ref.read(chatApiProvider);

    try {
      final result = await rec.stop();
      if (result == null) {
        _setError('Không lấy được audio');
        return;
      }

      // STT
      final STTResult sttResult;
      if (kIsWeb || result.isWeb) {
        sttResult = await api.speechToTextFromBytes(
          bytes: result.bytes!,
          filename: result.filename,
          language: widget.languageCode,
        );
      } else {
        sttResult = await api.speechToText(
          filePath: result.filePath!,
          language: widget.languageCode,
        );
      }

      final userText = sttResult.text.trim();
      if (userText.isEmpty) {
        // User chỉ nói "uh" hoặc tiếng ồn — bỏ qua, listen lại
        if (!mounted) return;
        await _startListening();
        return;
      }

      setState(() {
        _userTranscript = userText;
        _state = _VoiceState.thinking;
      });
      _syncPulse();

      // Gửi qua chat stream — contract enforcement vẫn áp ở đây
      String aiContent = '';
      bool wasRefusal = false;

      await for (final event in chatApi.sendStream(
        sessionId: widget.sessionId,
        content: userText,
        inputType: 'voice',
      )) {
        if (_exiting) return;
        switch (event) {
          case ChatStreamIntent(:final inScope):
            wasRefusal = !inScope;
          case ChatStreamToken(:final content):
            aiContent += content;
            setState(() => _aiText = aiContent);
          case ChatStreamDone(:final userMessageId):
            // Layer 4 — Fire-and-forget grammar correction. KHÔNG show UI
            // trong voice mode (giữ fluidity) nhưng vẫn trigger backend để
            // warm DB cache. Sau này nếu user vào chat history xem lại,
            // correction_json đã có sẵn trong messages table.
            if (!wasRefusal && userMessageId.isNotEmpty) {
              chatApi.getCorrection(userMessageId).catchError(
                (_) => const MessageCorrection(
                  hasError: false,
                  wrong: '',
                  corrected: '',
                  diff: [],
                  explanation: '',
                  nextSuggestions: [],
                ),
              );
            }
            break;
          case ChatStreamError(:final error):
            _setError('Lỗi LLM: $error');
            return;
        }
      }

      if (aiContent.isEmpty) {
        _setError('AI không trả lời');
        return;
      }

      // Save turn lên history strip
      setState(() {
        _turns.add(_VoiceTurn(
          user: userText,
          ai: aiContent,
          wasRefusal: wasRefusal,
        ));
        if (_turns.length > 5) _turns.removeAt(0);
      });

      // TTS
      setState(() => _state = _VoiceState.speaking);
      _syncPulse();
      try {
        final audioBytes = await api.textToSpeech(
          text: aiContent,
          languageCode: widget.languageCode,
        );
        final player = ref.read(audioPlayerServiceProvider);
        // playAndAwaitCompletion: chờ chính xác đến khi processingState=completed
        // Tránh bug stuck "AI đang trả lời" trên web vì just_audio.play() không
        // block — chỉ start playback rồi return.
        await player.playAndAwaitCompletion(
          messageId: 'voice-turn',
          audioBytes: audioBytes,
        );
      } catch (e) {
        // TTS fail không fatal — vẫn loop lại
        debugPrint('TTS failed: $e');
      }

      // Buffer 800ms sau khi TTS kết thúc để loa thực sự tắt — tránh mic
      // capture âm còn dư + feedback loop (mic nghe lại tiếng AI mình vừa nói).
      if (!_exiting && mounted) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (!_exiting && mounted) {
          _processingTurn = false;
          await _startListening();
          return;
        }
      }
    } catch (e) {
      _setError(e is AppError ? e.message : e.toString());
    } finally {
      _processingTurn = false;
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      _state = _VoiceState.error;
      _errorMsg = msg;
    });
    _syncPulse();
  }

  Future<void> _retry() async {
    _processingTurn = false;
    // Đảm bảo recorder cũ stop nếu vẫn đang run
    final rec = ref.read(voiceRecorderProvider);
    if (rec.isRecording) {
      try {
        await rec.cancel();
      } catch (_) {}
    }
    // Đảm bảo player stop nếu vẫn còn phát
    try {
      await ref.read(audioPlayerServiceProvider).stop();
    } catch (_) {}
    await _startListening();
  }

  // ==========================================================
  // UI
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildCenter()),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  static String _fmtDuration(int totalSeconds) {
    final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded,
                color: AppColors.navy, size: 24),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CUỘC GỌI VOICE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                // CHỈ Text này rebuild khi _elapsedSeconds đổi (1 lần/giây).
                // Không kéo theo waveform/section rebuild → giải lag.
                ValueListenableBuilder<int>(
                  valueListenable: _elapsedSeconds,
                  builder: (_, s, _) => Text(
                    _fmtDuration(s),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      letterSpacing: -0.4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _LiveChip(active: _state != _VoiceState.error),
        ],
      ),
    );
  }

  Widget _buildCenter() {
    if (_state == _VoiceState.error && _errorMsg != null) {
      return _buildErrorView();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        children: [
          // AI section — chiếm khoảng nửa trên
          Expanded(child: _buildAiSection()),
          const SizedBox(height: 12),
          // User section — nửa dưới
          Expanded(child: _buildUserSection()),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                color: AppColors.error, size: 56),
            const SizedBox(height: 12),
            Text(
              _errorMsg ?? 'Có lỗi xảy ra',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiSection() {
    final isSpeaking = _state == _VoiceState.speaking;
    final isThinking = _state == _VoiceState.thinking;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6E4EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trạng thái chip
          if (isSpeaking)
            _StatusChip(
              icon: Icons.auto_awesome,
              label: 'AI đang nói',
              color: AppColors.primary,
            )
          else if (isThinking)
            _StatusChip(
              icon: Icons.psychology,
              label: 'AI đang nghĩ...',
              color: const Color(0xFFB23A20),
            )
          else
            _StatusChip(
              icon: Icons.mic_none_rounded,
              label: 'AI đang lắng nghe',
              color: const Color(0xFF8C879E),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                _aiText.isEmpty
                    ? (isThinking
                        ? 'Đang chuẩn bị câu trả lời...'
                        : 'Hãy nói gì đó để bắt đầu cuộc trò chuyện.')
                    : '"$_aiText"',
                style: TextStyle(
                  color: _aiText.isEmpty
                      ? const Color(0xFF8C879E)
                      : AppColors.navy,
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _VoiceWaveform(
            active: isSpeaking,
            color: AppColors.primary,
            pulseCtrl: _pulseCtrl,
          ),
        ],
      ),
    );
  }

  Widget _buildUserSection() {
    final isListening = _state == _VoiceState.listening;
    final isTranscribing = _state == _VoiceState.transcribing;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5EF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFE0D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isListening
                      ? AppColors.primary
                      : const Color(0xFFD0CCDB),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isListening
                    ? 'ĐANG NGHE BẠN NÓI'
                    : isTranscribing
                        ? 'ĐANG NHẬN DIỆN...'
                        : 'BẠN VỪA NÓI',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _VoiceWaveform(
            active: isListening,
            color: AppColors.primary,
            pulseCtrl: _pulseCtrl,
            barCount: 28,
            barHeight: 52,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                _userTranscript.isEmpty
                    ? (isListening
                        ? 'Mic đang mở, hãy nói tự nhiên...'
                        : 'Chưa có câu nói nào.')
                    : '"$_userTranscript"',
                style: TextStyle(
                  color: _userTranscript.isEmpty
                      ? const Color(0xFF8C879E)
                      : AppColors.navy,
                  fontSize: 14,
                  height: 1.5,
                  fontStyle: _userTranscript.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final isListening = _state == _VoiceState.listening;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SideControl(
            icon: Icons.history_rounded,
            label: 'Lịch sử',
            onTap: _turns.isEmpty ? null : () => _showHistorySheet(context),
          ),
          // Mic to giữa — bấm để thoát call (giống "kết thúc cuộc gọi")
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.40),
                    offset: const Offset(0, 8),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(
                isListening
                    ? Icons.mic_rounded
                    : Icons.call_end_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          _SideControl(
            icon: Icons.settings_rounded,
            label: 'Chế độ',
            onTap: () => _showModeSheet(context),
          ),
        ],
      ),
    );
  }

  void _showHistorySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6E4EC),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Lịch sử cuộc gọi',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _turns.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final t = _turns[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.wasRefusal
                            ? const Color(0xFFFFF4E0)
                            : const Color(0xFFF7F5F0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: t.wasRefusal
                              ? const Color(0xFFFFD89C)
                              : const Color(0xFFE6E4EC),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('👤 ${t.user}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF5C5870))),
                          const SizedBox(height: 4),
                          Text('🤖 ${t.ai}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showModeSheet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tuỳ chọn chế độ — đang phát triển'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _VoiceTurn {
  final String user;
  final String ai;
  final bool wasRefusal;
  const _VoiceTurn({
    required this.user,
    required this.ai,
    required this.wasRefusal,
  });
}

// ============================================================
// UI helper widgets cho voice screen
// ============================================================

/// Chip Live xanh forest nhấp nháy ở header.
class _LiveChip extends StatefulWidget {
  final bool active;
  const _LiveChip({required this.active});
  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.active
            ? const Color(0xFFE6F4ED)
            : const Color(0xFFF0EFF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: widget.active
                ? const Color(0xFFB9DCC9)
                : const Color(0xFFE6E4EC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.active)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A6A52),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2A6A52)
                          .withValues(alpha: 0.5 * _ctrl.value),
                      blurRadius: 6 * _ctrl.value,
                      spreadRadius: 2 * _ctrl.value,
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFB23A20),
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            widget.active ? 'Live' : 'Lỗi',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: widget.active
                  ? const Color(0xFF2A6A52)
                  : const Color(0xFFB23A20),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip nhỏ "AI đang nói / đang nghĩ / đang lắng nghe".
class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Waveform bars TO, dramatic — animate khi `active=true`, static khi false.
///
/// Tối ưu lag (xem memory feedback_flutter_perf):
/// 1. Khi `active=false` → static, KHÔNG AnimatedBuilder rebuild
/// 2. Khi `active=true` → RepaintBoundary cô lập paint khỏi parent tree
/// 3. CustomPaint 1 paint op thay N widget Container
///
/// Style: bars dày 4px, height tới 60px, gradient end-to-end + glow khi
/// active để nhìn rõ "chuyển động sóng" (như Siri/Alexa).
class _VoiceWaveform extends StatelessWidget {
  final bool active;
  final Color color;
  final AnimationController pulseCtrl;
  final int barCount;
  final double barHeight;
  const _VoiceWaveform({
    required this.active,
    required this.color,
    required this.pulseCtrl,
    this.barCount = 20,
    this.barHeight = 56,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return SizedBox(
        height: barHeight,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _WavePainter(
              progress: 0,
              color: color.withValues(alpha: 0.28),
              barCount: barCount,
              barHeight: barHeight,
              animated: false,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }
    return SizedBox(
      height: barHeight,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: pulseCtrl,
          builder: (_, _) {
            return CustomPaint(
              painter: _WavePainter(
                progress: pulseCtrl.value,
                color: color,
                barCount: barCount,
                barHeight: barHeight,
                animated: true,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final Color color;
  final int barCount;
  final double barHeight;
  final bool animated;
  _WavePainter({
    required this.progress,
    required this.color,
    required this.barCount,
    required this.barHeight,
    required this.animated,
  });

  static double _sin(double x) {
    while (x > 3.14159) {
      x -= 6.28318;
    }
    while (x < -3.14159) {
      x += 6.28318;
    }
    return x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Bars dày + spacing rộng → trông rõ ràng như Siri waveform.
    // KHÔNG dùng MaskFilter.blur (gây WebGL context loss trên CanvasKit).
    // Thay bằng "halo" rect rộng hơn bên dưới với alpha thấp.
    const barWidth = 4.0;
    final spacing = barCount > 1
        ? (size.width - barCount * barWidth) / (barCount - 1)
        : 0.0;
    final cx = size.height / 2;

    final haloPaint = Paint()
      ..color = color.withValues(alpha: animated ? 0.22 : 0.0)
      ..style = PaintingStyle.fill;
    final mainPaint = Paint()
      ..color = color.withValues(alpha: animated ? 1.0 : 0.45)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      // 2 sin layered: tần số khác nhau tạo dao động phong phú như sóng âm
      final phase1 = (progress * 6.28318) + (i * 0.62);
      final phase2 = (progress * 12.566) + (i * 0.3);
      final amp = animated
          ? (0.5 + 0.5 * _sin(phase1) * 0.7 +
                  0.5 * 0.5 * _sin(phase2) * 0.3)
              .clamp(0.0, 1.0)
          : 0.20;
      final h = barHeight * (animated ? 0.18 + 0.82 * amp : 0.20);
      final x = i * (barWidth + spacing);
      final top = cx - h / 2;

      // Halo: rect rộng hơn 4px, alpha thấp — giả "glow" mà không cần blur
      if (animated) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 2, top - 2, barWidth + 4, h + 4),
            const Radius.circular(4),
          ),
          haloPaint,
        );
      }

      // Main bar — solid color (không shader gradient để tránh GPU stress)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, barWidth, h),
          const Radius.circular(2.5),
        ),
        mainPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.animated != animated ||
      old.barCount != barCount;
}

/// Button bên trái/phải bottom bar — icon round + label nhỏ bên dưới.
class _SideControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SideControl({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE6E4EC)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.05),
                    offset: const Offset(0, 4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: enabled
                    ? AppColors.navy
                    : const Color(0xFFB6B2C2),
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: enabled
                ? const Color(0xFF5C5870)
                : const Color(0xFFB6B2C2),
          ),
        ),
      ],
    );
  }
}
