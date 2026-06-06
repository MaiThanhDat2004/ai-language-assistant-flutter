import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/chat_api.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/audio/voice_recorder.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/message.dart';
import '../../core/models/vocabulary.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/utils/chat_suggestions.dart';
import '../../shared/utils/session_icon.dart';
import 'pronunciation_dialog.dart';
import 'voice_conversation_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String? initialTitle;
  const ChatScreen({super.key, required this.sessionId, this.initialTitle});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loadingHistory = true;
  bool _sending = false;
  String? _errorText;
  // Ngôn ngữ phản hồi của session — dùng để biết từ vựng user lưu là tiếng gì
  String _sessionLanguage = 'vi';
  // Voice input state
  bool _recording = false;
  bool _transcribing = false;
  Timer? _recordTimer;
  Duration _recordElapsed = Duration.zero;
  // Audio playback state — chỉ track messageId đang play để hightlight đúng bubble
  String? _playingMessageId;
  StreamSubscription<PlayingState>? _playerSub;
  // Layer 4 — Grammar correction state per user message id
  // status: loading | loaded (has_error=true) | none (has_error=false hoặc fail)
  final Map<String, _CorrectionState> _corrections = {};

  // Layer 4 trigger — sau khi stream Done, fetch correction cho user message
  // Lazy + best-effort: fail/none thì im lặng. Luôn giữ data để dùng cả
  // correction card (khi has_error) lẫn next_suggestions (mọi trường hợp).
  Future<void> _fetchCorrection(String userMessageId) async {
    setState(() {
      _corrections[userMessageId] =
          const _CorrectionState(status: _CorrectionStatus.loading);
    });
    try {
      final c = await ref.read(chatApiProvider).getCorrection(userMessageId);
      if (!mounted) return;
      setState(() {
        // status=loaded chỉ điều khiển render CARD (only when has_error).
        // data luôn lưu để nextSuggestions vẫn dùng được khi has_error=false.
        _corrections[userMessageId] = _CorrectionState(
          status: c.hasError
              ? _CorrectionStatus.loaded
              : _CorrectionStatus.none,
          data: c,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _corrections[userMessageId] =
            const _CorrectionState(status: _CorrectionStatus.none);
      });
    }
  }

  // Suggestions giờ derive runtime từ session title + language, qua
  // `suggestionsForSession()` trong shared/utils/chat_suggestions.dart

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadSessionMeta();
    // Listen audio player state để highlight bubble đang play
    _playerSub = ref.read(audioPlayerServiceProvider).stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _playingMessageId = s.isPlaying ? s.messageId : null);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _playerSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSessionMeta() async {
    try {
      final session =
          await ref.read(sessionsApiProvider).get(widget.sessionId);
      if (!mounted) return;
      setState(() => _sessionLanguage = session.responseLanguage);
    } catch (_) {
      // Silent fail — sẽ fallback dùng 'vi'
    }
  }

  Future<void> _showSaveWordDialog(ChatMessage sourceMessage) async {
    final wordCtrl = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
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
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Lưu từ vào sổ tay',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Ngôn ngữ: ${_sessionLanguage.toUpperCase()} • AI sẽ tự tạo định nghĩa và ví dụ',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: wordCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Từ cần lưu',
                hintText: 'Vd: serendipity',
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(wordCtrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Lưu',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;

    // Show loading snackbar
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Đang lưu "$result"...'),
      duration: const Duration(seconds: 10),
    ));

    try {
      await ref.read(vocabularyApiProvider).create(
            word: result,
            language: _sessionLanguage,
            sourceMessageId: sourceMessage.id.startsWith('local-')
                ? null
                : sourceMessage.id,
          );
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('✓ Đã lưu "$result" vào sổ tay'),
        backgroundColor: AppColors.success,
      ));
    } on AppError catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ==========================================================
  // VOICE CONVERSATION MODE — full-screen, user nói liên tục, AI trả lời bằng giọng
  // Reuse Whisper STT + chat/stream + gTTS TTS. Contract enforcement vẫn áp.
  // ==========================================================
  Future<void> _enterVoiceMode() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VoiceConversationScreen(
          sessionId: widget.sessionId,
          languageCode: _sessionLanguage,
          sessionTitle: widget.initialTitle ?? 'Hội thoại',
        ),
      ),
    );
    // Sau khi thoát voice mode — reload history vì có thể đã thêm tin nhắn
    if (mounted) _loadHistory();
  }

  // ==========================================================
  // PRONUNCIATION — user đọc theo câu AI, Whisper chấm điểm word-level
  // Defense angle: differentiate vs ChatGPT (không có chấm phát âm)
  // ==========================================================
  Future<void> _showPronunciationDialog(ChatMessage source) async {
    if (source.isUser || source.isRefusal) return;
    if (source.content.trim().isEmpty) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PronunciationDialog(
        referenceText: source.content,
        languageCode: _sessionLanguage,
        sessionId: widget.sessionId,
        messageId: source.id,
      ),
    );
  }

  // ==========================================================
  // AUTO-EXTRACT VOCABULARY — AI tự đề xuất từ đáng học từ message
  // ==========================================================
  Future<void> _showExtractDialog(ChatMessage source) async {
    if (source.isUser || source.isRefusal) return;
    // Show loading sheet
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight)),
    );
    List<VocabularyCandidate> candidates;
    try {
      candidates = await ref.read(vocabularyApiProvider).extract(
            text: source.content,
            sourceLanguage: _sessionLanguage,
            sourceMessageId:
                source.id.startsWith('local-') ? null : source.id,
            maxItems: 5,
          );
    } on AppError catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('AI không tìm được từ đáng học trong tin nhắn này')),
      );
      return;
    }
    await _showCandidatesPicker(source, candidates);
  }

  Future<void> _showCandidatesPicker(
    ChatMessage source,
    List<VocabularyCandidate> candidates,
  ) async {
    final selected = <int>{for (var i = 0; i < candidates.length; i++) i};

    final saveResult = await showModalBottomSheet<Set<int>>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: AppColors.primaryLight, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('AI đề xuất từ vựng',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    Text('${selected.length}/${candidates.length} chọn',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Bỏ tick các từ bạn đã biết. AI có thể bị nhầm — kiểm tra trước khi lưu.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: candidates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _CandidateTile(
                      candidate: candidates[i],
                      selected: selected.contains(i),
                      onToggle: () => setSheetState(() {
                        if (selected.contains(i)) {
                          selected.remove(i);
                        } else {
                          selected.add(i);
                        }
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.of(ctx).pop(selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      selected.isEmpty
                          ? 'Chọn ít nhất 1 từ'
                          : 'Lưu ${selected.length} từ vào sổ tay',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saveResult == null || saveResult.isEmpty || !mounted) return;
    await _saveSelectedCandidates(source, candidates, saveResult);
  }

  Future<void> _saveSelectedCandidates(
    ChatMessage source,
    List<VocabularyCandidate> candidates,
    Set<int> indices,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Đang lưu ${indices.length} từ...'),
      duration: const Duration(seconds: 30),
    ));

    int success = 0;
    int duplicate = 0;
    int failed = 0;
    for (final i in indices) {
      final c = candidates[i];
      try {
        await ref.read(vocabularyApiProvider).create(
              word: c.word,
              language: _sessionLanguage,
              definition: c.definition,
              example: c.example,
              sourceMessageId:
                  source.id.startsWith('local-') ? null : source.id,
              autoGenerate: false, // đã có definition+example từ extract
            );
        success++;
      } on AppError catch (e) {
        if (e.statusCode == 409) {
          duplicate++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    final parts = <String>[];
    if (success > 0) parts.add('✓ Lưu $success từ');
    if (duplicate > 0) parts.add('$duplicate đã có sẵn');
    if (failed > 0) parts.add('$failed lỗi');
    messenger.showSnackBar(SnackBar(
      content: Text(parts.join(' • ')),
      backgroundColor:
          failed > 0 ? AppColors.error : AppColors.success,
    ));
  }

  // ==========================================================
  // VOICE RECORDING — start/stop, STT, đẩy text vào input
  // ==========================================================
  Future<void> _toggleRecording() async {
    final recorder = ref.read(voiceRecorderProvider);
    if (_recording) {
      // Đang ghi → stop và transcribe
      await _stopAndTranscribe(recorder);
    } else {
      await _startRecording(recorder);
    }
  }

  Future<void> _startRecording(VoiceRecorder recorder) async {
    try {
      await recorder.start();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordElapsed = Duration.zero;
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordElapsed = recorder.elapsed);
      });
    } on VoiceRecorderException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _stopAndTranscribe(VoiceRecorder recorder) async {
    _recordTimer?.cancel();
    setState(() {
      _recording = false;
      _transcribing = true;
    });

    try {
      final rec = await recorder.stop();
      if (rec == null) {
        setState(() => _transcribing = false);
        return;
      }
      final api = ref.read(audioApiProvider);
      final result = rec.isWeb
          ? await api.speechToTextFromBytes(
              bytes: rec.bytes!,
              filename: rec.filename,
              language: _sessionLanguage,
            )
          : await api.speechToText(
              filePath: rec.filePath!,
              language: _sessionLanguage,
            );

      if (!mounted) return;
      // Append vào input (không gửi tự động — user reviews trước khi send)
      final current = _inputCtrl.text;
      final glue = current.isEmpty ? '' : ' ';
      _inputCtrl.text = '$current$glue${result.text}';
      _inputCtrl.selection =
          TextSelection.collapsed(offset: _inputCtrl.text.length);
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Lỗi nhận dạng giọng nói: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await ref.read(voiceRecorderProvider).cancel();
    if (mounted) setState(() => _recording = false);
  }

  // ==========================================================
  // AUDIO PLAYBACK — TTS cho AI message
  // ==========================================================
  Future<void> _togglePlayMessage(ChatMessage msg) async {
    final player = ref.read(audioPlayerServiceProvider);
    if (_playingMessageId == msg.id) {
      await player.stop();
      return;
    }
    try {
      final bytes = await ref.read(audioApiProvider).textToSpeech(
            text: msg.content,
            languageCode: msg.languageDetected ?? _sessionLanguage,
          );
      await player.play(messageId: msg.id, audioBytes: bytes);
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Lỗi phát âm: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _loadHistory() async {
    try {
      final msgs = await ref
          .read(chatApiProvider)
          .getMessages(widget.sessionId, limit: 50);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _loadingHistory = false;
      });
      _scrollToBottom();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _errorText = e.message;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? overrideText]) async {
    final text = (overrideText ?? _inputCtrl.text).trim();
    if (text.isEmpty || _sending) return;

    // Optimistic UI: user bubble + empty AI bubble đang stream
    final userLocalId = 'local-u-${DateTime.now().millisecondsSinceEpoch}';
    final aiLocalId = 'local-a-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _sending = true;
      _inputCtrl.clear();
      _messages.add(ChatMessage(
        id: userLocalId,
        sessionId: widget.sessionId,
        role: MessageRole.user,
        content: text,
        inputType: MessageInputType.text,
        createdAt: DateTime.now(),
      ));
      _messages.add(ChatMessage(
        id: aiLocalId,
        sessionId: widget.sessionId,
        role: MessageRole.assistant,
        content: '', // sẽ append từng token
        inputType: MessageInputType.text,
        createdAt: DateTime.now(),
      ));
    });
    _scrollToBottom();

    String aiContent = '';
    bool? streamInScope;
    String? streamModelUsed;
    bool errorHandled = false;

    try {
      await for (final event in ref
          .read(chatApiProvider)
          .sendStream(sessionId: widget.sessionId, content: text)) {
        if (!mounted) return;
        switch (event) {
          case ChatStreamIntent(:final inScope):
            streamInScope = inScope;
          case ChatStreamToken(:final content):
            aiContent += content;
            // Update bubble cuối với content mới (vẫn dùng local id)
            setState(() {
              _messages[_messages.length - 1] = ChatMessage(
                id: aiLocalId,
                sessionId: widget.sessionId,
                role: MessageRole.assistant,
                content: aiContent,
                inputType: MessageInputType.text,
                refusalReason: streamInScope == false ? 'off_scope' : null,
                createdAt: DateTime.now(),
              );
            });
            _scrollToBottom();
          case ChatStreamDone(
              :final modelUsed,
              :final userMessageId,
              :final assistantMessageId,
            ):
            streamModelUsed = modelUsed;
            // Replace local user + AI bubbles bằng IDs thật khi xong
            setState(() {
              _messages[_messages.length - 2] = ChatMessage(
                id: userMessageId.isNotEmpty ? userMessageId : userLocalId,
                sessionId: widget.sessionId,
                role: MessageRole.user,
                content: text,
                inputType: MessageInputType.text,
                createdAt: _messages[_messages.length - 2].createdAt,
              );
              _messages[_messages.length - 1] = ChatMessage(
                id: assistantMessageId.isNotEmpty
                    ? assistantMessageId
                    : aiLocalId,
                sessionId: widget.sessionId,
                role: MessageRole.assistant,
                content: aiContent,
                inputType: MessageInputType.text,
                modelUsed: streamModelUsed,
                refusalReason: streamInScope == false ? 'off_scope' : null,
                createdAt: _messages[_messages.length - 1].createdAt,
              );
            });
            // Layer 4 — Lazy fetch correction cho user message (best-effort,
            // không block UX). Skip nếu refusal (AI từ chối → không cần sửa
            // câu user).
            if (streamInScope != false && userMessageId.isNotEmpty) {
              _fetchCorrection(userMessageId);
            }
          case ChatStreamError(:final error):
            errorHandled = true;
            // Bỏ user + AI bubble đang stream
            setState(() {
              if (_messages.length >= 2) {
                _messages.removeRange(
                    _messages.length - 2, _messages.length);
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi: $error'),
                backgroundColor: AppColors.error,
                action: SnackBarAction(
                  label: 'Thử lại',
                  textColor: Colors.white,
                  onPressed: () => _send(text),
                ),
              ),
            );
        }
      }
    } on AppError catch (e) {
      if (!mounted || errorHandled) return;
      setState(() {
        if (_messages.length >= 2) {
          _messages.removeRange(_messages.length - 2, _messages.length);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
          action: SnackBarAction(
            label: 'Thử lại',
            textColor: Colors.white,
            onPressed: () => _send(text),
          ),
        ),
      );
    } catch (e) {
      if (!mounted || errorHandled) return;
      setState(() {
        if (_messages.length >= 2) {
          _messages.removeRange(_messages.length - 2, _messages.length);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi không xác định: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);  // subscribe để rebuild khi đổi theme
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(child: _buildBody()),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final flag = flagForLanguageCode(_sessionLanguage);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: const Color(0xFFE6E4EC))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.chevron_left, size: 26),
            color: AppColors.navy,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialTitle ?? 'Hội thoại',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(flag, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    Text(
                      _sessionLanguage.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5C5870),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD0CCDB),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const _LiveDot(),
                    const SizedBox(width: 5),
                    const Text(
                      'Đang hoạt động',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2A6A52),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Chế độ thoại',
            onPressed: _enterVoiceMode,
            icon: const Icon(Icons.mic_none_rounded,
                color: AppColors.primary, size: 22),
          ),
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF5C5870), size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingHistory) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight));
    }
    if (_errorText != null && _messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(_errorText!,
              style: const TextStyle(color: AppColors.error)),
        ),
      );
    }
    if (_messages.isEmpty) {
      return _buildEmptyState();
    }
    // Build flat list: time divider + bubbles (+ caret cho streaming bubble)
    // + typing dots khi chưa có token + inline suggestions sau AI cuối.
    final items = <Widget>[];
    items.add(_TimeDivider(time: _messages.first.createdAt));

    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final isLast = i == _messages.length - 1;
      // AI bubble cuối đang nhận token → render caret inline
      final isStreaming =
          isLast && _sending && !m.isUser && m.content.isNotEmpty;
      // AI bubble cuối còn trống (chưa có token) → bỏ render, dùng typing dots
      final skipEmpty =
          isLast && _sending && !m.isUser && m.content.isEmpty;
      if (skipEmpty) continue;
      items.add(_MessageBubble(
        message: m,
        sessionLanguage: _sessionLanguage,
        isPlaying: _playingMessageId == m.id,
        isStreaming: isStreaming,
        onSaveWord: () => _showSaveWordDialog(m),
        onExtract: () => _showExtractDialog(m),
        onPlay: () => _togglePlayMessage(m),
        onPronounce: () => _showPronunciationDialog(m),
      ));
      // Layer 4 — Card "GỢI Ý SỬA" dưới user bubble nếu correction đã load
      if (m.isUser) {
        final st = _corrections[m.id];
        if (st != null) {
          if (st.status == _CorrectionStatus.loading) {
            items.add(const _CorrectionSkeleton());
          } else if (st.status == _CorrectionStatus.loaded &&
              st.data != null) {
            items.add(_CorrectionCard(correction: st.data!));
          }
        }
      }
    }

    // Typing dots khi đang sending mà bubble cuối còn rỗng (waiting for first token)
    if (_sending &&
        _messages.isNotEmpty &&
        !_messages.last.isUser &&
        _messages.last.content.isEmpty) {
      items.add(const _TypingBubble());
    }

    // Inline suggestions sau AI bubble cuối — chỉ khi không stream, không refusal.
    // ƯU TIÊN next_suggestions từ correction (context-aware theo AI vừa trả lời).
    // Fallback suggestionsForSession nếu correction chưa load / empty.
    if (!_sending && _messages.isNotEmpty) {
      final last = _messages.last;
      if (!last.isUser && !last.isRefusal && last.content.isNotEmpty) {
        // Tìm user message gần nhất TRƯỚC AI bubble cuối để lấy correction
        ChatMessage? lastUser;
        for (int i = _messages.length - 2; i >= 0; i--) {
          if (_messages[i].isUser) {
            lastUser = _messages[i];
            break;
          }
        }
        List<String> suggestions = [];
        if (lastUser != null) {
          final st = _corrections[lastUser.id];
          if (st?.data != null && st!.data!.nextSuggestions.isNotEmpty) {
            suggestions = st.data!.nextSuggestions.take(3).toList();
          }
        }
        // Fallback nếu chưa có correction (đang load hoặc lần đầu load history)
        if (suggestions.isEmpty) {
          suggestions = suggestionsForSession(
            title: widget.initialTitle ?? '',
            langCode: _sessionLanguage,
          ).take(3).toList();
        }
        items.add(_InlineSuggestions(
          suggestions: suggestions,
          onTap: (s) => _send(s),
        ));
      }
    }

    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: items,
    );
  }

  Widget _buildEmptyState() {
    final suggestions = suggestionsForSession(
      title: widget.initialTitle ?? '',
      langCode: _sessionLanguage,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 40),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/images/logo.png',
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
          Text('Hãy bắt đầu trò chuyện',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('Bấm một gợi ý để gửi ngay',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: suggestions
                .map((s) => GestureDetector(
                      onTap: () => _send(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(s,
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13)),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    // Khi đang ghi âm: ẩn input → hiện thanh recording với duration + cancel/stop
    if (_recording) return _buildRecordingBar();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                enabled: !_transcribing,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: _transcribing
                      ? 'Đang nhận dạng giọng nói...'
                      : 'Nhập tin nhắn...',
                  hintStyle:
                      TextStyle(color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Mic button — chỉ hiện khi input trống và không đang sending
          if (_inputCtrl.text.trim().isEmpty && !_sending)
            _MicButton(
              transcribing: _transcribing,
              onTap: _transcribing ? null : _toggleRecording,
            )
          else
            _SendButton(
              enabled: _inputCtrl.text.trim().isNotEmpty && !_sending,
              sending: _sending,
              onTap: () => _send(),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    final mm = _recordElapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = _recordElapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          // Cancel
          IconButton(
            onPressed: _cancelRecording,
            icon: Icon(Icons.close, color: AppColors.textSecondary),
            tooltip: 'Huỷ',
          ),
          Expanded(
            child: Row(
              children: [
                _PulsingDot(),
                const SizedBox(width: 8),
                Text(
                  'Đang ghi âm  $mm:$ss',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          // Stop + transcribe
          GestureDetector(
            onTap: _toggleRecording,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.stop, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String sessionLanguage;
  final bool isPlaying;
  final bool isStreaming;
  final VoidCallback onSaveWord;
  final VoidCallback onExtract;
  final VoidCallback onPlay;
  final VoidCallback onPronounce;
  const _MessageBubble({
    required this.message,
    required this.sessionLanguage,
    required this.isPlaying,
    this.isStreaming = false,
    required this.onSaveWord,
    required this.onExtract,
    required this.onPlay,
    required this.onPronounce,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser && message.isRefusal)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _ContractBadge(
                      icon: Icons.shield_outlined,
                      label: 'Ngoài ngữ cảnh',
                      color: AppColors.warning,
                    ),
                  ),
                if (!isUser && message.languageRetryCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _ContractBadge(
                      icon: Icons.autorenew,
                      label: 'Đã sửa ngôn ngữ (${message.languageRetryCount}× retry)',
                      color: AppColors.primaryLight,
                    ),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    // Match Stitch design: AI = pale blue, User = white, cả 2 chữ đen
                    color: isUser
                        ? AppColors.chatBubbleUser
                        : (message.isRefusal
                            ? AppColors.warning.withValues(alpha: 0.10)
                            : AppColors.chatBubbleAi),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: message.isRefusal
                        ? Border.all(
                            color:
                                AppColors.warning.withValues(alpha: 0.4))
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textPrimary.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isUser
                      ? Text(message.content,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              height: 1.4))
                      : isStreaming
                          // Khi đang stream: render plain text + caret inline
                          // (markdown lazy render khi xong cho mượt).
                          ? RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                                children: [
                                  TextSpan(text: message.content),
                                  const WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: _StreamingCaret(),
                                  ),
                                ],
                              ),
                            )
                          : MarkdownBody(
                              data: message.content,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                    height: 1.4),
                                code: TextStyle(
                                    color: AppColors.primaryDark,
                                    backgroundColor: AppColors.textPrimary
                                        .withValues(alpha: 0.06)),
                                codeblockDecoration: BoxDecoration(
                                  color: AppColors.textPrimary
                                      .withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                strong: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700),
                                listBullet: TextStyle(
                                    color: AppColors.textPrimary, fontSize: 14),
                              ),
                            ),
                ),
                // PRIMARY CTA: Luyện phát âm — pill nổi bật, ẩn nếu refusal/text quá ngắn
                if (!isUser && _shouldShowPronounceCta(message))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _PronounceCta(onTap: onPronounce),
                  ),
                // Action row phụ — chỉ hiện trên bubble AI bình thường (không refusal)
                if (!isUser && !message.isRefusal)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Play TTS
                        InkWell(
                          onTap: onPlay,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isPlaying
                                      ? Icons.stop_circle_outlined
                                      : Icons.volume_up_outlined,
                                  size: 14,
                                  color: isPlaying
                                      ? AppColors.primaryLight
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isPlaying ? 'Đang phát' : 'Nghe',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isPlaying
                                        ? AppColors.primaryLight
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // AI extract — feature DIFFERENTIATING vs ChatGPT
                        InkWell(
                          onTap: onExtract,
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome,
                                    size: 14,
                                    color: AppColors.primaryLight),
                                SizedBox(width: 4),
                                Text(
                                  'AI gợi ý từ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primaryLight,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Overflow menu — chứa action ít dùng (Lưu tay)
                        _BubbleOverflowMenu(onSaveWord: onSaveWord),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Điều kiện hiển thị CTA Luyện phát âm dưới bubble AI:
// - Không phải refusal (không học cách từ chối)
// - Không đang stream (content còn rỗng)
// - Text đủ dài để luyện (>= 10 ký tự, lọc câu trả lời 1-2 từ "OK", "Vâng")
bool _shouldShowPronounceCta(ChatMessage message) {
  if (message.isRefusal) return false;
  final text = message.content.trim();
  if (text.length < 10) return false;
  return true;
}

/// CTA pill nổi bật cho Luyện phát âm — ngay dưới AI bubble.
/// Lý do thiết kế prominent: đây là feature DIFFERENTIATING vs ChatGPT
/// (P6+P7 — Whisper word-level scoring + chart 14 ngày). Đưa ra ngoài
/// overflow menu để demo + user discoverability tốt hơn.
class _PronounceCta extends StatelessWidget {
  final VoidCallback onTap;
  const _PronounceCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentOrange.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded,
                    size: 14, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text(
                'Luyện phát âm câu này',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded,
                  size: 14, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleOverflowMenu extends StatelessWidget {
  final VoidCallback onSaveWord;
  const _BubbleOverflowMenu({required this.onSaveWord});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Tác vụ khác',
      iconSize: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      icon: Icon(Icons.more_horiz,
          size: 18, color: AppColors.textSecondary),
      color: AppColors.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (value) {
        switch (value) {
          case 'save':
            onSaveWord();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'save',
          child: Row(
            children: [
              Icon(Icons.bookmark_add_outlined,
                  size: 16, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text('Lưu tay vào sổ',
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const _Dots(),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_ctrl.value - i * 0.2) % 1.0;
            final scale = 0.6 + 0.4 * (1 - (t * 2 - 1).abs());
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool sending;
  final VoidCallback onTap;
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: enabled ? AppColors.primaryGradient : null,
          color: enabled ? null : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: sending
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(
                Icons.send_rounded,
                color: enabled ? Colors.white : AppColors.textTertiary,
                size: 20,
              ),
      ),
    );
  }
}

class _ContractBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ContractBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool transcribing;
  final VoidCallback? onTap;
  const _MicButton({required this.transcribing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: transcribing
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primaryLight),
              )
            : const Icon(Icons.mic, color: AppColors.primaryLight, size: 22),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(_ctrl),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: AppColors.error,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final VocabularyCandidate candidate;
  final bool selected;
  final VoidCallback onToggle;
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(12),
      color: selected
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.background,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primaryLight
                  : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                color: selected
                    ? AppColors.primaryLight
                    : AppColors.textTertiary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(candidate.word,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    if (candidate.definition != null) ...[
                      const SizedBox(height: 4),
                      Text(candidate.definition!,
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.3)),
                    ],
                    if (candidate.example != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '"${candidate.example!}"',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                          fontStyle: FontStyle.italic,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Layer 4 — Grammar correction state types
// ============================================================
enum _CorrectionStatus { loading, loaded, none }

class _CorrectionState {
  final _CorrectionStatus status;
  final MessageCorrection? data;
  const _CorrectionState({required this.status, this.data});
}

// ============================================================
// Visual effects — Live status dot, Streaming caret, Time divider,
// Inline suggestion chips. Tách riêng để chat_screen gọn hơn.
// ============================================================

/// Chấm xanh nhấp nháy báo "AI đang sẵn sàng" trong header.
class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Container(
          width: 7,
          height: 7,
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
        );
      },
    );
  }
}

/// Caret nhấp nháy ở cuối AI bubble khi đang stream.
class _StreamingCaret extends StatefulWidget {
  const _StreamingCaret();
  @override
  State<_StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<_StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Opacity(
          opacity: _ctrl.value,
          child: Container(
            width: 2,
            height: 16,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      },
    );
  }
}

/// Chip thời gian giữa scroll — "Hôm nay · 10:42".
class _TimeDivider extends StatelessWidget {
  final DateTime time;
  const _TimeDivider({required this.time});

  String _format() {
    final now = DateTime.now();
    final isToday = now.year == time.year &&
        now.month == time.month &&
        now.day == time.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == time.year &&
        yesterday.month == time.month &&
        yesterday.day == time.day;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final dayLabel = isToday
        ? 'Hôm nay'
        : isYesterday
            ? 'Hôm qua'
            : '${time.day}/${time.month}';
    return '$dayLabel · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE6E4EC)),
          ),
          child: Text(
            _format(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8C879E),
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// 3 chip gợi ý câu tiếp theo — hiện dưới AI bubble cuối khi không stream.
/// Bấm chip → gửi luôn câu đó qua _send(text). Có thể tái dùng
/// suggestionsForSession từ shared/utils/chat_suggestions.dart.
class _InlineSuggestions extends StatelessWidget {
  final List<String> suggestions;
  final void Function(String) onTap;
  const _InlineSuggestions({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 4, 0, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: suggestions
            .map((s) => InkWell(
                  onTap: () => onTap(s),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE6E4EC)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome,
                            size: 12, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          s,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ============================================================
// Layer 4 — Grammar correction card
// ============================================================

/// Skeleton 2-line khi đang fetch correction (LLM ~2-3s).
class _CorrectionSkeleton extends StatefulWidget {
  const _CorrectionSkeleton();
  @override
  State<_CorrectionSkeleton> createState() => _CorrectionSkeletonState();
}

class _CorrectionSkeletonState extends State<_CorrectionSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 4, 0, 12),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) {
          final shade = Color.lerp(
            const Color(0xFFFFE5DC),
            const Color(0xFFFFD0BD),
            _ctrl.value,
          )!;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5EF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE0D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_fix_high,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'AI đang chấm câu...',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(height: 10, color: shade),
                const SizedBox(height: 6),
                Container(
                    height: 10,
                    width: MediaQuery.of(context).size.width * 0.4,
                    color: shade),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Card "GỢI Ý SỬA" hiển thị diff word-level dưới user bubble.
/// - Dòng 1 (wrong): segments type=keep + remove, "remove" gạch ngang đỏ
/// - Dòng 2 (corrected): segments type=keep + add, "add" highlight coral
/// - Explanation phụ ở dưới
class _CorrectionCard extends StatelessWidget {
  final MessageCorrection correction;
  const _CorrectionCard({required this.correction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 4, 0, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5EF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFE0D0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_fix_high,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'GỢI Ý SỬA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Dòng wrong: keep + remove
            _DiffLine(
              segments: correction.diff
                  .where((s) => !s.isAdd)
                  .toList(),
              isWrong: true,
            ),
            const SizedBox(height: 6),
            // Dòng corrected: keep + add
            _DiffLine(
              segments: correction.diff
                  .where((s) => !s.isRemove)
                  .toList(),
              isWrong: false,
            ),
            if (correction.explanation.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: 1,
                color: const Color(0xFFFFE0D0),
              ),
              const SizedBox(height: 8),
              Text(
                correction.explanation,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF5C5870),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  final List<CorrectionSegment> segments;
  final bool isWrong;
  const _DiffLine({required this.segments, required this.isWrong});

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 14,
      height: 1.4,
      color: AppColors.navy,
      fontWeight: FontWeight.w500,
    );
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: segments.map((s) {
          if (s.isKeep) {
            return TextSpan(text: s.text);
          }
          if (s.isRemove && isWrong) {
            return TextSpan(
              text: s.text,
              style: const TextStyle(
                color: Color(0xFFB23A20),
                decoration: TextDecoration.lineThrough,
                decorationColor: Color(0xFFB23A20),
                decorationThickness: 2,
                fontWeight: FontWeight.w600,
              ),
            );
          }
          if (s.isAdd && !isWrong) {
            return WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s.text,
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }
          return const TextSpan(text: '');
        }).toList(),
      ),
    );
  }
}
