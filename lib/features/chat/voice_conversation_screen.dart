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

  @override
  void initState() {
    super.initState();
    ref.watch;  // ensure ref accessible
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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
          case ChatStreamDone():
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
    ref.watch(themeModeProvider);  // theme rebuild

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(child: _buildCenter()),
              _buildHistoryStrip(),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.sessionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text('Chế độ thoại · ${widget.languageCode.toUpperCase()}',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenter() {
    final (label, color, icon) = switch (_state) {
      _VoiceState.idle => ('Đang chuẩn bị...', AppColors.textSecondary, Icons.hourglass_empty),
      _VoiceState.listening => ('Đang nghe bạn nói...', AppColors.primary, Icons.mic),
      _VoiceState.transcribing => ('Đang nhận diện...', AppColors.primaryLight, Icons.graphic_eq),
      _VoiceState.thinking => ('AI đang nghĩ...', AppColors.warning, Icons.psychology),
      _VoiceState.speaking => ('AI đang trả lời...', AppColors.success, Icons.volume_up),
      _VoiceState.error => ('Có lỗi xảy ra', AppColors.error, Icons.error_outline),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar pulse
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                final pulseScale = _state == _VoiceState.listening ||
                        _state == _VoiceState.speaking
                    ? 1.0 + (_pulseCtrl.value * 0.15)
                    : 1.0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_state == _VoiceState.listening ||
                        _state == _VoiceState.speaking)
                      Container(
                        width: 180 * pulseScale,
                        height: 180 * pulseScale,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.15),
                        ),
                      ),
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 56),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 20),
            // Live transcript hoặc AI text
            if (_state == _VoiceState.error && _errorMsg != null) ...[
              Text(
                _errorMsg!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.error, fontSize: 13),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Thử lại'),
              ),
            ] else if (_aiText.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.chatBubbleAi,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _aiText,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.5),
                  ),
                ),
              ),
            ] else if (_userTranscript.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.chatBubbleUser,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _userTranscript,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryStrip() {
    if (_turns.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _turns.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = _turns[i];
          return Container(
            constraints: const BoxConstraints(maxWidth: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: t.wasRefusal
                  ? AppColors.warning.withValues(alpha: 0.12)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: t.wasRefusal
                    ? AppColors.warning.withValues(alpha: 0.4)
                    : AppColors.border,
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '👤 ${t.user}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
                ),
                Text(
                  '🤖 ${t.ai}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Thoát chế độ thoại'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
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
