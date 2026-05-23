import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/vocabulary.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';

final _vocabListProvider =
    FutureProvider.autoDispose<List<Vocabulary>>((ref) async {
  return ref.read(vocabularyApiProvider).list(limit: 200);
});

final _vocabStatsProvider =
    FutureProvider.autoDispose<VocabStats>((ref) async {
  return ref.read(vocabularyApiProvider).getStats();
});

enum _VocabTab { learning, mastered }

class VocabularyScreen extends ConsumerStatefulWidget {
  const VocabularyScreen({super.key});

  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  _VocabTab _tab = _VocabTab.learning;

  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);  // subscribe để rebuild khi đổi theme
    final vocab = ref.watch(_vocabListProvider);
    final stats = ref.watch(_vocabStatsProvider);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              // Review banner — luôn hiện, có 2 trạng thái (due / done)
              stats.maybeWhen(
                data: (s) => s.total > 0
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _ReviewBanner(
                          dueCount: s.dueNow,
                          total: s.total,
                          reviewedToday: s.reviewedToday,
                          onTap: () async {
                            await context.push(AppRoutes.review);
                            ref.invalidate(_vocabListProvider);
                            ref.invalidate(_vocabStatsProvider);
                          },
                        ),
                      )
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),
              // Tab toggle Learning / Mastered (Stitch style)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _TabToggle(
                  selected: _tab,
                  learningCount: stats.maybeWhen(
                    data: (s) => _countLearning(vocab.valueOrNull ?? []),
                    orElse: () => 0,
                  ),
                  masteredCount: stats.maybeWhen(
                    data: (s) => _countMastered(vocab.valueOrNull ?? []),
                    orElse: () => 0,
                  ),
                  onChanged: (t) => setState(() => _tab = t),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    ref.invalidate(_vocabListProvider);
                    ref.invalidate(_vocabStatsProvider);
                    await ref.read(_vocabListProvider.future);
                  },
                  child: vocab.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                    error: (e, _) => Center(
                      child: Text(
                        e is AppError ? e.message : 'Lỗi tải sổ tay',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                    data: (list) {
                      if (list.isEmpty) return _emptyState();
                      final filtered = list.where(_matchesTab).toList();
                      if (filtered.isEmpty) return _emptyTabState();
                      return _buildGrid(context, filtered);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _matchesTab(Vocabulary v) {
    final mastered = _isMastered(v);
    return _tab == _VocabTab.mastered ? mastered : !mastered;
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          Text('Sổ tay từ vựng',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.menu_book,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text('Sổ tay đang trống',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Text(
                    'Khi chat với AI, bấm 🔖 trên tin nhắn để lưu từ vào sổ tay.\nAI sẽ tự tạo định nghĩa + ví dụ.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyTabState() {
    final msg = _tab == _VocabTab.mastered
        ? 'Chưa có từ nào thuộc nhóm "Thành thạo"'
        : 'Tất cả từ đã thuộc rồi 🎉';
    final sub = _tab == _VocabTab.mastered
        ? 'Ôn thường xuyên để đẩy từ lên mức thành thạo'
        : 'Lưu thêm từ mới khi chat để học tiếp';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _tab == _VocabTab.mastered
                  ? Icons.emoji_events_outlined
                  : Icons.school_outlined,
              color: AppColors.textTertiary,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<Vocabulary> list) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // childAspectRatio chọn 0.82 để card cao gần vuông, có chỗ cho def 3-4 dòng
        childAspectRatio: 0.82,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _VocabCard(
        vocab: list[i],
        onTap: () => _showDetail(context, list[i]),
        onLongPress: () => _confirmDelete(context, list[i]),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Vocabulary v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Xoá từ này?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Xoá "${v.word}" khỏi sổ tay?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Huỷ')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xoá', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(vocabularyApiProvider).delete(v.id);
      ref.invalidate(_vocabListProvider);
      ref.invalidate(_vocabStatsProvider);
    } on AppError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  void _showDetail(BuildContext context, Vocabulary vocab) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
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
              Row(
                children: [
                  Text(_langFlag(vocab.language),
                      style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(vocab.word,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (vocab.definition != null) ...[
                Text('Định nghĩa',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(vocab.definition!,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.5)),
                const SizedBox(height: 16),
              ],
              if (vocab.example != null) ...[
                Text('Ví dụ',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(vocab.example!,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                          fontStyle: FontStyle.italic)),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================================
// Helpers — mastery progress + mastered classification
// Logic khớp với backend stats: mastered = rep>=3 AND interval>=21
// ==========================================================
double _masteryProgress(Vocabulary v) {
  if (v.repetitions == 0) return 0.05;
  if (v.repetitions == 1) return 0.25;
  if (v.repetitions == 2) return 0.50;
  // rep >= 3 — kết hợp interval để chia 60-100%
  final intervalFactor = (v.intervalDays / 30).clamp(0.0, 1.0);
  return (0.60 + intervalFactor * 0.40).clamp(0.0, 1.0);
}

bool _isMastered(Vocabulary v) => v.repetitions >= 3 && v.intervalDays >= 21;

int _countLearning(List<Vocabulary> all) =>
    all.where((v) => !_isMastered(v)).length;
int _countMastered(List<Vocabulary> all) =>
    all.where(_isMastered).length;

String _langFlag(String code) {
  switch (code.toLowerCase()) {
    case 'vi':
      return '🇻🇳';
    case 'en':
      return '🇬🇧';
    case 'ja':
      return '🇯🇵';
    case 'ko':
      return '🇰🇷';
    case 'zh':
      return '🇨🇳';
    case 'fr':
      return '🇫🇷';
    case 'es':
      return '🇪🇸';
    case 'de':
      return '🇩🇪';
    default:
      return '🌐';
  }
}

// ==========================================================
// Tab toggle — pill segmented control giống Stitch
// ==========================================================
class _TabToggle extends StatelessWidget {
  final _VocabTab selected;
  final int learningCount;
  final int masteredCount;
  final ValueChanged<_VocabTab> onChanged;
  const _TabToggle({
    required this.selected,
    required this.learningCount,
    required this.masteredCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          _buildSegment(
            label: 'Đang học',
            count: learningCount,
            isSelected: selected == _VocabTab.learning,
            onTap: () => onChanged(_VocabTab.learning),
          ),
          _buildSegment(
            label: 'Thành thạo',
            count: masteredCount,
            isSelected: selected == _VocabTab.mastered,
            onTap: () => onChanged(_VocabTab.mastered),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryLight.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 16,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                count > 0 ? '$label ($count)' : label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================================
// Card từ vựng — style Stitch: word blue + def + progress bar
// ==========================================================
class _VocabCard extends StatelessWidget {
  final Vocabulary vocab;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _VocabCard({
    required this.vocab,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final progress = _masteryProgress(vocab);
    final pct = (progress * 100).round();

    return Material(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      // Soft shadow xuống dưới
      shadowColor: AppColors.textPrimary.withValues(alpha: 0.06),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Word (blue, bold)
              Text(
                vocab.word,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              // Definition (max 4 dòng để vừa với childAspectRatio 0.82)
              Expanded(
                child: Text(
                  vocab.definition ?? '—',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Progress bar + % + flag
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceLight,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primaryLight),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
}

class _ReviewBanner extends StatelessWidget {
  final int dueCount;
  final int total;
  final int reviewedToday;
  final VoidCallback onTap;
  const _ReviewBanner({
    required this.dueCount,
    required this.total,
    required this.reviewedToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDue = dueCount > 0;
    final gradient =
        hasDue ? AppColors.primaryGradient : AppColors.cardGradient3;
    final shadowColor =
        hasDue ? AppColors.primary : const Color(0xFF4FACFE);
    final title = hasDue
        ? '$dueCount từ cần ôn hôm nay'
        : 'Đã ôn xong hôm nay 🎉';
    final subtitle = hasDue
        ? 'Đã ôn $reviewedToday / Tổng $total từ'
        : 'Có $total từ trong sổ tay • Ôn ngẫu nhiên?';
    final icon = hasDue ? Icons.school : Icons.shuffle;

    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: shadowColor.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
