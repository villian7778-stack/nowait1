import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/review_service.dart';
import '../../theme/app_theme.dart';

class ReviewsScreen extends StatefulWidget {
  final ShopModel shop;

  const ReviewsScreen({super.key, required this.shop});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  List<ReviewModel> _reviews = [];
  int _total = 0;
  double _avgRating = 0.0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadReviews();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadReviews() async {
    try {
      final results = await Future.wait([
        ReviewService.instance.getReviews(widget.shop.id, page: 1, limit: 20),
        ReviewService.instance.getReviewSummary(widget.shop.id),
      ]);
      final data = results[0] as Map<String, dynamic>;
      final summary = results[1] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _reviews = data['reviews'] as List<ReviewModel>;
          _total = data['total'] as int;
          _avgRating = (summary['average_rating'] as num?)?.toDouble() ?? 0.0;
          _hasMore = data['has_more'] as bool;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await ReviewService.instance.getReviews(widget.shop.id, page: _page + 1, limit: 20);
      if (mounted) {
        setState(() {
          _reviews.addAll(data['reviews'] as List<ReviewModel>);
          _page++;
          _hasMore = data['has_more'] as bool;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.surface.withValues(alpha: 0.95),
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceContainerLow,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            title: Text(
              'Reviews',
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shop info + summary
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(color: AppColors.shadowPrimary, blurRadius: 14, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Big average number
                        Column(
                          children: [
                            Text(
                              _fmtRating(_avgRating),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                color: AppColors.onSurface,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _StarRow(rating: _avgRating, size: 18),
                            const SizedBox(height: 4),
                            Text(
                              '$_total review${_total == 1 ? '' : 's'}',
                              style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        // Vertical divider
                        Container(width: 1, height: 80, color: AppColors.outline.withValues(alpha: 0.15)),
                        const SizedBox(width: 20),
                        // Shop info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.shop.name,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.shop.category,
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'All Reviews',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
            )
          else if (_reviews.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.rate_review_outlined, size: 56,
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.3)),
                    const SizedBox(height: 14),
                    Text('No reviews yet',
                        style: GoogleFonts.inter(fontSize: 16, color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text('Be the first to leave a review!',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    if (i == _reviews.length) {
                      return _loadingMore
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              ),
                            )
                          : const SizedBox.shrink();
                    }
                    return _ReviewTile(review: _reviews[i]);
                  },
                  childCount: _reviews.length + (_hasMore ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final ReviewModel review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final firstName = review.userName.trim().split(' ').first;
    final displayName = firstName.isNotEmpty ? firstName : 'Customer';
    final initial = displayName[0].toUpperCase();

    final diff = DateTime.now().difference(review.createdAt);
    final String ago;
    if (diff.inDays >= 365) {
      ago = '${diff.inDays ~/ 365}y ago';
    } else if (diff.inDays >= 30) {
      ago = '${diff.inDays ~/ 30}mo ago';
    } else if (diff.inDays >= 1) {
      ago = '${diff.inDays}d ago';
    } else if (diff.inHours >= 1) {
      ago = '${diff.inHours}h ago';
    } else {
      ago = 'Just now';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient135,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(initial,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    Text(ago,
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              _StarRow(rating: review.rating.toDouble(), size: 14),
            ],
          ),
          if (review.review != null && review.review!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              review.review!,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface, height: 1.6),
            ),
          ],
        ],
      ),
    );
  }
}

String _fmtRating(double r) => r % 1 == 0 ? r.toInt().toString() : r.toStringAsFixed(1);

/// Renders 5 stars filled/half/outline based on [rating].
class _StarRow extends StatelessWidget {
  final double rating;
  final double size;

  const _StarRow({required this.rating, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (rating >= i + 1) {
          return Icon(Icons.star_rounded, size: size, color: const Color(0xFFFFC107));
        } else if (rating >= i + 0.5) {
          return Icon(Icons.star_half_rounded, size: size, color: const Color(0xFFFFC107));
        } else {
          return Icon(Icons.star_outline_rounded, size: size, color: AppColors.outline);
        }
      }),
    );
  }
}
