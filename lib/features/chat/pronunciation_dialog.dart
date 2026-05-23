import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/audio_api.dart';
import '../../core/audio/voice_recorder.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';

/// Dialog luyện phát âm — defense angle (Chương 4):
/// User đọc câu AI vừa nói → Whisper transcribe → so word-level với reference →
/// trả score + chữ sai. Không dùng cloud pronunciation API.
class PronunciationDialog extends ConsumerStatefulWidget {
  final String referenceText;
  final String languageCode;
  final String? sessionId;
  final String? messageId;

  const PronunciationDialog({
    super.key,
    required this.referenceText,
    required this.languageCode,
    this.sessionId,
    this.messageId,
  });

  @override
  ConsumerState<PronunciationDialog> createState() =>
      _PronunciationDialogState();
}

enum _DialogStage { idle, recording, scoring, result, error }

class _PronunciationDialogState extends ConsumerState<PronunciationDialog> {
  _DialogStage _stage = _DialogStage.idle;
  PronunciationResult? _result;
  String? _errorMsg;
  late final Stream<Duration> _ticker;
  // Coaching state — lazy load, chỉ fetch khi user bấm "Sửa cách phát âm"
  PronunciationCoaching? _coaching;
  bool _loadingCoach = false;
  String? _coachError;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(milliseconds: 200), (_) {
      final rec = ref.read(voiceRecorderProvider);
      return rec.elapsed;
    });
  }

  Future<void> _startRecording() async {
    final rec = ref.read(voiceRecorderProvider);
    try {
      await rec.start();
      setState(() {
        _stage = _DialogStage.recording;
        _errorMsg = null;
      });
    } on VoiceRecorderException catch (e) {
      setState(() {
        _stage = _DialogStage.error;
        _errorMsg = e.message;
      });
    } catch (e) {
      setState(() {
        _stage = _DialogStage.error;
        _errorMsg = 'Không khởi động được microphone: $e';
      });
    }
  }

  Future<void> _stopAndScore() async {
    final rec = ref.read(voiceRecorderProvider);
    final api = ref.read(audioApiProvider);

    setState(() => _stage = _DialogStage.scoring);

    try {
      final result = await rec.stop();
      if (result == null) {
        setState(() {
          _stage = _DialogStage.error;
          _errorMsg = 'Không lấy được audio';
        });
        return;
      }

      final PronunciationResult scored;
      // Bỏ messageId nếu là local-id (chưa save xuống DB) — tránh 422 FK
      final mid = widget.messageId;
      final safeMessageId =
          (mid != null && !mid.startsWith('local-')) ? mid : null;
      if (kIsWeb || result.isWeb) {
        scored = await api.scorePronunciationFromBytes(
          bytes: result.bytes!,
          filename: result.filename,
          referenceText: widget.referenceText,
          language: widget.languageCode,
          sessionId: widget.sessionId,
          messageId: safeMessageId,
        );
      } else {
        scored = await api.scorePronunciation(
          filePath: result.filePath!,
          referenceText: widget.referenceText,
          language: widget.languageCode,
          sessionId: widget.sessionId,
          messageId: safeMessageId,
        );
      }

      setState(() {
        _result = scored;
        _stage = _DialogStage.result;
      });
    } catch (e) {
      setState(() {
        _stage = _DialogStage.error;
        _errorMsg = e is AppError ? e.message : e.toString();
      });
    }
  }

  Future<void> _cancelRecording() async {
    final rec = ref.read(voiceRecorderProvider);
    try {
      await rec.cancel();
    } catch (_) {}
    setState(() => _stage = _DialogStage.idle);
  }

  void _retry() {
    setState(() {
      _result = null;
      _errorMsg = null;
      _coaching = null;
      _coachError = null;
      _loadingCoach = false;
      _stage = _DialogStage.idle;
    });
  }

  Future<void> _fetchCoaching(PronunciationResult r) async {
    if (_loadingCoach || _coaching != null) return;
    setState(() {
      _loadingCoach = true;
      _coachError = null;
    });
    try {
      final api = ref.read(audioApiProvider);
      // Gửi cả 3 loại: wrong + missing + low-conf — backend tự phân loại
      // thành kind=wrong/missing/unclear qua alignment. Sort priority để
      // backend cap 3 thì lấy được lỗi nặng nhất trước.
      final priority = {'wrong': 0, 'missing': 1};
      final scored = r.words
          .where((w) =>
              w.status == 'wrong' ||
              w.status == 'missing' ||
              w.isLowConfidence)
          .toList()
        ..sort((a, b) {
          // Wrong/missing trước; low-conf (status=match) sau
          final pa = priority[a.status] ?? 2;
          final pb = priority[b.status] ?? 2;
          if (pa != pb) return pa.compareTo(pb);
          // Cùng tier → confidence thấp lên trước
          final ca = a.confidence ?? 1.0;
          final cb = b.confidence ?? 1.0;
          return ca.compareTo(cb);
        });
      final wrong = scored
          .map((w) => w.ref ?? w.got ?? '')
          .where((s) => s.isNotEmpty)
          .take(10)
          .toList();
      final coach = await api.getPronunciationCoaching(
        referenceText: widget.referenceText,
        transcription: r.transcription,
        wrongWords: wrong,
        language: widget.languageCode,
      );
      if (!mounted) return;
      setState(() {
        _coaching = coach;
        _loadingCoach = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _coachError = e.message;
        _loadingCoach = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _coachError = 'Không lấy được hướng dẫn: $e';
        _loadingCoach = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);  // subscribe để rebuild khi đổi theme
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.record_voice_over_outlined,
                      color: AppColors.primaryLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Luyện phát âm',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Text(
                  widget.referenceText,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Flexible để inner SingleChildScrollView của result được bounded
              // height — tránh overflow khi coaching cards dài hơn screen.
              Flexible(child: _buildStageContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case _DialogStage.idle:
        return _buildIdle();
      case _DialogStage.recording:
        return _buildRecording();
      case _DialogStage.scoring:
        return _buildScoring();
      case _DialogStage.result:
        return _buildResult(_result!);
      case _DialogStage.error:
        return _buildError();
    }
  }

  Widget _buildIdle() {
    return Column(
      children: [
        Text(
          'Bấm nút bên dưới và đọc to câu trên',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _startRecording,
            icon: const Icon(Icons.mic),
            label: const Text('Bắt đầu thu âm'),
          ),
        ),
      ],
    );
  }

  Widget _buildRecording() {
    return Column(
      children: [
        StreamBuilder<Duration>(
          stream: _ticker,
          initialData: Duration.zero,
          builder: (context, snap) {
            final d = snap.data ?? Duration.zero;
            final s = d.inSeconds;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Đang thu — ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _cancelRecording,
                child: const Text('Huỷ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _stopAndScore,
                icon: const Icon(Icons.stop),
                label: const Text('Dừng & chấm'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildScoring() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            'Đang chấm phát âm...',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(PronunciationResult r) {
    final pct = (r.score * 100).round();
    final color = switch (r.rating) {
      'good' => AppColors.success,
      'fair' => AppColors.warning,
      _ => AppColors.error,
    };
    final label = switch (r.rating) {
      'good' => 'Tốt',
      'fair' => 'Khá',
      _ => 'Cần luyện thêm',
    };
    // Có cần coaching không? Khi có wrong/missing hoặc từ low-conf
    final hasIssues = r.words.any((w) =>
        w.status == 'wrong' ||
        w.status == 'missing' ||
        w.isLowConfidence);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '$pct% — $label',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Phân tích từng chữ:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in r.words) _wordChip(w),
            ],
          ),
          if (r.transcription.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Bạn đọc: ${r.transcription}',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          // Coaching section — CTA hoặc cards tuỳ state
          if (hasIssues) ...[
            const SizedBox(height: 14),
            _buildCoachingSection(r),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Thử lại'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Xong'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoachingSection(PronunciationResult r) {
    // 3 state: chưa fetch → CTA, đang fetch → spinner, đã có → cards
    if (_coaching != null) {
      return _CoachingResultView(coaching: _coaching!);
    }
    if (_loadingCoach) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'AI đang phân tích vị trí lưỡi, môi, hơi thở...',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }
    if (_coachError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline,
                size: 16, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_coachError!,
                  style: TextStyle(
                      color: AppColors.error, fontSize: 12)),
            ),
            TextButton(
              onPressed: () => _fetchCoaching(r),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    // CTA pill
    return InkWell(
      onTap: () => _fetchCoaching(r),
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentOrange.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.tips_and_updates_rounded,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sửa cách phát âm',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Xem vị trí lưỡi, môi, hơi thở cho từng âm',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded,
                color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _wordChip(PronunciationWord w) {
    // Low-confidence override: match từ về text nhưng Whisper KHÔNG chắc cách
    // phát âm — chuyển sang warning vàng + dấu ~ để báo "đọc chưa rõ".
    final isLow = w.isLowConfidence;
    final (text, color) = switch (w.status) {
      'match' when isLow => (
        '~${w.ref ?? w.got ?? ''}',
        AppColors.warning,
      ),
      'match' => (w.ref ?? w.got ?? '', AppColors.success),
      'wrong' => ('${w.ref} → ${w.got}', AppColors.error),
      'missing' => ('${w.ref} ✕', AppColors.error),
      'extra' when isLow => ('~+${w.got}', AppColors.warning),
      'extra' => ('+${w.got}', AppColors.warning),
      _ => (w.ref ?? '', AppColors.textSecondary),
    };
    final confLabel =
        w.confidence != null ? ' ${(w.confidence! * 100).round()}%' : '';
    return Tooltip(
      message: isLow
          ? 'Whisper nghe chưa rõ từ này (${(w.confidence! * 100).round()}%)'
          : (w.confidence != null
              ? 'Confidence: ${(w.confidence! * 100).round()}%'
              : ''),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
        ),
        child: Text(
          '$text$confLabel',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        Icon(Icons.error_outline, color: AppColors.error, size: 32),
        const SizedBox(height: 8),
        Text(
          _errorMsg ?? 'Có lỗi xảy ra',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.error, fontSize: 13),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _retry, child: const Text('Thử lại')),
        ),
      ],
    );
  }
}

/// Hiển thị kết quả coaching từ LLM — 1 summary card + N cards cho từng từ sai.
/// Mỗi card: word + phoneme + 3 row (👅 Lưỡi, 👄 Môi, 💨 Hơi thở) + 💡 Tip.
class _CoachingResultView extends StatelessWidget {
  final PronunciationCoaching coaching;
  const _CoachingResultView({required this.coaching});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accentOrange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.accentOrange.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tips_and_updates_rounded,
                  size: 16, color: AppColors.accentOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  coaching.summary,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Per-word cards
        for (final item in coaching.items) ...[
          _CoachingCard(item: item),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CoachingCard extends StatelessWidget {
  final PronunciationCoachingItem item;
  const _CoachingCard({required this.item});

  // Mapping kind → (label, color, icon)
  ({String label, Color color, IconData icon, String? heardLabel}) _kindStyle() {
    switch (item.kind) {
      case 'missing':
        return (
          label: 'Bỏ qua',
          color: AppColors.error,
          icon: Icons.remove_circle_outline,
          heardLabel: null,
        );
      case 'unclear':
        return (
          label: 'Chưa rõ',
          color: AppColors.warning,
          icon: Icons.graphic_eq,
          heardLabel: 'cần đọc gọn hơn',
        );
      case 'wrong':
      default:
        return (
          label: 'Sai âm',
          color: AppColors.error,
          icon: Icons.close,
          heardLabel: item.heardAs.isNotEmpty
              ? 'bạn đọc: ${item.heardAs}'
              : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = _kindStyle();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: word + kind badge + phoneme + "heard as"
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                item.word,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // Kind badge — quan trọng nhất, hiển thị đầu
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ks.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: ks.color.withValues(alpha: 0.4), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(ks.icon, size: 11, color: ks.color),
                    const SizedBox(width: 4),
                    Text(
                      ks.label,
                      style: TextStyle(
                        color: ks.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.phoneme.isNotEmpty && item.phoneme != '—')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        width: 0.5),
                  ),
                  child: Text(
                    item.phoneme,
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              if (ks.heardLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hearing,
                          size: 11, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        ks.heardLabel!,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (item.context.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                      color:
                          AppColors.warning.withValues(alpha: 0.6),
                      width: 3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 13,
                      color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.context,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (item.tongue.isNotEmpty)
            _CoachingRow(
                emoji: '👅', label: 'Lưỡi', content: item.tongue),
          if (item.lips.isNotEmpty)
            _CoachingRow(emoji: '👄', label: 'Môi', content: item.lips),
          if (item.airflow.isNotEmpty)
            _CoachingRow(
                emoji: '💨', label: 'Hơi thở', content: item.airflow),
          if (item.tip.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.tip,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoachingRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String content;
  const _CoachingRow({
    required this.emoji,
    required this.label,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              content,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
