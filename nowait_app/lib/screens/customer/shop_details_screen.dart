import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../services/shop_service.dart';
import '../../services/queue_service.dart';
import '../../services/staff_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../widgets/shop_card.dart' show showSchemeSheet;
import 'token_screen.dart';

class ShopDetailsScreen extends StatefulWidget {
  final ShopModel? shop;
  final String? shopId;

  const ShopDetailsScreen({super.key, this.shop, this.shopId})
      : assert(shop != null || shopId != null,
            'Either shop or shopId must be provided');

  @override
  State<ShopDetailsScreen> createState() => _ShopDetailsScreenState();
}

class _ShopDetailsScreenState extends State<ShopDetailsScreen> {
  int _currentImage = 0;
  final PageController _pageController = PageController();
  ShopModel? _shop;
  bool _isLoadingShop = false;
  bool _isJoining = false;
  List<StaffMember> _staff = [];
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _shop = widget.shop;
    _l.addListener(_onLocale);
    _fetchShopAndStaff();
  }

  Future<void> _fetchShopAndStaff() async {
    if (_shop == null) setState(() => _isLoadingShop = true);
    try {
      final shopId = widget.shop?.id ?? widget.shopId!;
      final shopFuture = ShopService.instance.getShop(shopId);
      final staffFuture = StaffService.instance
          .getStaffForCustomers(shopId)
          .catchError((_) => <StaffMember>[]);
      final results = await Future.wait([shopFuture, staffFuture]);
      if (mounted) {
        setState(() {
          _shop = results[0] as ShopModel;
          _staff = results[1] as List<StaffMember>;
          _isLoadingShop = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingShop = false);
    }
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _pageController.dispose();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  Future<void> _joinQueue() async {
    if (!(_shop?.canAcceptQueue ?? false)) return;
    setState(() => _isJoining = true);
    try {
      final entry = await QueueService.instance.joinQueue(_shop!.id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TokenScreen(
            shop: _shop!,
            token: entry.token,
            position: entry.position,
            estimatedWait: entry.estimatedWaitMinutes,
            entryId: entry.entryId,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_l.tr('somethingWrong'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingShop) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_shop == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(),
        body: const Center(child: Text('Shop not found')),
      );
    }

    final shop = _shop!;
    final canJoin = shop.canAcceptQueue;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── Image carousel ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 260,
                  child: Stack(
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        itemCount: shop.images.isNotEmpty ? shop.images.length : 1,
                        onPageChanged: (i) => setState(() => _currentImage = i),
                        itemBuilder: (_, i) {
                          if (shop.images.isNotEmpty) {
                            return Image.network(
                              shop.images[i],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              loadingBuilder: (_, child, progress) => progress == null
                                  ? child
                                  : Container(
                                      color: AppColors.surfaceContainerLow,
                                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                                    ),
                              errorBuilder: (_, __, ___) => _placeholderPage(shop, i),
                            );
                          }
                          return _placeholderPage(shop, i);
                        },
                      ),
                      // Back button
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 16,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 18),
                          ),
                        ),
                      ),
                      // Dots (only when multiple images)
                      if (shop.images.length > 1)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              shop.images.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: _currentImage == i ? 20 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _currentImage == i
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Shop name, status ─────────────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              shop.name,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusBadge(shop),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _metaChip(Icons.star_rounded,
                              shop.rating.toString(), const Color(0xFFFFB800)),
                          if (shop.ownerName.isNotEmpty)
                            _metaChip(Icons.person_outline_rounded,
                                shop.ownerName, AppColors.onSurfaceVariant),
                          _metaChip(
                              Icons.location_on_outlined,
                              '${shop.address}, ${shop.city}',
                              AppColors.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Subscription not active warning ───────────────────
                      if (!shop.hasActiveSubscription) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.outline
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: AppColors.onSurfaceVariant,
                                  size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _l.tr('shopNotAcceptingDetail'),
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Queue bento (only if open + subscribed) ───────────
                      if (canJoin) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _BentoCell(
                                icon: Icons.group_outlined,
                                value: '${shop.queueCount}',
                                label: _l.tr('inQueueLabel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _BentoCell(
                                icon: Icons.confirmation_number_outlined,
                                value:
                                    '#${shop.currentToken.toString().padLeft(2, '0')}',
                                label: _l.tr('servingNow'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _BentoCell(
                                icon: Icons.access_time_rounded,
                                value: shop.openingHours ?? '—',
                                label: 'Opening Hours',
                                valueSize: 13,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _BentoCell(
                                icon: Icons.schedule_outlined,
                                value: '~${shop.avgWaitMinutes}m',
                                label: _l.tr('avgWait'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ── Staff section (informational) ─────────────────────
                      if (_staff.isNotEmpty) ...[
                        _StaffSection(staffList: _staff),
                        const SizedBox(height: 24),
                      ],

                      // ── Active scheme ─────────────────────────────────────
                      if (shop.activeScheme != null) ...[
                        GestureDetector(
                          onTap: () => showSchemeSheet(context, shop.activeScheme!),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: shop.activeScheme!.isActive
                                  ? AppColors.primary.withValues(alpha: 0.06)
                                  : AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: shop.activeScheme!.isActive
                                      ? AppColors.primary.withValues(alpha: 0.2)
                                      : AppColors.outline.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    gradient: shop.activeScheme!.isActive
                                        ? AppColors.primaryGradient135
                                        : null,
                                    color: shop.activeScheme!.isActive
                                        ? null
                                        : AppColors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                      Icons.local_offer_outlined,
                                      color: shop.activeScheme!.isActive
                                          ? Colors.white
                                          : AppColors.onSurfaceVariant,
                                      size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shop.activeScheme!.title,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.onSurface,
                                        ),
                                      ),
                                      Text(
                                        shop.activeScheme!.description,
                                        style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: AppColors.onSurfaceVariant),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      shop.activeScheme!.validityText,
                                      style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: shop.activeScheme!.isActive
                                              ? AppColors.primary
                                              : AppColors.error),
                                    ),
                                    const SizedBox(height: 2),
                                    Icon(Icons.chevron_right_rounded,
                                        size: 16,
                                        color: shop.activeScheme!.isActive
                                            ? AppColors.primary
                                            : AppColors.onSurfaceVariant),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Services ──────────────────────────────────────────
                      Text(
                        _l.tr('services'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...shop.services.map((s) => _ServiceTile(service: s)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Sticky CTA ──────────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.surface.withValues(alpha: 0),
                    AppColors.surface,
                    AppColors.surface,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: canJoin
                  ? SizedBox(
                      width: double.infinity,
                      child: _isJoining
                          ? Container(
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient135,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                ),
                              ),
                            )
                          : GradientButton(
                              label: _l.tr('joinQueueGetToken'),
                              onPressed: _joinQueue,
                              icon: Icons.confirmation_number_outlined,
                            ),
                    )
                  : Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: !shop.hasActiveSubscription
                            ? AppColors.surfaceContainerHigh
                            : AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            !shop.hasActiveSubscription
                                ? Icons.block_rounded
                                : Icons.store_outlined,
                            color: AppColors.onSurfaceVariant,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            !shop.hasActiveSubscription
                                ? _l.tr('shopNotAccepting')
                                : _l.tr('shopCurrentlyClosed'),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(ShopModel shop) {
    if (!shop.hasActiveSubscription) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Unavailable',
          style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: shop.isOpen
            ? AppColors.tertiaryFixed.withValues(alpha: 0.3)
            : AppColors.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: shop.isOpen ? AppColors.tertiary : AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            shop.isOpen ? _l.tr('open') : _l.tr('closed'),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: shop.isOpen
                  ? AppColors.onTertiaryFixed
                  : AppColors.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: GoogleFonts.inter(fontSize: 12, color: color)),
      ],
    );
  }

  Widget _placeholderPage(ShopModel shop, int i) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _gradientForCategory(shop.category, i),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(_iconForCategory(shop.category), color: Colors.white.withValues(alpha: 0.25), size: 90),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.photo_camera_outlined, color: Colors.white54, size: 28),
                const SizedBox(height: 4),
                Text('No photos yet', style: GoogleFonts.inter(fontSize: 12, color: Colors.white60)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _gradientForCategory(String cat, int idx) {
    final base = CategoryTheme.gradient(cat);
    return [
      base[0].withValues(alpha: 0.6 + idx * 0.1),
      base[1].withValues(alpha: 0.6 + idx * 0.1),
    ];
  }

  IconData _iconForCategory(String cat) => CategoryTheme.icon(cat);
}

// ── Staff section — informational only, shown on shop detail ─────────────────

class _StaffSection extends StatelessWidget {
  final List<StaffMember> staffList;

  const _StaffSection({required this.staffList});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Our Team',
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
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${staffList.length}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: staffList.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _StaffAvatar(staff: staffList[i]),
          ),
        ),
      ],
    );
  }
}

class _StaffAvatar extends StatelessWidget {
  final StaffMember staff;

  const _StaffAvatar({required this.staff});

  @override
  Widget build(BuildContext context) {
    final initial = staff.displayName.isNotEmpty ? staff.displayName[0].toUpperCase() : '?';
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: staff.isOwnerStaff ? AppColors.primaryGradient135 : null,
              color: staff.isOwnerStaff ? null : AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: staff.isOwnerStaff ? Colors.white : AppColors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            staff.displayName,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (staff.isOwnerStaff)
            Text(
              'Owner',
              style: GoogleFonts.inter(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

// ── Bento cell ────────────────────────────────────────────────────────────────

class _BentoCell extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final double? valueSize;
  final bool fullWidth;

  const _BentoCell({
    required this.icon,
    required this.value,
    required this.label,
    this.valueSize,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final cell = Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadowPrimary,
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: fullWidth
          ? Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: valueSize ?? 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: valueSize ?? 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
    );
    return cell;
  }
}

// ── Service tile ──────────────────────────────────────────────────────────────

class _ServiceTile extends StatelessWidget {
  final ServiceModel service;

  const _ServiceTile({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadowPrimary,
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.spa_outlined,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface),
                ),
                Text(
                  service.description,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            service.price == 0 ? 'Free' : '₹${service.price.toInt()}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

