import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  // Be Vietnam Pro — đẹp với tiếng Việt + match design Welcome.html
  static TextTheme _textTheme(TextTheme base, {required Color bodyColor}) {
    return GoogleFonts.beVietnamProTextTheme(base).apply(
      bodyColor: bodyColor,
      displayColor: bodyColor,
    );
  }

  // ==========================================================
  // Light — Coral palette (Welcome.html reference)
  // ==========================================================
  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    const bgLight = Color(0xFFF2F2F7);
    const navy = AppColors.navy;
    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgLight,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.primaryLight,
        tertiary: AppColors.primaryDark,
        surface: Color(0xFFFFFFFF),
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: navy,
        onError: Colors.white,
      ),
      textTheme: _textTheme(base.textTheme, bodyColor: navy),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: navy),
        titleTextStyle: GoogleFonts.beVietnamPro(
          color: navy,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.36,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: const TextStyle(color: Color(0xFF8C879E), fontSize: 15),
        labelStyle: const TextStyle(color: Color(0xFF5C5870)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE6E4EC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE6E4EC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.32),
          textStyle: GoogleFonts.beVietnamPro(
              fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.beVietnamPro(
              fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navy,
          side: const BorderSide(color: Color(0xFFE6E4EC)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF),
        elevation: 0,
        shadowColor: navy.withValues(alpha: 0.06),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Color(0xFF8C879E),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 8,
      ),
      dividerTheme:
          const DividerThemeData(color: Color(0xFFE6E4EC), thickness: 1),
    );
  }

  // ==========================================================
  // Dark — Coral on near-black plum (derived from light)
  // ==========================================================
  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    const bgDark = Color(0xFF15121F);
    const surfaceDark = Color(0xFF1F1B2C);
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.primaryLight,
        tertiary: AppColors.primaryDark,
        surface: surfaceDark,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFFF7F5FA),
        onError: Colors.white,
      ),
      textTheme: _textTheme(base.textTheme, bodyColor: const Color(0xFFF7F5FA)),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Color(0xFFF7F5FA)),
        titleTextStyle: GoogleFonts.beVietnamPro(
          color: const Color(0xFFF7F5FA),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.36,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF272237),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: const TextStyle(color: Color(0xFF7E7891), fontSize: 15),
        labelStyle: const TextStyle(color: Color(0xFFB2ACC4)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF3A3450)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF3A3450)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          textStyle: GoogleFonts.beVietnamPro(
              fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.beVietnamPro(
              fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFF7F5FA),
          side: const BorderSide(color: Color(0xFF3A3450)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF221E30),
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceDark,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Color(0xFF7E7891),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 0,
      ),
      dividerTheme:
          const DividerThemeData(color: Color(0xFF2E2940), thickness: 1),
    );
  }
}
