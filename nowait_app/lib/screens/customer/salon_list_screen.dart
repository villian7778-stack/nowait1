import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/shop_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_theme.dart';
import '../../widgets/shop_card.dart' show ShopCard, showSchemeSheet;
import 'shop_details_screen.dart';

class SalonListScreen extends StatefulWidget {
  final String? category;
  final String? initialCity;
  final bool autofocusSearch;

  const SalonListScreen({super.key, this.category, this.initialCity, this.autofocusSearch = false});

  @override
  State<SalonListScreen> createState() => _SalonListScreenState();
}

class _SalonListScreenState extends State<SalonListScreen> {
  String _activeFilter = 'Near Me';
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<ShopModel> _shops = [];
  bool _isLoading = true;
  String? _selectedCity;
  final _l = LocaleService.instance;

  final _filters = ['Near Me', 'Top Rated', 'Wait Time', 'Open Now'];

  @override
  void initState() {
    super.initState();
    _l.addListener(_onLocale);
    _selectedCity = widget.initialCity;
    _loadShops();
    if (widget.autofocusSearch) {
      // Defer focus until widget is built
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocusNode.requestFocus());
    }
  }

  void _onLocale() => setState(() {});

  Future<void> _loadShops() async {
    setState(() => _isLoading = true);
    try {
      final shops = await ShopService.instance.listShops(city: _selectedCity);
      if (mounted) setState(() { _shops = shops; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<ShopModel> get _filteredShops {
    var shops = [..._shops];

    // Pre-filter by category if provided
    if (widget.category != null) {
      shops = shops.where((s) => s.category == widget.category).toList();
    }

    // Filter by open status where required
    if (_activeFilter == 'Wait Time' || _activeFilter == 'Open Now') {
      shops = shops.where((s) => s.isOpen).toList();
    }

    final q = _searchController.text.toLowerCase();
    if (q.isNotEmpty) {
      shops = shops
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              s.category.toLowerCase().contains(q) ||
              s.address.toLowerCase().contains(q) ||
              s.city.toLowerCase().contains(q))
          .toList();
    }

    // Sort: promoted always float to top, then by active filter within each group
    shops.sort((a, b) {
      if (a.isPromoted != b.isPromoted) return a.isPromoted ? -1 : 1;
      switch (_activeFilter) {
        case 'Top Rated':
          return b.rating.compareTo(a.rating);
        case 'Wait Time':
          return a.avgWaitMinutes.compareTo(b.avgWaitMinutes);
        default:
          return 0;
      }
    });

    return shops;
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.surface.withValues(alpha: 0.95),
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            leading: Navigator.canPop(context)
                ? IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                : null,
            title: Text(
              widget.category != null
                  ? '${widget.category} Shops'
                  : 'Discover Shops',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_horiz_rounded),
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(104),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    // Search bar
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.shadowPrimary,
                              blurRadius: 12,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search by name or service...',
                          prefixIcon: Icon(Icons.search_rounded, size: 20),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Filter chips
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _filters.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final f = _filters[i];
                          final active = _activeFilter == f;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _activeFilter = f),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: active
                                    ? AppColors.primaryGradient135
                                    : null,
                                color: active
                                    ? null
                                    : AppColors.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: active
                                      ? Colors.transparent
                                      : AppColors.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                f,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? Colors.white
                                      : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Results count + sort
                        Row(
                          children: [
                            Text(
                              '${_filteredShops.length} results',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.onSurfaceVariant),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.sort_rounded,
                                      size: 14,
                                      color: AppColors.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Text('Sort',
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color:
                                              AppColors.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Promoted shops section — shown in all filters
                        _buildPromotedSection(context),
                        if (_filteredShops.any((s) => s.isPromoted))
                          const SizedBox(height: 20),
                        ..._filteredShops.map((shop) => ShopCard(
                              shop: shop,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ShopDetailsScreen(shop: shop)),
                              ),
                              onSchemeTap: shop.activeScheme != null &&
                                      shop.activeScheme!.isActive
                                  ? () => showSchemeSheet(
                                      context, shop.activeScheme!)
                                  : null,
                            )),
                        if (_filteredShops.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(40),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.search_off_rounded,
                                      size: 48,
                                      color: AppColors.onSurfaceVariant
                                          .withValues(alpha: 0.4)),
                                  const SizedBox(height: 12),
                                  Text('No shops found',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              AppColors.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotedSection(BuildContext context) {
    final promoted = _filteredShops.where((s) => s.isPromoted).toList();
    if (promoted.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient135,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Promoted',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...promoted.map((shop) => _PromotedShopCard(
              shop: shop,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ShopDetailsScreen(shop: shop)),
              ),
            )),
      ],
    );
  }
}

class _PromotedShopCard extends StatelessWidget {
  final ShopModel shop;
  final VoidCallback onTap;

  const _PromotedShopCard({required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
                color: AppColors.shadowPrimary,
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            // Hero image area
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 100,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (shop.images.isNotEmpty)
                      Image.network(
                        shop.images.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _gradientPlaceholder(),
                      )
                    else
                      _gradientPlaceholder(),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient135,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, size: 10, color: Colors.white),
                          SizedBox(width: 3),
                          Text('Promoted', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.name,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${shop.category} • ${shop.distance}',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFFFB800), size: 14),
                          const SizedBox(width: 3),
                          Text(shop.rating.toString(),
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shop.isOpen
                            ? '~${shop.avgWaitMinutes} min'
                            : LocaleService.instance.tr('closed'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: shop.isOpen
                              ? AppColors.tertiary
                              : AppColors.error,
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _gradientPlaceholder() {
    final colors = CategoryTheme.gradient(shop.category);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors[0].withValues(alpha: 0.8), colors[1].withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(CategoryTheme.icon(shop.category), color: Colors.white.withValues(alpha: 0.3), size: 60)),
    );
  }
}
