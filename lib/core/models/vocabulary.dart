/// Đánh giá khả năng nhớ — mapping với rating của SM-2 ở backend.
/// Tên enum (name) khớp chính xác với string backend expect: 'again' | 'hard' | 'good' | 'easy'.
enum ReviewRating {
  again,  // quên hoàn toàn → restart
  hard,   // nhớ khó khăn → interval rút lại
  good,   // nhớ bình thường (default)
  easy,   // nhớ rất dễ → interval kéo dài
}

extension ReviewRatingX on ReviewRating {
  /// Nhãn tiếng Việt hiển thị trên UI flashcard.
  String get label {
    switch (this) {
      case ReviewRating.again:
        return 'Quên';
      case ReviewRating.hard:
        return 'Khó';
      case ReviewRating.good:
        return 'Được';
      case ReviewRating.easy:
        return 'Dễ';
    }
  }
}

/// Thống kê deck từ vựng — phục vụ home screen + báo cáo Chương 4.
class VocabStats {
  final int total;
  final int dueNow;
  final int learning;
  final int mastered;
  final int reviewedToday;
  final double avgEaseFactor;
  final int streakDays;

  const VocabStats({
    required this.total,
    required this.dueNow,
    required this.learning,
    required this.mastered,
    required this.reviewedToday,
    required this.avgEaseFactor,
    required this.streakDays,
  });

  factory VocabStats.fromJson(Map<String, dynamic> json) => VocabStats(
        total: (json['total'] as int?) ?? 0,
        dueNow: (json['due_now'] as int?) ?? 0,
        learning: (json['learning'] as int?) ?? 0,
        mastered: (json['mastered'] as int?) ?? 0,
        reviewedToday: (json['reviewed_today'] as int?) ?? 0,
        avgEaseFactor: ((json['avg_ease_factor'] as num?) ?? 2.5).toDouble(),
        streakDays: (json['streak_days'] as int?) ?? 0,
      );
}

/// Candidate trả về từ /vocabulary/extract — chưa được lưu DB.
class VocabularyCandidate {
  final String word;
  final String? definition;
  final String? example;

  const VocabularyCandidate({
    required this.word,
    this.definition,
    this.example,
  });

  factory VocabularyCandidate.fromJson(Map<String, dynamic> json) =>
      VocabularyCandidate(
        word: json['word'] as String,
        definition: json['definition'] as String?,
        example: json['example'] as String?,
      );
}

class Vocabulary {
  final String id;
  final String word;
  final String language;
  final String? definition;
  final String? example;
  final String? notes;
  final String? sourceMessageId;
  final int repetitions;
  final int intervalDays;
  final double easeFactor;
  final DateTime? lastReviewedAt;
  final DateTime? nextReviewAt;
  final DateTime createdAt;

  const Vocabulary({
    required this.id,
    required this.word,
    required this.language,
    this.definition,
    this.example,
    this.notes,
    this.sourceMessageId,
    required this.repetitions,
    required this.intervalDays,
    required this.easeFactor,
    this.lastReviewedAt,
    this.nextReviewAt,
    required this.createdAt,
  });

  bool get isDueForReview {
    if (nextReviewAt == null) return false;
    return nextReviewAt!.isBefore(DateTime.now());
  }

  factory Vocabulary.fromJson(Map<String, dynamic> json) => Vocabulary(
        id: json['id'] as String,
        word: json['word'] as String,
        language: json['language'] as String,
        definition: json['definition'] as String?,
        example: json['example'] as String?,
        notes: json['notes'] as String?,
        sourceMessageId: json['source_message_id'] as String?,
        repetitions: (json['repetitions'] as int?) ?? 0,
        intervalDays: (json['interval_days'] as int?) ?? 0,
        easeFactor: ((json['ease_factor'] as num?) ?? 2.5).toDouble(),
        lastReviewedAt: json['last_reviewed_at'] != null
            ? DateTime.parse(json['last_reviewed_at'] as String)
            : null,
        nextReviewAt: json['next_review_at'] != null
            ? DateTime.parse(json['next_review_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
