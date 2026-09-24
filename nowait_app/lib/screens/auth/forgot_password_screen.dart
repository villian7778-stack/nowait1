import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../services/auth_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _sent = false;
  final _l = LocaleService.instance;

  bool get _isValid => _emailController.text.contains('@');

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _sendResetLink() async {
    if (!_isValid) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.forgotPassword(_emailController.text.trim());
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_l.tr('somethingWrong'))),
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
              const SizedBox(height: 16),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  _sent ? Icons.mark_email_read_outlined : Icons.lock_reset_rounded,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _sent ? _l.tr('checkYourEmail') : _l.tr('forgotPassword'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _sent ? _l.tr('resetLinkSentHint') : _l.tr('forgotPasswordHint'),
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 28),
              if (!_sent) ...[
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.outline.withValues(alpha: 0.4)),
                  ),
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.onSurface),
                    decoration: InputDecoration(
                      hintText: _l.tr('emailAddress'),
                      hintStyle: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: 14),
                      prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20, color: AppColors.onSurfaceVariant),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
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
                          label: _l.tr('sendResetLink'),
                          onPressed: _isValid ? _sendResetLink : () {},
                          icon: Icons.send_rounded,
                        ),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    label: _l.tr('backToLogin'),
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    ),
                    icon: Icons.arrow_back_rounded,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
