import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/language.dart';
import '../../core/models/session.dart';
import '../../core/models/user.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/utils/language_enforcement.dart';
import '../../shared/utils/session_icon.dart';
import '../../shared/widgets/main_bottom_nav.dart';

final _recentSessionsProvider =
    FutureProvider.autoDispose<List<ChatSession>>((ref) async {
  return ref.read(sessionsApiProvider).list(limit: 5);
});

/// Gợi ý chủ đề — 6 lựa chọn nhanh, hiển thị 3 đầu trên Home.
/// `templateName` khớp với `templates.name` trong DB → frontend tìm
/// template_id để session kế thừa system_prompt + scope + cefr_level.
/// `contextPrompt` chỉ fallback nếu DB không có template khớp.
class _TopicSuggestion {
  final String emoji;
  final String title;
  final String hint;
  final String templateName;
  final String contextPrompt;
  final String defaultLang;
  const _TopicSuggestion({
    required this.emoji,
    required this.title,
    required this.hint,
    required this.templateName,
    required this.contextPrompt,
    required this.defaultLang,
  });
}

const _topics = <_TopicSuggestion>[
  _TopicSuggestion(
    emoji: '☕',
    title: 'Gọi cà phê',
    hint: 'Beginner · 5 phút',
    templateName: 'Hội thoại tự do',
    contextPrompt:
        'Hãy đóng vai nhân viên quán cà phê. Tôi sẽ luyện gọi món bằng tiếng Anh.',
    defaultLang: 'en',
  ),
  _TopicSuggestion(
    emoji: '🏥',
    title: 'Đi khám bệnh',
    hint: 'B1 · 8 phút',
    templateName: 'Hội thoại tự do',
    contextPrompt:
        'Hãy đóng vai bác sĩ. Tôi sẽ luyện kể triệu chứng bằng tiếng Anh.',
    defaultLang: 'en',
  ),
  _TopicSuggestion(
    emoji: '🎓',
    title: 'Phỏng vấn',
    hint: 'B2 · 12 phút',
    templateName: 'Nhập vai hội thoại',
    contextPrompt:
        'Hãy đóng vai HR phỏng vấn vị trí entry-level bằng tiếng Anh.',
    defaultLang: 'en',
  ),
  _TopicSuggestion(
    emoji: '✈️',
    title: 'Du lịch',
    hint: 'A2 · 6 phút',
    templateName: 'Hội thoại tự do',
    contextPrompt:
        'Hãy đóng vai nhân viên sân bay. Tôi luyện check-in chuyến bay.',
    defaultLang: 'en',
  ),
  _TopicSuggestion(
    emoji: '💼',
    title: 'Họp công việc',
    hint: 'B1 · 10 phút',
    templateName: 'Nhập vai hội thoại',
    contextPrompt: 'Hãy mở đầu một buổi họp ngắn với đồng nghiệp bằng tiếng Anh.',
    defaultLang: 'en',
  ),
  _TopicSuggestion(
    emoji: '🛍️',
    title: 'Mua sắm',
    hint: 'A2 · 5 phút',
    templateName: 'Hội thoại tự do',
    contextPrompt:
        'Hãy đóng vai nhân viên cửa hàng. Tôi luyện hỏi giá, đổi size.',
    defaultLang: 'en',
  ),
];

// emoji + flag mapping moved to shared/utils/session_icon.dart

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(_recentSessionsProvider);
    final me = ref.watch(meProvider);
    ref.watch(languagesProvider); // pre-fetch

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0), // cream nhẹ, tone v1
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(_recentSessionsProvider);
            ref.invalidate(meProvider);
            await ref.read(_recentSessionsProvider.future);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Greeting(me: me),
                  const SizedBox(height: 20),
                  _HeroCard(
                    onChat: () => _startFreeChat(context, ref),
                    onVoice: () => _startFreeChat(context, ref, voice: true),
                  ),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: 'Gợi ý chủ đề',
                    actionLabel: 'Tất cả',
                    onAction: () => context.push(AppRoutes.templates),
                  ),
                  const SizedBox(height: 12),
                  _TopicRow(
                    onTap: (t) => _startTopic(context, ref, t),
                  ),
                  const SizedBox(height: 28),
                  _SectionHeader(title: 'Tiếp tục từ hôm qua'),
                  const SizedBox(height: 12),
                  _ContinueCard(recent: recent),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const MainBottomNav(currentIndex: 0),
    );
  }

  // ============================================================
  // Actions
  // ============================================================
  Future<void> _startFreeChat(
    BuildContext context,
    WidgetRef ref, {
    bool voice = false,
  }) async {
    final me = ref.read(meProvider).valueOrNull;
    final defaultLang = me?.preferredLanguage ?? 'en';
    final lang = await _pickLanguage(context, ref, defaultLang);
    if (lang == null || !context.mounted) return;
    await _createAndOpenSession(
      context,
      ref,
      title: voice ? 'Trò chuyện bằng giọng nói' : 'Trò chuyện tự do',
      lang: lang,
      templateName: 'Hội thoại tự do',
      contextPrompt: 'Hãy trò chuyện tự nhiên cùng tôi.',
    );
  }

  Future<void> _startTopic(
    BuildContext context,
    WidgetRef ref,
    _TopicSuggestion topic,
  ) async {
    final me = ref.read(meProvider).valueOrNull;
    final defaultLang = me?.preferredLanguage ?? topic.defaultLang;
    final lang = await _pickLanguage(context, ref, defaultLang);
    if (lang == null || !context.mounted) return;
    await _createAndOpenSession(
      context,
      ref,
      title: topic.title,
      lang: lang,
      templateName: topic.templateName,
      contextPrompt: topic.contextPrompt,
    );
  }

  Future<void> _createAndOpenSession(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String lang,
    required String templateName,
    required String contextPrompt,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
    String? templateId;
    try {
      final templates =
          await ref.read(templatesApiProvider).list(limit: 100);
      final match = templates
          .where((t) => t.name == templateName)
          .cast<dynamic>()
          .firstOrNull;
      if (match != null) templateId = match.id as String;
    } catch (_) {}

    try {
      // contextPrompt = câu lệnh ép ngôn ngữ + role-play nhập vai. Lệnh ép
      // ngôn ngữ đặt TRƯỚC để model gặp đầu tiên → tăng tỉ lệ Layer 1 thành
      // công với gemma2:2b khi topic gây bias (vd "Họp công việc" tiếng Anh).
      final session = await ref.read(sessionsApiProvider).create(
            templateId: templateId,
            title: title,
            responseLanguage: lang,
            contextPrompt: buildContextPrompt(
              langCode: lang,
              rolePlay: contextPrompt,
            ),
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Consumer(
              builder: (ctx, ref, _) {
                final langs = ref.watch(languagesProvider);
                return Column(
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
                    Text(
                      'Chọn ngôn ngữ trả lời',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    langs.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary)),
                      ),
                      error: (_, _) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _langChipFallback(ctx, 'vi', '🇻🇳 Tiếng Việt'),
                          _langChipFallback(ctx, 'en', '🇬🇧 English'),
                        ],
                      ),
                      data: (list) {
                        final items = list.cast<Language>();
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: items.map((l) {
                            final sel = l.code == defaultLang;
                            final flag = flagForLanguageCode(l.code);
                            return InkWell(
                              onTap: () => Navigator.of(ctx).pop(l.code),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: sel ? AppColors.primary : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: sel
                                        ? AppColors.primary
                                        : const Color(0xFFE6E4EC),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(flag,
                                        style: const TextStyle(fontSize: 16)),
                                    const SizedBox(width: 6),
                                    Text(
                                      l.nativeName,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: sel
                                            ? Colors.white
                                            : AppColors.navy,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _langChipFallback(BuildContext ctx, String code, String label) {
    return InkWell(
      onTap: () => Navigator.of(ctx).pop(code),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE6E4EC)),
        ),
        child: Text(label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            )),
      ),
    );
  }
}

// ============================================================
// Widgets
// ============================================================

class _Greeting extends StatelessWidget {
  final AsyncValue<User> me;
  const _Greeting({required this.me});

  String _hourGreeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Sẵn sàng học chưa?';
    if (h < 14) return 'Bữa trưa nhẹ nhàng?';
    if (h < 18) return 'Học chút buổi chiều?';
    return 'Tối nay luyện gì?';
  }

  String _firstName(User? u) {
    final full = (u?.fullName ?? u?.username ?? '').trim();
    if (full.isEmpty) return 'bạn';
    final parts = full.split(RegExp(r'\s+'));
    return parts.last;
  }

  String _avatarText(User? u) {
    final full = (u?.fullName ?? u?.username ?? '').trim();
    if (full.isEmpty) return 'B';
    final parts = full.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = me.valueOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _hourGreeting(),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5C5870),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Hi ${_firstName(user)} 👋',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: () => GoRouter.of(context).go(AppRoutes.profile),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              _avatarText(user),
              style: GoogleFonts.beVietnamPro(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final VoidCallback onChat;
  final VoidCallback onVoice;
  const _HeroCard({required this.onChat, required this.onVoice});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.20),
            offset: const Offset(0, 14),
            blurRadius: 30,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Concentric circles deco — góc phải trên
          Positioned(
            right: -40,
            top: -40,
            child: _Concentric(),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BẮT ĐẦU NGAY',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: AppColors.primaryLight,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Trò chuyện\nvới trợ lý AI',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.7,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Nói chuyện tự nhiên — AI sửa lỗi, gợi ý từ vựng theo trình độ.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _HeroBtn(
                      icon: Icons.chat_bubble_rounded,
                      label: 'Nhắn tin',
                      filled: true,
                      onTap: onChat,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HeroBtn(
                      icon: Icons.mic_rounded,
                      label: 'Gọi voice',
                      filled: false,
                      onTap: onVoice,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Concentric extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Colors.white.withValues(alpha: 0.08);
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(160, c),
          _ring(120, c),
          _ring(80, c),
        ],
      ),
    );
  }

  Widget _ring(double size, Color c) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c, width: 1.5),
      ),
    );
  }
}

class _HeroBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _HeroBtn({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? AppColors.primary : Colors.transparent;
    final border =
        filled ? AppColors.primary : Colors.white.withValues(alpha: 0.25);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
              letterSpacing: -0.4,
            ),
          ),
        ),
        if (actionLabel != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                actionLabel!,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TopicRow extends StatelessWidget {
  final void Function(_TopicSuggestion) onTap;
  const _TopicRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // 3 chip hiển thị, cuộn ngang để xem hết
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _topics.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _TopicChip(topic: _topics[i], onTap: () => onTap(_topics[i])),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  final _TopicSuggestion topic;
  final VoidCallback onTap;
  const _TopicChip({required this.topic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 138,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6E4EC)),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.04),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1EC),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(topic.emoji, style: const TextStyle(fontSize: 20)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  topic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  topic.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF8C879E),
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

class _ContinueCard extends StatelessWidget {
  final AsyncValue<List<ChatSession>> recent;
  const _ContinueCard({required this.recent});

  @override
  Widget build(BuildContext context) {
    return recent.when(
      loading: () => _shell(
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      ),
      error: (e, _) => _shell(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            e is AppError ? e.message : 'Không tải được phiên gần đây',
            style: GoogleFonts.beVietnamPro(color: AppColors.error, fontSize: 13),
          ),
        ),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return _shell(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1EC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Text('✨', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Chưa có phiên nào',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          'Chọn 1 chủ đề ở trên để bắt đầu',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF8C879E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final s = sessions.first;
        return _shell(
          child: InkWell(
            onTap: () => GoRouter.of(context).push(
              '${AppRoutes.chat}/${s.id}?title=${Uri.encodeComponent(s.title)}',
            ),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1EC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(emojiForSessionTitle(s.title),
                        style: const TextStyle(fontSize: 28)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _subtitle(s),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: const Color(0xFF8C879E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _subtitle(ChatSession s) {
    final lang = s.responseLanguage.toUpperCase();
    return '$lang · ${s.messageCount} tin nhắn';
  }

  Widget _shell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6E4EC)),
      ),
      child: child,
    );
  }
}
