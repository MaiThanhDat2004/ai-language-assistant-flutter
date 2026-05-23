import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/session.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/utils/session_icon.dart';
import '../../shared/widgets/main_bottom_nav.dart';

final _sessionsListProvider =
    FutureProvider.autoDispose<List<ChatSession>>((ref) async {
  return ref.read(sessionsApiProvider).list(limit: 100);
});

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);  // subscribe để rebuild khi đổi theme
    final sessions = ref.watch(_sessionsListProvider);
    return Scaffold(
      bottomNavigationBar: const MainBottomNav(currentIndex: 1),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primaryLight,
                  onRefresh: () async {
                    ref.invalidate(_sessionsListProvider);
                    await ref.read(_sessionsListProvider.future);
                  },
                  child: sessions.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primaryLight)),
                    error: (e, _) => Center(
                      child: Text(
                        e is AppError ? e.message : 'Lỗi tải',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                    data: (list) {
                      if (list.isEmpty) {
                        return Center(
                          child: Text('Chưa có hội thoại nào',
                              style: TextStyle(
                                  color: AppColors.textSecondary)),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: list.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) => _SessionTile(
                          session: list[i],
                          onRename: () => _showRenameDialog(context, ref, list[i]),
                          onDelete: () => _confirmDelete(context, ref, list[i]),
                        ),
                      );
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

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Text('Hội thoại',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5)),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
      BuildContext context, WidgetRef ref, ChatSession session) async {
    final controller = TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Đổi tên hội thoại',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Tên mới',
            hintStyle: TextStyle(color: AppColors.textTertiary),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == session.title) {
      return;
    }
    try {
      await ref.read(sessionsApiProvider).update(session.id, title: newTitle);
      ref.invalidate(_sessionsListProvider);
    } on AppError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ChatSession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Xoá hội thoại?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Hội thoại "${session.title}" sẽ bị xoá vĩnh viễn.',
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
      await ref.read(sessionsApiProvider).delete(session.id);
      ref.invalidate(_sessionsListProvider);
    } on AppError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }
}

class _SessionTile extends StatelessWidget {
  final ChatSession session;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  const _SessionTile({
    required this.session,
    required this.onRename,
    required this.onDelete,
  });

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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1EC),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  emojiForSession(session),
                  style: const TextStyle(fontSize: 26),
                ),
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
                    Row(
                      children: [
                        Text(flagForLanguageCode(session.responseLanguage),
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 6),
                        Text(
                          '${session.messageCount} tin nhắn',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: AppColors.surface,
                icon: Icon(Icons.more_horiz,
                    color: AppColors.textTertiary),
                tooltip: 'Tuỳ chọn',
                onSelected: (v) {
                  if (v == 'rename') onRename();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined,
                            size: 18, color: AppColors.textPrimary),
                        SizedBox(width: 10),
                        Text('Đổi tên',
                            style: TextStyle(color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: AppColors.error),
                        SizedBox(width: 10),
                        Text('Xoá', style: TextStyle(color: AppColors.error)),
                      ],
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
