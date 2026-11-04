import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_theme.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../services/shop_service.dart';
import '../../services/queue_service.dart';
import '../../services/notification_service.dart';
import '../../services/queue_monitor_service.dart';
import '../../widgets/profile_details_card.dart';
import '../auth/login_screen.dart';
import '../help_support_screen.dart';
import 'category_screen.dart';
import 'history_screen.dart';
import 'featured_section.dart';
import 'notifications_screen.dart';
import 'queue_status_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    LocaleService.instance.addListener(_onLocale);
    // Start global queue monitor so rating popup appears on any screen.
    QueueMonitorService.instance.start();
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocale);
    QueueMonitorService.instance.stop();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  /// Bumped each time a tab is opened, so My Queue and History reload instead of showing what
  /// they loaded when the app started (IndexedStack keeps every tab alive).
  int _openCount = 0;

  /// Switches tab straight away; the tab itself loads its data (no waiting on the network first).
  void _onNavTap(int i) {
    setState(() {
      _currentIndex = i;
      _openCount++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeTab(refreshSignal: _currentIndex == 0 ? _openCount : null),
      _QueueTab(
        refreshSignal: _currentIndex == 1 ? _openCount : null,
        onGoHome: () => _onNavTap(0),
      ),
      _HistoryTab(
        refreshSignal: _currentIndex == 2 ? _openCount : null,
        onGoHome: () => _onNavTap(0),
      ),
      const _ProfileTab(),
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }
}

// ─── Bottom navigation ────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;
    final items = [
      (Icons.home_rounded, Icons.home_outlined, l.tr('home')),
      (Icons.confirmation_number_rounded, Icons.confirmation_number_outlined, l.tr('myQueue')),
      (Icons.history_rounded, Icons.history_outlined, l.tr('historyTab')),
      (Icons.person_rounded, Icons.person_outline_rounded, l.tr('profile')),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowPrimary,
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final (activeIcon, inactiveIcon, label) = items[i];
              final isActive = currentIndex == i;
              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: isActive ? 18 : 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: isActive ? AppColors.primaryGradient135 : null,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? activeIcon : inactiveIcon,
                        color: isActive ? Colors.white : AppColors.onSurfaceVariant,
                        size: 22,
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 7),
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─── Home tab ─────────────────────────────────────────────────────────────────

class _HomeTab extends StatefulWidget {
  /// Changes each time the Home tab is opened again (null while hidden): reload and reshuffle.
  final int? refreshSignal;
  const _HomeTab({this.refreshSignal});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  // Shown top to bottom in this order.
  static const _categories = [
    _CategoryInfo(name: 'Salon'),
    _CategoryInfo(name: 'Beauty Parlour'),
    _CategoryInfo(name: 'Hospital/Clinics', categoryKey: 'Hospital/Clinic'),
    _CategoryInfo(name: 'Garage'),
  ];

  List<ShopModel> _allShops = [];
  /// Promoted shops of the selected city, shuffled on every load (see [shuffledFeaturedShops]).
  List<ShopModel> _featured = [];
  bool _isLoading = true;
  String? _loadError;
  String? _selectedCity;
  List<String> _availableCities = [];
  int _unreadCount = 0;
  static const _cityPrefKey = 'selected_city';

  // Measured section heights, used to size the Explore cards so that Featured + Explore fit on
  // one screen (without Featured, the four Explore cards are all the home screen shows).
  final _heroKey = GlobalKey();
  final _featuredKey = GlobalKey();
  final _exploreHeaderKey = GlobalKey();
  double _viewportHeight = 0;
  double _heroHeight = 0;
  double _featuredHeight = 0;
  double _exploreHeaderHeight = 0;

  @override
  void initState() {
    super.initState();
    _initCity();
    _loadUnreadCount();
  }

  @override
  void didUpdateWidget(_HomeTab old) {
    super.didUpdateWidget(old);
    if (widget.refreshSignal != null && widget.refreshSignal != old.refreshSignal) {
      _loadShops(quiet: true);
      _loadUnreadCount();
    }
  }

  double _heightOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : 0;
  }

  void _measure() {
    if (!mounted) return;
    final hero = _heightOf(_heroKey);
    final featured = _heightOf(_featuredKey);
    final header = _heightOf(_exploreHeaderKey);
    bool changed(double a, double b) => (a - b).abs() > 0.5;
    if (changed(hero, _heroHeight) || changed(featured, _featuredHeight) ||
        changed(header, _exploreHeaderHeight)) {
      setState(() {
        _heroHeight = hero;
        _featuredHeight = featured;
        _exploreHeaderHeight = header;
      });
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final data = await NotificationService.instance.getNotifications();
      final count = data['unread_count'] as int? ?? 0;
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  Future<void> _initCity() async {
    // Always default to user's profile city; only override if they explicitly saved a different city
    final profileCity = AuthService.instance.profile?['city'] as String?;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_cityPrefKey);
    // If saved city exists use it, otherwise lock to profile city
    final city = saved ?? (profileCity?.isNotEmpty == true ? profileCity : null);
    if (mounted) setState(() => _selectedCity = city);
    // Ensure profile city is saved as default so it persists
    if (saved == null && profileCity != null && profileCity.isNotEmpty) {
      await prefs.setString(_cityPrefKey, profileCity);
    }
    await Future.wait([_loadShops(), _loadCities()]);
  }

  Future<void> _loadCities() async {
    try {
      final cities = await ShopService.instance.getCities();
      if (mounted) setState(() => _availableCities = cities);
    } catch (_) {}
  }

  /// [quiet]: refresh in the background (coming back to the Home tab) without the loading state.
  Future<void> _loadShops({bool quiet = false}) async {
    try {
      if (!quiet) setState(() { _isLoading = true; _loadError = null; });
      final city = _selectedCity;
      final shops = await ShopService.instance.listShops(city: city);
      // A slower answer for a city the user has since switched away from is dropped.
      if (!mounted || city != _selectedCity) return;
      setState(() {
        _allShops = shops;
        _featured = shuffledFeaturedShops(shops);
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !quiet) setState(() { _isLoading = false; _loadError = e.toString(); });
    }
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

  String get _userName {
    final profile = AuthService.instance.profile;
    if (profile == null) return 'there';
    final name = profile['name'] as String? ?? 'there';
    return name.split(' ').first;
  }

  bool get _showFeatured => !_isLoading && _featured.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return LayoutBuilder(builder: (context, box) {
      _viewportHeight = box.maxHeight;
      return _buildScroll(context);
    });
  }

  Widget _buildScroll(BuildContext context) {
    return CustomScrollView(
      // Home is sized to fit one screen (Explore cards shrink when Featured is shown), so with
      // clamping physics it doesn't move at all. If it ever can't fit (tiny phone, very large
      // system font) it still scrolls, so nothing is cut off.
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: KeyedSubtree(key: _heroKey, child: _buildHero(context))),
        if (_loadError != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loadError!,
                        style: const TextStyle(fontSize: 12, color: AppColors.onErrorContainer),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadShops,
                      child: const Icon(Icons.refresh_rounded, color: AppColors.error, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_showFeatured)
          SliverToBoxAdapter(
            child: Padding(
              key: _featuredKey,
              padding: const EdgeInsets.only(top: 16),
              child: FeaturedShopsSection(shops: _featured),
            ),
          ),
        SliverToBoxAdapter(child: _buildCategoryGrid(context)),
        const SliverToBoxAdapter(child: SizedBox(height: 8)), // = the 'breathing' room in _categoryCardHeight
      ],
    );
  }

  // ── Hero section ────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F4CDD), Color(0xFF5B3CDD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Decorative bubbles
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: size.width * 0.45,
              height: size.width * 0.45,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            right: size.width * 0.15,
            bottom: 40,
            child: Container(
              width: size.width * 0.22,
              height: size.width * 0.22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            left: -30,
            bottom: -30,
            child: Container(
              width: size.width * 0.35,
              height: size.width * 0.35,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Content
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: greeting + notification
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              LocaleService.instance.tr('hello', params: {'name': _userName}),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              LocaleService.instance.tr('findYourSpot'),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.78),
                                letterSpacing: 0.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                          );
                          _loadUnreadCount();
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.notifications_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            if (_unreadCount > 0)
                              Positioned(
                                right: 9,
                                top: 9,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF5252),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // City filter pill
                  GestureDetector(
                    onTap: _showCitySheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_outlined, color: Colors.white, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            _selectedCity ?? 'All Cities',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 14),
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

  // ── 2×2 Category grid ───────────────────────────────────────────────────────

  static const _cardGap = 12.0;

  /// Height of each Explore card. Square when there is room; with Featured above, the two rows
  /// share what is left of the first screen (down to [_CategoryCard.minHeight]).
  double _categoryCardHeight(double cardWidth, double topPad) {
    if (_viewportHeight <= 0 || _heroHeight <= 0 || _exploreHeaderHeight <= 0) return cardWidth;
    final featured = _showFeatured ? _featuredHeight : 0.0;
    const spacing = 14.0, breathing = 8.0;
    final room = _viewportHeight - _heroHeight - featured - topPad - _exploreHeaderHeight - spacing - breathing;
    final max = cardWidth > _CategoryCard.minHeight ? cardWidth : _CategoryCard.minHeight;
    return ((room - _cardGap) / 2).clamp(_CategoryCard.minHeight, max);
  }

  Widget _buildCategoryGrid(BuildContext context) {
    final topPad = _showFeatured ? 14.0 : 24.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            key: _exploreHeaderKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleService.instance.tr('explore'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                LocaleService.instance.tr('findYourSpot'),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 2 x 2: Salon | Beauty Parlour, Hospital/Clinics | Garage
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - _cardGap) / 2;
              final height = _categoryCardHeight(width, topPad);
              Widget card(int i) => _CategoryCard(
                    info: _categories[i],
                    width: width,
                    height: height,
                    allShops: _allShops,
                    isLoading: _isLoading,
                    selectedCity: _selectedCity,
                  );
              return Column(
                children: [
                  Row(children: [card(0), const SizedBox(width: _cardGap), card(1)]),
                  const SizedBox(height: _cardGap),
                  Row(children: [card(2), const SizedBox(width: _cardGap), card(3)]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

}

// ─── Category data model ─────────────────────────────────────────────────────

class _CategoryInfo {
  final String name;
  /// The category stored on shops, when it differs from the name shown ('Hospital/Clinic').
  final String? categoryKey;

  const _CategoryInfo({required this.name, this.categoryKey});

  String get filterKey => categoryKey ?? name;
  Color get color => CategoryTheme.color(filterKey);
  List<Color> get gradient => CategoryTheme.gradient(filterKey);
  IconData get icon => CategoryTheme.icon(filterKey);
}

// ─── Explore category card (2 x 2 grid tile) ─────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final _CategoryInfo info;
  final double width;
  final double height;
  final List<ShopModel> allShops;
  final bool isLoading;
  final String? selectedCity;

  /// Below [compactBelow] the tile puts the icon beside the text instead of above it; at
  /// [minHeight] it still shows the icon, the whole name and the open / shops line.
  static const minHeight = 60.0;
  static const compactBelow = 104.0;
  static const _maxTextScale = 1.15;

  const _CategoryCard({
    required this.info,
    required this.width,
    required this.height,
    required this.allShops,
    required this.isLoading,
    this.selectedCity,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryScreen(
          category: widget.info.filterKey,
          title: widget.info.name,
          initialCity: widget.selectedCity,
        ),
      ),
    );
  }

  /// Rounded square in a light tint of the category colour, with the icon in that colour.
  Widget _iconTile(double size) {
    final c = widget.info.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(widget.info.icon, color: c, size: size * 0.54),
    );
  }

  /// Name, then a dot + "3 open · 4 shops". [twoLineName]: on a tall tile a long name may wrap
  /// ("Hospital/ Clinics"); otherwise it stays on one line and shrinks a little - never "...".
  Widget _texts({
    required double nameSize,
    required double infoSize,
    required int openCount,
    required int shopCount,
    required bool twoLineName,
  }) {
    final status = widget.isLoading ? 'Loading…' : '$openCount open · $shopCount shops';
    final nameStyle = GoogleFonts.plusJakartaSans(
      fontSize: nameSize,
      fontWeight: FontWeight.w700,
      color: AppColors.onSurface,
      height: 1.2,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (twoLineName)
          Text(widget.info.name, maxLines: 2, style: nameStyle)
        else
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(widget.info.name, maxLines: 1, style: nameStyle),
          ),
        SizedBox(height: twoLineName ? 6 : 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: openCount > 0 ? AppColors.tertiary : AppColors.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                status,
                maxLines: 1,
                style: GoogleFonts.inter(fontSize: infoSize, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final c = info.color;
    final w = widget.width;
    final h = widget.height;
    final compact = h < _CategoryCard.compactBelow;
    final shops = widget.allShops.where((e) => e.category == info.filterKey);
    final shopCount = shops.length;
    final openCount = shops.where((e) => e.isOpen && e.hasActiveSubscription).length;
    // Upper limits that follow the tile height, never below the lower limit (clamp would throw).
    final padMax = h * 0.12 > 12.0 ? h * 0.12 : 12.0;
    final tileMax = h * 0.32 > 34.0 ? h * 0.32 : 34.0;
    final pad = compact ? 10.0 : (w * 0.105).clamp(12.0, 18.0).clamp(12.0, padMax);
    final tile = compact ? (h - 2 * pad).clamp(30.0, 40.0) : (w * 0.30).clamp(34.0, 52.0).clamp(34.0, tileMax);
    final nameSize = compact ? 14.0 : (w * 0.105).clamp(14.0, 17.0);
    // A long name may use two lines only when the tile is close to square (as tall as the design).
    final twoLineName = !compact && h >= w * 0.98;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        _open();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: _CategoryCard._maxTextScale,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(color: c.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6)),
                BoxShadow(color: AppColors.shadowPrimary, blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Large faded icon in the bottom-right corner - decoration only
                Positioned(
                  right: -w * 0.11,
                  bottom: -w * 0.11,
                  child: Icon(info.icon, size: compact ? h * 1.05 : w * 0.62, color: c.withValues(alpha: 0.06)),
                ),
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: compact
                      // Short tile: icon beside the text
                      ? Row(
                          children: [
                            _iconTile(tile),
                            const SizedBox(width: 9),
                            Expanded(
                              child: _texts(
                                nameSize: nameSize,
                                infoSize: 10.5,
                                openCount: openCount,
                                shopCount: shopCount,
                                twoLineName: false,
                              ),
                            ),
                          ],
                        )
                      // Full tile: icon + arrow on top, name and status at the bottom
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _iconTile(tile),
                                const Spacer(),
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(color: c.withValues(alpha: 0.10), shape: BoxShape.circle),
                                  child: Icon(Icons.arrow_forward_rounded, color: c, size: 16),
                                ),
                              ],
                            ),
                            const Spacer(),
                            _texts(
                              nameSize: nameSize,
                              infoSize: 11.5,
                              openCount: openCount,
                              shopCount: shopCount,
                              twoLineName: twoLineName,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Search tab ───────────────────────────────────────────────────────────────

// ─── Queue tab ────────────────────────────────────────────────────────────────

class _QueueTab extends StatefulWidget {
  final VoidCallback? onGoHome;
  /// Changes each time the tab is opened (null while another tab is showing): reload then.
  final int? refreshSignal;
  const _QueueTab({this.onGoHome, this.refreshSignal});

  @override
  State<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<_QueueTab> {
  List<QueueEntry> _entries = [];
  bool _isLoading = true;
  bool _failed = false;
  bool _loadingNow = false;

  @override
  void initState() {
    super.initState();
    LocaleService.instance.addListener(_onLocale);
    _loadQueue();
  }

  @override
  void didUpdateWidget(_QueueTab old) {
    super.didUpdateWidget(old);
    if (widget.refreshSignal != null && widget.refreshSignal != old.refreshSignal) {
      _loadQueue();
    }
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocale);
    super.dispose();
  }

  void _onLocale() => setState(() {});

  /// Keeps what is already on screen while refreshing; a full-screen spinner only on first load.
  Future<void> _loadQueue() async {
    if (_loadingNow) return;
    _loadingNow = true;
    try {
      final entries = await QueueService.instance.getMyStatus();
      final active = entries.where((e) =>
        e.status == QueueStatus.waiting ||
        e.status == QueueStatus.almostThere ||
        e.status == QueueStatus.yourTurn,
      ).toList();
      if (mounted) setState(() { _entries = active; _isLoading = false; _failed = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _failed = true; });
    } finally {
      _loadingNow = false;
    }
  }

  Future<void> _retry() async {
    setState(() { _isLoading = true; _failed = false; });
    await _loadQueue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          LocaleService.instance.tr('myQueue'),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadQueue,
              child: _entries.isEmpty
                  // Scrollable so pull-to-refresh also works on the empty / error state
                  ? LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: _failed ? _buildErrorState() : _buildEmptyState(context),
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _entries.length,
                      itemBuilder: (_, i) => _QueueEntryCard(
                        entry: _entries[i],
                        onTrack: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => QueueStatusScreen(entry: _entries[i]),
                          ),
                        ).then((_) => _loadQueue()),
                      ),
                    ),
            ),
    );
  }

  Widget _buildErrorState() {
    final l = LocaleService.instance;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.error.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              l.tr('couldNotLoadQueue'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: _retry, child: Text(l.tr('retry'))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.08),
                    AppColors.secondary.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.confirmation_number_outlined,
                size: 52,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              LocaleService.instance.tr('notInQueue'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              LocaleService.instance.tr('notInQueueSub'),
              style: GoogleFonts.inter(
                  fontSize: 14, color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => widget.onGoHome?.call(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient135,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  LocaleService.instance.tr('allShops'),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueEntryCard extends StatelessWidget {
  final QueueEntry entry;
  final VoidCallback onTrack;

  const _QueueEntryCard({required this.entry, required this.onTrack});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTrack,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: AppColors.shadowPrimary,
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient135,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Text(
                  entry.token,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.shopName,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.peopleAhead} ahead · ~${entry.estimatedWaitMinutes} min wait',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient135,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                LocaleService.instance.tr('live'),
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── History tab ─────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  final VoidCallback? onGoHome;
  final int? refreshSignal;
  const _HistoryTab({this.onGoHome, this.refreshSignal});

  @override
  Widget build(BuildContext context) {
    return HistoryScreen(onGoHome: onGoHome, refreshSignal: refreshSignal);
  }
}

// ─── Profile tab ──────────────────────────────────────────────────────────────

Future<void> _showDeleteAccountFlow(BuildContext context) async {
  final l = LocaleService.instance;
  final controller = TextEditingController();

  final typed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 22),
          const SizedBox(width: 8),
          Text(l.tr('deleteAccount'),
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.error)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.tr('deleteAccountWarning'),
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5)),
            const SizedBox(height: 16),
            Text(l.tr('typeDeleteConfirm'),
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              onChanged: (_) => setS(() {}),
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'DELETE',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.4))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.error, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.tr('cancel'),
                style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: controller.text.trim() == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
            child: Text(l.tr('confirmDelete'),
                style: GoogleFonts.inter(
                    color: controller.text.trim() == 'DELETE' ? AppColors.error : AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (typed != true || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(l.tr('deleteConfirmTitle'),
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 18)),
      content: Text(l.tr('deleteConfirmBody'),
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.tr('noKeep'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.onSurface)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.tr('yesDelete'),
              style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await AuthService.instance.deleteAccount();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (r) => false,
      );
    }
  } catch (_) {
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LocaleService.instance.tr('deleteAccountFailed'),
            style: GoogleFonts.inter()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  void _showLanguageSheet(BuildContext context) {
    final l = LocaleService.instance;
    final langs = [
      (kLangEn, l.tr('english')),
      (kLangHi, l.tr('hindi')),
      (kLangMr, l.tr('marathi')),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final current = LocaleService.instance.lang;
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 32, offset: const Offset(0, -8))],
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.outline.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 20),
                Text(l.tr('selectLanguage'),
                    style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                const SizedBox(height: 16),
                ...langs.map((entry) {
                  final (code, label) = entry;
                  final selected = current == code;
                  return GestureDetector(
                    onTap: () {
                      LocaleService.instance.setLanguage(code);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                      decoration: BoxDecoration(
                        gradient: selected ? AppColors.primaryGradient135 : null,
                        color: selected ? null : AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: selected ? [] : [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Row(
                        children: [
                          Text(label, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : AppColors.onSurface)),
                          const Spacer(),
                          if (selected) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l = LocaleService.instance;
    final profile = AuthService.instance.profile;
    final name = profile?['name'] as String? ?? 'User';
    final phone = profile?['phone'] as String? ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final displayPhone =
        phone.length > 3 ? '+91 ${phone.substring(3)}' : phone;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          // Gradient header
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1F4CDD), Color(0xFF5B3CDD)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    children: [
                      // Avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2),
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayPhone,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Customer badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_rounded,
                                color: Colors.white, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              l.tr('customer'),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Menu items
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ProfileDetailsCard(),
                  const SizedBox(height: 24),
                  Text(
                    l.tr('profile').toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ProfileSection(
                    items: [
                      _ProfileTile(
                        icon: Icons.notifications_outlined,
                        label: l.tr('notifications'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const NotificationsScreen()),
                        ),
                      ),
                      _ProfileTile(
                        icon: Icons.language_rounded,
                        label: l.tr('changeLanguage'),
                        onTap: () => _showLanguageSheet(context),
                        trailing: Text(
                          l.lang == kLangEn ? l.tr('english') : l.lang == kLangHi ? l.tr('hindi') : l.tr('marathi'),
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l.tr('helpSupport').toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ProfileSection(
                    items: [
                      _ProfileTile(
                        icon: Icons.help_outline_rounded,
                        label: l.tr('helpSupport'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // Sign out button
                  GestureDetector(
                    onTap: () async {
                      await AuthService.instance.logout();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (r) => false,
                        );
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout_rounded,
                              color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            l.tr('signOut'),
                            style: GoogleFonts.inter(
                              color: AppColors.error,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Delete account button
                  GestureDetector(
                    onTap: () => _showDeleteAccountFlow(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.delete_outline_rounded,
                              color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            l.tr('deleteAccount'),
                            style: GoogleFonts.inter(
                              color: AppColors.error,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final List<_ProfileTile> items;
  const _ProfileSection({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowPrimary,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (i) {
          final tile = items[i];
          final isLast = i == items.length - 1;
          return Column(
            children: [
              GestureDetector(
                onTap: tile.onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(tile.icon,
                            color: AppColors.primary, size: 19),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          tile.label,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (tile.trailing != null) ...[
                        const SizedBox(width: 8),
                        tile.trailing!,
                        const SizedBox(width: 6),
                      ],
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.onSurfaceVariant, size: 20),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.only(left: 66),
                  child: Container(
                    height: 1,
                    color: AppColors.surfaceContainerLow,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _ProfileTile {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });
}

// ─── Searchable city picker sheet ─────────────────────────────────────────────

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
          : widget.availableCities.where((c) => c.toLowerCase().contains(q)).toList();
    });
  }

  void _pick(String? city) {
    Navigator.pop(context);
    widget.onSelect(city);
  }

  @override
  Widget build(BuildContext context) {
    final profileCity = AuthService.instance.profile?['city'] as String?;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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
            // Handle + header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.outline.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  Text('Select City', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Shops from your city are shown by default', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  // Search box
                  TextField(
                    controller: _searchCtrl,
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: 'Search city…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            // City list
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                children: [
                  // My city (profile city) shortcut — always shown first if available
                  if (profileCity != null && profileCity.isNotEmpty && _searchCtrl.text.isEmpty) ...[
                    _CityTile(
                      city: profileCity,
                      label: '$profileCity (My City)',
                      isSelected: widget.selectedCity?.toLowerCase() == profileCity.toLowerCase(),
                      onTap: () => _pick(profileCity),
                    ),
                    const SizedBox(height: 8),
                    // Divider label
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('ALL CITIES', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.onSurfaceVariant)),
                    ),
                  ],
                  ..._filtered
                      .where((c) => c != profileCity || _searchCtrl.text.isNotEmpty)
                      .map((city) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CityTile(
                          city: city,
                          label: city,
                          isSelected: widget.selectedCity?.toLowerCase() == city.toLowerCase(),
                          onTap: () => _pick(city),
                        ),
                      )),
                  if (_filtered.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No cities found', style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant)),
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

class _CityTile extends StatelessWidget {
  final String city;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CityTile({required this.city, required this.label, required this.isSelected, required this.onTap});

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
          boxShadow: isSelected ? [] : [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 16,
              color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppColors.onSurface),
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
