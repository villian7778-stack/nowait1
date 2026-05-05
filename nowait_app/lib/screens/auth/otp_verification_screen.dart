import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../services/auth_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../customer/home_screen.dart';
import '../owner/owner_dashboard_screen.dart';
import 'create_account_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phone;
  final bool isNewUser;
  final String role;

  const OtpVerificationScreen({
    super.key,
    required this.phone,
    required this.isNewUser,
    this.role = 'Customer',
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  int _resendSeconds = 30;
  Timer? _timer;
  bool _isVerifying = false;
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _l.addListener(_onLocale);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNodes[0].requestFocus());
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _timer?.cancel();
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    super.dispose();
  }

  void _onLocale() => setState(() {});

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 0) {
        t.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();
  bool get _isComplete => _otp.length == 6;

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
    setState(() {});
  }

  void _verify() async {
    if (!_isComplete) return;
    setState(() => _isVerifying = true);
    try {
      final profileComplete =
          await AuthService.instance.verifyOtp(widget.phone, _otp);
      if (!mounted) return;

      if (profileComplete && widget.isNewUser) {
        // Phone is already registered — warn the user and go back to create account
        _clearOtp();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'This mobile number is already registered. Please use Login instead.',
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
        // Log out the session we just created — user should log in explicitly
        await AuthService.instance.logout();
        if (!mounted) return;
        Navigator.of(context).pop(); // back to CreateAccountScreen
        return;
      }

      if (!profileComplete) {
        // New user verified — if we have pending data from the create-account
        // form, complete the profile automatically without showing the form again.
        final auth = AuthService.instance;
        if (auth.pendingName != null &&
            auth.pendingState != null &&
            auth.pendingCity != null &&
            auth.pendingRole != null) {
          await auth.completeProfile(
            auth.pendingName!,
            auth.pendingState!,
            auth.pendingCity!,
            auth.pendingRole!,
          );
          if (!mounted) return;
          final isOwner = AuthService.instance.isOwner;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) =>
                  isOwner ? const OwnerDashboardScreen() : const HomeScreen(),
            ),
            (route) => false,
          );
          return;
        }
        // No pending data (e.g. user came from login flow) — show the form
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                const CreateAccountScreen(isCompletingProfile: true),
          ),
          (route) => false,
        );
        return;
      }

      // Existing user logging in normally — go to appropriate home
      final isOwner = AuthService.instance.isOwner;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              isOwner ? const OwnerDashboardScreen() : const HomeScreen(),
        ),
        (route) => false,
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
          SnackBar(content: Text(_l.tr('verificationFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _clearOtp() {
    for (final c in _controllers) {
      c.clear();
    }
    if (mounted) {
      _focusNodes[0].requestFocus();
      setState(() {});
    }
  }

  void _resendOtp() async {
    _startResendTimer();
    try {
      await AuthService.instance.sendOtp(widget.phone);
    } catch (_) {} // silently handle
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // Background abstract circles
          Positioned(
            top: 60,
            right: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  width: 40,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.06),
                  width: 30,
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Shield icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.primary, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _l.tr('verifyNumber'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(
                          fontSize: 14, color: AppColors.onSurfaceVariant),
                      children: [
                        TextSpan(text: _l.tr('sentCodeTo')),
                        TextSpan(
                          text: '+91 ${widget.phone}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // OTP boxes — LayoutBuilder makes them scale with screen width
                  LayoutBuilder(
                    builder: (ctx, constraints) {
                      // 5 gaps of 8 px between 6 boxes
                      final boxW = (constraints.maxWidth - 40) / 6;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:
                            List.generate(6, (i) => _buildOtpBox(i, boxW)),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  // Resend
                  Center(
                    child: _resendSeconds > 0
                        ? RichText(
                            text: TextSpan(
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.onSurfaceVariant),
                              children: [
                                TextSpan(text: _l.tr('resendIn')),
                                TextSpan(
                                  text: "${_resendSeconds}s",
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GestureDetector(
                            onTap: _resendOtp,
                            child: Text(
                              _l.tr('resendOtp'),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: _isVerifying
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
                            label: _l.tr('verifyAndContinue'),
                            onPressed: _verify,
                            icon: Icons.check_circle_outline_rounded,
                          ),
                  ),
                  const SizedBox(height: 28),
                  // Security info card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.security_rounded,
                            size: 20,
                            color: AppColors.primary.withValues(alpha: 0.7)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _l.tr('demoHint'),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildOtpBox(int index, double boxW) {
    final isFocused = _focusNodes[index].hasFocus;
    final hasValue = _controllers[index].text.isNotEmpty;
    final boxH = boxW * 1.25;
    final fontSize = (boxW * 0.44).clamp(18.0, 26.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: boxW,
      height: boxH,
      decoration: BoxDecoration(
        color: hasValue
            ? AppColors.primary.withValues(alpha: 0.06)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFocused
              ? AppColors.primary
              : hasValue
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.outline.withValues(alpha: 0.4),
          width: isFocused ? 2 : 1,
        ),
      ),
      // Center wrapping ensures the TextField sits in the middle vertically
      child: Center(
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.backspace &&
                _controllers[index].text.isEmpty) {
              _onBackspace(index);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            maxLength: 1,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) => _onDigitChanged(index, v),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              // Remove all internal padding so our Center widget controls alignment
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            style: GoogleFonts.plusJakartaSans(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
