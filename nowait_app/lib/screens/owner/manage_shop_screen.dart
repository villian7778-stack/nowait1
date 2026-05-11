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
    ).whenComplete(ctrl.dispose);
  }

  /// Shows skip confirmation dialog with optional reason, then calls the API.
  void _showSkipDialog(String entryId, String customerName) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppColors.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_off_rounded, color: AppColors.error, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Skip Customer?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to skip $customerName? They will lose their position in the queue.',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // Optional reason field
              StatefulBuilder(
                builder: (ctx, setSt) => TextField(
                  controller: noteCtrl,
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Reason (optional, e.g. Did not show up)',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.4)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    prefixIcon: const Icon(Icons.edit_note_rounded, size: 18, color: AppColors.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await QueueService.instance.skipCustomer(
                            entryId,
                            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                          );
                          if (mounted) {
                            _loadQueue();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$customerName skipped'),
                                backgroundColor: AppColors.onSurfaceVariant,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } on ApiException catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
                            );
                          }
                        }
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.skip_next_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Yes, Skip',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(noteCtrl.dispose);
  }

  /// Returns service details for a queue entry.
  /// Prefers `selected_services` from the API (contains name/price/duration).
  /// Falls back to cross-referencing `_shop.services` by ID for older API responses.
  List<Map<String, dynamic>> _resolveServices(Map<String, dynamic> entry) {
    final raw = entry['selected_services'] as List?;
    if (raw != null && raw.isNotEmpty) {
      return raw.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    }
    final ids = entry['service_ids'] as List? ?? [];
    if (ids.isEmpty) return const [];
    final shopServicesMap = {for (final s in _shop.services) s.id: s};
    final result = <Map<String, dynamic>>[];
    for (final id in ids) {
      final svc = shopServicesMap[id.toString()];
      if (svc != null) {
        result.add({'name': svc.name, 'price': svc.price, 'duration_minutes': svc.durationMinutes});
      }
    }
    return result;
  }

  void _showServiceDetailsPopup(String customerName, List<Map<String, dynamic>> services) {
    double total = 0;
    for (final s in services) {
      final price = s['price'];
      if (price != null) total += (price as num).toDouble();
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient135,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Selected Services', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                        Text(customerName, style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (services.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No services selected', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                )
              else
                ...services.map((s) {
                  final sName = s['name']?.toString() ?? 'Service';
                  final price = s['price'] != null ? (s['price'] as num).toDouble() : 0.0;
                  final dur = s['duration_minutes'] as int?;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sName, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                              if (dur != null)
                                Text('~$dur min', style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Text(
                          '₹${price % 1 == 0 ? price.toInt() : price.toStringAsFixed(1)}',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ],
                    ),
                  );
                }),
              if (services.length > 1) ...[
                Container(height: 1, color: AppColors.outline.withValues(alpha: 0.15)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                    Text(
                      '₹${total % 1 == 0 ? total.toInt() : total.toStringAsFixed(1)}',
                      style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: 'Done',
                  onPressed: () => Navigator.pop(context),
                  height: 46,
                  borderRadius: 12,
                ),
              ),
            ],
          ),
        ),
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

      // Resolve service details — uses selected_services from API when present, falls back to service_ids
      final resolvedServices = _resolveServices(entry);
      final hasServices = resolvedServices.isNotEmpty;

      double serviceTotal = 0;
      for (final s in resolvedServices) {
        final price = s['price'];
        if (price != null) serviceTotal += (price as num).toDouble();
      }
      final serviceNames = resolvedServices.map((s) => s['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();

      return GestureDetector(
        onTap: () => _showServiceDetailsPopup(name, resolvedServices),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          if (hasServices && !isServing) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.receipt_long_rounded, size: 10, color: AppColors.onSurfaceVariant),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    serviceNames.join(', '),
                                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '₹${serviceTotal % 1 == 0 ? serviceTotal.toInt() : serviceTotal.toStringAsFixed(1)}',
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Receipt icon — always visible so owner knows to tap for details
                    Container(
                      width: 28, height: 28,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: hasServices
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        size: 14,
                        color: hasServices ? AppColors.primary : AppColors.onSurfaceVariant.withValues(alpha: 0.4),
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
                    // Skip / Serving badge
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
                            color: hasSubscription ? AppColors.errorContainer : AppColors.surfaceContainerLow,
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
              ),
              // Inline service breakdown for the currently serving customer
              if (isServing && hasServices) ...[
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
                  ),
                  child: Column(
                    children: [
                      ...resolvedServices.map((s) {
                        final sName = s['name']?.toString() ?? '';
                        final price = s['price'] != null ? (s['price'] as num).toDouble() : 0.0;
                        final dur = s['duration_minutes'] as int?;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  sName + (dur != null ? '  (~$dur min)' : ''),
                                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurface),
                                ),
                              ),
                              Text(
                                '₹${price % 1 == 0 ? price.toInt() : price.toStringAsFixed(1)}',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (resolvedServices.length > 1) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                            Text(
                              '₹${serviceTotal % 1 == 0 ? serviceTotal.toInt() : serviceTotal.toStringAsFixed(1)}',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
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
                  MaterialPageRoute(builder: (_) => const NotificationsScreen(showPromoTab: false)),
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

