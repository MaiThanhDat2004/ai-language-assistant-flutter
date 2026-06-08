import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  const SizedBox(height: 16),
                  const _Header(),
                  const SizedBox(height: 36),
                  const _LanguagePillsCollage(),
                  const SizedBox(height: 36),
                  const _Eyebrow(),
                  const SizedBox(height: 12),
                  const _HeroHeading(),
                  const SizedBox(height: 16),
                  Text(
                    'Trợ lý AI luyện hội thoại, chấm phát âm và ghi nhớ tiến độ học của bạn — qua 12 ngôn ngữ.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                      color: const Color(0xFF5C5870),
                    ),
                  ),
                  const Spacer(),
                  _PrimaryCta(
                    onPressed: () => context.go(AppRoutes.register),
                  ),
                  const SizedBox(height: 6),
                  _GhostCta(
                    onPressed: () => context.go(AppRoutes.login),
                  ),
                  const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/images/logo.png',
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'DLanguage',
          style: GoogleFonts.beVietnamPro(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _LanguagePillsCollage extends StatelessWidget {
  const _LanguagePillsCollage();

  @override
  Widget build(BuildContext context) {
    // Width khả dụng = min(screen, 420) − 48px padding ngang của màn Welcome.
    // KHÔNG dùng LayoutBuilder: nó không trả intrinsic dimension nên sẽ làm
    // SliverFillRemaining(hasScrollBody: false) ở màn Welcome crash khi đo cao.
    final screenW = MediaQuery.sizeOf(context).width;
    final w = (screenW < 420 ? screenW : 420) - 48;
    // Tỷ lệ pill so với 342px của thiết kế gốc — scale theo width hiện tại.
    double s(double px) => px * w / 342;
    return SizedBox(
          height: s(260),
          child: Stack(
            children: [
              // "Hi" — coral big square
              Positioned(
                left: s(44),
                top: s(10),
                child: _Pill(
                  text: 'Hi',
                  size: Size(s(130), s(130)),
                  bg: AppColors.primary,
                  fg: Colors.white,
                  fontSize: s(48),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.92,
                  radius: s(28),
                  shadow: BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    offset: Offset(0, s(20)),
                    blurRadius: s(40),
                  ),
                ),
              ),
              // こんにちは — dark navy
              Positioned(
                left: s(180),
                top: s(70),
                child: _Pill(
                  text: 'こんにちは',
                  size: Size(s(110), s(110)),
                  bg: AppColors.navy,
                  fg: Colors.white,
                  fontSize: s(20),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  radius: s(24),
                ),
              ),
              // 안녕 — yellow
              Positioned(
                left: s(0),
                top: s(150),
                child: _Pill(
                  text: '안녕',
                  size: Size(s(80), s(80)),
                  bg: const Color(0xFFFFE066),
                  fg: AppColors.navy,
                  fontSize: s(22),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.44,
                  radius: s(20),
                ),
              ),
              // Bonjour — green
              Positioned(
                left: s(206),
                top: s(186),
                child: _Pill(
                  text: 'Bonjour',
                  size: Size(s(72), s(60)),
                  bg: const Color(0xFF2A6A52),
                  fg: Colors.white,
                  fontSize: s(13),
                  fontWeight: FontWeight.w700,
                  radius: s(16),
                ),
              ),
              // Small accent dot
              Positioned(
                left: s(154),
                top: s(140),
                child: Container(
                  width: s(16),
                  height: s(16),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Size size;
  final Color bg;
  final Color fg;
  final double fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;
  final double radius;
  final BoxShadow? shadow;

  const _Pill({
    required this.text,
    required this.size,
    required this.bg,
    required this.fg,
    required this.fontSize,
    required this.fontWeight,
    this.letterSpacing = 0,
    required this.radius,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow != null ? [shadow!] : null,
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.beVietnamPro(
          color: fg,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: 1.0,
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow();
  @override
  Widget build(BuildContext context) {
    return Text(
      'HỌC NGOẠI NGỮ CÙNG AI',
      style: GoogleFonts.beVietnamPro(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.88,
        color: AppColors.primaryDark,
      ),
    );
  }
}

class _HeroHeading extends StatelessWidget {
  const _HeroHeading();
  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.beVietnamPro(
      fontSize: 36,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.08,
      height: 1.05,
      color: AppColors.navy,
    );
    final coral = base.copyWith(color: AppColors.primary);
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'Nói thật.\n'),
          const TextSpan(text: 'Nghe thật.\n'),
          TextSpan(text: 'Học thật.', style: coral),
        ],
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  final VoidCallback onPressed;
  const _PrimaryCta({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB23A20).withValues(alpha: 0.18),
              offset: const Offset(0, 1),
              blurRadius: 0,
            ),
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.32),
              offset: const Offset(0, 6),
              blurRadius: 18,
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Bắt đầu miễn phí',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.16,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostCta extends StatelessWidget {
  final VoidCallback onPressed;
  const _GhostCta({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF2E2A40),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          'Tôi đã có tài khoản',
          style: GoogleFonts.beVietnamPro(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.16,
          ),
        ),
      ),
    );
  }
}
