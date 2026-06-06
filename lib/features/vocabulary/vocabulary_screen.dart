import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/vocabulary.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/main_bottom_nav.dart';

final _vocabListProvider =
    FutureProvider.autoDispose<List<Vocabulary>>((ref) async {
  return ref.read(vocabularyApiProvider).list(limit: 200);
});

final _vocabStatsProvider =
    FutureProvider.autoDispose<VocabStats>((ref) async {
  return ref.read(vocabularyApiProvider).getStats();
});

enum _Filter { all, due, mastered, fresh, hard }

class VocabularyScreen extends ConsumerStatefulWidget {
  const VocabularyScreen({super.key});

  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final vocab = ref.watch(_vocabListProvider);
    final stats = ref.watch(_vocabStatsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      bottomNavigationBar: const MainBottomNav(currentIndex: 3),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(_vocabListProvider);
            ref.invalidate(_vocabStatsProvider);
            await ref.read(_vocabListProvider.future);
          },
          child: vocab.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  e is AppError ? e.message : 'Lỗi tải sổ tay',
                  style: const TextStyle(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (list) {
              final dueCount = stats.maybeWhen(
                data: (s) => s.dueNow,
                orElse: () => list.where((v) => v.isDueForReview).length,
              );
              final filtered = _applyFilter(list);
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  _Header(total: list.length),
                  const SizedBox(height: 16),
                  _ReviewBanner(
                    dueCount: dueCount,
                    total: list.length,
                    onTap: () async {
                      await context.push(AppRoutes.review);
                      ref.invalidate(_vocabListProvider);
                      ref.invalidate(_vocabStatsProvider);
                    },
                  ),
                  const SizedBox(height: 16),
                  _FilterChips(
                    selected: _filter,
                    counts: _countByFilter(list),
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: 14),
                  if (list.isEmpty)
                    _EmptyState()
                  else if (filtered.isEmpty)
                    _EmptyFilterState(filter: _filter)
                  else
                    ...filtered.map((v) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _VocabListItem(
                            vocab: v,
                            onTap: () => _showDetail(context, v),
                            onLongPress: () => _confirmDelete(context, v),
                          ),
                        )),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Vocabulary> _applyFilter(List<Vocabulary> all) {
    switch (_filter) {
      case _Filter.all:
        return all;
      case _Filter.due:
        return all.where((v) => v.isDueForReview).toList();
      case _Filter.mastered:
        return all.where(_isMastered).toList();
      case _Filter.fresh:
        return all.where((v) => v.repetitions == 0).toList();
      case _Filter.hard:
        return all.where((v) => v.easeFactor < 2.0).toList();
    }
  }

  Map<_Filter, int> _countByFilter(List<Vocabulary> all) {
    return {
      _Filter.all: all.length,
      _Filter.due: all.where((v) => v.isDueForReview).length,
      _Filter.mastered: all.where(_isMastered).length,
      _Filter.fresh: all.where((v) => v.repetitions == 0).length,
      _Filter.hard: all.where((v) => v.easeFactor < 2.0).length,
    };
  }

  Future<void> _confirmDelete(BuildContext context, Vocabulary v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Xoá từ này?',
            style: TextStyle(color: AppColors.navy)),
        content: Text('Xoá "${v.word}" khỏi sổ tay?',
            style: const TextStyle(color: Color(0xFF5C5870))),
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
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
              Row(
                children: [
                  Text(_langFlag(vocab.language),
                      style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(vocab.word,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (vocab.definition != null) ...[
                const _SectionEyebrow('NGHĨA'),
                const SizedBox(height: 6),
                Text(vocab.definition!,
                    style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 15,
                        height: 1.5)),
                const SizedBox(height: 16),
              ],
              if (vocab.example != null) ...[
                const _SectionEyebrow('VÍ DỤ'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5EF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFE0D0)),
                  ),
                  child: Text(vocab.example!,
                      style: const TextStyle(
                          color: AppColors.navy,
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

// ============================================================
// Header — eyebrow + h1 + count + add button
// ============================================================
class _Header extends StatelessWidget {
  final int total;
  const _Header({required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TỪ VỰNG CỦA BẠN',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Sổ tay ',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    '$total',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: -0.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Add button — placeholder, future: open add-word sheet
        Material(
          color: AppColors.navy,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Thêm từ thủ công — sắp ra mắt'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.add, color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Review banner — progress circle + due count + start button
// ============================================================
class _ReviewBanner extends StatelessWidget {
  final int dueCount;
  final int total;
  final VoidCallback onTap;
  const _ReviewBanner({
    required this.dueCount,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDue = dueCount > 0;
    final progress =
        total == 0 ? 0.0 : (1.0 - dueCount / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6E4EC)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.04),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          // Progress ring với số ở giữa
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0xFFFFE0D0),
                    valueColor:
                        AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                Text(
                  '$dueCount',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasDue
                      ? '$dueCount thẻ chờ ôn'
                      : 'Đã ôn xong hôm nay',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasDue
                      ? 'Spaced repetition · ~${(dueCount * 0.3).ceil()} phút'
                      : 'Quay lại sau hoặc ôn ngẫu nhiên',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8C879E),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasDue ? 'Bắt đầu' : 'Ôn',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Filter chips horizontal scroll
// ============================================================
class _FilterChips extends StatelessWidget {
  final _Filter selected;
  final Map<_Filter, int> counts;
  final ValueChanged<_Filter> onChanged;
  const _FilterChips({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (_Filter.all, 'Tất cả'),
      (_Filter.due, 'Đến hạn'),
      (_Filter.mastered, 'Đã thuộc'),
      (_Filter.fresh, 'Mới'),
      (_Filter.hard, 'Khó'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (f, label) = items[i];
          final isSel = f == selected;
          final count = counts[f] ?? 0;
          return InkWell(
            onTap: () => onChanged(f),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSel ? AppColors.navy : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isSel
                        ? AppColors.navy
                        : const Color(0xFFE6E4EC)),
              ),
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSel ? Colors.white : AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSel
                          ? Colors.white.withValues(alpha: 0.22)
                          : const Color(0xFFFFF1EC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isSel ? Colors.white : AppColors.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// List item — progress ring + word + def + chip + review time
// ============================================================
class _VocabListItem extends StatelessWidget {
  final Vocabulary vocab;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _VocabListItem({
    required this.vocab,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final progress = _masteryProgress(vocab);
    final ringColor = _ringColor(vocab);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6E4EC)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Progress ring 42×42
              SizedBox(
                width: 42,
                height: 42,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        strokeCap: StrokeCap.round,
                        backgroundColor: const Color(0xFFEFEDE6),
                        valueColor: AlwaysStoppedAnimation(ringColor),
                      ),
                    ),
                    Icon(
                      Icons.bookmark_rounded,
                      size: 14,
                      color: ringColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Word + definition
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            vocab.word,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          vocab.language.toLowerCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8C879E),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vocab.definition ?? '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF5C5870),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Trailing: review time + chip
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: ringColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _levelLabel(vocab),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: ringColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _nextReviewLabel(vocab),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8C879E),
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

// ============================================================
// Empty states
// ============================================================
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1EC),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: const Text('📚', style: TextStyle(fontSize: 36)),
          ),
          const SizedBox(height: 14),
          const Text(
            'Sổ tay còn trống',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Bấm 🤖 "AI gợi ý từ" trên tin nhắn AI để lưu vào sổ tay tự động',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF5C5870)),
          ),
        ],
      ),
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  final _Filter filter;
  const _EmptyFilterState({required this.filter});

  String _msg() {
    switch (filter) {
      case _Filter.due:
        return 'Không có từ nào đến hạn ôn.';
      case _Filter.mastered:
        return 'Chưa có từ nào đã thuộc.';
      case _Filter.fresh:
        return 'Không có từ mới chưa ôn.';
      case _Filter.hard:
        return 'Không có từ nào khó.';
      case _Filter.all:
        return 'Trống.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Text(
          _msg(),
          style: const TextStyle(fontSize: 13, color: Color(0xFF8C879E)),
        ),
      ),
    );
  }
}

class _SectionEyebrow extends StatelessWidget {
  final String text;
  const _SectionEyebrow(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: AppColors.primaryDark,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ============================================================
// Helpers — mastery progress + level
// Logic khớp backend stats: mastered = rep>=3 AND interval>=21
// ============================================================
double _masteryProgress(Vocabulary v) {
  if (v.repetitions == 0) return 0.05;
  if (v.repetitions == 1) return 0.25;
  if (v.repetitions == 2) return 0.50;
  final intervalFactor = (v.intervalDays / 30).clamp(0.0, 1.0);
  return (0.60 + intervalFactor * 0.40).clamp(0.0, 1.0);
}

bool _isMastered(Vocabulary v) =>
    v.repetitions >= 3 && v.intervalDays >= 21;

/// Ring color theo trạng thái: yellow=new, green=mastered, rose=hard, sun=mid
Color _ringColor(Vocabulary v) {
  if (_isMastered(v)) return const Color(0xFF2A6A52); // forest
  if (v.easeFactor < 2.0) return const Color(0xFFE55436); // rose/coral
  if (v.repetitions == 0) return const Color(0xFFFFB04A); // sun
  return AppColors.primary; // coral default
}

String _levelLabel(Vocabulary v) {
  // Heuristic: estimate CEFR-ish from EF + repetitions
  if (_isMastered(v)) return 'C1';
  if (v.repetitions >= 2) return 'B2';
  if (v.repetitions >= 1) return 'B1';
  return 'A2';
}

String _nextReviewLabel(Vocabulary v) {
  final next = v.nextReviewAt;
  if (next == null) return 'Mới';
  final now = DateTime.now();
  if (next.isBefore(now)) return 'Hôm nay';
  final diff = next.difference(now);
  if (diff.inHours < 24) return 'Hôm nay';
  if (diff.inDays == 1) return 'Ngày mai';
  if (diff.inDays < 7) return '${diff.inDays} ngày';
  if (diff.inDays < 30) {
    final weeks = (diff.inDays / 7).round();
    return '$weeks tuần';
  }
  final months = (diff.inDays / 30).round();
  return '$months tháng';
}

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
