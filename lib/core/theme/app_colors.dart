import 'package:flutter/material.dart';

/// Coral light palette (2026-05-23 redesign).
///
/// Brand colors + gradients giữ `const` (primary/accent/success) — không đổi
/// giữa light/dark để brand nhất quán.
///
/// Surface/text colors là dynamic — đổi qua `AppColors.setDarkMode()` và được
/// trigger rebuild qua `themeModeProvider`.

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
  background: Color(0xFFF2F2F7),
  surface: Color(0xFFFFFFFF),
  surfaceLight: Color(0xFFF7F7FB),
  surfaceCard: Color(0xFFFFFFFF),
  textPrimary: Color(0xFF181428),
  textSecondary: Color(0xFF5C5870),
  textTertiary: Color(0xFF8C879E),
  divider: Color(0xFFE6E4EC),
  border: Color(0xFFE6E4EC),
  chatBubbleAi: Color(0xFFFFFFFF),
  chatBubbleUser: Color(0xFFFFE5DC),
);

const _ThemePalette _dark = _ThemePalette(
  background: Color(0xFF15121F),
  surface: Color(0xFF1F1B2C),
  surfaceLight: Color(0xFF272237),
  surfaceCard: Color(0xFF221E30),
  textPrimary: Color(0xFFF7F5FA),
  textSecondary: Color(0xFFB2ACC4),
  textTertiary: Color(0xFF7E7891),
  divider: Color(0xFF2E2940),
  border: Color(0xFF3A3450),
  chatBubbleAi: Color(0xFF272237),
  chatBubbleUser: Color(0xFF4A2A20),
);

class AppColors {
  AppColors._();

  // ===== Brand colors (const) =====
  // Coral 500 — primary brand color
  static const Color primary = Color(0xFFFF6B47);
  static const Color primaryLight = Color(0xFFFFA47E);
  static const Color primaryDark = Color(0xFFE55436);

  // Accent giữ tên cũ cho backward compat — alias of primary
  static const Color accent = Color(0xFFFF6B47);
  static const Color accentOrange = Color(0xFFFFA47E);

  static const Color success = Color(0xFF2A6A52);
  static const Color warning = Color(0xFFFFE066);
  static const Color error = Color(0xFFE53935);

  // Dark navy — used for logo bg, dark pill, contrast headings
  static const Color navy = Color(0xFF181428);

  // ===== Theme-aware (dynamic) =====
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

  // ===== Gradients (const) =====
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA47E), Color(0xFFFF6B47)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8A66), Color(0xFFE55436)],
  );

  static const LinearGradient _backgroundGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF7F7FB), Color(0xFFF2F2F7)],
  );
  static const LinearGradient _backgroundGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF15121F), Color(0xFF1F1B2C)],
  );
  static LinearGradient get backgroundGradient =>
      _isDark ? _backgroundGradientDark : _backgroundGradientLight;

  // Quick Start cards — bộ 6 màu warm/cool tươi sáng phù hợp Coral palette
  static const LinearGradient cardGradient1 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8A66), Color(0xFFFF6B47)],
  );

  static const LinearGradient cardGradient2 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFE066), Color(0xFFFFB04A)],
  );

  static const LinearGradient cardGradient3 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4FB39B), Color(0xFF2A6A52)],
  );

  static const LinearGradient cardGradient4 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6E78F3), Color(0xFF4D56C9)],
  );

  static const LinearGradient cardGradient5 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA47E), Color(0xFFFFE066)],
  );

  static const LinearGradient cardGradient6 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2C2640), Color(0xFF181428)],
  );
}
