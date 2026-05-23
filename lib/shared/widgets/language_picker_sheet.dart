import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/language.dart';
import '../../core/theme/app_colors.dart';
import '../providers/app_providers.dart';
import '../utils/session_icon.dart';

/// Bottom sheet chọn ngôn ngữ trả lời cho session mới. Dùng chung cho
/// Home (topic chip / quick start) + Templates (chọn mẫu) + chỗ khác.
///
/// Trả về language code (vd "en", "ja") khi user pick, null nếu dismiss.
Future<String?> pickLanguage(
  BuildContext context,
  WidgetRef ref, {
  String defaultLang = 'en',
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _LanguagePickerSheet(defaultLang: defaultLang),
  );
}

class _LanguagePickerSheet extends ConsumerWidget {
  final String defaultLang;
  const _LanguagePickerSheet({required this.defaultLang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langs = ref.watch(languagesProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
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
            const SizedBox(height: 4),
            Text(
              'AI sẽ trả lời bằng ngôn ngữ bạn chọn.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: const Color(0xFF8C879E),
              ),
            ),
            const SizedBox(height: 16),
            langs.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
              ),
              error: (_, _) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(context, 'vi', '🇻🇳', 'Tiếng Việt', false),
                  _chip(context, 'en', '🇬🇧', 'English', defaultLang == 'en'),
                ],
              ),
              data: (list) {
                final items = list.cast<Language>();
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: items
                      .map((l) => _chip(
                            context,
                            l.code,
                            flagForLanguageCode(l.code),
                            l.nativeName,
                            l.code == defaultLang,
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String code,
    String flag,
    String label,
    bool selected,
  ) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(code),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE6E4EC),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
