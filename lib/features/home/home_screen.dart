import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/language.dart';
import '../../core/models/session.dart';
import '../../core/models/vocabulary.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';

final _recentSessionsProvider =
    FutureProvider.autoDispose<List<ChatSession>>((ref) async {
  return ref.read(sessionsApiProvider).list(limit: 5);
});

final _homeVocabStatsProvider =
    FutureProvider.autoDispose<VocabStats>((ref) async {
  return ref.read(vocabularyApiProvider).getStats();
});

/// Quick Start item — gắn với 1 template trong DB qua `templateName`.
/// Khi tạo session, frontend tìm template theo name → dùng template_id để
/// session kế thừa system_prompt + out_of_scope_examples + cefr_level từ DB
/// (đồng nhất với khi user vào màn Templates và chọn). Tránh tình trạng
/// Quick Start dùng prompt cứng khác với Templates.
///
/// `contextPrompt` chỉ là fallback nếu không tìm thấy template khớp tên
/// (vd template bị xoá / DB không seed).
class _QuickStartItem {
  final String emoji;
  final String title;
  final String subtitle;
  final String templateName;   // match `templates.name` trong DB
  final String contextPrompt;  // fallback nếu không tìm thấy template
  final String defaultLanguage;
  final LinearGradient gradient;

  const _QuickStartItem({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.templateName,
    required this.contextPrompt,
    required this.defaultLanguage,
    required this.gradient,
  });
}

const _quickStartItems = <_QuickStartItem>[
  _QuickStartItem(
    emoji: '💬',
    title: 'Hội thoại tự do',
    subtitle: 'Trò chuyện về cuộc sống hàng ngày',
    templateName: 'Hội thoại tự do',
    contextPrompt: 'Hãy trò chuyện tự nhiên với tôi về cuộc sống hàng ngày.',
    defaultLanguage: 'vi',
    gradient: AppColors.cardGradient1,
  ),
  _QuickStartItem(
    emoji: '🌍',
    title: 'Luyện tiếng Anh',
    subtitle: 'Conversation practice',
    templateName: 'Luyện hội thoại',
    contextPrompt:
        'Let\'s practice English conversation. Correct my mistakes gently.',
    defaultLanguage: 'en',
    gradient: AppColors.cardGradient2,
  ),
  _QuickStartItem(
    emoji: '📝',
    title: 'Dịch thuật',
    subtitle: 'Dịch văn bản đa ngôn ngữ',
    templateName: 'Dịch thuật',
    contextPrompt:
        'Bạn là chuyên gia dịch thuật. Hãy dịch văn bản tôi đưa ra.',
    defaultLanguage: 'vi',
    gradient: AppColors.cardGradient3,
  ),
  _QuickStartItem(
    emoji: '✍️',
    title: 'Viết & Sửa văn',
    subtitle: 'Cải thiện văn phong',
    templateName: 'Góp ý bài viết',
    contextPrompt:
        'Bạn là biên tập viên. Giúp tôi cải thiện văn phong, ngữ pháp.',
    defaultLanguage: 'vi',
    gradient: AppColors.cardGradient4,
  ),
  _QuickStartItem(
    emoji: '📚',
    title: 'Học từ vựng',
    subtitle: 'Mở rộng vốn từ',
    templateName: 'Xây dựng từ vựng',
    contextPrompt:
        'Hãy giúp tôi học từ vựng mới: giải thích nghĩa, ví dụ.',
    defaultLanguage: 'vi',
    gradient: AppColors.cardGradient5,
  ),
  _QuickStartItem(
    emoji: '🎯',
    title: 'Phỏng vấn',
    subtitle: 'Luyện phỏng vấn xin việc',
    templateName: 'Nhập vai hội thoại',
    contextPrompt:
        'Bạn là chuyên gia tuyển dụng. Đặt câu hỏi phỏng vấn cho tôi.',
    defaultLanguage: 'vi',
    gradient: AppColors.cardGradient6,
  ),
];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);  // subscribe để rebuild khi đổi theme
    final recent = ref.watch(_recentSessionsProvider);
    final stats = ref.watch(_homeVocabStatsProvider);
    // Pre-fetch danh sách ngôn ngữ ngay khi vào home, tránh spinner khi mở bottom sheet
    ref.watch(languagesProvider);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.primaryLight,
            onRefresh: () async {
              ref.invalidate(_recentSessionsProvider);
              ref.invalidate(_homeVocabStatsProvider);
              await Future.wait([
                ref.read(_recentSessionsProvider.future),
                ref.read(_homeVocabStatsProvider.future),
              ]);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildHeader(context, ref, stats),
                // TODAY section — chỉ render khi user có data (>= 1 từ trong sổ tay
                // hoặc có session gần đây). Hide hẳn khi user mới đăng ký.
                SliverToBoxAdapter(
                  child: _TodaySection(
                    stats: stats,
                    recent: recent,
                  ),
                ),
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(title: 'Khám phá chủ đề'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.95,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final item = _quickStartItems[i];
                        return _QuickStartCard(
                          item: item,
                          onTap: () => _startQuickSession(context, ref, item),
                        );
                      },
                      // Chỉ hiển thị 4 Quick Start đầu (gọn home, còn lại
                      // user vào màn "Mẫu hội thoại" để xem đầy đủ)
                      childCount: _quickStartItems.length > 4
                          ? 4
                          : _quickStartItems.length,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Hội thoại gần đây',
                      action: TextButton(
                        onPressed: () => context.push(AppRoutes.sessions),
                        child: const Text('Xem tất cả',
                            style: TextStyle(color: AppColors.primaryLight)),
                      ),
                    ),
                  ),
                ),
                recent.when(
                  loading: () => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primaryLight),
                      ),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        e is AppError ? e.message : 'Lỗi tải hội thoại',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 20, vertical: 24),
                          child: _EmptyState(),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SessionTile(session: sessions[i]),
                          ),
                          childCount: sessions.length,
                        ),
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _BottomNav(currentIndex: 0),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<VocabStats> stats,
  ) {
    final streakDays = stats.maybeWhen(
      data: (s) => s.streakDays,
      orElse: () => 0,
    );
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Xin chào 👋',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  SizedBox(height: 2),
                  Text('AI Trợ lý Ngôn ngữ',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            // Streak badge — chỉ hiện khi streak >= 1; bấm vào → Stats screen
            if (streakDays > 0) ...[
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push(AppRoutes.stats),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text('$streakDays',
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              tooltip: 'Thống kê',
              onPressed: () => context.push(AppRoutes.stats),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.bar_chart,
                    color: AppColors.textPrimary, size: 22),
              ),
            ),
            IconButton(
              onPressed: () => context.push(AppRoutes.profile),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.person_outline,
                    color: AppColors.textPrimary, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startQuickSession(
    BuildContext context,
    WidgetRef ref,
    _QuickStartItem item,
  ) async {
    final lang = await _pickLanguage(context, ref, item.defaultLanguage);
    if (lang == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight)),
    );

    // Tìm template trong DB theo name. Nếu match → dùng template_id (kế thừa
    // system_prompt + out_of_scope_examples + cefr_level). Nếu không có thì
    // fallback contextPrompt cứng.
    String? templateId;
    try {
      final templates =
          await ref.read(templatesApiProvider).list(limit: 100);
      final match = templates
          .where((t) => t.name == item.templateName)
          .cast<dynamic>()
          .firstOrNull;
      if (match != null) templateId = match.id as String;
    } catch (_) {
      // Silent fail → fallback contextPrompt
    }

    try {
      final session = await ref.read(sessionsApiProvider).create(
            templateId: templateId,
            title: item.title,
            responseLanguage: lang,
            contextPrompt: templateId == null ? item.contextPrompt : null,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(_recentSessionsProvider);
      context.push(
        '${AppRoutes.chat}/${session.id}?title=${Uri.encodeComponent(session.title)}',
      );
    } on AppError catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  Future<String?> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    String defaultLang,
  ) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Consumer(
              builder: (ctx, ref, _) {
                final langs = ref.watch(languagesProvider);
                return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text('Chọn ngôn ngữ trả lời',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 16),
                langs.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primaryLight)),
                  ),
                  error: (_, _) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _LangChipFallback(code: 'vi', label: '🇻🇳 Tiếng Việt'),
                      _LangChipFallback(code: 'en', label: '🇬🇧 English'),
                    ],
                  ),
                  data: (list) {
                    final items = list.cast<Language>();
                    if (items.isEmpty) {
                      return Text('Không có ngôn ngữ',
                          style: TextStyle(color: AppColors.textSecondary));
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: items.map((l) {
                        final selected = l.code == defaultLang;
                        return GestureDetector(
                          onTap: () => Navigator.of(ctx).pop(l.code),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              gradient:
                                  selected ? AppColors.primaryGradient : null,
                              color: selected ? null : AppColors.surfaceCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? Colors.transparent
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(
                              '${l.flag} ${l.nativeName}',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Section "HÔM NAY" — feature DIFFERENTIATING vs ChatGPT.
/// Hiển thị: review queue card + stats row + resume last session.
/// Tự ẩn hoàn toàn khi user chưa có data (chưa lưu từ + chưa có session).
// ==========================================================
// Smart TODAY card — gộp 3 card (Review / Pronunciation / Resume) → 1
// Decide CTA dựa trên state:
//   1. Có due vocab → ưu tiên ôn từ
//   2. Else có session gần đây → tiếp tục session
//   3. Else (user mới) → bắt đầu chat
// Stats mini row + Pronunciation entry đã có ở Profile + Bottom nav,
// không lặp ở Home nữa để giữ giao diện tập trung 1 CTA chính.
// ==========================================================
class _TodaySection extends StatelessWidget {
  final AsyncValue<VocabStats> stats;
  final AsyncValue<List<ChatSession>> recent;
  const _TodaySection({required this.stats, required this.recent});

  @override
  Widget build(BuildContext context) {
    final vocabStats = stats.value;
    final recentList = recent.value;
    final hasDue = (vocabStats?.dueNow ?? 0) > 0;
    final hasRecent = (recentList ?? []).isNotEmpty;
    final hasVocab = (vocabStats?.total ?? 0) > 0;

    // User hoàn toàn mới → hide section, để Quick Start làm CTA
    if (!hasVocab && !hasRecent) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _SmartTodayCard(
        hasDue: hasDue,
        dueCount: vocabStats?.dueNow ?? 0,
        reviewedToday: vocabStats?.reviewedToday ?? 0,
        recentSession: hasRecent ? recentList!.first : null,
      ),
    );
  }
}

class _SmartTodayCard extends StatelessWidget {
  final bool hasDue;
  final int dueCount;
  final int reviewedToday;
  final ChatSession? recentSession;

  const _SmartTodayCard({
    required this.hasDue,
    required this.dueCount,
    required this.reviewedToday,
    required this.recentSession,
  });

  @override
  Widget build(BuildContext context) {
    // Decide content + route + gradient
    final String title;
    final String subtitle;
    final IconData icon;
    final LinearGradient gradient;
    final VoidCallback onTap;
    final Color shadowColor;

    if (hasDue) {
      title = '$dueCount từ cần ôn hôm nay';
      subtitle = reviewedToday > 0
          ? 'Đã ôn $reviewedToday từ · Tiếp tục để giữ streak'
          : 'Chỉ vài phút để giữ trí nhớ';
      icon = Icons.school;
      gradient = AppColors.primaryGradient;
      shadowColor = AppColors.primary;
      onTap = () => context.push(AppRoutes.review);
    } else if (recentSession != null) {
      title = 'Tiếp tục: ${recentSession!.title}';
      subtitle = '${recentSession!.messageCount} tin nhắn · Quay lại học';
      icon = Icons.chat_bubble;
      gradient = AppColors.accentGradient;
      shadowColor = AppColors.accent;
      onTap = () => context.push(
            '${AppRoutes.chat}/${recentSession!.id}?title=${Uri.encodeComponent(recentSession!.title)}',
          );
    } else {
      title = 'Bắt đầu hội thoại mới';
      subtitle = 'Chọn chủ đề bên dưới · AI sẽ dạy theo ngữ cảnh';
      icon = Icons.auto_awesome;
      gradient = AppColors.primaryGradient;
      shadowColor = AppColors.primary;
      onTap = () => context.push(AppRoutes.templates);
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: shadowColor.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward, color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangChipFallback extends StatelessWidget {
  final String code;
  final String label;
  const _LangChipFallback({required this.code, required this.label});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(color: AppColors.textPrimary)),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        ?action,
      ],
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  final _QuickStartItem item;
  final VoidCallback onTap;
  const _QuickStartCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: item.gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(item.emoji,
                    style: const TextStyle(fontSize: 22)),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final ChatSession session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(
          '${AppRoutes.chat}/${session.id}?title=${Uri.encodeComponent(session.title)}',
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.chat_bubble_outline,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(
                      '${session.messageCount} tin nhắn • ${_relativeTime(session.updatedAt)}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  static String _relativeTime(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'vừa xong';
    if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
    if (d.inHours < 24) return '${d.inHours} giờ trước';
    if (d.inDays < 7) return '${d.inDays} ngày trước';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.chat_outlined,
              size: 48, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text('Chưa có hội thoại nào',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('Chọn một chủ đề ở trên để bắt đầu',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  const _BottomNav({required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Trang chủ',
                active: currentIndex == 0,
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                label: 'Hội thoại',
                active: currentIndex == 1,
                onTap: () => context.push(AppRoutes.sessions),
              ),
              _NavItem(
                icon: Icons.menu_book_outlined,
                activeIcon: Icons.menu_book,
                label: 'Sổ tay',
                active: currentIndex == 2,
                onTap: () => context.push(AppRoutes.vocabulary),
              ),
              _NavItem(
                icon: Icons.dashboard_outlined,
                activeIcon: Icons.dashboard,
                label: 'Mẫu',
                active: currentIndex == 3,
                onTap: () => context.push(AppRoutes.templates),
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Hồ sơ',
                active: currentIndex == 4,
                onTap: () => context.push(AppRoutes.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primaryLight : AppColors.textTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
