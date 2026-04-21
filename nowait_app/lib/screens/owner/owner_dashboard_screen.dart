import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../services/shop_service.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../auth/login_screen.dart';
import 'manage_shop_screen.dart';
import 'create_shop_screen.dart';
import 'staff_management_screen.dart';
import 'subscription_screen.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  int _tabIndex = 0;
  ShopModel? _cachedShop;

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
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _ShopsTab(
            onRefresh: () => setState(() {}),
            onShopLoaded: (shop) => setState(() => _cachedShop = shop),
          ),
          _AnalyticsTab(shop: _cachedShop),
          _StaffTab(shop: _cachedShop),
          const _OwnerProfileTab(),
        ],
      ),
      bottomNavigationBar: _OwnerNav(
        index: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
      ),
    );
  }
}

class _OwnerNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _OwnerNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;
    final items = [
      (Icons.store_rounded, Icons.store_outlined, l.tr('myShops')),
      (Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Analytics'),
      (Icons.group_rounded, Icons.group_outlined, 'Staff'),
      (Icons.person_rounded, Icons.person_outline_rounded, l.tr('profile')),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final (active, inactive, label) = items[i];
              final isActive = index == i;
              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(horizontal: isActive ? 24 : 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isActive ? AppColors.primaryGradient135 : null,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isActive ? active : inactive, color: isActive ? Colors.white : AppColors.onSurfaceVariant, size: 22),
                      if (isActive) ...[
                        const SizedBox(width: 6),
                        Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
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

// ─── Shops tab ────────────────────────────────────────────────────────────────

class _ShopsTab extends StatefulWidget {
  final VoidCallback onRefresh;
  final ValueChanged<ShopModel?> onShopLoaded;

  const _ShopsTab({required this.onRefresh, required this.onShopLoaded});

  @override
  State<_ShopsTab> createState() => _ShopsTabState();
}

class _ShopsTabState extends State<_ShopsTab> {
  ShopModel? _shop;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  Future<void> _loadShop() async {
    try {
      final shop = await ShopService.instance.getMyShop();
      if (mounted) {
        setState(() { _shop = shop; _isLoading = false; });
        widget.onShopLoaded(shop);
      }
    } on ApiException {
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _ownerInitial {
    final name = AuthService.instance.profile?['name'] as String? ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : 'O';
  }

  String get _ownerName {
    return AuthService.instance.profile?['name'] as String? ?? 'Owner';
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: AppColors.surface.withValues(alpha: 0.95),
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          flexibleSpace: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient135,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(_ownerInitial, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(LocaleService.instance.tr('welcome', params: {'name': _ownerName}), style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface), overflow: TextOverflow.ellipsis),
                        Text(LocaleService.instance.tr('ownerDashboard'), style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          toolbarHeight: 72,
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_shop == null && !_isLoading) ...[
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      label: LocaleService.instance.tr('createNewShop'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CreateShopScreen()),
                      ).then((_) => _loadShop()),
                      icon: Icons.add_business_outlined,
                      height: 56,
                      borderRadius: 16,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Item 18: Onboarding steps
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Get started in 3 steps', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                        const SizedBox(height: 14),
                        _OnboardingStep(number: '1', title: 'Create Shop', subtitle: 'Add your shop name, address, and category'),
                        const SizedBox(height: 10),
                        _OnboardingStep(number: '2', title: 'Add Services', subtitle: 'List the services you offer with pricing'),
                        const SizedBox(height: 10),
                        _OnboardingStep(number: '3', title: 'Subscribe', subtitle: 'Activate your plan to start receiving customers'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ] else if (_shop != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient135,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.info_outline_rounded,
                              color: Colors.white, size: 16),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            LocaleService.instance.tr('ownerInfo'),
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.primary,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  LocaleService.instance.tr('myShops'),
                  style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  LocaleService.instance.tr('ownerInfo'),
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_shop == null)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 12, offset: const Offset(0, 3))],
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.store_outlined, size: 48, color: AppColors.onSurfaceVariant.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text(LocaleService.instance.tr('noShopYet'), style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(LocaleService.instance.tr('createFirstShop'), style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  )
                else
                  _OwnerShopCard(
                    shop: _shop!,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ManageShopScreen(shop: _shop!)),
                    ).then((_) => _loadShop()),
                    onSubscriptionTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SubscriptionScreen(shop: _shop!)),
                    ).then((_) => _loadShop()),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OwnerShopCard extends StatelessWidget {
  final ShopModel shop;
  final VoidCallback onTap;
  final VoidCallback onSubscriptionTap;

  const _OwnerShopCard({required this.shop, required this.onTap, required this.onSubscriptionTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: AppColors.shadowPrimary, blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: shop.hasActiveSubscription
                          ? AppColors.primaryGradient135
                          : const LinearGradient(colors: [Color(0xFFB0B8D1), Color(0xFF9099B3)]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.store_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ),
                            _statusChip(shop),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${shop.address}, ${shop.city}',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _metaBadge(Icons.group_outlined, '${shop.queueCount} ${LocaleService.instance.tr('inQueue')}'),
                            _metaBadge(Icons.star_rounded, shop.rating.toString()),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant),
                ],
              ),
            ),
          ),

          if (!shop.hasActiveSubscription) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      LocaleService.instance.tr('subscriptionInactive'),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onErrorContainer),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onSubscriptionTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        LocaleService.instance.tr('activate'),
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(ShopModel s) {
    if (!s.hasActiveSubscription) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
        child: Text(LocaleService.instance.tr('inactive'), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: s.isOpen ? AppColors.tertiaryFixed.withValues(alpha: 0.35) : AppColors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        s.isOpen ? LocaleService.instance.tr('open') : LocaleService.instance.tr('closed'),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: s.isOpen ? AppColors.onTertiaryFixed : AppColors.onErrorContainer,
        ),
      ),
    );
  }

  Widget _metaBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ─── Analytics tab ────────────────────────────────────────────────────────────

class _AnalyticsTab extends StatefulWidget {
  final ShopModel? shop;
  const _AnalyticsTab({this.shop});

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  AnalyticsSummary? _summary;
  List<Map<String, dynamic>> _hourly = [];
  List<Map<String, dynamic>> _staffPerf = [];
  bool _isLoading = false;
  bool _hasError = false; // Item 16
  String _period = 'today';

  @override
  void didUpdateWidget(_AnalyticsTab old) {
    super.didUpdateWidget(old);
    if (widget.shop != null && old.shop == null) _load();
  }

  @override
  void initState() {
    super.initState();
    if (widget.shop != null) _load();
  }

  Future<void> _load() async {
    if (widget.shop == null) return; // Item 7
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final results = await Future.wait([
        AnalyticsService.instance.getSummary(widget.shop!.id, period: _period),
        AnalyticsService.instance.getHourlyStats(widget.shop!.id),
        AnalyticsService.instance.getStaffPerformance(widget.shop!.id),
      ]);
      if (mounted) {
        setState(() {
          _summary = results[0] as AnalyticsSummary;
          _hourly = results[1] as List<Map<String, dynamic>>;
          _staffPerf = results[2] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _hasError = true; }); // Item 16
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.shop == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bar_chart_outlined, size: 52, color: AppColors.onSurfaceVariant.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text('Create a shop to see analytics', style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.surface.withValues(alpha: 0.95),
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: Text('Analytics', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700))),
                    IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), color: AppColors.primary),
                  ],
                ),
              ),
            ),
            toolbarHeight: 64,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Period selector
                  Row(
                    children: [
                      for (final p in ['today', 'week', 'month'])
                        Expanded(
                          child: GestureDetector(
                            onTap: () { setState(() => _period = p); _load(); },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                gradient: _period == p ? AppColors.primaryGradient135 : null,
                                color: _period == p ? null : AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  p[0].toUpperCase() + p.substring(1),
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _period == p ? Colors.white : AppColors.onSurfaceVariant),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  // Item 16: Show error state with retry
                  else if (_hasError)
                    GestureDetector(
                      onTap: _load,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.onSurfaceVariant),
                            const SizedBox(height: 10),
                            Text(
                              "Couldn't load analytics — tap to retry",
                              style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_summary != null) ...[
                    // Metric grid
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        _MetricCard(label: 'Total Joined', value: '${_summary!.totalJoined}', icon: Icons.people_outline_rounded, color: AppColors.primary),
                        _MetricCard(label: 'Served', value: '${_summary!.totalServed}', icon: Icons.check_circle_outline_rounded, color: AppColors.tertiary),
                        _MetricCard(label: 'Cancel Rate', value: '${_summary!.cancelRatePct}%', icon: Icons.cancel_outlined, color: AppColors.error),
                        _MetricCard(label: 'Skip Rate', value: '${_summary!.skipRatePct}%', icon: Icons.skip_next_rounded, color: AppColors.secondary),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _MetricCard(
                          label: 'Avg Service',
                          value: _summary!.avgServiceMinutes != null ? '${_summary!.avgServiceMinutes!.toStringAsFixed(1)} min' : 'N/A',
                          icon: Icons.timer_outlined,
                          color: AppColors.primary,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _MetricCard(
                          label: 'Peak Hour',
                          value: _summary!.peakHourText,
                          icon: Icons.schedule_rounded,
                          color: AppColors.secondary,
                        )),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Hourly bar chart
                    Text('Customers by Hour (Last 7 days)', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _HourlyBarChart(data: _hourly),
                    if (_staffPerf.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Staff Performance', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      ..._staffPerf.map((s) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(gradient: AppColors.primaryGradient135, shape: BoxShape.circle),
                              child: Center(child: Text(
                                (s['staff_name'] as String? ?? '?')[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                              )),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s['staff_name'] ?? '', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                                  Text('${s['total_served']} served / ${s['total_entries']} total', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            if (s['avg_service_minutes'] != null)
                              Text('${(s['avg_service_minutes'] as num).toStringAsFixed(1)} min avg', style: GoogleFonts.inter(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )),
                    ],
                  ] else
                    Center(child: Text('No data yet', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
              Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HourlyBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _HourlyBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final maxCount = data.map((d) => (d['count'] as int? ?? 0)).fold(0, (a, b) => a > b ? a : b);
    return Container(
      height: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final count = d['count'] as int? ?? 0;
          final h = d['hour'] as int? ?? 0;
          final frac = maxCount > 0 ? count / maxCount : 0.0;
          final isLabeled = h % 6 == 0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: frac.clamp(0.05, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: frac > 0.7 ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3 + frac * 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isLabeled)
                    Text('${h}h', style: GoogleFonts.inter(fontSize: 8, color: AppColors.onSurfaceVariant))
                  else
                    const SizedBox(height: 10),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Staff tab ────────────────────────────────────────────────────────────────

class _StaffTab extends StatelessWidget {
  final ShopModel? shop;
  const _StaffTab({this.shop});

  @override
  Widget build(BuildContext context) {
    if (shop == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: Text('Create a shop to manage staff', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant))),
      );
    }
    return StaffManagementScreen(shop: shop!);
  }
}

// ─── Profile tab ──────────────────────────────────────────────────────────────

class _OwnerProfileTab extends StatelessWidget {
  const _OwnerProfileTab();

  String get _name => AuthService.instance.profile?['name'] as String? ?? 'Owner';
  String get _initial => _name.isNotEmpty ? _name[0].toUpperCase() : 'O';

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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l.tr('profile'), style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(gradient: AppColors.primaryGradient135, shape: BoxShape.circle),
                child: Center(child: Text(_initial, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700))),
              ),
            ),
            const SizedBox(height: 10),
            Text(_name, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            Text(l.tr('shopOwner'), style: GoogleFonts.inter(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 28),
            _tile(context, Icons.language_rounded, l.tr('changeLanguage'), () => _showLanguageSheet(context),
              trailing: Text(
                l.lang == kLangEn ? l.tr('english') : l.lang == kLangHi ? l.tr('hindi') : l.tr('marathi'),
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ),
            _tile(context, Icons.help_outline_rounded, l.tr('helpSupport'), () {}),
            _tile(context, Icons.info_outline_rounded, l.tr('aboutNowait'), () {}),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await AuthService.instance.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (r) => false,
                    );
                  }
                },
                icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                label: Text(l.tr('signOut'), style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, VoidCallback onTap, {Widget? trailing}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.onSurface))),
            if (trailing != null) ...[trailing, const SizedBox(width: 6)],
            const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

// Item 18: Onboarding step widget used in _ShopsTab when no shop exists
class _OnboardingStep extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _OnboardingStep({required this.number, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient135,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
              Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
