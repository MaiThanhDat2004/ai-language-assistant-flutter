import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/vocabulary.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';

/// Flashcard review screen — Spaced Repetition flow.
///
/// UX:
/// 1. Load danh sách due → hiện thẻ đầu (mặt trước: word)
/// 2. User tap "Hiện đáp án" → flip card (mặt sau: definition + example)
/// 3. User chấm điểm 1 trong 4: Quên / Khó / Được / Dễ
/// 4. POST /vocabulary/{id}/review → server áp dụng SM-2
/// 5. Tự động chuyển sang thẻ tiếp theo, hoặc kết thúc nếu hết
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  List<Vocabulary> _queue = [];
  int _index = 0;
  bool _showAnswer = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  // Stats
  int _reviewedCount = 0;
  final Map<ReviewRating, int> _ratingCounts = {};
  // Self-test typing
  final _guessCtrl = TextEditingController();
  /// Kết quả check: null=chưa check, true=đúng, false=sai
  bool? _guessCorrect;
  /// Đang ở chế độ browse (không còn từ due, đang ôn ngẫu nhiên)
  bool _browseMode = false;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  @override
  void dispose() {
    _guessCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vocabularyApiProvider);
      // Ưu tiên từ due. Nếu không có → fallback random (browse mode)
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
        _guessCtrl.clear();
        _guessCorrect = null;
        _loading = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
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
      setState(() {
        _reviewedCount++;
        _index++;
        _showAnswer = false;
        _submitting = false;
        // Reset self-test state cho thẻ tiếp theo
        _guessCtrl.clear();
        _guessCorrect = null;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  /// Check guess của user với definition của từ.
  /// Match logic: lowercase + remove diacritics + check chứa keyword.
  /// Đơn giản đủ dùng cho V1; V2 có thể dùng fuzzy matching (Levenshtein).
  void _checkGuess() {
    if (_index >= _queue.length) return;
    final current = _queue[_index];
    final guess = _guessCtrl.text.trim();
    if (guess.isEmpty) return;

    final def = current.definition ?? '';
    final guessNorm = _normalize(guess);
    final defNorm = _normalize(def);

    // Match 2 chiều: guess chứa trong def HOẶC def chứa trong guess
    final correct = defNorm.contains(guessNorm) || guessNorm.contains(defNorm);
    setState(() {
      _guessCorrect = correct;
      _showAnswer = true; // luôn hiện đáp án sau khi check
    });
  }

  static String _normalize(String s) {
    var t = s.toLowerCase().trim();
    // Bỏ dấu tiếng Việt cơ bản — giúp match "ngây thơ" với "ngay tho"
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    var buf = StringBuffer();
    for (final c in t.split('')) {
      final i = from.indexOf(c);
      buf.write(i >= 0 ? to[i] : c);
    }
    // Bỏ punctuation
    return buf.toString().replaceAll(RegExp(r'[^\w\s]'), '').trim();
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
              _buildHeader(context),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final progress = _queue.isEmpty ? 0.0 : _index / _queue.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: Icon(Icons.arrow_back,
                    color: AppColors.textPrimary),
              ),
              Text(_browseMode ? 'Ôn ngẫu nhiên' : 'Ôn tập',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              if (_browseMode) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Browse',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight)),
                ),
              ],
              const Spacer(),
              if (_queue.isNotEmpty)
                Text(
                  '${_index.clamp(0, _queue.length)}/${_queue.length}',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_queue.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppColors.surface,
                valueColor: const AlwaysStoppedAnimation(
                    AppColors.primaryLight),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              style: const TextStyle(color: AppColors.error)),
        ),
      );
    }
    if (_queue.isEmpty) {
      return _emptyState();
    }
    if (_index >= _queue.length) {
      return _completedState();
    }
    return _buildFlashcard(_queue[_index]);
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
                gradient: AppColors.cardGradient4,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.celebration,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            Text('Không có từ nào cần ôn',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Hoặc bạn chưa lưu từ nào, hoặc đã ôn xong hôm nay.\nQuay lại sau nhé!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
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
                gradient: AppColors.cardGradient4,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.check_circle,
                  color: Colors.white, size: 48),
            ),
            const SizedBox(height: 16),
            Text('Hoàn thành $_reviewedCount thẻ!',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 24),
            _statRow('Quên', again, AppColors.error),
            _statRow('Khó', hard, AppColors.warning),
            _statRow('Được', good, AppColors.primaryLight),
            _statRow('Dễ', easy, AppColors.success),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Ôn tiếp',
                        style: TextStyle(color: Colors.white)),
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
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Text(label,
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const Spacer(),
          Text('$count',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildFlashcard(Vocabulary v) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildCardBody(v),
          const SizedBox(height: 24),
          _buildActionRow(v),
        ],
      ),
    );
  }

  Widget _buildCardBody(Vocabulary v) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 280),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient1,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  v.language.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              if (v.repetitions > 0)
                Text(
                  '🔁 ${v.repetitions} lần • EF ${v.easeFactor.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              v.word,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          if (_showAnswer) ...[
            const Divider(color: Colors.white24, height: 24),
            if (v.definition != null) ...[
              Text(
                'Định nghĩa',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              Text(
                v.definition!,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 16),
            ],
            if (v.example != null) ...[
              Text(
                'Ví dụ',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              Text(
                v.example!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ] else
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Hãy đoán nghĩa của từ này',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionRow(Vocabulary v) {
    if (!_showAnswer) {
      final canCheck = _guessCtrl.text.trim().isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'Tự kiểm tra — gõ nghĩa bạn đoán rồi bấm "Kiểm tra"',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          TextField(
            controller: _guessCtrl,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),  // để nút "Kiểm tra" enable/disable đúng
            onSubmitted: (_) => _checkGuess(),
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Định nghĩa bạn đoán...',
              hintStyle: TextStyle(color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppColors.primaryLight, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 2 nút song song — "Kiểm tra" primary, "Bỏ qua" outlined
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _showAnswer = true),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Bỏ qua',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: canCheck ? _checkGuess : null,
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text(
                      'Kiểm tra',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.surfaceLight,
                      disabledForegroundColor: AppColors.textTertiary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Sau khi reveal — nếu user đã guess, hiện feedback đúng/sai trước rating row
    final feedback = _guessCorrect == null
        ? const SizedBox.shrink()
        : Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (_guessCorrect!
                      ? AppColors.success
                      : AppColors.error)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_guessCorrect!
                        ? AppColors.success
                        : AppColors.error)
                    .withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _guessCorrect! ? Icons.check_circle : Icons.cancel,
                  color: _guessCorrect!
                      ? AppColors.success
                      : AppColors.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _guessCorrect!
                        ? 'Đoán đúng! Chọn "Được" hoặc "Dễ" để ghi nhận.'
                        : 'Chưa khớp. Xem định nghĩa trên và chọn "Quên" hoặc "Khó".',
                    style: TextStyle(
                      fontSize: 12,
                      color: _guessCorrect!
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          );

    return Column(
      children: [
        feedback,
        // 4 nút rating — màu tăng dần theo độ "thuộc"
        Row(
          children: [
            Expanded(
                child: _ratingButton(ReviewRating.again, AppColors.error)),
            const SizedBox(width: 8),
            Expanded(
                child: _ratingButton(ReviewRating.hard, AppColors.warning)),
            const SizedBox(width: 8),
            Expanded(
                child:
                    _ratingButton(ReviewRating.good, AppColors.primaryLight)),
            const SizedBox(width: 8),
            Expanded(
                child: _ratingButton(ReviewRating.easy, AppColors.success)),
          ],
        ),
      ],
    );
  }

  Widget _ratingButton(ReviewRating rating, Color color) {
    return Material(
      color: _submitting ? color.withValues(alpha: 0.4) : color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _submitting ? null : () => _submitRating(rating),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(_ratingIcon(rating), color: Colors.white, size: 22),
              const SizedBox(height: 4),
              Text(
                rating.label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _ratingIcon(ReviewRating r) {
    switch (r) {
      case ReviewRating.again:
        return Icons.close;
      case ReviewRating.hard:
        return Icons.sentiment_dissatisfied;
      case ReviewRating.good:
        return Icons.check;
      case ReviewRating.easy:
        return Icons.bolt;
    }
  }
}
