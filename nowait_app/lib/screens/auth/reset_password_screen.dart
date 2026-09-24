import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import 'login_screen.dart';

/// Shown when the app is opened via Supabase's password-recovery deep link.
/// Supabase has already established a temporary recovery session by this
/// point — this screen just collects the new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _isLoading = false;
  final _l = LocaleService.instance;

  bool get _isValid =>
      _passwordController.text.length >= 8 &&
      _passwordController.text == _confirmController.text;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_isValid) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.resetPassword(_passwordController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l.tr('passwordUpdated')),
          backgroundColor: AppColors.tertiary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      await AuthService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_l.tr('somethingWrong')), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.password_rounded, color: AppColors.primary, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                _l.tr('resetPassword'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _l.tr('newPasswordHint'),
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              _field(
                controller: _passwordController,
                hint: _l.tr('newPassword'),
                obscure: _obscure1,
                toggle: () => setState(() => _obscure1 = !_obscure1),
              ),
              const SizedBox(height: 12),
              _field(
                controller: _confirmController,
                hint: _l.tr('confirmPassword'),
                obscure: _obscure2,
                toggle: () => setState(() => _obscure2 = !_obscure2),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient135,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          ),
                        ),
                      )
                    : GradientButton(
                        label: _l.tr('resetPassword'),
                        onPressed: _isValid ? _submit : () {},
                        icon: Icons.check_circle_outline_rounded,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback toggle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.4)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: (_) => setState(() {}),
        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: 14),
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.onSurfaceVariant),
          suffixIcon: IconButton(
            onPressed: toggle,
            icon: Icon(
              obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
