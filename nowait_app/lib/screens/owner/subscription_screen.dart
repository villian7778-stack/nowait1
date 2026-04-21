import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/subscription_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
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
  Map<String, dynamic>? _subscriptionData;
  final _l = LocaleService.instance;

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
    try {
      final res = await SubscriptionService.instance.getSubscription(widget.shop.id);
      if (mounted && !_subscriptionJustActivated) {
        setState(() {
          _isActive = res['has_active_subscription'] as bool? ?? _isActive;
          _subscriptionData = res['subscription'] as Map<String, dynamic>?;
        });
      }
    } catch (_) {}
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

  int get _price => _selectedPlan == 'yearly' ? 2999 : 300;
  String get _period => _selectedPlan == 'yearly' ? '/year' : '/month';
  int get _durationDays => _selectedPlan == 'yearly' ? 365 : 30;
  // Backend expects 'basic' or 'premium', not the UI label
  String get _backendPlan => _selectedPlan == 'yearly' ? 'premium' : 'basic';

  final _benefits = [
    (Icons.queue_rounded, 'Accept Customer Queues', 'Customers can join your queue', true),
    (Icons.toggle_on_rounded, 'Open/Close Shop Control', 'Manage your shop status', true),
    (Icons.bar_chart_rounded, 'Queue Analytics', 'Daily traffic & wait insights', true),
    (Icons.rocket_launch_outlined, 'Featured Promotions (add-on)', 'Appear in featured section (₹20/day)', false),
    (Icons.local_offer_outlined, 'Add Schemes & Offers', 'Run deals for customers', true),
    (Icons.support_agent_rounded, 'Priority Support', '24/7 dedicated support', false),
  ];

  void _activate() {
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
                        Text('${_selectedPlan == 'yearly' ? 'Annual' : 'Monthly'} subscription', style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
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
              setState(() => _isLoading = true);
              bool success = false;
              String? errorMsg;
              try {
                await SubscriptionService.instance.createSubscription(
                  widget.shop.id,
                  plan: _backendPlan,
                  durationDays: _durationDays,
                );
                success = true;
              } on ApiException catch (e) {
                errorMsg = e.message;
              } catch (_) {
                errorMsg = 'Something went wrong. Please try again.';
              } finally {
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
                        content: const Text('✓  Subscription activated! Your shop is now live.'),
                        backgroundColor: AppColors.tertiary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  } else {
                    setState(() => _isLoading = false);
                    if (errorMsg != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(errorMsg), backgroundColor: AppColors.error),
                      );
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
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Subscription?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text(
          'Your shop will immediately be closed and customers will not be able to join the queue.',
          style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Keep Active', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                await SubscriptionService.instance.cancelSubscription(widget.shop.id);
                if (mounted) setState(() { _isActive = false; _isLoading = false; });
              } on ApiException catch (e) {
                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
                  );
                }
              } catch (_) {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: Text('Cancel Subscription', style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                                      Text('Subscription Active', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.tertiary)),
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
                          _isActive ? 'Manage Your Plan' : 'Choose Your Plan',
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

                        // ── Plan toggle ───────────────────────────────────────────
                        Row(
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
                                        '₹300',
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
                                onTap: () => setState(() => _selectedPlan = 'yearly'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: _selectedPlan == 'yearly' ? AppColors.primaryGradient135 : null,
                                    color: _selectedPlan == 'yearly' ? null : AppColors.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _selectedPlan == 'yearly'
                                          ? Colors.transparent
                                          : AppColors.outline.withValues(alpha: 0.3),
                                    ),
                                    boxShadow: _selectedPlan == 'yearly'
                                        ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))]
                                        : [],
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '₹2,999',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: _selectedPlan == 'yearly' ? Colors.white : AppColors.onSurface,
                                        ),
                                      ),
                                      Text(
                                        'per year',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _selectedPlan == 'yearly' ? Colors.white70 : AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                      if (_selectedPlan == 'yearly')
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text('Save ₹601', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
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
                        if (!_isActive)
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
