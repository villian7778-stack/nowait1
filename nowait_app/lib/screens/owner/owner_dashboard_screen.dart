import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../services/review_service.dart';
import '../../services/shop_service.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../auth/login_screen.dart';
import '../help_support_screen.dart';
import 'manage_shop_screen.dart';
import 'create_shop_screen.dart';
import 'edit_shop_screen.dart';
import 'promotion_screen.dart';
import 'scheme_screen.dart';
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
  Timer? _refreshTimer;

  List<ReviewModel> _reviews = [];
  double _avgRating = 0.0;
  int _totalReviews = 0;
  bool _reviewsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadShop();
    // Refresh shop queue count every 10 seconds so the card stays live
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadShop());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadShop() async {
    try {
      final shop = await ShopService.instance.getMyShop();
      if (mounted) {
        setState(() { _shop = shop; _isLoading = false; });
        widget.onShopLoaded(shop);
        if (shop != null) _loadReviews(shop.id);
      }
    } on ApiException {
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadReviews(String shopId) async {
    if (_reviewsLoading) return;
    if (mounted) setState(() => _reviewsLoading = true);
    try {
      final data = await ReviewService.instance.getReviews(shopId, limit: 10);
      if (mounted) {
        setState(() {
          _reviews = data['reviews'] as List<ReviewModel>;
          _avgRating = data['avg_rating'] as double;
          _totalReviews = data['total'] as int;
          _reviewsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _reviewsLoading = false);
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
                if (_shop != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    LocaleService.instance.tr('shopTools'),
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 12),
                  _DashActionTile(
                    icon: Icons.edit_outlined,
                    iconColor: const Color(0xFF7C3AED),
                    iconBg: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                    title: LocaleService.instance.tr('editShopDetails'),
                    subtitle: LocaleService.instance.tr('editShopSubtitle'),
                    onTap: () async {
                      final updated = await Navigator.push<ShopModel>(
                        context,
                        MaterialPageRoute(builder: (_) => EditShopScreen(shop: _shop!)),
                      );
                      if (updated != null && mounted) {
                        setState(() => _shop = updated);
                        widget.onShopLoaded(updated);
                      }
                    },
                  ),
                  _DashActionTile(
                    icon: Icons.rocket_launch_outlined,
                    iconColor: AppColors.primary,
                    iconBg: AppColors.primary.withValues(alpha: 0.1),
                    title: LocaleService.instance.tr('promoteShop'),
                    subtitle: LocaleService.instance.tr('promoteSubtitle'),
                    badge: _shop!.isPromoted ? 'Active' : '₹20/day',
                    badgeColor: _shop!.isPromoted ? AppColors.tertiary : AppColors.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PromotionScreen(shop: _shop!)),
                    ).then((_) => _loadShop()),
                  ),
                  _DashActionTile(
                    icon: Icons.local_offer_outlined,
                    iconColor: AppColors.secondary,
                    iconBg: AppColors.secondary.withValues(alpha: 0.1),
                    title: LocaleService.instance.tr('addEditScheme'),
                    subtitle: LocaleService.instance.tr('addEditSchemeSubtitle'),
                    badge: _shop!.activeScheme != null ? _shop!.activeScheme!.validityText : 'None',
                    badgeColor: _shop!.activeScheme != null ? AppColors.secondary : AppColors.onSurfaceVariant,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SchemeScreen(shop: _shop!)),
                    ).then((_) => _loadShop()),
                  ),
                  _DashActionTile(
                    icon: Icons.workspace_premium_outlined,
                    iconColor: _shop!.hasActiveSubscription ? AppColors.tertiary : AppColors.error,
                    iconBg: _shop!.hasActiveSubscription ? AppColors.tertiary.withValues(alpha: 0.1) : AppColors.errorContainer,
                    title: LocaleService.instance.tr('subscription'),
                    subtitle: _shop!.hasActiveSubscription
                        ? LocaleService.instance.tr('subscriptionActiveMsg')
                        : LocaleService.instance.tr('activateToOpen'),
                    badge: _shop!.hasActiveSubscription ? LocaleService.instance.tr('activate') : LocaleService.instance.tr('inactive'),
                    badgeColor: _shop!.hasActiveSubscription ? AppColors.tertiary : AppColors.error,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SubscriptionScreen(shop: _shop!)),
                    ).then((_) => _loadShop()),
                  ),
                  const SizedBox(height: 24),
                  _OwnerReviewsSection(
                    reviews: _reviews,
                    avgRating: _avgRating,
                    totalReviews: _totalReviews,
                    isLoading: _reviewsLoading,
                  ),
                ],
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

// ─── Owner Reviews Section ────────────────────────────────────────────────────

class _OwnerReviewsSection extends StatelessWidget {
  final List<ReviewModel> reviews;
  final double avgRating;
  final int totalReviews;
  final bool isLoading;

  const _OwnerReviewsSection({
    required this.reviews,
    required this.avgRating,
    required this.totalReviews,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.star_rounded, size: 20, color: Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            Text(
              'Reviews & Ratings',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            if (totalReviews > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$totalReviews',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (isLoading)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (reviews.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.rate_review_outlined, size: 36, color: AppColors.onSurfaceVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 8),
                  Text('No reviews yet', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
          )
        else ...[
          // Summary header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Column(
                  children: [
                    Text(
                      avgRating.toStringAsFixed(1),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                    ),
                    _StarRow(rating: avgRating, size: 16),
                    const SizedBox(height: 2),
                    Text(
                      '$totalReviews ${totalReviews == 1 ? "review" : "reviews"}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [5, 4, 3, 2, 1].map((star) {
                      final count = reviews.where((r) => r.rating == star).length;
                      final ratio = totalReviews > 0 ? count / totalReviews : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text('$star', style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 4),
                            const Icon(Icons.star_rounded, size: 11, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 6,
                                  backgroundColor: AppColors.surfaceContainerLow,
                                  valueColor: const AlwaysStoppedAnimation(Color(0xFFF59E0B)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 18,
                              child: Text('$count', style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Individual review cards
          ...reviews.map((r) => _ReviewCard(review: r)),
        ],
      ],
    );
  }
}

class _StarRow extends StatelessWidget {
  final double rating;
  final double size;

  const _StarRow({required this.rating, required this.size});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.floor();
        final half = !filled && i < rating;
        return Icon(
          half ? Icons.star_half_rounded : (filled ? Icons.star_rounded : Icons.star_outline_rounded),
          size: size,
          color: const Color(0xFFF59E0B),
        );
      }),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final ReviewModel review;

  const _ReviewCard({required this.review});

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final initial = review.userName.isNotEmpty ? review.userName[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient135,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.userName, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    _StarRow(rating: review.rating.toDouble(), size: 13),
                  ],
                ),
              ),
              Text(
                _formatDate(review.createdAt),
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
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

Future<void> _showOwnerDeleteAccountFlow(BuildContext context) async {
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
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
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
            _tile(context, Icons.help_outline_rounded, l.tr('helpSupport'), () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
            )),
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
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showOwnerDeleteAccountFlow(context),
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                label: Text(l.tr('deleteAccount'),
                    style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w500)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.25)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: AppColors.error.withValues(alpha: 0.03),
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
class _DashActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _DashActionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (badgeColor ?? AppColors.primary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor ?? AppColors.primary),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

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
