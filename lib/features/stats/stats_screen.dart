import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error.dart';
import '../../core/models/dashboard_stats.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';

final _dashboardProvider = FutureProvider.autoDispose<DashboardStats>((ref) {
  return ref.read(statsApiProvider).dashboard();
});

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);  // subscribe để rebuild khi đổi theme
    final async = ref.watch(_dashboardProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Thống kê'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_dashboardProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  e is AppError ? e.message : 'Không tải được số liệu',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(_dashboardProvider),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(_dashboardProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryRow(summary: data.vocabSummary),
              const SizedBox(height: 20),
              _SectionTitle(
                title: 'Phân bố từ vựng theo SM-2',
                subtitle: 'Mức độ thuộc từ tăng dần →',
              ),
              const SizedBox(height: 12),
              _MasteryChart(buckets: data.vocabMastery),
              const SizedBox(height: 24),
              _SectionTitle(
                title: 'Hoạt động 14 ngày gần nhất',
                subtitle: 'Số chat/voice/ôn tập mỗi ngày',
              ),
              const SizedBox(height: 12),
              _ActivityChart(points: data.activity14d),
              const SizedBox(height: 24),
              _SectionTitle(
                title: 'Điểm phát âm 14 ngày',
                subtitle: 'Trung bình điểm mỗi ngày — tap để xem chi tiết',
              ),
              const SizedBox(height: 12),
              _PronunciationTrendChart(points: data.pronunciation14d),
              const SizedBox(height: 24),
              _SectionTitle(
                title: 'Chất lượng phản hồi của trợ lý',
                subtitle:
                    'Tỷ lệ giữ đúng ngôn ngữ & bám phạm vi học tập',
              ),
              const SizedBox(height: 12),
              _ContractCard(metrics: data.contractMetrics),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionTitle({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final VocabSummary summary;
  const _SummaryRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SummaryTile(
          icon: Icons.local_fire_department,
          color: const Color(0xFFFF9A56),
          label: 'Streak',
          value: '${summary.streakDays}',
          suffix: 'ngày',
        ),
        const SizedBox(width: 8),
        _SummaryTile(
          icon: Icons.menu_book,
          color: AppColors.primaryLight,
          label: 'Tổng từ',
          value: '${summary.total}',
        ),
        const SizedBox(width: 8),
        _SummaryTile(
          icon: Icons.access_time,
          color: AppColors.warning,
          label: 'Đến hạn',
          value: '${summary.dueNow}',
        ),
        const SizedBox(width: 8),
        _SummaryTile(
          icon: Icons.task_alt,
          color: AppColors.success,
          label: 'Hôm nay',
          value: '${summary.reviewedToday}',
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? suffix;
  const _SummaryTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (suffix != null)
              Text(
                suffix!,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MasteryChart extends StatelessWidget {
  final List<MasteryBucket> buckets;
  const _MasteryChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final maxY = buckets.isEmpty
        ? 1.0
        : (buckets.map((b) => b.count).reduce((a, b) => a > b ? a : b))
            .toDouble()
            .clamp(1.0, double.infinity);
    final colors = const [
      Color(0xFFFF9A56), // Mới
      Color(0xFFFFD93D), // Đang học
      Color(0xFF6C63FF), // Trẻ
      Color(0xFF4ECDC4), // Thành thạo
    ];

    return Container(
      height: 240,
      padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.2,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: AppColors.divider, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      buckets[i].label,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < buckets.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: buckets[i].count.toDouble(),
                    color: colors[i % colors.length],
                    width: 28,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityChart extends StatelessWidget {
  final List<ActivityPoint> points;
  const _ActivityChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final maxY = points.isEmpty
        ? 1.0
        : (points.map((p) => p.count).reduce((a, b) => a > b ? a : b))
            .toDouble()
            .clamp(1.0, double.infinity);

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY * 1.2,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: AppColors.divider, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  // Hiển thị mỗi 3 ngày để tránh đè chữ
                  if (i % 3 != 0 && i != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  final dd = points[i].date.substring(5); // mm-dd
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      dd,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].count.toDouble()),
              ],
              isCurved: true,
              curveSmoothness: 0.25,
              barWidth: 3,
              color: AppColors.primaryLight,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: 3,
                  color: AppColors.primaryLight,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primaryLight.withValues(alpha: 0.3),
                    AppColors.primaryLight.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PronunciationTrendChart extends StatelessWidget {
  final List<PronunciationDailyAvg> points;
  const _PronunciationTrendChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final hasData = points.any((p) => p.count > 0);
    if (!hasData) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        alignment: Alignment.center,
        child: Text(
          'Chưa có dữ liệu phát âm trong 14 ngày qua',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
      );
    }

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 1.0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 0.25,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: AppColors.divider, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 0.25,
                getTitlesWidget: (v, _) => Text(
                  '${(v * 100).round()}%',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  if (i % 3 != 0 && i != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  final dd = points[i].date.substring(5);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      dd,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              // Skip ngày không có attempt (count=0) bằng cách render điểm null
              spots: [
                for (var i = 0; i < points.length; i++)
                  if (points[i].count > 0)
                    FlSpot(i.toDouble(), points[i].avgScore),
              ],
              isCurved: false,
              barWidth: 3,
              color: AppColors.accentOrange,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: AppColors.accentOrange,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.accentOrange.withValues(alpha: 0.3),
                    AppColors.accentOrange.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _ContractCard extends StatelessWidget {
  final ContractMetrics metrics;
  const _ContractCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final total = metrics.totalAssistantMessages;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          _MetricRow(
            icon: Icons.forum_outlined,
            label: 'Tổng tin nhắn AI',
            value: '$total',
            color: AppColors.primaryLight,
          ),
          const SizedBox(height: 12),
          _MetricRow(
            icon: Icons.block,
            label: 'Refusal off-scope',
            value:
                '${metrics.refusals} (${(metrics.refusalRate * 100).toStringAsFixed(1)}%)',
            color: AppColors.error,
          ),
          const SizedBox(height: 12),
          _MetricRow(
            icon: Icons.translate,
            label: 'Sửa ngôn ngữ (retry > 0)',
            value:
                '${metrics.languageRetries} (${(metrics.languageRetryRate * 100).toStringAsFixed(1)}%)',
            color: AppColors.warning,
          ),
          const SizedBox(height: 12),
          _MetricRow(
            icon: Icons.speed,
            label: 'Thời gian phản hồi TB',
            value:
                '${metrics.avgResponseTimeMs.toStringAsFixed(0)} ms',
            color: AppColors.success,
          ),
          if (total == 0) ...[
            const SizedBox(height: 12),
            Text(
              'Chưa có tin nhắn AI nào — chat thử vài câu để có số liệu.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
