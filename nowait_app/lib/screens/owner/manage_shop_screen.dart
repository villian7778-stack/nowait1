import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/queue_service.dart';
import '../../services/shop_service.dart';
import '../../services/subscription_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import 'subscription_screen.dart';
import 'promotion_screen.dart';
import 'scheme_screen.dart';
import 'edit_shop_screen.dart';
import '../../services/notification_service.dart';
import '../customer/notifications_screen.dart';

class ManageShopScreen extends StatefulWidget {
  final ShopModel shop;

  const ManageShopScreen({super.key, required this.shop});

  @override
  State<ManageShopScreen> createState() => _ManageShopScreenState();
}

class _ManageShopScreenState extends State<ManageShopScreen> {
  late ShopModel _shop;
  bool _isCallingNext = false;
  bool _isTogglingOpen = false;
  bool _isTogglingPause = false;
  List<Map<String, dynamic>> _queueItems = [];
  bool _loadingQueue = false;
  int _unreadCount = 0;
  int? _subscriptionDaysLeft;
  Timer? _refreshTimer;
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _shop = widget.shop;
    _l.addListener(_onLocale);
    _loadQueue();
    _loadUnreadCount();
    _loadSubscriptionExpiry();
    // Auto-refresh queue every 15 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadQueue());
  }

  Future<void> _loadUnreadCount() async {
    try {
      final data = await NotificationService.instance.getNotifications();
      if (mounted) setState(() => _unreadCount = (data['unread_count'] as int?) ?? 0);
    } catch (_) {}
  }

  Future<void> _loadSubscriptionExpiry() async {
    try {
      final res = await SubscriptionService.instance.getSubscription(_shop.id);
      final sub = res['subscription'] as Map<String, dynamic>?;
      final days = sub?['days_remaining'] as int?;
      if (mounted) setState(() => _subscriptionDaysLeft = days);
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _l.removeListener(_onLocale);
    super.dispose();
  }

  void _onLocale() => setState(() {});

  Future<void> _loadQueue() async {
    setState(() => _loadingQueue = true);
    try {
      final res = await QueueService.instance.getShopQueue(_shop.id);
      final raw = res['queue'] as List? ?? (res['entries'] as List? ?? []);
      if (mounted) {
        setState(() {
          _queueItems = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loadingQueue = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingQueue = false);
    }
  }

  Future<void> _togglePause() async {
    setState(() => _isTogglingPause = true);
    try {
      if (_shop.queuePaused) {
        await QueueService.instance.resumeQueue(_shop.id);
      } else {
        await QueueService.instance.pauseQueue(_shop.id);
      }
      final updated = await ShopService.instance.getShop(_shop.id);
      if (mounted) setState(() { _shop = updated; _isTogglingPause = false; });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isTogglingPause = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    } catch (_) {
      if (mounted) setState(() => _isTogglingPause = false);
    }
  }

  void _showMaxSizeSheet() {
    final ctrl = TextEditingController(text: _shop.maxQueueSize?.toString() ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.outline.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Text('Max Queue Size', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Leave empty for unlimited', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'e.g. 30',
                  suffixText: 'customers',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: 'Set Limit',
                  onPressed: () async {
                    final val = int.tryParse(ctrl.text.trim());
                    Navigator.pop(context);
                    await QueueService.instance.setMaxSize(_shop.id, val);
                    final updated = await ShopService.instance.getShop(_shop.id);
                    if (mounted) setState(() => _shop = updated);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows skip dialog with optional reason, then calls the API.
  void _showSkipDialog(String entryId, String customerName) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Skip $customerName?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Optionally add a reason:', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Did not show up',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await QueueService.instance.skipCustomer(entryId, note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
                if (mounted) {
                  _loadQueue();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$customerName skipped'), backgroundColor: AppColors.onSurfaceVariant, behavior: SnackBarBehavior.floating),
                  );
                }
              } on ApiException catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
              }
            },
            child: Text('Skip', style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildQueueList() {
    final hasSubscription = _shop.hasActiveSubscription;

    if (_loadingQueue) {
      return [const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))];
    }

    if (_queueItems.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(14)),
          child: Center(
            child: Text('No customers in queue', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
          ),
        ),
      ];
    }

    return _queueItems.map((entry) {
      final token = entry['token_number'] as int? ?? 0;
      final name = entry['customer_name'] as String? ?? 'Customer';
      final status = entry['status'] as String? ?? 'waiting';
      final entryId = entry['id'] as String? ?? '';
      final pos = entry['position'] as int? ?? 0;
      final isServing = status == 'serving';
      final isComing = entry['coming_at'] != null;

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isServing
              ? AppColors.primary.withValues(alpha: 0.06)
              : isComing
                  ? AppColors.tertiary.withValues(alpha: 0.04)
                  : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: isServing
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.25))
              : isComing
                  ? Border.all(color: AppColors.tertiary.withValues(alpha: 0.25))
                  : null,
          boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: isServing ? AppColors.primaryGradient135 : null,
                color: isServing ? null : AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '#${token.toString().padLeft(2, '0')}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: isServing ? Colors.white : AppColors.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  Text(
                    isServing ? 'Now serving' : 'Position $pos',
                    style: GoogleFonts.inter(fontSize: 11, color: isServing ? AppColors.primary : AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (isComing) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(color: AppColors.tertiary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_walk_rounded, size: 12, color: AppColors.tertiary),
                    const SizedBox(width: 3),
                    Text('Coming', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.tertiary)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
            // Skip button — only for waiting customers
            if (!isServing && entryId.isNotEmpty)
              GestureDetector(
                onTap: hasSubscription
                    ? () => _showSkipDialog(entryId, name)
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Activate a subscription to manage your queue')),
                        ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasSubscription
                        ? AppColors.errorContainer
                        : AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: hasSubscription ? AppColors.error : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isServing ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isServing ? 'Serving' : 'Waiting',
                  style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: isServing ? AppColors.primary : AppColors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      );
    }).toList();
  }

  Future<void> _callNext() async {
    if (!_shop.hasActiveSubscription) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activate a subscription to manage your queue')),
      );
      return;
    }
    if (_shop.queueCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l.tr('queueEmpty')),
          backgroundColor: AppColors.onSurfaceVariant,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    setState(() => _isCallingNext = true);
    try {
      final res = await QueueService.instance.advanceQueue(_shop.id);
      final nowServingToken = res['now_serving_token'] as int? ?? (_shop.currentToken + 1);
      if (mounted) {
        // Refresh shop data instead of manually reconstructing ShopModel
        final updatedShop = await ShopService.instance.getShop(_shop.id);
        setState(() => _shop = updatedShop);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓  Calling Token #${nowServingToken.toString().padLeft(2, '0')}'),
            backgroundColor: AppColors.tertiary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        _loadQueue();
        _loadUnreadCount();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_l.tr('failedAdvanceQueue'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isCallingNext = false);
    }
  }

  Future<void> _toggleOpen() async {
    setState(() => _isTogglingOpen = true);
    try {
      final updated = await ShopService.instance.toggleOpen(_shop.id);
      if (mounted) setState(() { _shop = updated; _isTogglingOpen = false; });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isTogglingOpen = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isTogglingOpen = false);
    }
  }

  // Name of customer currently being served
  String? get _servingName {
    try {
      return _queueItems.firstWhere((e) => e['status'] == 'serving')['customer_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSubscription = _shop.hasActiveSubscription;
    final showExpiryWarning = hasSubscription &&
        _subscriptionDaysLeft != null &&
        _subscriptionDaysLeft! <= 5 &&
        _subscriptionDaysLeft! >= 1;

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
            title: Text(_l.tr('manageShop'), style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
            actions: [
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ).then((_) => _loadUnreadCount()),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.notifications_outlined, color: AppColors.primary, size: 22),
                    ),
                    if (_unreadCount > 0)
                      Positioned(
                        right: 4,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                          child: Text(
                            _unreadCount > 9 ? '9+' : '$_unreadCount',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SubscriptionScreen(shop: _shop)),
                ).then((_) => setState(() {})),
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: hasSubscription ? AppColors.primaryGradient135 : null,
                    color: hasSubscription ? null : AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        size: 14,
                        color: hasSubscription ? Colors.white : AppColors.onErrorContainer,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        hasSubscription ? _l.tr('premium') : _l.tr('subscribe'),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: hasSubscription ? Colors.white : AppColors.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Subscription expiry warning (items 3-5 days) ─────────
                  if (showExpiryWarning) ...[
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SubscriptionScreen(shop: _shop)),
                      ).then((_) => _loadSubscriptionExpiry()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_rounded, color: Color(0xFFA67C00), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Subscription expiring in $_subscriptionDaysLeft day${_subscriptionDaysLeft == 1 ? '' : 's'} — Renew Now',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF7A5800)),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF7A5800), size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Subscription inactive warning ───────────────────────
                  if (!hasSubscription) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppColors.onErrorContainer, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _l.tr('subscriptionRequired'),
                                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onErrorContainer),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _l.tr('subRequiredMsg'),
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.onErrorContainer),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => SubscriptionScreen(shop: _shop)),
                              ).then((_) => setState(() {})),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                minimumSize: const Size(double.infinity, 42),
                              ),
                              child: Text(_l.tr('activateSubscription'), style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Shop header card ─────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: hasSubscription
                            ? [AppColors.primary.withValues(alpha: 0.85), AppColors.secondary.withValues(alpha: 0.85)]
                            : [const Color(0xFF9099B3), const Color(0xFF7A82A0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_shop.name, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                              const SizedBox(height: 3),
                              Text('${_shop.address}, ${_shop.city}', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
                            ],
                          ),
                        ),
                        if (hasSubscription)
                          GestureDetector(
                            onTap: _isTogglingOpen ? null : _toggleOpen,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                // Green tint when open, red tint when closed
                                color: _shop.isOpen
                                    ? Colors.green.withValues(alpha: 0.3)
                                    : Colors.red.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _isTogglingOpen
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      _shop.isOpen
                                          ? 'OPEN — tap to close'
                                          : 'CLOSED — tap to open',
                                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                                    ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(_l.tr('inactive'), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Queue metrics bento ──────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCell(
                          icon: Icons.how_to_reg_outlined,
                          value: _shop.currentToken.toString().padLeft(2, '0'),
                          label: _l.tr('currentServing'),
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCell(
                          icon: Icons.group_outlined,
                          value: '${_shop.queueCount}',
                          label: _l.tr('waitingInQueue'),
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── NEXT button ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 72,
                    child: _isCallingNext
                        ? Container(
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient135,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              ),
                            ),
                          )
                        : GradientButton(
                            label: !hasSubscription
                                ? 'Subscription required'
                                : _shop.queueCount > 0
                                    ? 'Next  ·  Call Token #${(_shop.currentToken + 1).toString().padLeft(2, '0')}'
                                    : 'Queue Empty',
                            onPressed: _callNext,
                            icon: !hasSubscription
                                ? Icons.lock_outlined
                                : _shop.queueCount > 0
                                    ? Icons.campaign_rounded
                                    : Icons.check_circle_outline_rounded,
                            height: 72,
                            borderRadius: 20,
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _l.tr('pressNextHint'),
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // ── Queue controls row ────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _isTogglingPause ? null : _togglePause,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _shop.queuePaused ? AppColors.errorContainer : AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: _isTogglingPause
                                ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _shop.queuePaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                        size: 18,
                                        color: _shop.queuePaused ? AppColors.error : AppColors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _shop.queuePaused ? 'Resume Queue' : 'Pause Queue',
                                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _shop.queuePaused ? AppColors.error : AppColors.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _showMaxSizeSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            children: [
                              const Icon(Icons.people_outline_rounded, size: 16, color: AppColors.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                _shop.maxQueueSize != null ? 'Max: ${_shop.maxQueueSize}' : 'No limit',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Live queue ────────────────────────────────────────────
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text('Live Queue', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _loadQueue,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Queue quick stats header ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'In queue: ${_shop.queueCount}  ·  Avg wait: ${_shop.avgWaitMinutes} min'
                            '${_servingName != null ? '  ·  Serving: $_servingName' : ''}',
                            style: GoogleFonts.inter(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._buildQueueList(),

                  const SizedBox(height: 24),

                  // ── Action menu ───────────────────────────────────────────
                  Text(
                    _l.tr('shopTools'),
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 14),

                  _ActionTile(
                    icon: Icons.edit_outlined,
                    iconColor: const Color(0xFF7C3AED),
                    iconBg: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                    title: _l.tr('editShopDetails'),
                    subtitle: _l.tr('editShopSubtitle'),
                    onTap: () async {
                      final updated = await Navigator.push<ShopModel>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => EditShopScreen(shop: _shop)),
                      );
                      if (updated != null && mounted) {
                        setState(() => _shop = updated);
                      }
                    },
                  ),

                  _ActionTile(
                    icon: Icons.rocket_launch_outlined,
                    iconColor: AppColors.primary,
                    iconBg: AppColors.primary.withValues(alpha: 0.1),
                    title: _l.tr('promoteShop'),
                    subtitle: _l.tr('promoteSubtitle'),
                    badge: _shop.isPromoted ? 'Active' : '₹20/day',
                    badgeColor: _shop.isPromoted ? AppColors.tertiary : AppColors.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PromotionScreen(shop: _shop)),
                    ).then((_) => setState(() {})),
                  ),

                  _ActionTile(
                    icon: Icons.local_offer_outlined,
                    iconColor: AppColors.secondary,
                    iconBg: AppColors.secondary.withValues(alpha: 0.1),
                    title: _l.tr('addEditScheme'),
                    subtitle: _l.tr('addEditSchemeSubtitle'),
                    badge: _shop.activeScheme != null ? _shop.activeScheme!.validityText : 'None',
                    badgeColor: _shop.activeScheme != null ? AppColors.secondary : AppColors.onSurfaceVariant,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SchemeScreen(shop: _shop)),
                    ).then((_) => setState(() {})),
                  ),

                  _ActionTile(
                    icon: Icons.workspace_premium_outlined,
                    iconColor: hasSubscription ? AppColors.tertiary : AppColors.error,
                    iconBg: hasSubscription ? AppColors.tertiary.withValues(alpha: 0.1) : AppColors.errorContainer,
                    title: _l.tr('subscription'),
                    subtitle: hasSubscription
                        ? _l.tr('subscriptionActiveMsg')
                        : _l.tr('activateToOpen'),
                    badge: hasSubscription ? _l.tr('activate') : _l.tr('inactive'),
                    badgeColor: hasSubscription ? AppColors.tertiary : AppColors.error,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SubscriptionScreen(shop: _shop)),
                    ).then((_) => setState(() {})),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _MetricCell extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MetricCell({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.onSurface),
          ),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _ActionTile({
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
                  Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            if (badge != null)
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
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }
}
