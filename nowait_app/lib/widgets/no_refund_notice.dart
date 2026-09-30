import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Small notice shown wherever an owner is about to pay (subscription, extension,
/// Featured Promotion) or cancel: payments are final and never refunded.
class NoRefundNotice extends StatelessWidget {
  const NoRefundNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.tr('noRefundPolicy'),
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurface, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
