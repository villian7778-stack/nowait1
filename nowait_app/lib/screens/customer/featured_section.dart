import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_theme.dart';
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
    final cardWidth = (MediaQuery.sizeOf(context).width * 0.80).clamp(260.0, 320.0);

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
        const SizedBox(height: 10),
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
        const SizedBox(height: 12),
        // Promoted shop cards
        SizedBox(
          height: FeaturedShopsSection.cardHeight + 16, // + room for the card shadow
          child: ListView.separated(
            key: ValueKey(_category),
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
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

  static const _imageWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;
    final color = CategoryTheme.color(shop.category);
    final hasScheme = shop.activeScheme?.isActive ?? false;
    final open = shop.isOpen;

    return MediaQuery.withClampedTextScaling(
      // The card has a fixed height: very large system fonts would not fit in it.
      maxScaleFactor: 1.15,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: FeaturedShopsSection.cardHeight,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: AppColors.shadowPrimary, blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Photo + open / closed badge
              SizedBox(
                width: _imageWidth,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    shop.images.isNotEmpty
                        ? Image.network(
                            shop.images.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(color),
                          )
                        : _placeholder(color),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: open ? AppColors.tertiaryFixed : AppColors.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: open ? AppColors.tertiary : AppColors.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l.tr(open ? 'open' : 'closed'),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: open ? AppColors.tertiary : AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_categoryLabel(shop.category)} · ${shop.address}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      _rating(l),
                      const Spacer(),
                      Row(
                        children: [
                          Flexible(
                            child: _chip(
                              Icons.groups_rounded,
                              shop.isQueuePausedByOwner
                                  ? l.tr('queuePausedShort')
                                  : '${shop.queueCount} · ~${shop.queueCount * shop.avgWaitMinutes} ${l.tr('minShort')}',
                              AppColors.onSurfaceVariant,
                              AppColors.surfaceContainerLow,
                            ),
                          ),
                          if (hasScheme) ...[
                            const SizedBox(width: 6),
                            _chip(Icons.local_offer_rounded, l.tr('offerBadge'), color,
                                color.withValues(alpha: 0.10)),
                          ],
                        ],
                      ),
                    ],
                  ),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.28)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(CategoryTheme.icon(shop.category), color: color, size: 34),
      );

  static String _categoryLabel(String category) {
    for (final (key, label) in featuredTabs) {
      if (key == category) return LocaleService.instance.tr(label);
    }
    return category;
  }
}
