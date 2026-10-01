import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/subscription_service.dart';
import '../../services/payment_service.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/no_refund_notice.dart';
import '../../widgets/gradient_button.dart';

class SubscriptionScreen extends StatefulWidget {
  final ShopModel shop;

  const SubscriptionScreen({super.key, required this.shop});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late bool _isActive;
  String _selectedPlan = 'monthly';
  bool _isLoading = false;
  bool _subscriptionJustActivated = false;
  // True while this shop has never had a plan and its owner hasn't had their one free month:
  // the screen then offers "Activate Free Trial" and keeps the paid plans out of the way.
  bool _trialAvailable = false;
  Map<String, dynamic>? _subscriptionData;
  final _l = LocaleService.instance;
  final _ctaKey = GlobalKey();

  void _scrollToCta() {
    final ctx = _ctaKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut, alignment: 0.5);
  }

  @override
  void initState() {
    super.initState();
    _isActive = widget.shop.hasActiveSubscription;
    _l.addListener(_onLocale);
    _fetchSubscription();
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    super.dispose();
  }

  void _onLocale() => setState(() {});

  Future<void> _fetchSubscription() async {
    if (mounted) setState(() => _isLoading = true);
    // Picks up any earlier payment Razorpay captured but we never activated
    // (e.g. UPI payment success when app was backgrounded, so verify never ran).
    try {
      final activated = await SubscriptionService.instance.reconcilePayments(widget.shop.id);
      if (activated.isNotEmpty && mounted) {
        // Let the getSubscription call below refresh the UI.
        _subscriptionJustActivated = false;
      }
    } catch (_) {}
    try {
      final res = await SubscriptionService.instance.getSubscription(widget.shop.id);
      if (mounted && !_subscriptionJustActivated) {
        setState(() {
          _isActive = res['has_active_subscription'] as bool? ?? _isActive;
          _subscriptionData = res['subscription'] as Map<String, dynamic>?;
          _trialAvailable = res['trial_available'] as bool? ?? false;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  /// "Activate Free Trial": the shop goes live for 30 days with no payment. Afterwards the
  /// 1-month / 3-month plans show and paying for one extends from the end of the trial.
  Future<void> _startTrial() async {
    setState(() => _isLoading = true);
    String? error;
    try {
      final res = await SubscriptionService.instance.startTrial(widget.shop.id);
      if (!mounted) return;
      setState(() {
        _isActive = res['has_active_subscription'] as bool? ?? true;
        _subscriptionData = res['subscription'] as Map<String, dynamic>?;
        _trialAvailable = false;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✓  Free trial activated! Your shop is now live for 1 month.'),
          backgroundColor: AppColors.tertiary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Something went wrong. Please try again.';
    }
    // Not started (e.g. already used): reload so the screen shows the paid plans instead.
    await _fetchSubscription();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: AppColors.error));
    }
  }

  String _formatExpiry() {
    if (_subscriptionData == null) return '';
    final expiresAt = _subscriptionData!['expires_at'] as String?;
    final daysRemaining = _subscriptionData!['days_remaining'] as int?;
    if (expiresAt == null) return '';
    try {
      final dt = DateTime.parse(expiresAt).toLocal();
      final day = dt.day.toString().padLeft(2, '0');
      final month = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1];
      final year = dt.year;
      final days = daysRemaining ?? 0;
      return 'Expires $day $month $year · $days day${days == 1 ? '' : 's'} left';
    } catch (_) {
      return '';
    }
  }

  // Two plans: 1 month (₹49) and 3 months (₹130). The server charges these same amounts.
  int get _price => _selectedPlan == 'quarterly' ? 130 : 49;
  String get _period => _selectedPlan == 'quarterly' ? '/3 months' : '/month';
  int get _durationDays => _selectedPlan == 'quarterly' ? 90 : 30;
  String get _planName => _selectedPlan == 'quarterly' ? '3-month' : 'Monthly';
  // The free first month given to new owners (plan == 'trial').
  bool get _isTrial => _subscriptionData?['plan'] == 'trial';
  // Backend expects 'basic' or 'premium', not the UI label
  String get _backendPlan => 'basic';

  final _benefits = [
    (Icons.queue_rounded, 'Accept Customer Queues', 'Customers can join your queue', true),
    (Icons.toggle_on_rounded, 'Open/Close Shop Control', 'Manage your shop status', true),
    (Icons.bar_chart_rounded, 'Queue Analytics', 'Daily traffic & wait insights', true),
    (Icons.rocket_launch_outlined, 'Featured Promotions (add-on)', 'Appear in featured section (₹10/day)', false),
    (Icons.local_offer_outlined, 'Add Schemes & Offers', 'Run deals for customers', true),
    (Icons.support_agent_rounded, 'Priority Support', '24/7 dedicated support', false),
  ];

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

  /// Entry point for the Pay button. If the shop already has an active
  /// subscription, explain when it ends and ask before extending it.
  void _activate() {
    final expiresAt = _subscriptionData?['expires_at'] as String?;
    final end = expiresAt == null ? null : DateTime.tryParse(expiresAt)?.toLocal();
    if (_isActive && end != null && end.isAfter(DateTime.now())) {
      final newEnd = end.add(Duration(days: _durationDays));
      final length = _selectedPlan == 'quarterly' ? '3 months' : '1 month';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Subscription already active', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your active subscription ends on ${_fmtDate(end)}.\n\n'
                'Do you want to extend it by $length? The new end date will be ${_fmtDate(newEnd)}.',
                style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 12),
              const NoRefundNotice(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showPaymentDialog(extend: true);
              },
              child: Text('Extend', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }
    _showPaymentDialog();
  }

  void _showPaymentDialog({bool extend = false}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Confirm Payment', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
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
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Professional Plan', style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
                        Text('$_planName subscription', style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('₹$_price', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Once activated, your shop will be open to receive customers.',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
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
            onPressed: () async {
              Navigator.pop(context);
              final expiryBeforePayment = _subscriptionData?['expires_at'];
              setState(() => _isLoading = true);
              bool success = false;
              String? errorMsg;
              // Once Razorpay checkout succeeds, money is captured — a failure
              // after that point needs very different messaging than one before it.
              bool paymentCaptured = false;
              // True once the Razorpay checkout was opened and closed without a success
              // callback. With UPI, Razorpay can capture the money and still close via its
              // error/cancel path (e.g. its "order is already paid" screen, then X), so we
              // must ask the server before telling the owner the payment failed.
              bool checkoutClosedWithoutSuccess = false;
              try {
                final order = await SubscriptionService.instance.createPaymentOrder(
                  widget.shop.id,
                  plan: _backendPlan,
                  durationDays: _durationDays,
                  extend: extend,
                );
                final result = await PaymentService.instance.openCheckout(
                  keyId: order['key_id'] as String,
                  orderId: order['order_id'] as String,
                  amountPaise: order['amount'] as int,
                  name: widget.shop.name,
                  description: '$_planName subscription',
                  contact: AuthService.instance.profile?['phone'] as String?,
                  email: AuthService.instance.profile?['email'] as String?,
                );
                paymentCaptured = true;
                await SubscriptionService.instance.verifyPaymentAndActivate(
                  widget.shop.id,
                  plan: _backendPlan,
                  durationDays: _durationDays,
                  razorpayOrderId: result.orderId,
                  razorpayPaymentId: result.paymentId,
                  razorpaySignature: result.signature,
                );
                success = true;
              } on PaymentAlreadyCaptured catch (_) {
                // UPI captured the payment but Razorpay delivered the "order is already
                // paid" error screen instead of the success callback. Money is on
                // Razorpay's end — mark as captured and let reconcile activate it below.
                paymentCaptured = true;
                // Fallback message if reconcile also fails (e.g. Razorpay still processing).
                errorMsg = 'Your payment was received and your subscription is being activated. It will show here shortly.';
              } on PaymentException catch (e) {
                checkoutClosedWithoutSuccess = true;
                errorMsg = e.message;
              } on ApiException catch (e) {
                // 409 = subscription is already active (e.g. reconcile just activated it
                // while the user was looking at the screen). Refresh state and show the
                // extend dialog instead of a red error.
                if (e.statusCode == 409 && !paymentCaptured) {
                  if (mounted) setState(() => _isLoading = false);
                  await _fetchSubscription();
                  if (mounted) _showPaymentDialog(extend: true);
                  return;
                }
                errorMsg = e.message;
              } catch (_) {
                errorMsg = paymentCaptured
                    ? 'Your payment may have gone through, but something went wrong confirming it. Please contact support before trying again.'
                    : 'Something went wrong. Please try again.';
              }
              // Razorpay took the money but verify failed / delivered "already paid"
              // error: ask the server to confirm with Razorpay directly.
              // The webhook may have activated it already (reconcile then reports nothing
              // new), so also compare the expiry with what it was before paying, retrying
              // briefly while Razorpay/webhook catch up.
              if (!success && (paymentCaptured || checkoutClosedWithoutSuccess)) {
                for (var attempt = 0; attempt < 4 && !success; attempt++) {
                  if (attempt > 0) await Future.delayed(const Duration(seconds: 2));
                  try {
                    success = (await SubscriptionService.instance.reconcilePayments(widget.shop.id))
                        .contains('subscription');
                    if (!success) {
                      final res = await SubscriptionService.instance.getSubscription(widget.shop.id);
                      final sub = res['subscription'] as Map<String, dynamic>?;
                      success = sub != null && sub['expires_at'] != expiryBeforePayment;
                    }
                  } catch (_) {}
                  if (!paymentCaptured) break; // plain cancel: one check is enough
                }
              }
              {
                if (mounted) {
                  if (success) {
                    setState(() {
                      _isActive = true;
                      _isLoading = false;
                      _subscriptionJustActivated = false; // Allow refresh
                    });
                    _fetchSubscription();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(extend
                            ? '✓  Payment completed! Your subscription has been extended.'
                            : '✓  Payment completed! Subscription is active and your shop is live.'),
                        backgroundColor: AppColors.tertiary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  } else {
                    setState(() => _isLoading = false);
                    if (errorMsg != null) {
                      if (paymentCaptured) {
                        // Payment went through but activation failed — this needs a
                        // dialog the owner has to actively dismiss, not a snackbar
                        // that can be missed.
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
                            content: Text(errorMsg!, style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, height: 1.5)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('OK', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(errorMsg), backgroundColor: AppColors.error),
                        );
                      }
                    }
                  }
                }
              }
            },
            child: Text('Pay ₹$_price', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _cancel() {
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final confirmed = confirmCtrl.text == 'CANCEL'; // exact: no spaces, no lowercase
          Widget point(String text) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.circle, size: 6, color: AppColors.error),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface, height: 1.4))),
                  ],
                ),
              );
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(child: Text('Cancel Subscription?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700))),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  point('Your subscription will be cancelled right away.'),
                  point('There will be NO REFUND for the days you have left.'),
                  point('Your shop will become inactive and be closed. Customers will not be able to find it or join its queue.'),
                  point('You will not be able to manage it as an active shop until you subscribe again.'),
                  const SizedBox(height: 8),
                  Text('Type CANCEL below to confirm.', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmCtrl,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setDialog(() {}),
                    decoration: const InputDecoration(hintText: 'CANCEL'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Keep Active', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: !confirmed
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(context);
                        setState(() => _isLoading = true);
                        String? error;
                        try {
                          await SubscriptionService.instance.cancelSubscription(widget.shop.id);
                        } on ApiException catch (e) {
                          error = e.message;
                        } catch (_) {
                          error = 'Something went wrong. Please try again.';
                        }
                        if (!mounted) return;
                        if (error == null) {
                          // Cancelled: go straight back to the shop page, which reloads and shows it inactive.
                          messenger.hideCurrentSnackBar();
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text('Subscription cancelled. Your shop is now inactive.'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                          navigator.popUntil((r) => r.isFirst);
                          return;
                        }
                        // The request may have gone through even though the reply failed, so
                        // reload the real state instead of leaving the screen as it was.
                        await _fetchSubscription();
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(content: Text(error), backgroundColor: AppColors.error));
                      },
                child: Text('Cancel Subscription', style: GoogleFonts.inter(color: confirmed ? AppColors.error : AppColors.onSurfaceVariant.withValues(alpha: 0.5), fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Offer the free month only to a shop with no plan yet whose owner hasn't used theirs.
    final trialOffer = !_isActive && _trialAvailable;
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
            title: Text('Subscription', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: _isLoading
                  ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Status banner ─────────────────────────────────────────
                        if (!_isActive) ...[
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
                                    const Icon(Icons.block_rounded, color: AppColors.onErrorContainer, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Subscription Inactive',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.onErrorContainer,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${widget.shop.name} is closed and not accepting queues. Subscribe to activate.',
                                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.onErrorContainer, height: 1.4),
                                ),
                                const SizedBox(height: 10),
                                GestureDetector(
                                  onTap: _scrollToCta,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        trialOffer ? 'Try 1 month free trial' : 'Choose a plan',
                                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.arrow_downward_rounded, size: 16, color: AppColors.primary),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.tertiaryFixed.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: AppColors.tertiary, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_isTrial ? 'Free Trial Active' : 'Subscription Active', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.tertiary)),
                                      Text('${widget.shop.name} is live and accepting queues', style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
                                      if (_formatExpiry().isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(_formatExpiry(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ── Hero ──────────────────────────────────────────────────
                        Text(
                          _isActive ? 'Manage Your Plan' : (trialOffer ? 'Start Your Free Month' : 'Choose Your Plan'),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'A subscription keeps your shop live and customers can join your queue.',
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
                        ),
                        const SizedBox(height: 24),

                        // ── Free trial offer (first-time owners, before any plan) ───────────
                        if (trialOffer) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient135,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 22),
                                    const SizedBox(width: 10),
                                    Text('1 Month Free Trial',
                                        style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Your shop goes live straight away — no payment needed. After the free month you can continue with a 1-month (₹49) or 3-month (₹130) plan.',
                                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.85), height: 1.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── Plan toggle ───────────────────────────────────────────
                        if (!trialOffer) Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedPlan = 'monthly'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: _selectedPlan == 'monthly' ? AppColors.primaryGradient135 : null,
                                    color: _selectedPlan == 'monthly' ? null : AppColors.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _selectedPlan == 'monthly'
                                          ? Colors.transparent
                                          : AppColors.outline.withValues(alpha: 0.3),
                                    ),
                                    boxShadow: _selectedPlan == 'monthly'
                                        ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))]
                                        : [],
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '₹49',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: _selectedPlan == 'monthly' ? Colors.white : AppColors.onSurface,
                                        ),
                                      ),
                                      Text(
                                        'per month',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _selectedPlan == 'monthly' ? Colors.white70 : AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedPlan = 'quarterly'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: _selectedPlan == 'quarterly' ? AppColors.primaryGradient135 : null,
                                    color: _selectedPlan == 'quarterly' ? null : AppColors.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _selectedPlan == 'quarterly'
                                          ? Colors.transparent
                                          : AppColors.outline.withValues(alpha: 0.3),
                                    ),
                                    boxShadow: _selectedPlan == 'quarterly'
                                        ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))]
                                        : [],
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '₹130',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: _selectedPlan == 'quarterly' ? Colors.white : AppColors.onSurface,
                                        ),
                                      ),
                                      Text(
                                        'per 3 months',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _selectedPlan == 'quarterly' ? Colors.white70 : AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                      if (_selectedPlan == 'quarterly')
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text('Save ₹17', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ── What's included ───────────────────────────────────────
                        Text(
                          "What's Included",
                          style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                        ),
                        const SizedBox(height: 14),
                        ..._benefits.map((b) => _BenefitTile(icon: b.$1, title: b.$2, subtitle: b.$3, included: b.$4)),
                        const SizedBox(height: 24),

                        // ── CTA ───────────────────────────────────────────────────
                        SizedBox(key: _ctaKey, height: 0),
                        if (trialOffer)
                          SizedBox(
                            width: double.infinity,
                            child: GradientButton(
                              label: 'Activate Free Trial',
                              onPressed: _startTrial,
                              icon: Icons.card_giftcard_rounded,
                            ),
                          )
                        else if (!_isActive)
                          SizedBox(
                            width: double.infinity,
                            child: GradientButton(
                              label: 'Activate  ·  ₹$_price$_period',
                              onPressed: _activate,
                              icon: Icons.lock_open_rounded,
                            ),
                          )
                        else ...[
                          SizedBox(
                            width: double.infinity,
                            child: GradientButton(
                              label: 'Renew / Upgrade Plan',
                              onPressed: _activate,
                              icon: Icons.autorenew_rounded,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: _cancel,
                              child: Text(
                                'Cancel Subscription',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.error),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool included;

  const _BenefitTile({required this.icon, required this.title, required this.subtitle, required this.included});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: included
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: included ? AppColors.primary : AppColors.onSurfaceVariant.withValues(alpha: 0.5),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: included ? AppColors.onSurface : AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant.withValues(alpha: included ? 1.0 : 0.5),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            included ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
            color: included ? AppColors.tertiary : AppColors.onSurfaceVariant.withValues(alpha: 0.3),
            size: 18,
          ),
        ],
      ),
    );
  }
}
