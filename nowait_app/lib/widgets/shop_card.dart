import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/review_service.dart';
import '../theme/app_theme.dart';
import '../theme/category_theme.dart';
import 'status_badge.dart';

class ShopCard extends StatelessWidget {
  final ShopModel shop;
  final VoidCallback onTap;
  final VoidCallback? onSchemeTap;
  /// When true, suppress the Directions button (e.g. on owner dashboard).
  final bool hideDirections;

  const ShopCard({
    super.key,
    required this.shop,
    required this.onTap,
    this.onSchemeTap,
    this.hideDirections = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: shop.isPromoted
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.18))
              : null,
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowPrimary,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: shop.images.isNotEmpty
                      ? Image.network(
                          shop.images.first,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _iconThumbnail(),
                        )
                      : _iconThumbnail(),
                ),
                // Star badge on thumbnail for promoted shops
                if (shop.isPromoted)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient135,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.star_rounded, size: 10, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          shop.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (shop.isPromoted) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient135,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, size: 9, color: Colors.white),
                              SizedBox(width: 3),
                              Text(
                                'Promoted',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${shop.category} • ${shop.distance}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (shop.reviewCount > 0) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => showReviewsSheet(context, shop: shop),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: Color(0xFFFFC107)),
                          const SizedBox(width: 3),
                          Text(
                            shop.avgReviewRating.toStringAsFixed(1),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '(${shop.reviewCount})',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '· ${shop.reviewCount} review${shop.reviewCount == 1 ? '' : 's'}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right_rounded,
                              size: 13, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ],
                  if (shop.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 11,
                            color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            '${shop.address}, ${shop.city}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      StatusBadge(isOpen: shop.isOpen),
                      if (shop.isOpen) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.group_outlined, size: 12, color: AppColors.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                '${shop.queueCount} in queue',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        WaitTimeBadge(minutes: shop.queueCount * shop.avgWaitMinutes),
                      ],
                      // Directions button — only when shop has saved coordinates
                      if (!hideDirections &&
                          shop.latitude != null &&
                          shop.longitude != null)
                        DirectionsChip(
                          lat: shop.latitude!,
                          lng: shop.longitude!,
                        ),
                    ],
                  ),
                  if (shop.activeScheme != null &&
                      shop.activeScheme!.isActive) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: onSchemeTap != null
                          ? () => onSchemeTap!()
                          : null,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color:
                              AppColors.primary.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  AppColors.primary.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient135,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.local_offer_rounded,
                                  size: 9, color: Colors.white),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Scheme On',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '· ${shop.activeScheme!.title}',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (onSchemeTap != null) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right_rounded,
                                  size: 13, color: AppColors.primary),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconThumbnail() {
    final color = CategoryTheme.color(shop.category);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.25)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(CategoryTheme.icon(shop.category), color: color, size: 32),
      ),
    );
  }
}

/// Tappable chip that opens Google Maps navigation for a location.
/// Public so ShopDetailsScreen and compact cards can reuse it.
class DirectionsChip extends StatefulWidget {
  final double lat;
  final double lng;

  const DirectionsChip({super.key, required this.lat, required this.lng});

  @override
  State<DirectionsChip> createState() => _DirectionsChipState();
}

class _DirectionsChipState extends State<DirectionsChip> {
  bool _launching = false;

  Future<void> _launch() async {
    if (_launching) return;
    setState(() => _launching = true);
    await LocationService.instance.launchDirections(widget.lat, widget.lng);
    if (mounted) setState(() => _launching = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _launch,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _launching
                ? const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.directions_rounded, size: 11, color: AppColors.primary),
            const SizedBox(width: 4),
            const Text(
              'Directions',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a bottom sheet showing all reviews for [shop].
void showReviewsSheet(BuildContext context, {required ShopModel shop}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReviewsBottomSheet(shop: shop),
  );
}

class _ReviewsBottomSheet extends StatefulWidget {
  final ShopModel shop;
  const _ReviewsBottomSheet({required this.shop});

  @override
  State<_ReviewsBottomSheet> createState() => _ReviewsBottomSheetState();
}

class _ReviewsBottomSheetState extends State<_ReviewsBottomSheet> {
  List<ReviewModel> _reviews = [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final data = await ReviewService.instance.getReviews(widget.shop.id, page: 1, limit: 15);
      if (mounted) {
        setState(() {
          _reviews = data['reviews'] as List<ReviewModel>;
          _total = data['total'] as int;
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
      final data = await ReviewService.instance.getReviews(widget.shop.id, page: _page + 1, limit: 15);
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
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle + header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.shop.name,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 18, fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFC107)),
                                const SizedBox(width: 4),
                                Text(
                                  widget.shop.avgReviewRating.toStringAsFixed(1),
                                  style: GoogleFonts.inter(
                                    fontSize: 15, fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$_total review${_total == 1 ? '' : 's'}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13, color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, size: 18, color: AppColors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(color: AppColors.outline.withValues(alpha: 0.2), height: 1),
                ],
              ),
            ),
            // Reviews list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                  : _reviews.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.rate_review_outlined, size: 48,
                                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.3)),
                              const SizedBox(height: 12),
                              Text('No reviews yet',
                                  style: GoogleFonts.inter(fontSize: 15, color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                          itemCount: _reviews.length + (_hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _reviews.length) {
                              if (!_loadingMore) _loadMore();
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                              );
                            }
                            return _ReviewTile(review: _reviews[i]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single review row used inside the reviews bottom sheet.
class _ReviewTile extends StatelessWidget {
  final ReviewModel review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final firstName = review.userName.trim().split(' ').first;
    final displayName = firstName.isNotEmpty ? firstName : 'Customer';
    final initial = displayName[0].toUpperCase();

    final diff = DateTime.now().difference(review.createdAt);
    String ago;
    if (diff.inDays >= 365) ago = '${diff.inDays ~/ 365}y ago';
    else if (diff.inDays >= 30) ago = '${diff.inDays ~/ 30}mo ago';
    else if (diff.inDays >= 1) ago = '${diff.inDays}d ago';
    else if (diff.inHours >= 1) ago = '${diff.inHours}h ago';
    else ago = 'Just now';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar circle with gradient
              Container(
                width: 38, height: 38,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient135,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(initial,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    Text(ago,
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              // Stars
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) => Icon(
                  i < review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 14,
                  color: i < review.rating ? const Color(0xFFFFC107) : AppColors.outline,
                )),
              ),
            ],
          ),
          if (review.review != null && review.review!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review.review!,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet showing full scheme details. Call from any screen.
void showSchemeSheet(BuildContext context, SchemeModel scheme) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _SchemeDetailSheet(scheme: scheme),
  );
}

class _SchemeDetailSheet extends StatelessWidget {
  final SchemeModel scheme;

  const _SchemeDetailSheet({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final days = scheme.validUntil.difference(DateTime.now()).inDays;
    final isExpiringSoon = days <= 3;

    return Container(
      margin: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 60,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowPrimary,
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          // Header gradient banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient135,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_offer_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Special Scheme',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.75),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        scheme.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Offer Details',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    scheme.description,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.onSurface,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Validity row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isExpiringSoon
                    ? AppColors.errorContainer.withValues(alpha: 0.5)
                    : AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isExpiringSoon
                      ? AppColors.error.withValues(alpha: 0.25)
                      : AppColors.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: isExpiringSoon
                        ? AppColors.error
                        : AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      scheme.validityText,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isExpiringSoon
                            ? AppColors.error
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  Text(
                    'Until ${_formatDate(scheme.validUntil)}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
              height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
