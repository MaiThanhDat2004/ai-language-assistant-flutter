import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_error.dart';
import '../../core/models/template.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';

final _templatesProvider =
    FutureProvider.autoDispose<List<Template>>((ref) async {
  return ref.read(templatesApiProvider).list(limit: 100);
});

class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);  // subscribe để rebuild khi đổi theme
    final templates = ref.watch(_templatesProvider);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildSearchBar(),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    ref.invalidate(_templatesProvider);
                    await ref.read(_templatesProvider.future);
                  },
                  child: templates.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                    error: (e, _) => Center(
                      child: Text(
                        e is AppError ? e.message : 'Lỗi tải',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                    data: (list) {
                      if (list.isEmpty) {
                        return Center(
                          child: Text('Chưa có mẫu nào',
                              style: TextStyle(
                                  color: AppColors.textSecondary)),
                        );
                      }
                      final filtered = _filter(list);
                      if (filtered.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off,
                                    color: AppColors.textTertiary, size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  'Không tìm thấy mẫu nào khớp "$_query"',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) => _TemplateCard(
                          template: filtered[i],
                          onUse: () =>
                              _useTemplate(context, ref, filtered[i]),
                          onToggleFav: () =>
                              _toggleFavorite(ref, filtered[i]),
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

  List<Template> _filter(List<Template> list) {
    if (_query.isEmpty) return list;
    final q = _query.toLowerCase();
    return list.where((t) {
      if (t.name.toLowerCase().contains(q)) return true;
      if ((t.description ?? '').toLowerCase().contains(q)) return true;
      if ((t.category ?? '').toLowerCase().contains(q)) return true;
      return false;
    }).toList();
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
          Text('Mẫu hội thoại',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim()),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Tìm mẫu hội thoại...',
          prefixIcon: Icon(Icons.search,
              color: AppColors.textTertiary, size: 22),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close,
                      color: AppColors.textTertiary, size: 20),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceLight,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Future<void> _useTemplate(
      BuildContext context, WidgetRef ref, Template t) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
    );
    try {
      final session = await ref.read(sessionsApiProvider).create(
            templateId: t.id,
            title: t.name,
            responseLanguage: t.defaultResponseLanguage,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop();
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

  Future<void> _toggleFavorite(WidgetRef ref, Template t) async {
    try {
      await ref
          .read(templatesApiProvider)
          .toggleFavorite(t.id, !t.isFavorite);
      ref.invalidate(_templatesProvider);
    } catch (_) {}
  }
}

// ==========================================================
// Category style mapping — icon + accent + tinted bg
// ==========================================================
class _CategoryStyle {
  final IconData icon;
  final Color accent;       // màu text + icon đậm
  final Color tintedBg;     // bg avatar nhạt tone với accent
  const _CategoryStyle({
    required this.icon,
    required this.accent,
    required this.tintedBg,
  });
}

const Map<String, _CategoryStyle> _categoryStyles = {
  'grammar': _CategoryStyle(
    icon: Icons.text_format,
    accent: Color(0xFF5B9BFF),
    tintedBg: Color(0xFFDCEEFF),
  ),
  'vocabulary': _CategoryStyle(
    icon: Icons.menu_book_outlined,
    accent: Color(0xFF10B981),
    tintedBg: Color(0xFFD1FAE5),
  ),
  'speaking': _CategoryStyle(
    icon: Icons.mic_outlined,
    accent: Color(0xFFFB8568),
    tintedBg: Color(0xFFFEE2D9),
  ),
  'reading': _CategoryStyle(
    icon: Icons.auto_stories_outlined,
    accent: Color(0xFF8B5CF6),
    tintedBg: Color(0xFFEDE9FE),
  ),
  'translation': _CategoryStyle(
    icon: Icons.translate,
    accent: Color(0xFF06B6D4),
    tintedBg: Color(0xFFCFFAFE),
  ),
  'writing': _CategoryStyle(
    icon: Icons.edit_note,
    accent: Color(0xFFF59E0B),
    tintedBg: Color(0xFFFEF3C7),
  ),
  'pronunciation': _CategoryStyle(
    icon: Icons.volume_up_outlined,
    accent: Color(0xFFEC4899),
    tintedBg: Color(0xFFFCE7F3),
  ),
  'general': _CategoryStyle(
    icon: Icons.chat_outlined,
    accent: Color(0xFF6B7280),
    tintedBg: Color(0xFFE5E7EB),
  ),
};

_CategoryStyle _styleFor(String? category) {
  if (category == null) return _categoryStyles['general']!;
  return _categoryStyles[category.toLowerCase()] ?? _categoryStyles['general']!;
}

// ==========================================================
// Template card — Stitch style: icon avatar + colored title + desc
// ==========================================================
class _TemplateCard extends StatelessWidget {
  final Template template;
  final VoidCallback onUse;
  final VoidCallback onToggleFav;
  const _TemplateCard({
    required this.template,
    required this.onUse,
    required this.onToggleFav,
  });

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(template.category);
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      shadowColor: AppColors.textPrimary.withValues(alpha: 0.06),
      elevation: 2,
      child: InkWell(
        onTap: onUse,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar icon — tinted bg + colored icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: style.tintedBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(style.icon, color: style.accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: style.accent,
                      ),
                    ),
                    if (template.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        template.description!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Favorite — gọn sang góc trên
              SizedBox(
                width: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.topCenter,
                  onPressed: onToggleFav,
                  icon: Icon(
                    template.isFavorite ? Icons.star : Icons.star_border,
                    color: template.isFavorite
                        ? AppColors.warning
                        : AppColors.textTertiary,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
