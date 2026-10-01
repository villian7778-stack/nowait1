import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/promotion_service.dart';
import '../../services/subscription_service.dart';
import '../../services/payment_service.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/no_refund_notice.dart';

class PromotionScreen extends StatefulWidget {
  final ShopModel shop;

  const PromotionScreen({super.key, required this.shop});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  int _selectedDays = 7;
  bool _isLoading = false;
  bool _isCancelling = false;

  // Active promotion loaded from API
  Map<String, dynamic>? _activePromotion;
  bool _loadingPromotion = true;

  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _l.addListener(_onLocale);
    _loadActivePromotion();
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    super.dispose();
  }

  void _onLocale() => setState(() {});

  Future<void> _loadActivePromotion() async {
    // Picks up any earlier payment Razorpay captured but we never activated.
    try {
      await SubscriptionService.instance.reconcilePayments(widget.shop.id);
    } catch (_) {}
    if (mounted) setState(() => _loadingPromotion = true);
    try {
      final promos = await PromotionService.instance.getPromotions(
        widget.shop.id,
        activeOnly: true,
      );
      // Featured Promotion entries are the paid visibility boosts; ignore any that have expired
      final featured = promos.where((p) {
        if (p['title'] != 'Featured Promotion') return false;
        final end = DateTime.tryParse(p['valid_until'] as String? ?? '');
        return end != null && end.isAfter(DateTime.now());
      }).toList();
      if (mounted) {
        setState(() {
          _activePromotion = featured.isNotEmpty ? featured.first : null;
          _loadingPromotion = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPromotion = false);
    }
  }

  static const _pricePerDay = 10;
  int get _totalCost => _selectedDays * _pricePerDay;

  static const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _fmtDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

  DateTime? get _activeEnd {
    final v = _activePromotion?['valid_until'] as String?;
    return v == null ? null : DateTime.tryParse(v)?.toLocal();
  }

  /// Whole days left on the running promotion (rounded up, so the last day still counts).
  int _daysLeft(DateTime end) {
    final hours = end.difference(DateTime.now()).inHours;
    return hours <= 0 ? 0 : (hours / 24).ceil();
  }

  /// Total days this promotion has been bought for (first purchase + every extension).
  int? get _totalDays {
    final created = DateTime.tryParse(_activePromotion?['created_at'] as String? ?? '');
    final end = _activeEnd;
    if (created == null || end == null) return null;
    final d = (end.difference(created.toLocal()).inMinutes / 1440).round();
    return d < 1 ? 1 : d;
  }

  bool get _hasActivePromotion => _activePromotion != null;

  void _payAndActivate() {
    final end = _activeEnd;
    final extending = _hasActivePromotion && end != null && end.isAfter(DateTime.now());
    final daysText = '$_selectedDays day${_selectedDays == 1 ? '' : 's'}';
    final newEnd = extending
        ? end.add(Duration(days: _selectedDays))
        : DateTime.now().add(Duration(days: _selectedDays));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(extending ? 'Extend Promotion' : 'Confirm Payment',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient135,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$daysText × ₹$_pricePerDay/day', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                  Text('₹$_totalCost',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              extending
                  ? 'Your promotion is active until ${_fmtDate(end)}. Adding $daysText extends it to ${_fmtDate(newEnd)}.'
                  : 'Your shop will appear in the Promotions section for $daysText, until ${_fmtDate(newEnd)}.',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 12),
            const NoRefundNotice(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _runPayment(extending: extending);
            },
            child: Text('Pay ₹$_totalCost', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _runPayment({required bool extending}) async {
    final days = _selectedDays;
    final endBefore = _activePromotion?['valid_until'];
    setState(() => _isLoading = true);
    bool success = false;
    String? errorMsg;
    // Once Razorpay checkout succeeds the money is captured, so a failure after that
    // needs different messaging than one before it.
    bool paymentCaptured = false;
    // Checkout closed without a success callback. With UPI, Razorpay can capture the
    // money and still close via its error/cancel path, so ask the server before
    // telling the owner the payment failed.
    bool checkoutClosedWithoutSuccess = false;
    try {
      final description = '${extending ? 'Promotion extended' : 'Shop promoted'} for $days day${days == 1 ? '' : 's'}';
      final order = await PromotionService.instance.createPaymentOrder(widget.shop.id, days: days);
      final result = await PaymentService.instance.openCheckout(
        keyId: order['key_id'] as String,
        orderId: order['order_id'] as String,
        amountPaise: order['amount'] as int,
        name: widget.shop.name,
        description: description,
        contact: AuthService.instance.profile?['phone'] as String?,
        email: AuthService.instance.profile?['email'] as String?,
        purpose: 'promotion',
      );
      paymentCaptured = true;
      await PromotionService.instance.verifyPaymentAndActivate(
        widget.shop.id,
        razorpayOrderId: result.orderId,
        razorpayPaymentId: result.paymentId,
        razorpaySignature: result.signature,
      );
      success = true;
    } on PaymentAlreadyCaptured catch (_) {
      paymentCaptured = true;
      errorMsg = 'Your payment was received and your promotion is being activated. It will show here shortly.';
    } on PaymentException catch (e) {
      checkoutClosedWithoutSuccess = true;
      errorMsg = e.message;
    } on ApiException catch (e) {
      errorMsg = e.message;
    } catch (_) {
      errorMsg = paymentCaptured
          ? 'Your payment may have gone through, but something went wrong confirming it. Please contact support before trying again.'
          : _l.tr('somethingWrong');
    }

    // Money taken but verify failed / checkout closed oddly: ask the server to confirm with
    // Razorpay, and also compare the end date with what it was before paying (the webhook
    // may have activated it already), retrying briefly while things catch up.
    if (!success && (paymentCaptured || checkoutClosedWithoutSuccess)) {
      for (var attempt = 0; attempt < 4 && !success; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(seconds: 2));
        try {
          success = (await SubscriptionService.instance.reconcilePayments(widget.shop.id)).contains('promotion');
        } catch (_) {}
        if (!success) {
          try {
            final promos = await PromotionService.instance.getPromotions(widget.shop.id, activeOnly: true);
            final featured = promos.where((p) => p['title'] == 'Featured Promotion').toList();
            success = featured.isNotEmpty && featured.first['valid_until'] != endBefore;
          } catch (_) {}
        }
        if (!paymentCaptured) break; // plain cancel: one check is enough
      }
    }

    if (!mounted) return;
    if (success) {
      await _loadActivePromotion();
      if (!mounted) return;
      setState(() => _isLoading = false);
      final end = _activeEnd;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extending
              ? '✓  Payment completed! Promotion extended by $days day${days == 1 ? '' : 's'}${end != null ? ' — active until ${_fmtDate(end)}' : ''}.'
              : '✓  Payment completed! Promotion is active${end != null ? ' until ${_fmtDate(end)}' : ''}.'),
          backgroundColor: AppColors.tertiary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    setState(() => _isLoading = false);
    if (errorMsg == null) return;
    if (paymentCaptured) {
      _showPaymentCapturedDialog(errorMsg);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: AppColors.error),
      );
    }
  }

  /// Money was captured but activation could not be confirmed — a dialog the owner has to
  /// dismiss, not a snackbar that can be missed.
  void _showPaymentCapturedDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(child: Text('Payment received', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700))),
          ],
        ),
        content: Text(message, style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _cancelPromotion() {
    final promoId = _activePromotion?['id'] as String?;
    if (promoId == null) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Promotion?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your shop will stop appearing in the featured section.',
              style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            const NoRefundNotice(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Keep Active', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isCancelling = true);
              try {
                await PromotionService.instance.deletePromotion(promoId);
                if (mounted) {
                  setState(() { _activePromotion = null; _isCancelling = false; });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Promotion cancelled'), behavior: SnackBarBehavior.floating),
                  );
                }
              } on ApiException catch (e) {
                if (mounted) {
                  setState(() => _isCancelling = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
                  );
                }
              } catch (_) {
                if (mounted) setState(() => _isCancelling = false);
              }
            },
            child: Text('Cancel Promotion', style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _activeBanner() {
    final end = _activeEnd;
    final total = _totalDays;
    final left = end == null ? null : _daysLeft(end);
    final note = _activePromotion?['description'] as String?;
    Widget stat(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value,
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tertiaryFixed.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.tertiary, size: 20),
              const SizedBox(width: 8),
              Text('Promotion is active',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.tertiary)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (total != null) stat('Total promoted', '$total day${total == 1 ? '' : 's'}'),
              if (left != null) stat('Days left', '$left'),
              if (end != null) stat('Expires on', _fmtDate(end)),
            ],
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(note, style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        title: Text('Promote Shop', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Active promotion: days, days left, expiry and any extension
                  if (_loadingPromotion)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  else if (_hasActivePromotion) ...[
                    _activeBanner(),
                    const SizedBox(height: 20),
                  ],
                  // Hero
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient135,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.rocket_launch_outlined, color: Colors.white, size: 28),
                        const SizedBox(height: 12),
                        Text(
                          'Boost Your Visibility',
                          style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your shop will appear in the featured Promotions section — the first thing customers see when they open your category.',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.85), height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    _hasActivePromotion ? 'Add More Days' : 'Select Duration',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [3, 7, 15].map((days) {
                      final selected = _selectedDays == days;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedDays = days),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: selected ? AppColors.primaryGradient135 : null,
                            color: selected ? null : AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? Colors.transparent : AppColors.outline.withValues(alpha: 0.3),
                            ),
                            boxShadow: selected
                                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))]
                                : [],
                          ),
                          child: Column(
                            children: [
                              Text(
                                '$days',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? Colors.white : AppColors.onSurface,
                                ),
                              ),
                              Text(
                                days == 1 ? 'Day' : 'Days',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: selected ? Colors.white70 : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Cost', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                            Text(
                              '₹$_totalCost',
                              style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Rate', style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
                            Text('₹$_pricePerDay/day', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                            Text('for $_selectedDays day${_selectedDays == 1 ? '' : 's'}', style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          // Pinned CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: (_isLoading || _isCancelling)
                      ? Container(
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient135,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            ),
                          ),
                        )
                      : GradientButton(
                          label: _hasActivePromotion ? 'Extend Promotion  ₹$_totalCost' : 'Pay & Activate  ₹$_totalCost',
                          onPressed: _payAndActivate,
                          icon: Icons.payment_rounded,
                        ),
                ),
                if (_hasActivePromotion && !_isCancelling) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _cancelPromotion,
                      child: Text(
                        'Cancel Promotion',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.error),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
