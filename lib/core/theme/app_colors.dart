import 'package:flutter/material.dart';

/// Theme palette tách 2 phần:
///   - **Brand colors + gradients**: giữ `const` (primary, accent, success, ...)
///     Lý do: KHÔNG đổi giữa light/dark — để brand nhất quán + widget có thể
///     dùng trong `const` constructor.
///   - **Surface/text colors**: dynamic — đổi theo `AppColors.setDarkMode()`.
///     Tradeoff: mất `const` ở chỗ khai báo background/surface/text trong
///     `BoxDecoration` — phải remove `const` wrapper.
///
/// Cách switch: gọi `AppColors.setDarkMode(true|false)` lúc app khởi động
/// và mỗi khi user toggle. Riverpod themeModeProvider sẽ trigger rebuild.

class _ThemePalette {
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceCard;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color border;
  final Color chatBubbleAi;
  final Color chatBubbleUser;
  const _ThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceCard,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.border,
    required this.chatBubbleAi,
    required this.chatBubbleUser,
  });
}

const _ThemePalette _light = _ThemePalette(
  background: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  surfaceLight: Color(0xFFF5F7FB),
  surfaceCard: Color(0xFFFFFFFF),
  textPrimary: Color(0xFF1A1F36),
  textSecondary: Color(0xFF6B7280),
  textTertiary: Color(0xFF9CA3AF),
  divider: Color(0xFFE5E7EB),
  border: Color(0xFFE5E7EB),
  chatBubbleAi: Color(0xFFCFE5F7),
  chatBubbleUser: Color(0xFFFEE2D9),
);

const _ThemePalette _dark = _ThemePalette(
  background: Color(0xFF0F1035),
  surface: Color(0xFF1A1D4E),
  surfaceLight: Color(0xFF252A6B),
  surfaceCard: Color(0xFF20245C),
  textPrimary: Color(0xFFFFFFFF),
  textSecondary: Color(0xFF8B9BD0),
  textTertiary: Color(0xFF5A6BA8),
  divider: Color(0xFF2A2F6B),
  border: Color(0xFF353B7A),
  // Bubble AI ở dark: deep navy with blue tint — đủ đậm để nổi trên bg
  chatBubbleAi: Color(0xFF253665),
  // Bubble user: dark warm tone (coral đậm) — vẫn coral hue như light mode
  chatBubbleUser: Color(0xFF4D2A24),
);

class AppColors {
  AppColors._();

  // ===== Brand colors + accents (giữ const, không đổi giữa light/dark) =====
  static const Color primary = Color(0xFF2D6FF0);
  static const Color primaryLight = Color(0xFF5B9BFF);
  static const Color primaryDark = Color(0xFF1E4FBF);

  static const Color accent = Color(0xFFFB8568);
  static const Color accentOrange = Color(0xFFFF9A56);

  static const Color success = Color(0xFF2DD4BF);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // ===== Theme-aware (dynamic) — đổi qua setDarkMode() =====
  static _ThemePalette _active = _light;
  static bool _isDark = false;
  static bool get isDark => _isDark;

  static void setDarkMode(bool dark) {
    _isDark = dark;
    _active = dark ? _dark : _light;
  }

  static Color get background => _active.background;
  static Color get surface => _active.surface;
  static Color get surfaceLight => _active.surfaceLight;
  static Color get surfaceCard => _active.surfaceCard;
  static Color get textPrimary => _active.textPrimary;
  static Color get textSecondary => _active.textSecondary;
  static Color get textTertiary => _active.textTertiary;
  static Color get divider => _active.divider;
  static Color get border => _active.border;
  static Color get chatBubbleAi => _active.chatBubbleAi;
  static Color get chatBubbleUser => _active.chatBubbleUser;

  // ===== Gradients giữ const =====
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5B9BFF), Color(0xFF2D6FF0)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFB8568), Color(0xFFFF9A56)],
  );

  // Background gradient — DYNAMIC theo theme.
  // Lose `const` ở mọi BoxDecoration dùng gradient này (script fix tự động).
  static const LinearGradient _backgroundGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFF5F7FB)],
  );
  static const LinearGradient _backgroundGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0F1035), Color(0xFF1A1D4E)],
  );
  static LinearGradient get backgroundGradient =>
      _isDark ? _backgroundGradientDark : _backgroundGradientLight;

  // Quick Start cards — vibrant, không đổi giữa light/dark (làm điểm nhấn)
  static const LinearGradient cardGradient1 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
  );

  static const LinearGradient cardGradient2 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF093FB), Color(0xFFF5576C)],
  );

  static const LinearGradient cardGradient3 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)],
  );

  static const LinearGradient cardGradient4 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF43E97B), Color(0xFF38F9D7)],
  );

  static const LinearGradient cardGradient5 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFA709A), Color(0xFFFEE140)],
  );

  static const LinearGradient cardGradient6 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA8EDEA), Color(0xFFFED6E3)],
  );
}
