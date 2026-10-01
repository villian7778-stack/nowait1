import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Read-only summary of the signed-in user's account details (name, email, mobile,
/// account type, city & state). Shown on both the customer and owner profile tabs.
/// Deliberately has no edit controls — these details cannot be changed in the app.
class ProfileDetailsCard extends StatelessWidget {
  const ProfileDetailsCard({super.key});

  /// "+919834086519" / "9834086519" -> "+91 98340 86519". Anything unexpected is shown as-is.
  static String formatPhone(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return (raw ?? '').trim();
    final n = digits.substring(digits.length - 10);
    return '+91 ${n.substring(0, 5)} ${n.substring(5)}';
  }

  static String formatLocation(String? city, String? state) {
    final parts = [city, state].map((e) => (e ?? '').trim()).where((e) => e.isNotEmpty);
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the language changes or the profile is refreshed — a `const` child would
    // otherwise be skipped when the parent tab rebuilds.
    return ListenableBuilder(
      listenable: Listenable.merge([LocaleService.instance, AuthService.instance]),
      builder: (context, _) {
        final l = LocaleService.instance;
        final p = AuthService.instance.profile;
        final isOwner = p?['role'] == 'owner';
        final rows = <(IconData, String, String)>[
          (Icons.person_outline_rounded, l.tr('detailName'), (p?['name'] as String? ?? '').trim()),
          (Icons.mail_outline_rounded, l.tr('detailEmail'), (p?['email'] as String? ?? '').trim()),
          (Icons.phone_outlined, l.tr('detailMobile'), formatPhone(p?['phone'] as String?)),
          (Icons.badge_outlined, l.tr('detailRole'), l.tr(isOwner ? 'shopOwner' : 'customer')),
          (
            Icons.location_on_outlined,
            l.tr('detailLocation'),
            formatLocation(p?['city'] as String?, p?['state'] as String?),
          ),
        ];

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.tr('yourDetails').toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              for (final (icon, label, value) in rows) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            value.isEmpty ? '—' : value,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.onSurfaceVariant.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.tr('detailsLocked'),
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant.withValues(alpha: 0.8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
