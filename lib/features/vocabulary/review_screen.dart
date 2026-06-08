import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/vocabulary.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';

/// Flashcard review screen — Spaced Repetition flow.
///
/// UX (theo HTML design "_n t_p _ Card flip.html"):
/// 1. Load due → card đầu (mặt trước: word)
/// 2. Tap card → flip 3D sang mặt sau (definition + example)
/// 3. Pick 1 trong 4 rating: Quên / Khó / Ổn / Dễ với hint time
/// 4. POST /vocabulary/{id}/review → server áp SM-2 → next card
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen>
    with SingleTickerProviderStateMixin {
  List<Vocabulary> _queue = [];
  int _index = 0;
  bool _showAnswer = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  int _reviewedCount = 0;
  final Map<ReviewRating, int> _ratingCounts = {};
  bool _browseMode = false;
  int _streakDays = 0;

  late final AnimationController _flipCtrl;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _loadQueue();
    _loadStreak();
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vocabularyApiProvider);
      var queue = await api.listDue(limit: 50);
      _browseMode = queue.isEmpty;
      if (queue.isEmpty) {
        queue = await api.listRandom(limit: 20);
      }
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _index = 0;
        _showAnswer = false;
        _loading = false;
      });
      _flipCtrl.reset();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadStreak() async {
    try {
      final s = await ref.read(vocabularyApiProvider).getStats();
      if (!mounted) return;
      setState(() => _streakDays = s.streakDays);
    } catch (_) {/* best-effort */}
  }

  void _toggleAnswer() {
    if (_showAnswer) {
      _flipCtrl.reverse();
      setState(() => _showAnswer = false);
    } else {
      _flipCtrl.forward();
      setState(() => _showAnswer = true);
    }
  }

  Future<void> _submitRating(ReviewRating rating) async {
    if (_submitting || _index >= _queue.length) return;
    setState(() => _submitting = true);
    final current = _queue[_index];
    try {
      await ref.read(vocabularyApiProvider).review(current.id, rating);
      if (!mounted) return;
      _ratingCounts[rating] = (_ratingCounts[rating] ?? 0) + 1;
      _flipCtrl.reset();
      setState(() {
        _reviewedCount++;
        _index++;
        _showAnswer = false;
        _submitting = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final progress = _queue.isEmpty ? 0.0 : _index / _queue.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.navy, size: 24),
              ),
              Expanded(
                child: Center(
                  child: _queue.isEmpty
                      ? Text(
                          _browseMode ? 'Ôn ngẫu nhiên' : 'Ôn tập',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5C5870),
                          ),
                        )
                      : RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                            children: [
                              TextSpan(text: '${_index.clamp(0, _queue.length)}'),
                              TextSpan(
                                text: ' / ${_queue.length}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8C879E),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              if (_streakDays > 0) _StreakChip(days: _streakDays)
              else const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFFFE0D0),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error)),
        ),
      );
    }
    if (_queue.isEmpty) return _emptyState();
    if (_index >= _queue.length) return _completedState();
    return _buildCardView(_queue[_index]);
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4ED),
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: const Text('🎉', style: TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 14),
            const Text('Không có từ nào cần ôn',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                )),
            const SizedBox(height: 6),
            const Text(
              'Hoặc bạn chưa lưu từ nào, hoặc đã ôn xong hôm nay.\nQuay lại sau nhé!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF5C5870), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _completedState() {
    final again = _ratingCounts[ReviewRating.again] ?? 0;
    final hard = _ratingCounts[ReviewRating.hard] ?? 0;
    final good = _ratingCounts[ReviewRating.good] ?? 0;
    final easy = _ratingCounts[ReviewRating.easy] ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4ED),
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: const Text('✨', style: TextStyle(fontSize: 48)),
            ),
            const SizedBox(height: 14),
            Text('Hoàn thành $_reviewedCount thẻ!',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                )),
            const SizedBox(height: 20),
            _statRow('Quên', again, AppColors.error),
            _statRow('Khó', hard, const Color(0xFFFFB04A)),
            _statRow('Ổn', good, AppColors.primary),
            _statRow('Dễ', easy, const Color(0xFF2A6A52)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFE6E4EC)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Xong'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loadQueue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Ôn tiếp'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF5C5870), fontSize: 14)),
          const Spacer(),
          Text('$count',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  // ============================================================
  // Card view — front + back with 3D flip
  // ============================================================
  Widget _buildCardView(Vocabulary v) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _toggleAnswer,
                child: AnimatedBuilder(
                  animation: _flipCtrl,
                  builder: (_, _) {
                    final angle = _flipCtrl.value * math.pi;
                    final isFront = _flipCtrl.value < 0.5;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(angle),
                      child: isFront
                          ? _cardFront(v)
                          : Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(math.pi),
                              child: _cardBack(v),
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildRatingSection(v),
        ],
      ),
    );
  }

  Widget _cardFront(Vocabulary v) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 320),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6E4EC)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.06),
            offset: const Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1EC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_levelLabel(v)} · ${v.language.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              _TtsButton(text: v.word, language: v.language),
            ],
          ),
          const Spacer(),
          Center(
            child: Text(
              v.word,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                letterSpacing: -1.0,
              ),
            ),
          ),
          if (v.repetitions > 0) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                '🔁 ${v.repetitions} lần · EF ${v.easeFactor.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8C879E),
                ),
              ),
            ),
          ],
          const Spacer(),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bấm để xem nghĩa',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF8C879E),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF8C879E), size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardBack(Vocabulary v) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 320),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6E4EC)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.06),
            offset: const Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    v.word,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                _TtsButton(text: v.word, language: v.language, compact: true),
              ],
            ),
            const SizedBox(height: 18),
            if (v.definition != null) ...[
              const _CardSectionLabel('NGHĨA'),
              const SizedBox(height: 6),
              Text(
                v.definition!,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (v.example != null) ...[
              const _CardSectionLabel('VÍ DỤ'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5EF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE0D0)),
                ),
                child: Text(
                  v.example!,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.navy,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRatingSection(Vocabulary v) {
    if (!_showAnswer) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Đoán nghĩa trong đầu rồi lật thẻ',
          style: TextStyle(
            color: const Color(0xFF8C879E),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Bạn nhớ từ này tốt như nào?',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5C5870),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _RatingButton(
                label: 'Quên',
                timeHint: _hintFor(v, ReviewRating.again),
                color: AppColors.error,
                onTap: _submitting
                    ? null
                    : () => _submitRating(ReviewRating.again),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RatingButton(
                label: 'Khó',
                timeHint: _hintFor(v, ReviewRating.hard),
                color: const Color(0xFFFFB04A),
                onTap: _submitting
                    ? null
                    : () => _submitRating(ReviewRating.hard),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RatingButton(
                label: 'Ổn',
                timeHint: _hintFor(v, ReviewRating.good),
                color: AppColors.primary,
                onTap: _submitting
                    ? null
                    : () => _submitRating(ReviewRating.good),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RatingButton(
                label: 'Dễ',
                timeHint: _hintFor(v, ReviewRating.easy),
                color: const Color(0xFF2A6A52),
                onTap: _submitting
                    ? null
                    : () => _submitRating(ReviewRating.easy),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Hint khoảng thời gian next review hiển thị dưới mỗi rating button.
  /// Estimate dựa trên SM-2 logic (backend tính chính xác — đây chỉ là hint).
  String _hintFor(Vocabulary v, ReviewRating r) {
    if (r == ReviewRating.again) return '<1m';
    final ef = v.easeFactor;
    final reps = v.repetitions;
    // again resets; hard reduces interval; good keeps; easy multiplies
    if (reps == 0) {
      switch (r) {
        case ReviewRating.hard:
          return '6m';
        case ReviewRating.good:
          return '10m';
        case ReviewRating.easy:
          return '4 ngày';
        default:
          return '<1m';
      }
    }
    final interval = v.intervalDays;
    final factor = switch (r) {
      ReviewRating.hard => 1.2,
      ReviewRating.good => ef,
      ReviewRating.easy => ef * 1.3,
      _ => 0.0,
    };
    final days = (interval * factor).round().clamp(1, 9999);
    if (days < 1) return '<1 ngày';
    if (days == 1) return '1 ngày';
    if (days < 7) return '$days ngày';
    if (days < 30) {
      final w = (days / 7).round();
      return '$w tuần';
    }
    final m = (days / 30).round();
    return '$m tháng';
  }
}

// ============================================================
// UI helpers
// ============================================================

class _StreakChip extends StatelessWidget {
  final int days;
  const _StreakChip({required this.days});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD89C)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(
            '$days',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFFB23A20),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSectionLabel extends StatelessWidget {
  final String text;
  const _CardSectionLabel(this.text);
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

class _TtsButton extends ConsumerStatefulWidget {
  final String text;
  final String language;
  final bool compact;
  const _TtsButton({
    required this.text,
    required this.language,
    this.compact = false,
  });

  @override
  ConsumerState<_TtsButton> createState() => _TtsButtonState();
}

class _TtsButtonState extends ConsumerState<_TtsButton> {
  bool _loading = false;

  Future<void> _play() async {
    final text = widget.text.trim();
    if (_loading || text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final bytes = await ref.read(audioApiProvider).textToSpeech(
            text: text,
            languageCode: widget.language,
          );
      await ref.read(audioPlayerServiceProvider).play(
            messageId: 'vocab-tts',
            audioBytes: bytes,
          );
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 32.0 : 36.0;
    return Material(
      color: AppColors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _loading ? null : _play,
        child: SizedBox(
          width: size,
          height: size,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  final String label;
  final String timeHint;
  final Color color;
  final VoidCallback? onTap;
  const _RatingButton({
    required this.label,
    required this.timeHint,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: disabled
                  ? const Color(0xFFE6E4EC)
                  : color.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: disabled ? const Color(0xFFB6B2C2) : color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                timeHint,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: disabled
                      ? const Color(0xFFB6B2C2)
                      : color.withValues(alpha: 0.7),
                  fontFeatures: const [FontFeature.tabularFigures()],
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
// Helpers — level estimate from EF/repetitions
// ============================================================
String _levelLabel(Vocabulary v) {
  if (v.repetitions >= 3 && v.intervalDays >= 21) return 'C1';
  if (v.repetitions >= 2) return 'B2';
  if (v.repetitions >= 1) return 'B1';
  return 'A2';
}
