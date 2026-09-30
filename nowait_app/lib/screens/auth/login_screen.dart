import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../config/app_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../services/auth_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import 'create_account_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isCheckingEmail = false;
  bool _emailNotFound = false;
  // Email validation messages appear after the field is left or Continue is tapped.
  bool _emailSubmitted = false;
  bool _emailTouched = false;
  final _emailFocus = FocusNode();
  // 0 = choose method, 1 = enter email, 2 = enter password
  int _step = 0;
  final _l = LocaleService.instance;

  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late Animation<double> _logoFlip;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;

  bool get _isValid =>
      _emailController.text.contains('@') && _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus && _emailController.text.isNotEmpty) setState(() => _emailTouched = true);
    });
    _emailController.addListener(() {
      if (_emailNotFound) _emailNotFound = false;
      setState(() {});
    });
    _passwordController.addListener(() => setState(() {}));
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
    _emailController.dispose();
    _emailFocus.dispose();
    _passwordController.dispose();
    _logoCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  void _login() async {
    if (!_isValid) return;
    setState(() => _isLoading = true);
    try {
      final profileComplete = await AuthService.instance.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      if (!profileComplete) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const CreateAccountScreen(isCompletingProfile: true),
          ),
          (route) => false,
        );
        return;
      }
      // Home/OwnerDashboard routing happens centrally in main.dart on rebuild
      // once AuthService.isLoggedIn flips true — pop back to the app root.
      Navigator.of(context).popUntil((r) => r.isFirst);
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

  void _continueWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      await sb.Supabase.instance.client.auth.signInWithOAuth(
        sb.OAuthProvider.google,
        redirectTo: AppConfig.authCallbackUrl,
      );
      // Session arrival + navigation is handled centrally in main.dart via
      // onAuthStateChange once the browser redirects back into the app.
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_l.tr('googleSignInFailed')), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  bool get _isEmailValid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailController.text.trim());

  String? get _emailError {
    final e = _emailController.text.trim();
    if (e.isEmpty) return _emailSubmitted ? _l.tr('errEmailRequired') : null;
    if (!_isEmailValid && (_emailSubmitted || _emailTouched)) return _l.tr('errEmailInvalid');
    return null;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  Future<void> _checkEmail() async {
    if (!_isEmailValid || _isCheckingEmail) return;
    FocusScope.of(context).unfocus();
    setState(() { _isCheckingEmail = true; _emailNotFound = false; });
    try {
      final exists = await AuthService.instance.emailExists(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        if (exists) {
          _step = 2;
        } else {
          _emailNotFound = true;
        }
      });
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(_l.tr('somethingWrong'));
    } finally {
      if (mounted) setState(() => _isCheckingEmail = false);
    }
  }

  void _goBack() {
    setState(() {
      _emailNotFound = false;
      _passwordController.clear();
      _step = _step == 2 ? 1 : 0;
    });
  }

  Widget _stepHeading(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
        ],
      );

  Widget _backButton() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: Text(_l.tr('back')),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary, padding: EdgeInsets.zero),
        ),
      );

  Widget _loadingBar({required bool gradient}) => Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: gradient ? AppColors.primaryGradient135 : null,
          color: gradient ? null : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: gradient ? null : Border.all(color: AppColors.outline.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: gradient ? Colors.white : null,
            ),
          ),
        ),
      );

  List<Widget> _buildChooseStep() => [
        _stepHeading(_l.tr('welcomeBack'), _l.tr('chooseHowToContinue')),
        SizedBox(
          width: double.infinity,
          child: _isGoogleLoading
              ? _loadingBar(gradient: false)
              : _GoogleButton(
                  label: _l.tr('continueWithGoogle'),
                  recommendedLabel: _l.tr('recommended'),
                  onPressed: _continueWithGoogle,
                ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            label: _l.tr('continueWithEmail'),
            onPressed: () => setState(() => _step = 1),
            icon: Icons.mail_outline_rounded,
          ),
        ),
      ];

  List<Widget> _buildEmailStep() => [
        _backButton(),
        const SizedBox(height: 8),
        _stepHeading(_l.tr('enterYourEmail'), _l.tr('enterEmailToContinue')),
        _AuthTextField(
          controller: _emailController,
          hint: _l.tr('emailAddress'),
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          focusNode: _emailFocus,
          errorText: _emailError,
        ),
        const SizedBox(height: 16),
        if (_emailNotFound) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _l.tr('noAccountForEmail'),
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: _l.tr('createAccount'),
              icon: Icons.person_add_outlined,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateAccountScreen(initialEmail: _emailController.text.trim()),
                ),
              ),
            ),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            child: _isCheckingEmail
                ? _loadingBar(gradient: true)
                : GradientButton(
                    label: _l.tr('continueLabel'),
                    onPressed: _isEmailValid ? _checkEmail : () => setState(() => _emailSubmitted = true),
                    icon: Icons.arrow_forward_rounded,
                  ),
          ),
      ];

  List<Widget> _buildPasswordStep() => [
        _backButton(),
        const SizedBox(height: 8),
        _stepHeading(_l.tr('enterYourPassword'), _emailController.text.trim()),
        _AuthTextField(
          controller: _passwordController,
          hint: _l.tr('password'),
          icon: Icons.lock_outline_rounded,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
            ),
            child: Text(
              _l.tr('forgotPassword'),
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _isLoading
              ? _loadingBar(gradient: true)
              : GradientButton(
                  label: _l.tr('login'),
                  onPressed: _isValid ? _login : () {},
                  icon: Icons.login_rounded,
                ),
        ),
      ];

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
                      if (_step == 0) ..._buildChooseStep(),
                      if (_step == 1) ..._buildEmailStep(),
                      if (_step == 2) ..._buildPasswordStep(),
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

/// Shared styled text field for login/create-account/forgot-password/reset-password.
class _AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final FocusNode? focusNode;
  /// When set, the field gets a red outline and this message underneath.
  final String? errorText;

  const _AuthTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.focusNode,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _box(hasError),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              errorText!,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _box(bool hasError) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError ? AppColors.error : AppColors.outline.withValues(alpha: 0.4),
          width: hasError ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: 14),
          prefixIcon: Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final String label;
  final String recommendedLabel;
  final VoidCallback onPressed;
  const _GoogleButton({
    required this.label,
    required this.recommendedLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: BorderSide(color: AppColors.outline.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _GoogleGLogo(size: 24),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: GoogleFonts.inter(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: -10,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.tertiary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              recommendedLabel,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// Google "G" in the brand colours: a bold "G" glyph masked with a hard-stop
/// sweep gradient (blue, green, yellow, red) — no image asset needed.
class _GoogleGLogo extends StatelessWidget {
  final double size;
  const _GoogleGLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const SweepGradient(
        colors: [
          Color(0xFF4285F4), Color(0xFF4285F4),
          Color(0xFF34A853), Color(0xFF34A853),
          Color(0xFFFBBC05), Color(0xFFFBBC05),
          Color(0xFFEA4335), Color(0xFFEA4335),
          Color(0xFF4285F4), Color(0xFF4285F4),
        ],
        stops: [0.0, 0.12, 0.12, 0.38, 0.38, 0.55, 0.55, 0.85, 0.85, 1.0],
      ).createShader(bounds),
      child: Text(
        'G',
        style: GoogleFonts.roboto(
          fontSize: size,
          fontWeight: FontWeight.w900,
          height: 1.0,
          color: Colors.white,
        ),
      ),
    );
  }
}
