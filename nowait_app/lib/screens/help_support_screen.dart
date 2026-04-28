import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _phone = '+91 98765 43210';
  static const _email = 'support@nowait.app';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
        final l = LocaleService.instance;
        final faqs = l.faqs;
        return Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            title: Text(
              l.tr('helpSupport'),
              style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel(l.tr('contactUs')),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: AppColors.shadowPrimary, blurRadius: 10, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      _contactTile(
                        context,
                        icon: Icons.phone_outlined,
                        label: l.tr('callUs'),
                        value: _phone,
                        snackLabel: l.tr('copiedClipboard'),
                      ),
                      Container(height: 1, margin: const EdgeInsets.only(left: 66), color: AppColors.surfaceContainerLow),
                      _contactTile(
                        context,
                        icon: Icons.email_outlined,
                        label: l.tr('emailUs'),
                        value: _email,
                        snackLabel: l.tr('copiedClipboard'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _sectionLabel(l.tr('faqSection')),
                const SizedBox(height: 10),
                ...faqs.map((faq) => _FaqItem(question: faq.$1, answer: faq.$2)),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'NOWAIT v1.0.0',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  Widget _contactTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String snackLabel,
  }) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackLabel, style: GoogleFonts.inter()),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w500)),
                  Text(value,
                      style: GoogleFonts.inter(
                          fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                ],
              ),
            ),
            const Icon(Icons.copy_rounded, size: 16, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                Text(
                  widget.answer,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
