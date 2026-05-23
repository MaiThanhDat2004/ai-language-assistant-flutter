import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_config.dart';
import '../../core/api/audio_api.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/user.dart';
import '../../core/models/vocabulary.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';

final _meProvider = FutureProvider.autoDispose<User>((ref) async {
  return ref.read(authApiProvider).getMe();
});

final _profileVocabStatsProvider =
    FutureProvider.autoDispose<VocabStats>((ref) async {
  return ref.read(vocabularyApiProvider).getStats();
});

final _profilePronunStatsProvider =
    FutureProvider.autoDispose<PronunciationStats>((ref) async {
  return ref.read(audioApiProvider).getPronunciationStats();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(_meProvider);
    final vocabStats = ref.watch(_profileVocabStatsProvider);
    final pronunStats = ref.watch(_profilePronunStatsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: me.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary)),
                  error: (e, _) => Center(
                    child: Text(
                      e is AppError ? e.message : 'Lỗi tải hồ sơ',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                  data: (user) => RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      ref.invalidate(_meProvider);
                      ref.invalidate(_profileVocabStatsProvider);
                      ref.invalidate(_profilePronunStatsProvider);
                      await ref.read(_meProvider.future);
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _HeroCard(
                          user: user,
                          onAvatarTap: () =>
                              _pickAndUploadAvatar(context, ref),
                        ),
                        const SizedBox(height: 16),
                        _StatsRow(
                          vocabStats: vocabStats,
                          pronunStats: pronunStats,
                        ),
                        const SizedBox(height: 20),
                        const _SectionTitle('Tài khoản'),
                        const SizedBox(height: 8),
                        _InfoCard(items: [
                          _InfoItem(
                            icon: Icons.alternate_email,
                            iconBg: const Color(0xFFDCEEFF),
                            iconColor: const Color(0xFF5B9BFF),
                            label: 'Tên đăng nhập',
                            value: user.username,
                          ),
                          _InfoItem(
                            icon: Icons.email_outlined,
                            iconBg: const Color(0xFFFEE2D9),
                            iconColor: const Color(0xFFFB8568),
                            label: 'Email',
                            value: user.email,
                          ),
                          _InfoItem(
                            icon: Icons.calendar_today_outlined,
                            iconBg: const Color(0xFFEDE9FE),
                            iconColor: const Color(0xFF8B5CF6),
                            label: 'Ngày tạo tài khoản',
                            value:
                                '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}',
                          ),
                        ]),
                        const SizedBox(height: 20),
                        const _SectionTitle('Học tập'),
                        const SizedBox(height: 8),
                        _InfoCard(items: [
                          _InfoItem(
                            icon: Icons.language,
                            iconBg: const Color(0xFFD1FAE5),
                            iconColor: const Color(0xFF10B981),
                            label: 'Ngôn ngữ ưa thích',
                            value: _langName(user.preferredLanguage),
                          ),
                          _InfoItem(
                            icon: Icons.bar_chart,
                            iconBg: const Color(0xFFCFFAFE),
                            iconColor: const Color(0xFF06B6D4),
                            label: 'Thống kê chi tiết',
                            value: 'Xem biểu đồ tiến độ',
                            onTap: () => context.push(AppRoutes.stats),
                          ),
                          _InfoItem(
                            icon: Icons.record_voice_over,
                            iconBg: const Color(0xFFFCE7F3),
                            iconColor: const Color(0xFFEC4899),
                            label: 'Luyện phát âm',
                            value: 'Xem lịch sử + chấm điểm',
                            onTap: () => context.push(AppRoutes.pronunciation),
                          ),
                          _InfoItem(
                            icon: Icons.menu_book_outlined,
                            iconBg: const Color(0xFFFEF3C7),
                            iconColor: const Color(0xFFF59E0B),
                            label: 'Sổ tay từ vựng',
                            value: 'Quản lý + ôn tập SM-2',
                            onTap: () =>
                                context.push(AppRoutes.vocabulary),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        const _SectionTitle('Tuỳ chỉnh hiển thị'),
                        const SizedBox(height: 8),
                        _InfoCard(items: [
                          _InfoItem(
                            icon: isDark
                                ? Icons.dark_mode
                                : Icons.light_mode,
                            iconBg: isDark
                                ? const Color(0xFF353B7A)
                                : const Color(0xFFFEF3C7),
                            iconColor: isDark
                                ? const Color(0xFFCFE5F7)
                                : const Color(0xFFF59E0B),
                            label: 'Chế độ giao diện',
                            value: isDark
                                ? 'Đang dùng: Tối — chạm để chuyển Sáng'
                                : 'Đang dùng: Sáng — chạm để chuyển Tối',
                            onTap: () => ref
                                .read(themeModeProvider.notifier)
                                .toggle(),
                          ),
                        ]),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmLogout(context, ref),
                            icon: const Icon(Icons.logout,
                                color: AppColors.error),
                            label: const Text('Đăng xuất',
                                style: TextStyle(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.error),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          Text('Hồ sơ',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  /// Pick image từ gallery → upload → invalidate _meProvider để reload avatar.
  Future<void> _pickAndUploadAvatar(
      BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Không mở được thư viện ảnh: $e'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    if (picked == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Đang tải ảnh lên...'),
      duration: Duration(seconds: 10),
    ));

    try {
      // Web: image_picker trả blob URL → phải dùng bytes
      // Mobile/desktop: filePath thật → dùng fromFile (nhanh hơn, không load hết vào RAM)
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        await ref.read(authApiProvider).uploadAvatarFromBytes(
              bytes: bytes,
              filename: picked.name,
            );
      } else {
        await ref
            .read(authApiProvider)
            .uploadAvatar(filePath: picked.path);
      }
      ref.invalidate(_meProvider);
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text('✓ Đã cập nhật ảnh đại diện'),
        backgroundColor: AppColors.success,
      ));
    } on AppError catch (e) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Đăng xuất?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Bạn sẽ cần đăng nhập lại lần sau.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Huỷ')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Đăng xuất',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authStateProvider.notifier).logout();
  }
}

String _langName(String? code) {
  switch ((code ?? '').toLowerCase()) {
    case 'vi':
      return 'Tiếng Việt';
    case 'en':
      return 'English';
    case 'ja':
      return '日本語';
    case 'ko':
      return '한국어';
    case 'zh':
      return '中文';
    case 'fr':
      return 'Français';
    case 'es':
      return 'Español';
    case 'de':
      return 'Deutsch';
    default:
      return code == null || code.isEmpty ? 'Chưa đặt' : code.toUpperCase();
  }
}

// ==========================================================
// Hero card — avatar gradient + name + email
// Tap avatar → pick + upload ảnh mới.
// ==========================================================
class _HeroCard extends StatelessWidget {
  final User user;
  final VoidCallback onAvatarTap;
  const _HeroCard({required this.user, required this.onAvatarTap});

  @override
  Widget build(BuildContext context) {
    final initial =
        user.username.isNotEmpty ? user.username[0].toUpperCase() : '?';
    final hasAvatar =
        user.avatarUrl != null && user.avatarUrl!.isNotEmpty;
    // Backend trả URL relative `/uploads/avatars/...` → ghép baseUrl
    final fullAvatarUrl = hasAvatar
        ? (user.avatarUrl!.startsWith('http')
            ? user.avatarUrl!
            : '${ApiConfig.baseUrl}${user.avatarUrl}')
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onAvatarTap,
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4), width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: fullAvatarUrl != null
                        ? CachedNetworkImage(
                            imageUrl: fullAvatarUrl,
                            fit: BoxFit.cover,
                            width: 72,
                            height: 72,
                            placeholder: (_, _) => _avatarFallback(initial),
                            errorWidget: (_, _, _) =>
                                _avatarFallback(initial),
                          )
                        : _avatarFallback(initial),
                  ),
                ),
                // Camera badge ở góc dưới phải để gợi ý "đổi avatar"
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt,
                        color: AppColors.primary, size: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName ?? user.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _avatarFallback(String initial) {
  return Container(
    color: Colors.white.withValues(alpha: 0.0),
    alignment: Alignment.center,
    child: Text(
      initial,
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );
}

// ==========================================================
// Stats row — Streak / Vocab / Pronunciation
// ==========================================================
class _StatsRow extends StatelessWidget {
  final AsyncValue<VocabStats> vocabStats;
  final AsyncValue<PronunciationStats> pronunStats;
  const _StatsRow({required this.vocabStats, required this.pronunStats});

  @override
  Widget build(BuildContext context) {
    final streak = vocabStats.maybeWhen(
      data: (s) => s.streakDays,
      orElse: () => 0,
    );
    final totalVocab = vocabStats.maybeWhen(
      data: (s) => s.total,
      orElse: () => 0,
    );
    final mastered = vocabStats.maybeWhen(
      data: (s) => s.mastered,
      orElse: () => 0,
    );
    final pronunBest = pronunStats.maybeWhen(
      data: (s) => (s.bestScore * 100).round(),
      orElse: () => 0,
    );

    return Row(
      children: [
        _StatTile(
          icon: Icons.local_fire_department,
          color: const Color(0xFFFB8568),
          value: '$streak',
          label: 'Streak',
        ),
        const SizedBox(width: 10),
        _StatTile(
          icon: Icons.menu_book,
          color: const Color(0xFF5B9BFF),
          value: '$totalVocab',
          label: 'Tổng từ',
        ),
        const SizedBox(width: 10),
        _StatTile(
          icon: Icons.task_alt,
          color: const Color(0xFF10B981),
          value: '$mastered',
          label: 'Đã thuộc',
        ),
        const SizedBox(width: 10),
        _StatTile(
          icon: Icons.record_voice_over,
          color: const Color(0xFFEC4899),
          value: '$pronunBest%',
          label: 'Phát âm',
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                )),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// Section title
// ==========================================================
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ==========================================================
// Info card group — wrap list of _InfoItem trong 1 white card
// ==========================================================
class _InfoCard extends StatelessWidget {
  final List<_InfoItem> items;
  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Divider(
                    color: AppColors.divider.withValues(alpha: 0.6),
                    height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _InfoItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right,
                  color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
