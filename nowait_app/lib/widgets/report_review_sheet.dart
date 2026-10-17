import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../services/review_service.dart';
import '../theme/app_theme.dart';
import 'gradient_button.dart';

/// Small flag button shown on a review. Google Play requires that users can report
/// objectionable user content; the backend hides a review once several people report it.
/// Not shown on your own review.
class ReportReviewButton extends StatelessWidget {
  final ReviewModel review;
  const ReportReviewButton({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    final me = AuthService.instance.profile?['id'] as String?;
    if (me == null || me == review.userId || review.id.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: LocaleService.instance.tr('reportReview'),
      visualDensity: VisualDensity.compact,
      onPressed: () => showReportReviewSheet(context, reviewId: review.id),
      icon: Icon(Icons.flag_outlined, size: 18, color: AppColors.onSurfaceVariant.withValues(alpha: 0.8)),
    );
  }
}

/// Asks why, sends the report and tells the user what happened.
Future<void> showReportReviewSheet(BuildContext context, {required String reviewId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(reviewId: reviewId, messenger: ScaffoldMessenger.of(context)),
  );
}

class _ReportSheet extends StatefulWidget {
  final String reviewId;
  final ScaffoldMessengerState messenger;
  const _ReportSheet({required this.reviewId, required this.messenger});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _reasons = ['spam', 'offensive', 'fake', 'other'];
  static const _reasonKeys = {'spam': 'reasonSpam', 'offensive': 'reasonOffensive', 'fake': 'reasonFake', 'other': 'reasonOther'};
  String _reason = 'offensive';
  final _details = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = LocaleService.instance;
    setState(() => _sending = true);
    String message;
    try {
      final already = await ReviewService.instance.reportReview(widget.reviewId, reason: _reason, details: _details.text);
      message = l.tr(already ? 'reportAlready' : 'reportThanks');
    } on ApiException catch (e) {
      message = e.message;
    } catch (_) {
      message = l.tr('somethingWrong');
    }
    if (!mounted) return;
    Navigator.pop(context);
    widget.messenger.showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 32, offset: const Offset(0, -8))],
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.tr('reportReview'),
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
              const SizedBox(height: 4),
              Text(l.tr('reportReviewHint'), style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 12),
              for (final r in _reasons)
                ListTile(
                  onTap: _sending ? null : () => setState(() => _reason = r),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  selected: _reason == r,
                  leading: Icon(
                    _reason == r ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: _reason == r ? AppColors.primary : AppColors.onSurfaceVariant,
                  ),
                  title: Text(l.tr(_reasonKeys[r]!), style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface)),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                maxLength: 300,
                maxLines: 2,
                enabled: !_sending,
                decoration: InputDecoration(
                  hintText: l.tr('reportDetailsHint'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: _sending
                    ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                    : GradientButton(label: l.tr('sendReport'), onPressed: _send, icon: Icons.flag_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
