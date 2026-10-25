import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_update_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';

/// Shown instead of the whole app while this build is too old (see [AppUpdateService]).
/// There is no way past it except updating from the store.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_rounded, size: 44, color: AppColors.primary),
              ),
              const SizedBox(height: 24),
              Text(
                l.tr('updateRequiredTitle'),
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              ),
              const SizedBox(height: 12),
              Text(
                l.tr('updateRequiredBody'),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 15, height: 1.5, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: l.tr('updateNow'),
                  icon: Icons.download_rounded,
                  onPressed: AppUpdateService.instance.openStore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
