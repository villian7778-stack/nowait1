import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Shown to customers in place of a shop whose owner has no active subscription:
/// only the name and an "Unavailable" tag — no image, rating or details, and not tappable.
class LockedShopCard extends StatelessWidget {
  final ShopModel shop;

  const LockedShopCard({super.key, required this.shop});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, size: 18, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              shop.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              LocaleService.instance.tr('unavailable'),
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
