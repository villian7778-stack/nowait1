import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';
import '../../services/shop_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_theme.dart';
import '../../widgets/shop_card.dart' show showSchemeSheet;
import 'shop_details_screen.dart';

IconData _categoryIconFor(String category) => CategoryTheme.icon(category);

class CategoryScreen extends StatefulWidget {
  final String category;
  /// City passed from the home screen. If null, falls back to SharedPreferences.
  final String? initialCity;

  const CategoryScreen({super.key, required this.category, this.initialCity});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  static const _cityPrefKey = 'selected_city';
  final _searchController = TextEditingController();
  String _filterType = 'Name';
  String _filterQuery = '';
  List<ShopModel> _allShops = [];
  bool _isLoading = true;
  String? _selectedCity;
  List<String> _availableCities = [];
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _l.addListener(_onLocale);
    _initCity();
  }

  void _onLocale() => setState(() {});

  Future<void> _initCity() async {
    if (widget.initialCity != null) {
      setState(() => _selectedCity = widget.initialCity);
      await Future.wait([_loadShops(), _loadCities()]);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_cityPrefKey);
    if (mounted) setState(() => _selectedCity = saved);
    await Future.wait([_loadShops(), _loadCities()]);
  }

  Future<void> _loadCities() async {
    try {
      final cities = await ShopService.instance.getCities();
      if (mounted) setState(() => _availableCities = cities);
    } catch (_) {}
  }

  Future<void> _loadShops() async {
    try {
      final shops = await ShopService.instance
          .listShops(category: widget.category, city: _selectedCity);
      if (mounted) setState(() { _allShops = shops; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectCity(String? city) async {
    final prefs = await SharedPreferences.getInstance();
    if (city != null) {
      await prefs.setString(_cityPrefKey, city);
    } else {
      await prefs.remove(_cityPrefKey);
    }
    setState(() { _selectedCity = city; _isLoading = true; });
    await _loadShops();
  }

  void _showCitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CityPickerSheet(
        selectedCity: _selectedCity,
        availableCities: _availableCities,
        onSelect: (city) => _selectCity(city),
      ),
    );
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _searchController.dispose();
    super.dispose();
  }

  List<ShopModel> get _promotedShops =>
      _allShops.where((s) => s.isPromoted && s.hasActiveSubscription).toList();

  List<ShopModel> get _filteredShops {
    var shops = [..._allShops];
    if (_filterQuery.trim().isNotEmpty) {
      final q = _filterQuery.toLowerCase().trim();
      shops = shops.where((s) {
        switch (_filterType) {
          case 'Address':
            return s.address.toLowerCase().contains(q);
          case 'City':
            return s.city.toLowerCase().contains(q);
          default:
            return s.name.toLowerCase().contains(q);
        }
      }).toList();
    }
    // Promoted shops always float to top
    shops.sort((a, b) {
      if (a.isPromoted && !b.isPromoted) return -1;
      if (!a.isPromoted && b.isPromoted) return 1;
      return 0;
    });
    return shops;
  }

  IconData get _categoryIcon => CategoryTheme.icon(widget.category);
  Color get _categoryColor => CategoryTheme.color(widget.category);
  List<Color> get _categoryGradient => CategoryTheme.gradient(widget.category);

  List<CategoryProduct> get _products {
    switch (widget.category) {
      case 'Salon': return const [
        CategoryProduct(name: 'Haircut', icon: '✂️', priceFrom: '₹149'),
        CategoryProduct(name: 'Beard Trim', icon: '🪒', priceFrom: '₹99'),
        CategoryProduct(name: 'Hair Color', icon: '🎨', priceFrom: '₹499'),
        CategoryProduct(name: 'Head Massage', icon: '💆', priceFrom: '₹149'),
        CategoryProduct(name: 'Threading', icon: '🧵', priceFrom: '₹50'),
        CategoryProduct(name: 'Kids Cut', icon: '👶', priceFrom: '₹99'),
        CategoryProduct(name: 'Shave', icon: '🪮', priceFrom: '₹80'),
        CategoryProduct(name: 'Styling', icon: '💈', priceFrom: '₹199'),
      ];
      case 'Beauty Parlour': return const [
        CategoryProduct(name: 'Facial', icon: '🧖', priceFrom: '₹349'),
        CategoryProduct(name: 'Waxing', icon: '💅', priceFrom: '₹199'),
        CategoryProduct(name: 'Manicure', icon: '💅', priceFrom: '₹199'),
        CategoryProduct(name: 'Pedicure', icon: '🦶', priceFrom: '₹249'),
        CategoryProduct(name: 'Eyebrows', icon: '👁️', priceFrom: '₹60'),
        CategoryProduct(name: 'Bleach', icon: '✨', priceFrom: '₹299'),
        CategoryProduct(name: 'Cleanup', icon: '🧴', priceFrom: '₹199'),
        CategoryProduct(name: 'Bridal', icon: '👰', priceFrom: '₹2999'),
      ];
      case 'Hospital': return const [
        CategoryProduct(name: 'General OPD', icon: '🩺', priceFrom: '₹200'),
        CategoryProduct(name: 'Emergency', icon: '🚨', priceFrom: 'Free'),
        CategoryProduct(name: 'Dentist', icon: '🦷', priceFrom: '₹300'),
        CategoryProduct(name: 'Blood Test', icon: '🩸', priceFrom: '₹150'),
        CategoryProduct(name: 'X-Ray', icon: '🔬', priceFrom: '₹400'),
        CategoryProduct(name: 'Eye Check', icon: '👁️', priceFrom: '₹250'),
        CategoryProduct(name: 'Pediatric', icon: '👶', priceFrom: '₹300'),
        CategoryProduct(name: 'Orthopedic', icon: '🦴', priceFrom: '₹500'),
      ];
      default: return const [
        CategoryProduct(name: 'Oil Change', icon: '🛢️', priceFrom: '₹399'),
        CategoryProduct(name: 'Tyre Service', icon: '🔧', priceFrom: '₹199'),
        CategoryProduct(name: 'AC Repair', icon: '❄️', priceFrom: '₹799'),
        CategoryProduct(name: 'Brake Check', icon: '🛑', priceFrom: '₹299'),
        CategoryProduct(name: 'Denting', icon: '🔨', priceFrom: '₹499'),
        CategoryProduct(name: 'Wash & Clean', icon: '🚿', priceFrom: '₹149'),
        CategoryProduct(name: 'Battery', icon: '🔋', priceFrom: '₹299'),
        CategoryProduct(name: 'Alignment', icon: '⚙️', priceFrom: '₹599'),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    final filtered = _isLoading ? <ShopModel>[] : _filteredShops;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.surface.withValues(alpha: 0.96),
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
              widget.category,
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            actions: [
              // City pill
              GestureDetector(
                onTap: _showCitySheet,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.outline.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        _selectedCity ?? 'All',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 13, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _categoryGradient),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_categoryIcon, color: Colors.white, size: 18),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── SECTION 1: Products related to this category ──────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    'Popular Services',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: products.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => _ProductChip(
                      product: products[i],
                      color: _categoryColor,
                    ),
                  ),
                ),

                // ── SECTION 2: Filter section ─────────────────────────────────
                const SizedBox(height: 24),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowPrimary,
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FILTER SHOPS',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Filter type chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['Name', 'Address', 'City'].map((type) {
                          final selected = _filterType == type;
                          return GestureDetector(
                            onTap: () => setState(() {
                              _filterType = type;
                              _filterQuery = _searchController.text;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? LinearGradient(colors: _categoryGradient)
                                    : null,
                                color: selected ? null : AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'By $type',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      // Search input
                      TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _filterQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search by ${_filterType.toLowerCase()}...',
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: _categoryColor,
                            size: 20,
                          ),
                          suffixIcon: _filterQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _filterQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _categoryColor, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── SECTION 3: Promotions & Offers ────────────────────────────
                if (_promotedShops.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 18,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: _categoryGradient),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Promotions',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: _categoryGradient),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_promotedShops.length}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 210,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _promotedShops.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                      itemBuilder: (context, i) => _PromotedShopCard(
                        shop: _promotedShops[i],
                        gradient: _categoryGradient,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShopDetailsScreen(shop: _promotedShops[i]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // ── SECTION 4: All shops ───────────────────────────────────────
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        _filterQuery.isEmpty
                            ? (_selectedCity != null
                                ? '${widget.category}s in $_selectedCity'
                                : 'All ${widget.category}s')
                            : '${filtered.length} Result${filtered.length == 1 ? '' : 's'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No shops found for "$_filterQuery"',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: filtered
                          .map((shop) => _ShopListCard(
                                shop: shop,
                                categoryColor: _categoryColor,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ShopDetailsScreen(shop: shop),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Product chip ─────────────────────────────────────────────────────────────

class _ProductChip extends StatelessWidget {
  final CategoryProduct product;
  final Color color;

  const _ProductChip({required this.product, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(product.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            product.name,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            product.priceFrom,
            style: GoogleFonts.inter(
              fontSize: 9,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Promoted shop card (horizontal scroll) ───────────────────────────────────

class _PromotedShopCard extends StatelessWidget {
  final ShopModel shop;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _PromotedShopCard({required this.shop, required this.gradient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 230,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowPrimary,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image / gradient hero
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: SizedBox(
                height: 95,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (shop.images.isNotEmpty)
                      Image.network(
                        shop.images.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                          ),
                          child: Center(child: Icon(_categoryIconFor(shop.category), color: Colors.white.withValues(alpha: 0.5), size: 48)),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                        ),
                        child: Center(child: Icon(_categoryIconFor(shop.category), color: Colors.white.withValues(alpha: 0.5), size: 48)),
                      ),
                  Positioned(
                    top: 8,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, size: 9, color: Colors.white),
                          SizedBox(width: 3),
                          Text('Featured', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: shop.isOpen
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.red.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        shop.isOpen ? LocaleService.instance.tr('open') : LocaleService.instance.tr('closed'),
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shop.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 12),
                      const SizedBox(width: 3),
                      Text(
                        shop.rating.toString(),
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.location_on_outlined, size: 11, color: AppColors.onSurfaceVariant),
                      Text(
                        shop.distance,
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  // Scheme badge
                  if (shop.activeScheme != null &&
                      shop.activeScheme!.isActive) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => showSchemeSheet(context, shop.activeScheme!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: gradient.first.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: gradient.first.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.local_offer_rounded,
                                size: 11, color: gradient.first),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Scheme On · ${shop.activeScheme!.title}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: gradient.first,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.chevron_right_rounded,
                                size: 12, color: gradient.first),
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
}

// ─── Shop list card ───────────────────────────────────────────────────────────

class _ShopListCard extends StatelessWidget {
  final ShopModel shop;
  final Color categoryColor;
  final VoidCallback onTap;

  const _ShopListCard({
    required this.shop,
    required this.categoryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canJoin = shop.canAcceptQueue;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowPrimary,
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Shop image thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: shop.images.isNotEmpty
                  ? Image.network(
                      shop.images.first,
                      width: 68,
                      height: 68,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _iconThumbnail(categoryColor),
                    )
                  : _iconThumbnail(categoryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + promoted badge
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
                            gradient: LinearGradient(
                                colors: _categoryGradientForColor(
                                    categoryColor)),
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
                    '${shop.address}, ${shop.city}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            // Open / Closed / Subscription required
                            _StatusPill(shop: shop),
                            if (canJoin) ...[
                              _infoBadge(Icons.group_outlined, '${shop.queueCount}'),
                              _infoBadge(Icons.schedule_outlined, '~${shop.avgWaitMinutes}m'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 12),
                          const SizedBox(width: 2),
                          Text(
                            shop.rating.toStringAsFixed(1),
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (shop.activeScheme != null &&
                      shop.activeScheme!.isActive) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () =>
                          showSchemeSheet(context, shop.activeScheme!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: categoryColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: categoryColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.local_offer_rounded,
                                  size: 9, color: Colors.white),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Scheme On',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: categoryColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '· ${shop.activeScheme!.title}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: categoryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right_rounded,
                                size: 13, color: categoryColor),
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

  Widget _iconThumbnail(Color color) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(_categoryIconFor(shop.category), color: color, size: 30),
      ),
    );
  }

  List<Color> _categoryGradientForColor(Color color) {
    // Slightly darken for end color to make a subtle gradient
    return [color, Color.fromARGB(
      (color.a * 255).round().clamp(0, 255),
      ((color.r * 255) * 0.85).round().clamp(0, 255),
      ((color.g * 255) * 0.85).round().clamp(0, 255),
      ((color.b * 255) * 0.85).round().clamp(0, 255),
    )];
  }

  Widget _infoBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            text,
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── City picker sheet ─────────────────────────────────────────────────────────

class _CityPickerSheet extends StatefulWidget {
  final String? selectedCity;
  final List<String> availableCities;
  final ValueChanged<String?> onSelect;

  const _CityPickerSheet({
    required this.selectedCity,
    required this.availableCities,
    required this.onSelect,
  });

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<String> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.availableCities;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.availableCities
          : widget.availableCities
              .where((c) => c.toLowerCase().contains(q))
              .toList();
    });
  }

  void _pick(String? city) {
    Navigator.pop(context);
    widget.onSelect(city);
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
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Filter by City',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Showing shops from your selected city',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search city…',
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: AppColors.outline.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: AppColors.outline.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                children: [
                  // All cities option
                  _CityOption(
                    label: 'All Cities',
                    isSelected: widget.selectedCity == null,
                    onTap: () => _pick(null),
                  ),
                  const SizedBox(height: 8),
                  ..._filtered.map((city) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CityOption(
                          label: city,
                          isSelected: widget.selectedCity?.toLowerCase() ==
                              city.toLowerCase(),
                          onTap: () => _pick(city),
                        ),
                      )),
                  if (_filtered.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No cities found',
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppColors.onSurfaceVariant)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CityOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CityOption(
      {required this.label,
      required this.isSelected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient135 : null,
          color:
              isSelected ? null : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? []
              : [
                  BoxShadow(
                      color: AppColors.shadowPrimary,
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Row(
          children: [
            Icon(Icons.location_on_outlined,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : AppColors.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : AppColors.onSurface),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ShopModel shop;

  const _StatusPill({required this.shop});

  @override
  Widget build(BuildContext context) {
    if (!shop.hasActiveSubscription) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Unavailable',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: shop.isOpen
            ? AppColors.tertiaryFixed.withValues(alpha: 0.35)
            : AppColors.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: shop.isOpen ? AppColors.tertiary : AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            shop.isOpen ? LocaleService.instance.tr('open') : LocaleService.instance.tr('closed'),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: shop.isOpen ? AppColors.onTertiaryFixed : AppColors.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}
