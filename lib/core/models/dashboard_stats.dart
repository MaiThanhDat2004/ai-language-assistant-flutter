/// Model cho response của GET /stats/dashboard.
///
/// Tất cả số liệu để render Stats screen — KHÔNG fetch lẻ tẻ từng chart.
class DashboardStats {
  final List<MasteryBucket> vocabMastery;
  final List<ActivityPoint> activity14d;
  final List<PronunciationDailyAvg> pronunciation14d;
  final ContractMetrics contractMetrics;
  final VocabSummary vocabSummary;

  const DashboardStats({
    required this.vocabMastery,
    required this.activity14d,
    required this.pronunciation14d,
    required this.contractMetrics,
    required this.vocabSummary,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      vocabMastery: (json['vocab_mastery'] as List)
          .map((e) => MasteryBucket.fromJson(e as Map<String, dynamic>))
          .toList(),
      activity14d: (json['activity_14d'] as List)
          .map((e) => ActivityPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      pronunciation14d: (json['pronunciation_14d'] as List? ?? [])
          .map((e) =>
              PronunciationDailyAvg.fromJson(e as Map<String, dynamic>))
          .toList(),
      contractMetrics: ContractMetrics.fromJson(
          json['contract_metrics'] as Map<String, dynamic>),
      vocabSummary:
          VocabSummary.fromJson(json['vocab_summary'] as Map<String, dynamic>),
    );
  }
}

class PronunciationDailyAvg {
  final String date;
  final double avgScore;   // 0.0 - 1.0
  final int count;
  const PronunciationDailyAvg({
    required this.date,
    required this.avgScore,
    required this.count,
  });
  factory PronunciationDailyAvg.fromJson(Map<String, dynamic> j) =>
      PronunciationDailyAvg(
        date: j['date'] as String,
        avgScore: (j['avg_score'] as num).toDouble(),
        count: (j['count'] as num).toInt(),
      );
}

class MasteryBucket {
  final String label;
  final int count;
  const MasteryBucket({required this.label, required this.count});
  factory MasteryBucket.fromJson(Map<String, dynamic> j) =>
      MasteryBucket(label: j['label'] as String, count: (j['count'] as num).toInt());
}

class ActivityPoint {
  final String date; // ISO yyyy-mm-dd
  final int count;
  const ActivityPoint({required this.date, required this.count});
  factory ActivityPoint.fromJson(Map<String, dynamic> j) =>
      ActivityPoint(date: j['date'] as String, count: (j['count'] as num).toInt());
}

class ContractMetrics {
  final int totalAssistantMessages;
  final int refusals;
  final double refusalRate;
  final int languageRetries;
  final double languageRetryRate;
  final double avgResponseTimeMs;

  const ContractMetrics({
    required this.totalAssistantMessages,
    required this.refusals,
    required this.refusalRate,
    required this.languageRetries,
    required this.languageRetryRate,
    required this.avgResponseTimeMs,
  });

  factory ContractMetrics.fromJson(Map<String, dynamic> j) => ContractMetrics(
        totalAssistantMessages: (j['total_assistant_messages'] as num).toInt(),
        refusals: (j['refusals'] as num).toInt(),
        refusalRate: (j['refusal_rate'] as num).toDouble(),
        languageRetries: (j['language_retries'] as num).toInt(),
        languageRetryRate: (j['language_retry_rate'] as num).toDouble(),
        avgResponseTimeMs: (j['avg_response_time_ms'] as num).toDouble(),
      );
}

class VocabSummary {
  final int total;
  final int dueNow;
  final int reviewedToday;
  final int streakDays;

  const VocabSummary({
    required this.total,
    required this.dueNow,
    required this.reviewedToday,
    required this.streakDays,
  });

  factory VocabSummary.fromJson(Map<String, dynamic> j) => VocabSummary(
        total: (j['total'] as num).toInt(),
        dueNow: (j['due_now'] as num).toInt(),
        reviewedToday: (j['reviewed_today'] as num).toInt(),
        streakDays: (j['streak_days'] as num).toInt(),
      );
}
