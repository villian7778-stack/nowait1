import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../services/shop_service.dart';
import '../../services/queue_service.dart';
import '../../services/notification_service.dart';
import '../auth/login_screen.dart';
import 'category_screen.dart';
import 'history_screen.dart';
import 'notifications_screen.dart';
import 'salon_list_screen.dart';
import 'shop_details_screen.dart';
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
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocale);
    super.dispose();
  }

  void _onLocale() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _HomeTab(),
      const _SearchTab(),
      const _QueueTab(),
      const _HistoryTab(),
      const _ProfileTab(),
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
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
      (Icons.search_rounded, Icons.search_outlined, l.tr('explore')),
      (Icons.confirmation_number_rounded, Icons.confirmation_number_outlined, l.tr('myQueue')),
      (Icons.history_rounded, Icons.history_outlined, 'History'),
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
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  static const _categories = [
    _CategoryInfo(
      name: 'Salon',
      subtitle: 'Haircut · Beard · Styling',
      color: Color(0xFF2563EB),
      icon: Icons.spa_outlined,
    ),
    _CategoryInfo(
      name: 'Beauty Parlour',
      subtitle: 'Facial · Waxing · Bridal',
      color: Color(0xFFDB2777),
      icon: Icons.diamond_outlined,
    ),
    _CategoryInfo(
      name: 'Hospital',
      subtitle: 'OPD · Dentist · Lab Tests',
      color: Color(0xFF059669),
      icon: Icons.favorite_outline_rounded,
    ),
    _CategoryInfo(
      name: 'Garage',
      subtitle: 'Oil · Tyres · AC Repair',
      color: Color(0xFFD97706),
      icon: Icons.settings_outlined,
    ),
  ];

  List<ShopModel> _allShops = [];
  bool _isLoading = true;
  String? _loadError;
  String? _selectedCity;
  List<String> _availableCities = [];
  int _unreadCount = 0;
  static const _cityPrefKey = 'selected_city';

  @override
  void initState() {
    super.initState();
    _initCity();
    _loadUnreadCount();
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

  Future<void> _loadShops() async {
    try {
      setState(() { _isLoading = true; _loadError = null; });
      final shops = await ShopService.instance.listShops(city: _selectedCity);
      if (mounted) setState(() { _allShops = shops; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _loadError = e.toString(); });
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

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHero(context)),
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
        SliverToBoxAdapter(child: _buildCategoryGrid(context)),
        SliverToBoxAdapter(child: _buildOpenNow(context)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
                            ),
                            const SizedBox(height: 5),
                            Text(
                              LocaleService.instance.tr('findYourSpot'),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.78),
                                letterSpacing: 0.1,
                              ),
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
                  const SizedBox(height: 14),
                  // Search bar
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SalonListScreen(
                        initialCity: _selectedCity,
                        autofocusSearch: true,
                      )),
                    ),
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded,
                              color: AppColors.onSurfaceVariant, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              LocaleService.instance.tr('searchByName'),
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ),
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

  Widget _buildCategoryGrid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
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
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final gap = 12.0;
              final cardSize = (constraints.maxWidth - gap) / 2;
              return Column(
                children: [
                  Row(
                    children: [
                      _CategoryGridCard(
                        info: _categories[0],
                        cardSize: cardSize,
                        allShops: _allShops,
                        isLoading: _isLoading,
                        selectedCity: _selectedCity,
                      ),
                      SizedBox(width: gap),
                      _CategoryGridCard(
                        info: _categories[1],
                        cardSize: cardSize,
                        allShops: _allShops,
                        isLoading: _isLoading,
                        selectedCity: _selectedCity,
                      ),
                    ],
                  ),
                  SizedBox(height: gap),
                  Row(
                    children: [
                      _CategoryGridCard(
                        info: _categories[2],
                        cardSize: cardSize,
                        allShops: _allShops,
                        isLoading: _isLoading,
                        selectedCity: _selectedCity,
                      ),
                      SizedBox(width: gap),
                      _CategoryGridCard(
                        info: _categories[3],
                        cardSize: cardSize,
                        allShops: _allShops,
                        isLoading: _isLoading,
                        selectedCity: _selectedCity,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Open Now horizontal scroll ───────────────────────────────────────────────

  Widget _buildOpenNow(BuildContext context) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(LocaleService.instance.tr('openNow'), isLive: true, context: context),
            const SizedBox(height: 14),
            SizedBox(
              height: 158,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 3,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _ShimmerCard(width: 158),
              ),
            ),
          ],
        ),
      );
    }

    final openShops = _allShops
        .where((s) => s.isOpen && s.hasActiveSubscription)
        .take(6)
        .toList();

    if (openShops.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _sectionHeader(LocaleService.instance.tr('openNow'), isLive: true, context: context),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 158,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: openShops.length,
              itemBuilder: (_, i) => _CompactShopCard(
                shop: openShops[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShopDetailsScreen(shop: openShops[i]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title,
      {bool isLive = false, required BuildContext context}) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        if (isLive) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(),
                const SizedBox(width: 5),
                Text(
                  LocaleService.instance.tr('live'),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.tertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SalonListScreen(initialCity: _selectedCity)),
          ),
          child: Row(
            children: [
              Text(
                LocaleService.instance.tr('seeAll'),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 12, color: AppColors.primary),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Category data model ─────────────────────────────────────────────────────

class _CategoryInfo {
  final String name;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _CategoryInfo({
    required this.name,
    required this.subtitle,
    required this.color,
    required this.icon,
  });
}

// ─── Category grid card (square, white, single-colour icon) ──────────────────

class _CategoryGridCard extends StatefulWidget {
  final _CategoryInfo info;
  final double cardSize;
  final List<ShopModel> allShops;
  final bool isLoading;
  final String? selectedCity;

  const _CategoryGridCard({
    required this.info,
    required this.cardSize,
    required this.allShops,
    required this.isLoading,
    this.selectedCity,
  });

  @override
  State<_CategoryGridCard> createState() => _CategoryGridCardState();
}

class _CategoryGridCardState extends State<_CategoryGridCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.info.color;
    final s = widget.cardSize;
    final shopCount =
        widget.allShops.where((e) => e.category == widget.info.name).length;
    final openCount = widget.allShops
        .where((e) =>
            e.category == widget.info.name &&
            e.isOpen &&
            e.hasActiveSubscription)
        .length;

    // Proportional sizes — all derived from card width so nothing overflows
    final pad = (s * 0.105).clamp(12.0, 18.0);
    final iconBoxSize = (s * 0.30).clamp(36.0, 52.0);
    final iconSize = iconBoxSize * 0.54;
    final nameFontSize = (s * 0.105).clamp(12.0, 16.0);
    final subFontSize = (s * 0.068).clamp(9.0, 12.0);
    final infoFontSize = (s * 0.062).clamp(8.5, 11.0);
    final ghostSize = s * 0.62;
    final arrowBox = (s * 0.175).clamp(24.0, 30.0);

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => CategoryScreen(
                    category: widget.info.name,
                    initialCity: widget.selectedCity,
                  )),
        );
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: c.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                // Ghost icon — decorative background, clipped by ClipRRect
                Positioned(
                  right: -ghostSize * 0.18,
                  bottom: -ghostSize * 0.18,
                  child: Icon(
                    widget.info.icon,
                    size: ghostSize,
                    color: c.withValues(alpha: 0.055),
                  ),
                ),
                // Content column
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: icon box + arrow
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: iconBoxSize,
                            height: iconBoxSize,
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.10),
                              borderRadius:
                                  BorderRadius.circular(iconBoxSize * 0.30),
                            ),
                            child: Icon(widget.info.icon,
                                color: c, size: iconSize),
                          ),
                          const Spacer(),
                          Container(
                            width: arrowBox,
                            height: arrowBox,
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.arrow_forward_rounded,
                                color: c, size: arrowBox * 0.50),
                          ),
                        ],
                      ),
                      // Flexible gap — absorbs extra space, never causes overflow
                      const Expanded(child: SizedBox()),
                      // Name
                      Text(
                        widget.info.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: nameFontSize,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: (s * 0.02).clamp(2, 4)),
                      // Subtitle
                      Text(
                        widget.info.subtitle,
                        style: GoogleFonts.inter(
                          fontSize: subFontSize,
                          color: AppColors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: (s * 0.045).clamp(5, 9)),
                      // Info — single line with coloured dot, no overflow possible
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: openCount > 0
                                  ? AppColors.tertiary
                                  : AppColors.onSurfaceVariant,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: (s * 0.03).clamp(3, 6)),
                          Flexible(
                            child: Text(
                              widget.isLoading
                                  ? 'Loading…'
                                  : '$openCount open · $shopCount shops',
                              style: GoogleFonts.inter(
                                fontSize: infoFontSize,
                                fontWeight: FontWeight.w500,
                                color: AppColors.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

}

// ─── Compact shop card (horizontal scroll) ────────────────────────────────────

class _CompactShopCard extends StatelessWidget {
  final ShopModel shop;
  final VoidCallback onTap;

  const _CompactShopCard({required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 158,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: shop.isPromoted
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.15))
              : null,
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
            // Icon + promoted badge row
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: shop.images.isNotEmpty
                      ? Image.network(
                          shop.images.first,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _iconBox(),
                        )
                      : _iconBox(),
                ),
                const Spacer(),
                if (shop.isPromoted)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient135,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.star_rounded, size: 10, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              shop.name,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Expanded(child: SizedBox()),
            // Status row
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  LocaleService.instance.tr('open'),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${shop.queueCount} ${LocaleService.instance.tr('inQueue')} · ~${shop.avgWaitMinutes}m',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppColors.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBox() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(_categoryIcon(shop.category), color: _categoryColor(shop.category), size: 22),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'salon':
        return Icons.spa_outlined;
      case 'beauty parlour':
        return Icons.diamond_outlined;
      case 'hospital':
        return Icons.favorite_outline_rounded;
      case 'garage':
        return Icons.settings_outlined;
      default:
        return Icons.storefront_outlined;
    }
  }

  Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'salon':
        return const Color(0xFF2563EB);
      case 'beauty parlour':
        return const Color(0xFFDB2777);
      case 'hospital':
        return const Color(0xFF059669);
      case 'garage':
        return const Color(0xFFD97706);
      default:
        return AppColors.primary;
    }
  }
}

// ─── Shimmer placeholder card ─────────────────────────────────────────────────

class _ShimmerCard extends StatefulWidget {
  final double width;
  const _ShimmerCard({required this.width});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: widget.width,
        height: 158,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

// ─── Pulsing dot for "Live" badge ─────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.tertiary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── Search tab ───────────────────────────────────────────────────────────────

class _SearchTab extends StatelessWidget {
  const _SearchTab();

  @override
  Widget build(BuildContext context) {
    return const SalonListScreen();
  }
}

// ─── Queue tab ────────────────────────────────────────────────────────────────

class _QueueTab extends StatefulWidget {
  const _QueueTab();

  @override
  State<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<_QueueTab> {
  List<QueueEntry> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    try {
      setState(() => _isLoading = true);
      final entries = await QueueService.instance.getMyStatus();
      if (mounted) setState(() { _entries = entries; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
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
            onPressed: _loadQueue,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
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
              LocaleService.instance.tr('noShopsFound'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LocaleService.instance.tr('joinQueue'),
              style: GoogleFonts.inter(
                  fontSize: 14, color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SalonListScreen()),
              ),
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
    return Container(
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
          GestureDetector(
            onTap: onTrack,
            child: Container(
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
          ),
        ],
      ),
    );
  }
}

// ─── History tab ─────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    return const HistoryScreen();
  }
}

// ─── Profile tab ──────────────────────────────────────────────────────────────

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
                        onTap: () {},
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
