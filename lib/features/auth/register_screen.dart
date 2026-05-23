import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/errors/app_error.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_providers.dart';
import 'login_screen.dart' show AuthWidgets;

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  String? _selectedLang;

  static const _langs = <_LangChoice>[
    _LangChoice('en', '🇬🇧', 'Anh'),
    _LangChoice('ja', '🇯🇵', 'Nhật'),
    _LangChoice('ko', '🇰🇷', 'Hàn'),
    _LangChoice('zh', '🇨🇳', 'Trung'),
    _LangChoice('fr', '🇫🇷', 'Pháp'),
    _LangChoice('es', '🇪🇸', 'Tây BN'),
    _LangChoice('de', '🇩🇪', 'Đức'),
    _LangChoice('th', '🇹🇭', 'Thái'),
  ];

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _usernameFromEmail(String email) {
    // Lấy phần trước @, đảm bảo tối thiểu 3 ký tự (backend yêu cầu)
    final at = email.indexOf('@');
    final raw = at > 0 ? email.substring(0, at) : email;
    // Strip non-alphanumeric (giữ . _ -)
    final clean =
        raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '').toLowerCase();
    return clean.length >= 3 ? clean : '${clean}_user';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLang == null) {
      setState(() => _error = 'Hãy chọn ngôn ngữ bạn muốn học');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authApi = ref.read(authApiProvider);
      final email = _emailCtrl.text.trim();
      final fullName = _fullNameCtrl.text.trim();
      final tokens = await authApi.register(
        username: _usernameFromEmail(email),
        email: email,
        password: _passwordCtrl.text,
        fullName: fullName.isEmpty ? null : fullName,
      );
      await ref.read(tokenStorageProvider).saveTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            userId: tokens.userId,
            username: tokens.username,
          );
      // Lưu ngôn ngữ học vào profile (best-effort — không block flow nếu fail)
      try {
        await authApi.updateProfile(preferredLanguage: _selectedLang);
      } catch (_) {/* ignore */}
      ref.read(authStateProvider.notifier).setAuthenticated(true);
      if (mounted) context.go(AppRoutes.home);
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Đã có lỗi xảy ra, thử lại');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthWidgets.backButton(
                        onTap: () => context.go(AppRoutes.welcome)),
                    const SizedBox(height: 24),
                    Text(
                      'Tạo tài khoản',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -1.0,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      'của bạn',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -1.0,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Vài giây để mở khoá trợ lý AI riêng cho bạn.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 15,
                        height: 1.5,
                        color: const Color(0xFF5C5870),
                      ),
                    ),
                    const SizedBox(height: 28),
                    AuthWidgets.fieldLabel('HỌ VÀ TÊN'),
                    const SizedBox(height: 8),
                    AuthWidgets.input(
                      controller: _fullNameCtrl,
                      enabled: !_loading,
                      hint: 'Mai Thành Đạt',
                    ),
                    const SizedBox(height: 16),
                    AuthWidgets.fieldLabel('EMAIL'),
                    const SizedBox(height: 8),
                    AuthWidgets.input(
                      controller: _emailCtrl,
                      enabled: !_loading,
                      hint: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Nhập email';
                        if (!v.contains('@')) return 'Email không hợp lệ';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    AuthWidgets.fieldLabel('MẬT KHẨU'),
                    const SizedBox(height: 8),
                    AuthWidgets.input(
                      controller: _passwordCtrl,
                      enabled: !_loading,
                      hint: 'Ít nhất 8 ký tự',
                      obscureText: _obscure,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: const Color(0xFF8C879E),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Nhập mật khẩu';
                        if (v.length < 8) return 'Tối thiểu 8 ký tự';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    AuthWidgets.fieldLabel('BẠN MUỐN HỌC NGÔN NGỮ NÀO?'),
                    const SizedBox(height: 12),
                    _LangGrid(
                      choices: _langs,
                      selected: _selectedLang,
                      enabled: !_loading,
                      onSelect: (code) => setState(() {
                        _selectedLang = code;
                        if (_error == 'Hãy chọn ngôn ngữ bạn muốn học') {
                          _error = null;
                        }
                      }),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      AuthWidgets.errorBanner(_error!),
                    ],
                    const SizedBox(height: 24),
                    AuthWidgets.primaryButton(
                      label: 'Tạo tài khoản',
                      loading: _loading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Đã có tài khoản? ',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 14,
                            color: const Color(0xFF5C5870),
                          ),
                        ),
                        InkWell(
                          onTap: _loading
                              ? null
                              : () => context.go(AppRoutes.login),
                          child: Text(
                            'Đăng nhập',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangChoice {
  final String code;
  final String flag;
  final String label;
  const _LangChoice(this.code, this.flag, this.label);
}

class _LangGrid extends StatelessWidget {
  final List<_LangChoice> choices;
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onSelect;
  const _LangGrid({
    required this.choices,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final w = (c.maxWidth - gap * 3) / 4;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: choices.map((it) {
            final isSel = it.code == selected;
            return SizedBox(
              width: w,
              height: 78,
              child: _LangChip(
                choice: it,
                selected: isSel,
                onTap: enabled ? () => onSelect(it.code) : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _LangChip extends StatelessWidget {
  final _LangChoice choice;
  final bool selected;
  final VoidCallback? onTap;
  const _LangChip({
    required this.choice,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primary : Colors.white;
    final fg = selected ? Colors.white : AppColors.navy;
    final border = selected
        ? AppColors.primary
        : const Color(0xFFE6E4EC);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.5 : 1),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      offset: const Offset(0, 6),
                      blurRadius: 14,
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(choice.flag, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 4),
              Text(
                choice.label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
