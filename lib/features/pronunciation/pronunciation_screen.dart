import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/audio_api.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';
import '../chat/pronunciation_dialog.dart';

final _historyProvider =
    FutureProvider.autoDispose<List<PronunciationAttempt>>((ref) async {
  return ref.read(audioApiProvider).listPronunciationHistory(limit: 50);
});

final _statsProvider =
    FutureProvider.autoDispose<PronunciationStats>((ref) async {
  return ref.read(audioApiProvider).getPronunciationStats();
});

/// Màn hình "Luyện phát âm" — dedicated screen với header stats + list lịch sử.
class PronunciationScreen extends ConsumerWidget {
  const PronunciationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);  // subscribe để rebuild khi đổi theme
    final historyAsync = ref.watch(_historyProvider);
    final statsAsync = ref.watch(_statsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Luyện phát âm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(_historyProvider);
              ref.invalidate(_statsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_historyProvider);
          ref.invalidate(_statsProvider);
          await ref.read(_statsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatsHeader(asyncStats: statsAsync),
            const SizedBox(height: 20),
            Text(
              'Lịch sử luyện gần đây',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            historyAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    e is AppError ? e.message : 'Không tải được lịch sử',
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ),
              data: (items) => items.isEmpty
                  ? const _EmptyState()
                  : Column(
                      children: [
                        for (final a in items)
                          _AttemptCard(
                            attempt: a,
                            onTap: () => _showDetail(context, ref, a),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetail(
    BuildContext context,
    WidgetRef ref,
    PronunciationAttempt a,
  ) async {
    final shouldRetry = await showDialog<bool>(
      context: context,
      builder: (_) => _AttemptDetailDialog(attempt: a),
    );
    if (shouldRetry == true && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => PronunciationDialog(
          referenceText: a.referenceText,
          languageCode: a.language ?? 'en',
        ),
      );
      ref.invalidate(_historyProvider);
      ref.invalidate(_statsProvider);
    }
  }
}

/// Detail dialog — hiển thị lại phân tích lỗi của attempt cũ.
/// Trả về true nếu user muốn luyện lại, false/null khi đóng.
class _AttemptDetailDialog extends StatelessWidget {
  final PronunciationAttempt attempt;
  const _AttemptDetailDialog({required this.attempt});

  @override
  Widget build(BuildContext context) {
    final pct = (attempt.score * 100).round();
    final (color, label) = switch (attempt.rating) {
      'good' => (AppColors.success, 'Tốt'),
      'fair' => (AppColors.warning, 'Khá'),
      _ => (AppColors.error, 'Cần luyện thêm'),
    };

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
                  const Icon(Icons.history,
                      color: AppColors.primaryLight, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chi tiết lần luyện',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '$pct% — $label',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Câu cần đọc:',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Text(
                  attempt.referenceText,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (attempt.words.isNotEmpty) ...[
                Text(
                  'Phân tích từng chữ:',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final w in attempt.words) _wordChip(w),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (attempt.transcription.isNotEmpty) ...[
                Text(
                  'Bạn đã đọc:',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  attempt.transcription,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Đóng'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Luyện lại'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wordChip(PronunciationWord w) {
    final isLow = w.isLowConfidence;
    final (text, color) = switch (w.status) {
      'match' when isLow => ('~${w.ref ?? w.got ?? ''}', AppColors.warning),
      'match' => (w.ref ?? w.got ?? '', AppColors.success),
      'wrong' => ('${w.ref} → ${w.got}', AppColors.error),
      'missing' => ('${w.ref} ✕', AppColors.error),
      'extra' when isLow => ('~+${w.got}', AppColors.warning),
      'extra' => ('+${w.got}', AppColors.warning),
      _ => (w.ref ?? '', AppColors.textSecondary),
    };
    return Tooltip(
      message: isLow
          ? 'Whisper nghe chưa rõ (${(w.confidence! * 100).round()}%)'
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
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  final AsyncValue<PronunciationStats> asyncStats;
  const _StatsHeader({required this.asyncStats});

  @override
  Widget build(BuildContext context) {
    return asyncStats.when(
      loading: () => const _StatsSkeleton(),
      error: (_, _) => const SizedBox.shrink(),
      data: (s) {
        final avgPct = (s.avgScoreWeek * 100).round();
        final bestPct = (s.bestScore * 100).round();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.record_voice_over,
                      color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Tiến độ phát âm',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _StatTile(
                    value: '$avgPct%',
                    label: 'TB tuần này',
                  ),
                  _StatTile(
                    value: '$bestPct%',
                    label: 'Cao nhất',
                  ),
                  _StatTile(
                    value: '${s.streakDays}',
                    label: 'Streak',
                  ),
                  _StatTile(
                    value: '${s.totalAttempts}',
                    label: 'Lần luyện',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttemptCard extends StatelessWidget {
  final PronunciationAttempt attempt;
  final VoidCallback onTap;
  const _AttemptCard({required this.attempt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pct = (attempt.score * 100).round();
    final (color, label) = switch (attempt.rating) {
      'good' => (AppColors.success, 'Tốt'),
      'fair' => (AppColors.warning, 'Khá'),
      _ => (AppColors.error, 'Cần luyện'),
    };
    final dateStr = DateFormat('dd/MM HH:mm').format(attempt.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '$pct%',
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(color: color, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attempt.referenceText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                        if (attempt.wrongWords.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Sai: ${attempt.wrongWords.take(3).join(", ")}'
                              '${attempt.wrongWords.length > 3 ? "..." : ""}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.record_voice_over_outlined,
              color: AppColors.textTertiary, size: 40),
          SizedBox(height: 12),
          Text(
            'Chưa có lần luyện nào',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Vào màn Hội thoại → bấm ⋯ trên tin nhắn AI → "Luyện nói"\nđể bắt đầu',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
