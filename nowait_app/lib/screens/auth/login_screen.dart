import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../services/auth_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import 'otp_verification_screen.dart';
import 'create_account_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _phoneController = TextEditingController();
  bool _isValid = false;
  bool _isLoading = false;
  final _l = LocaleService.instance;

  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late Animation<double> _logoFlip;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() {
      final len = _phoneController.text.length;
      setState(() => _isValid = len >= 10 && len <= 11);
    });
    _l.addListener(_onLocale);

    // Hourglass: flips 180° then pauses, repeating every 2.4s
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _logoFlip = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: pi)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(tween: ConstantTween(pi), weight: 70),
    ]).animate(_logoCtrl);

    // App name + tagline: fade in + slide up once on mount
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _textFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textCtrl, curve: const Interval(0.0, 0.8, curve: Curves.easeOut)),
    );
    _textSlide = Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _textCtrl, curve: const Interval(0.0, 0.9, curve: Curves.easeOut)),
    );
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _phoneController.dispose();
    _logoCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  void _sendOtp() async {
    if (!_isValid) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.sendOtp(_phoneController.text);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            phone: _phoneController.text,
            isNewUser: false,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_l.tr('failedOtp')),
          ),
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
      body: Stack(
        children: [
          // Background decorative blobs — purely visual, no layout impact
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Scrollable so nothing overflows on small devices
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                      const SizedBox(height: 40),
                      // Animated hourglass logo
                      Center(
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient135,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.28),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: AnimatedBuilder(
                            animation: _logoFlip,
                            builder: (_, child) => Transform.rotate(
                              angle: _logoFlip.value,
                              child: child,
                            ),
                            child: const Icon(
                              Icons.hourglass_bottom_rounded,
                              color: Colors.white,
                              size: 38,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Animated app name + tagline
                      FadeTransition(
                        opacity: _textFade,
                        child: SlideTransition(
                          position: _textSlide,
                          child: Column(
                            children: [
                              Center(
                                child: Text(
                                  _l.tr('appName'),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1,
                                    foreground: Paint()
                                      ..shader = const LinearGradient(
                                        colors: [AppColors.primary, AppColors.secondary],
                                      ).createShader(const Rect.fromLTWH(0, 0, 220, 50)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Center(
                                child: Text(
                                  _l.tr('appTagline'),
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Text(
                        _l.tr('welcomeBack'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _l.tr('enterMobile'),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Phone input
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.outline.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Country prefix — no emoji to avoid Noto-font warning
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 16),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'IN',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    '+91',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11),
                                ],
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: _l.tr('mobileNumber'),
                                  hintStyle: GoogleFonts.inter(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 15,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (_isValid)
                              const Padding(
                                padding: EdgeInsets.only(right: 14),
                                child: Icon(Icons.check_circle_rounded,
                                    color: AppColors.tertiary, size: 20),
                              ),
                          ],
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
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.5),
                                  ),
                                ),
                              )
                            : GradientButton(
                                label: _l.tr('sendOtp'),
                                onPressed: _sendOtp,
                                icon: Icons.send_rounded,
                              ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: GhostButton(
                          label: _l.tr('createAccount'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CreateAccountScreen()),
                          ),
                          icon: Icons.person_add_outlined,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                              children: [
                                TextSpan(text: _l.tr('termsPrefix')),
                                TextSpan(
                                  text: _l.tr('termsOfService'),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(text: _l.tr('termsAnd')),
                                TextSpan(
                                  text: _l.tr('privacyPolicy'),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
