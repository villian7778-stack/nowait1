import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';
import '../../services/shop_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_theme.dart';
import '../../widgets/shop_card.dart' show ShopCard, showSchemeSheet;
import 'salon_list_screen.dart';
import 'notifications_screen.dart';
import 'shop_details_screen.dart';

class CategoryListScreen extends StatefulWidget {
  final String? initialCategory;
  final String? initialCity;

  const CategoryListScreen(
      {super.key, this.initialCategory, this.initialCity});

  @override
  State<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends State<CategoryListScreen> {
  static const _cityPrefKey = 'selected_city';
  late String _selectedCategory;
  String? _selectedCity;
  List<String> _availableCities = [];
  final _searchController = TextEditingController();
  List<ShopModel> _shops = [];
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _l.addListener(_onLocale);
    _selectedCategory = widget.initialCategory ?? 'All';
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
      final shops = await ShopService.instance.listShops(city: _selectedCity);
      if (mounted) setState(() => _shops = shops);
    } catch (_) {}
  }

  Future<void> _selectCity(String? city) async {
    final prefs = await SharedPreferences.getInstance();
    if (city != null) {
      await prefs.setString(_cityPrefKey, city);
    } else {
      await prefs.remove(_cityPrefKey);
    }
    setState(() => _selectedCity = city);
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

  List<ShopModel> get _filteredShops {
    return _shops.where((s) {
      final matchesCategory = _selectedCategory == 'All' || s.category == _selectedCategory;
      final query = _searchController.text.toLowerCase();
      final matchesSearch = query.isEmpty ||
          s.name.toLowerCase().contains(query) ||
          s.category.toLowerCase().contains(query) ||
          s.address.toLowerCase().contains(query) ||
          s.city.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['All', 'Salon', 'Beauty Parlour', 'Hospital', 'Garage'];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
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
              _selectedCategory == 'All' ? 'All Categories' : _selectedCategory,
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              // City filter pill
              GestureDetector(
                onTap: _showCitySheet,
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
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
              IconButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen())),
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications_outlined),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(116),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search shops, categories...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor: AppColors.surfaceContainerLowest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Category filter chips
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final cat = categories[i];
                          final selected = _selectedCategory == cat;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedCategory = cat),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: selected ? AppColors.primaryGradient135 : null,
                                color: selected ? null : AppColors.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected ? Colors.transparent : AppColors.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                cat,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white : AppColors.onSurfaceVariant,
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  // Banner carousel
                  SizedBox(
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length - 1,
                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final catName = categories[i + 1];
                        final cat = (name: catName, shopCount: _shops.where((s) => s.category == catName).length);
                        return GestureDetector(
                          onTap: () => setState(() => _selectedCategory = cat.name),
                          child: Container(
                            width: 160,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: CategoryTheme.gradient(cat.name),
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Icon(_catIcon(cat.name), color: Colors.white.withValues(alpha: 0.9), size: 28),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cat.name,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      '${cat.shopCount} shops',
                                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedCity != null
                              ? '${_filteredShops.length} Shops in $_selectedCity'
                              : '${_filteredShops.length} Shops',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const SalonListScreen())),
                        child: Text(
                          'Map View',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ..._filteredShops.map((shop) => ShopCard(
                    shop: shop,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ShopDetailsScreen(shop: shop)),
                    ),
                    onSchemeTap: shop.activeScheme != null &&
                            shop.activeScheme!.isActive
                        ? () => showSchemeSheet(context, shop.activeScheme!)
                        : null,
                  )),
                  if (_filteredShops.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: AppColors.onSurfaceVariant.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text(
                              _l.tr('noShopsFound'),
                              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _catIcon(String name) => CategoryTheme.icon(name);
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
                          isSelected:
                              widget.selectedCity?.toLowerCase() ==
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient135 : null,
          color: isSelected ? null : AppColors.surfaceContainerLowest,
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
