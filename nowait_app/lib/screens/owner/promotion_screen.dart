import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/promotion_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

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
    setState(() => _loadingPromotion = true);
    try {
      final promos = await PromotionService.instance.getPromotions(
        widget.shop.id,
        activeOnly: true,
      );
      // Featured Promotion entries are the paid visibility boosts
      final featured = promos.where((p) => p['title'] == 'Featured Promotion').toList();
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

  int get _totalCost => _selectedDays * 20;

  String _formatExpiry(String? expiresAt) {
    if (expiresAt == null) return '';
    try {
      final dt = DateTime.parse(expiresAt).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return 'Active until ${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  void _payAndActivate() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Confirm Payment', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
                  Text('$_selectedDays days × ₹20/day', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                  Text('₹$_totalCost', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your shop will appear in the Promotions section for $_selectedDays days.',
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
              try {
                final validUntil = DateTime.now()
                    .add(Duration(days: _selectedDays))
                    .toUtc()
                    .toIso8601String();
                await PromotionService.instance.createPromotion(
                  widget.shop.id,
                  title: 'Featured Promotion',
                  description: 'Shop promoted for $_selectedDays day${_selectedDays == 1 ? '' : 's'}',
                  validUntil: validUntil,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓  Promotion activated for $_selectedDays days!'),
                      backgroundColor: AppColors.tertiary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                  await _loadActivePromotion();
                  setState(() => _isLoading = false);
                }
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
            child: Text('Pay ₹$_totalCost', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w700)),
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
        content: Text(
          'Your shop will stop appearing in the featured section.',
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

  bool get _hasActivePromotion => _activePromotion != null || widget.shop.isPromoted;

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
                  // Status card with expiry date
                  if (_loadingPromotion)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  else if (_hasActivePromotion) ...[
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
                                Text(
                                  'Promotion is currently active',
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.tertiary),
                                ),
                                // Item 14: Show expiry date
                                if (_activePromotion?['valid_until'] != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatExpiry(_activePromotion!['valid_until'] as String?),
                                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
                    'Select Duration',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [1, 3, 7, 14, 30].map((days) {
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
                            Text('₹20/day', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
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
                // Item 14: Cancel promotion button
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
