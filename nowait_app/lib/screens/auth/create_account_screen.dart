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
import 'otp_verification_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  final bool isCompletingProfile;

  const CreateAccountScreen({super.key, this.isCompletingProfile = false});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  String _selectedRole = 'customer';
  bool _isLoading = false;

  LocaleService get _l => LocaleService.instance;

  @override
  void initState() {
    super.initState();
    LocaleService.instance.addListener(_onLocale);
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocale);
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  bool get _isValid {
    if (widget.isCompletingProfile) {
      return _nameController.text.trim().isNotEmpty &&
          _cityController.text.trim().isNotEmpty;
    }
    return _nameController.text.trim().isNotEmpty &&
        _phoneController.text.length == 10 &&
        _cityController.text.trim().isNotEmpty;
  }

  void _createAccount() async {
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l.tr('fillAllFields'))),
      );
      return;
    }
    setState(() => _isLoading = true);
    final apiRole = _selectedRole; // already stores 'customer' or 'owner'
    try {
      if (widget.isCompletingProfile) {
        await AuthService.instance.completeProfile(
          _nameController.text.trim(),
          _cityController.text.trim(),
          apiRole,
        );
        if (!mounted) return;
        final isOwner = AuthService.instance.isOwner;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                isOwner ? const OwnerDashboardScreen() : const HomeScreen(),
          ),
          (r) => false,
        );
      } else {
        AuthService.instance.pendingName = _nameController.text.trim();
        AuthService.instance.pendingCity = _cityController.text.trim();
        AuthService.instance.pendingRole = apiRole;
        await AuthService.instance.sendOtp(_phoneController.text);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              phone: _phoneController.text,
              isNewUser: true,
              role: _selectedRole,
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
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
      body: Stack(
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: 0.04),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      if (!widget.isCompletingProfile)
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 20),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      const SizedBox(width: 12),
                      Text(
                        widget.isCompletingProfile
                            ? _l.tr('completeProfile')
                            : _l.tr('createAccount'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Personal Details ───────────────────────────────
                        _sectionLabel(_l.tr('personalDetails')),
                        const SizedBox(height: 16),
                        _buildSection([
                          _buildField(
                            controller: _nameController,
                            label: _l.tr('fullName'),
                            hint: _l.tr('fullNameHint'),
                            icon: Icons.person_outline_rounded,
                            textCapitalization: TextCapitalization.words,
                          ),
                          if (!widget.isCompletingProfile) ...[
                            const SizedBox(height: 14),
                            _buildPhoneField(),
                          ],
                        ]),
                        const SizedBox(height: 24),
                        // ── Location & Role ────────────────────────────────
                        _sectionLabel(_l.tr('locationAndRole')),
                        const SizedBox(height: 16),
                        _buildSection([
                          _buildField(
                            controller: _addressController,
                            label: _l.tr('addressLabel'),
                            hint: _l.tr('addressHint'),
                            icon: Icons.location_on_outlined,
                          ),
                          const SizedBox(height: 14),
                          _buildField(
                            controller: _cityController,
                            label: _l.tr('cityLabel'),
                            hint: _l.tr('cityHint'),
                            icon: Icons.location_city_outlined,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 14),
                          _buildRoleSelector(),
                        ]),
                        const SizedBox(height: 24),
                        // ── Preferred Language ─────────────────────────────
                        _sectionLabel(_l.tr('preferredLanguage')),
                        const SizedBox(height: 16),
                        _buildSection([_buildLanguageSelector()]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sticky bottom button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              decoration: BoxDecoration(
                color: AppColors.surface,
                gradient: LinearGradient(
                  colors: [
                    AppColors.surface.withValues(alpha: 0),
                    AppColors.surface,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SizedBox(
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
                        label: _l.tr('continueBtn'),
                        onPressed: _createAccount,
                        icon: Icons.arrow_forward_rounded,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  Widget _buildSection(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowPrimary,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _l.tr('mobileLabel').toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outline.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: AppColors.onSurface),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _l.tr('tenDigitHint'),
                    hintStyle: GoogleFonts.inter(
                        color: AppColors.onSurfaceVariant, fontSize: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _l.tr('accountType').toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _roleChip(_l.tr('customer'), Icons.person_outline_rounded, 'customer'),
            const SizedBox(width: 10),
            _roleChip(_l.tr('shopOwner'), Icons.storefront_outlined, 'owner'),
          ],
        ),
      ],
    );
  }

  Widget _roleChip(String label, IconData icon, String roleKey) {
    final selected = _selectedRole == roleKey;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = roleKey),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.primaryGradient135 : null,
            color: selected ? null : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? Colors.white : AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    final langs = [
      (kLangEn, _l.tr('english'), '🇬🇧'),
      (kLangHi, _l.tr('hindi'), 'अ'),
      (kLangMr, _l.tr('marathi'), 'अ'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _l.tr('language').toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: langs.map((entry) {
            final (code, label, badge) = entry;
            final selected = _l.lang == code;
            final isLast = entry == langs.last;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 8),
                child: GestureDetector(
                  onTap: () => LocaleService.instance.setLanguage(code),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      gradient: selected ? AppColors.primaryGradient135 : null,
                      color: selected ? null : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          badge,
                          style: TextStyle(
                            fontSize: code == kLangEn ? 16 : 18,
                            color: selected ? Colors.white : AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : AppColors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
