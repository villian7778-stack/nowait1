import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Small "Walk-in" label for a queue entry the owner added at the counter (customer without the
/// app). Used in the owner's live queue and in the queue customers see.
class WalkInTag extends StatelessWidget {
  const WalkInTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_walk_rounded, size: 11, color: AppColors.tertiary),
          const SizedBox(width: 2),
          Text(
            LocaleService.instance.tr('walkInTag'),
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.tertiary),
          ),
        ],
      ),
    );
  }
}
