import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_theme.dart';
import '../../widgets/auto_scroll.dart';
import 'shop_details_screen.dart';

/// Promoted shops (paid "Featured Promotion", subscription active) from [shops], in random order.
/// The home screen calls this on every load so each promoted shop gets a fair turn at the front.
List<ShopModel> shuffledFeaturedShops(List<ShopModel> shops, [Random? random]) =>
    shops.where((s) => s.isPromoted && s.hasActiveSubscription).toList()..shuffle(random);

/// Tabs of the Featured section: (category stored on the shop, text key). null = All.
const featuredTabs = <(String?, String)>[
  (null, 'featuredAll'),
  ('Salon', 'catSalon'),
  ('Beauty Parlour', 'catBeautyParlor'),
  ('Garage', 'catGarage'),
  ('Hospital/Clinic', 'catHospital'),
];

/// Home screen "Featured" section: category tabs over one horizontally scrolling row of promoted
/// shop cards. [shops] must already be the shuffled promoted shops of the selected city; the
/// caller leaves the section out entirely when there are none.
class FeaturedShopsSection extends StatefulWidget {
  final List<ShopModel> shops;

  const FeaturedShopsSection({super.key, required this.shops});

  /// Height of the card row; the home screen uses it to fit Featured and Explore on one screen.
  static const cardHeight = 128.0;
  static const _gap = 10.0;

  @override
  State<FeaturedShopsSection> createState() => _FeaturedShopsSectionState();
}

class _FeaturedShopsSectionState extends State<FeaturedShopsSection> {
  String? _category; // null = All
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FeaturedShopsSection old) {
    super.didUpdateWidget(old);
    // New city / new shuffle: start the row from the beginning again, and fall back to All if
    // the chosen category no longer has promoted shops.
    if (!identical(old.shops, widget.shops)) {
      if (_category != null && !widget.shops.any((s) => s.category == _category)) _category = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _select(String? category) {
    if (category == _category) return;
    setState(() => _category = category);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;
    // Keep the shuffled order inside every tab, so no category is always first.
    final visible = _category == null
        ? widget.shops
        : widget.shops.where((s) => s.category == _category).toList();
    final tabs = featuredTabs
        .where((t) => t.$1 == null || widget.shops.any((s) => s.category == t.$1))
        .toList();
    // Two cards side by side within the 20 px page margins.
    final cardWidth = ((MediaQuery.sizeOf(context).width - 40 - FeaturedShopsSection._gap) / 2).clamp(140.0, 240.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Text(
                l.tr('featured'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Category tabs
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final (category, key) = tabs[i];
              final selected = category == _category;
              final color = category == null ? AppColors.primary : CategoryTheme.color(category);
              return GestureDetector(
                onTap: () => _select(category),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? color : AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    l.tr(key),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Promoted shop cards
        SizedBox(
          height: FeaturedShopsSection.cardHeight + 14, // + room for the card shadow
          child: AutoScroll(
            controller: _scroll,
            step: cardWidth + FeaturedShopsSection._gap,
            child: ListView.separated(
            key: ValueKey(_category),
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(width: FeaturedShopsSection._gap),
            itemBuilder: (_, i) => FeaturedShopCard(
              shop: visible[i],
              width: cardWidth,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ShopDetailsScreen(shop: visible[i])),
              ),
            ),
          ),
          ),
        ),
      ],
    );
  }
}

/// One promoted shop: photo with open/closed badge, name, category · address, rating, queue and
/// wait, and an "Offer" badge when a scheme is running (the offer itself shows on the shop page).
class FeaturedShopCard extends StatelessWidget {
  final ShopModel shop;
  final double width;
  final VoidCallback onTap;

  const FeaturedShopCard({super.key, required this.shop, required this.width, required this.onTap});

  static const _thumb = 44.0;

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;
    final color = CategoryTheme.color(shop.category);
    final hasScheme = shop.activeScheme?.isActive ?? false;
    final open = shop.isOpen;

    return MediaQuery.withClampedTextScaling(
      // The card has a fixed height: very large system fonts would not fit in it.
      maxScaleFactor: 1.1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: FeaturedShopsSection.cardHeight,
          // Same look as the Explore tiles: white, soft shadow in the category colour, a faint
          // large category icon in the corner, and a very light border in that colour
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.14), blurRadius: 16, offset: const Offset(0, 5)),
              BoxShadow(color: AppColors.shadowPrimary, blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: -width * 0.10,
                bottom: -width * 0.10,
                child: Icon(CategoryTheme.icon(shop.category), size: width * 0.5, color: color.withValues(alpha: 0.06)),
              ),
              Padding(
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo + name / category
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: _thumb,
                      height: _thumb,
                      child: shop.images.isNotEmpty
                          ? Image.network(
                              shop.images.first,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder(color),
                            )
                          : _placeholder(color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          _categoryLabel(shop.category),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              // Address
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 11, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      shop.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              // Rating, with the "Offer" badge right beside it when a scheme is running
              Row(
                children: [
                  _rating(l),
                  if (hasScheme) ...[
                    const SizedBox(width: 6),
                    // Scales down as a whole on a very narrow card, never overflows
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _chip(Icons.local_offer_rounded, l.tr('offerBadge'), color,
                            color.withValues(alpha: 0.12)),
                      ),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              // Small open / closed badge, then queue and waiting time
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: open ? AppColors.tertiaryFixed.withValues(alpha: 0.55) : AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: open ? AppColors.tertiary : AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          l.tr(open ? 'open' : 'closed'),
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: open ? AppColors.tertiary : AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.groups_rounded, size: 12, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      shop.isQueuePausedByOwner
                          ? l.tr('queuePausedShort')
                          : '${shop.queueCount} · ~${shop.queueCount * shop.avgWaitMinutes} ${l.tr('minShort')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rating(LocaleService l) {
    final count = shop.reviewCount;
    final avg = shop.avgReviewRating;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 15, color: count > 0 ? const Color(0xFFF59E0B) : AppColors.outline.withValues(alpha: 0.5)),
        const SizedBox(width: 3),
        Text(
          count > 0 ? avg.toStringAsFixed(1) : l.tr('newShop'),
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onSurface),
        ),
        if (count > 0) ...[
          const SizedBox(width: 3),
          Text(
            '($count)',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _chip(IconData icon, String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg),
              ),
            ),
          ],
        ),
      );

  Widget _placeholder(Color color) => Container(
        color: color.withValues(alpha: 0.12),
        child: Icon(CategoryTheme.icon(shop.category), color: color, size: 22),
      );

  static String _categoryLabel(String category) {
    for (final (key, label) in featuredTabs) {
      if (key == category) return LocaleService.instance.tr(label);
    }
    return category;
  }
}
