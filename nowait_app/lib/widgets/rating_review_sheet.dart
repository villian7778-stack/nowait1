import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/review_service.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// Shows the post-service rating sheet as a modal bottom sheet.
/// Returns true if the user submitted a rating, false if they skipped/dismissed.
Future<bool> showRatingReviewSheet(
  BuildContext context, {
  required String shopName,
  required String shopId,
  required String queueEntryId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _RatingReviewSheet(
      shopName: shopName,
      shopId: shopId,
      queueEntryId: queueEntryId,
    ),
  );
  return result ?? false;
}

class _RatingReviewSheet extends StatefulWidget {
  final String shopName;
  final String shopId;
  final String queueEntryId;

  const _RatingReviewSheet({
    required this.shopName,
    required this.shopId,
    required this.queueEntryId,
  });

  @override
  State<_RatingReviewSheet> createState() => _RatingReviewSheetState();
}

class _RatingReviewSheetState extends State<_RatingReviewSheet>
    with SingleTickerProviderStateMixin {
  int _selectedRating = 0;
  final _reviewController = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;

  late AnimationController _bounceController;
  late List<Animation<double>> _starAnims;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _starAnims = List.generate(5, (i) {
      final start = i * 0.12;
      return Tween<double>(begin: 1.0, end: 1.35).animate(
        CurvedAnimation(
          parent: _bounceController,
          curve: Interval(start, (start + 0.3).clamp(0, 1), curve: Curves.elasticOut),
        ),
      );
    });
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  void _onStarTap(int star) {
    setState(() => _selectedRating = star);
    _bounceController.forward(from: 0);
  }

  Future<void> _submit() async {
    if (_selectedRating == 0 || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await ReviewService.instance.submitReview(
        shopId: widget.shopId,
        queueEntryId: widget.queueEntryId,
        rating: _selectedRating,
        review: _reviewController.text.trim().isEmpty
            ? null
            : _reviewController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitted = true;
        });
        await Future.delayed(const Duration(milliseconds: 1400));
        if (mounted) Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String get _ratingLabel {
    switch (_selectedRating) {
      case 1: return 'Poor';
      case 2: return 'Fair';
      case 3: return 'Good';
      case 4: return 'Great';
      case 5: return 'Excellent!';
      default: return 'Tap a star to rate';
    }
  }

  Color get _ratingColor {
    switch (_selectedRating) {
      case 1: return AppColors.error;
      case 2: return const Color(0xFFFF8C00);
      case 3: return const Color(0xFFF5A623);
      case 4: return AppColors.tertiary;
      case 5: return const Color(0xFF00A651);
      default: return AppColors.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(24, 28, 24, 28 + bottom),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowPrimary.withValues(alpha: 0.3),
            blurRadius: 40,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: _submitted ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient135,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 16),
        Text(
          'Thanks for your feedback!',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your review helps others choose the right shop.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Trophy icon + heading
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient135,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.thumb_up_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 14),
        Text(
          'How was your visit?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.shopName,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 24),

        // Stars
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final star = i + 1;
            final filled = star <= _selectedRating;
            return AnimatedBuilder(
              animation: _starAnims[i],
              builder: (_, __) => Transform.scale(
                scale: filled ? _starAnims[i].value : 1.0,
                child: GestureDetector(
                  onTap: () => _onStarTap(star),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 48,
                      color: filled ? const Color(0xFFFFC107) : AppColors.outline,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _ratingLabel,
            key: ValueKey(_selectedRating),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _ratingColor,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Optional review text
        TextField(
          controller: _reviewController,
          maxLines: 3,
          maxLength: 500,
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface),
          decoration: InputDecoration(
            hintText: 'Share your experience (optional)…',
            hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.all(14),
            counterStyle: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 20),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context, false),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      'Skip',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: _selectedRating > 0 && !_isSubmitting ? _submit : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: _selectedRating > 0 ? AppColors.primaryGradient135 : null,
                    color: _selectedRating == 0 ? AppColors.outline.withValues(alpha: 0.2) : null,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.send_rounded,
                                size: 16,
                                color: _selectedRating > 0 ? Colors.white : AppColors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Submit Rating',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _selectedRating > 0 ? Colors.white : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
