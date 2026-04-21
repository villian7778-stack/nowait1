import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/queue_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/ping_dot.dart';
import '../../widgets/dashed_circle_painter.dart';
import 'queue_status_screen.dart';

class TokenScreen extends StatefulWidget {
  final ShopModel shop;
  final String token;
  final int position;
  final int estimatedWait;
  final String entryId;

  const TokenScreen({
    super.key,
    required this.shop,
    required this.token,
    required this.position,
    required this.estimatedWait,
    required this.entryId,
  });

  @override
  State<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends State<TokenScreen> with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _entryController;
  late Animation<double> _entryAnim;

  bool _isComing = false;
  bool _comingNotified = false;
  Timer? _autoNavTimer;
  int _countdown = 3;
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _l.addListener(_onLocale);

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _entryAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack);

    // Auto-navigate to QueueStatusScreen after 3 seconds
    _startCountdown();
  }

  void _startCountdown() {
    _autoNavTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _autoNavigate();
      }
    });
  }

  Future<void> _autoNavigate() async {
    if (!mounted) return;
    // Fetch live entry so QueueStatusScreen starts with fresh data
    QueueEntry? entry;
    try {
      final entries = await QueueService.instance.getMyStatus(shopId: widget.shop.id);
      entry = entries.where((e) => e.entryId == widget.entryId).firstOrNull;
    } catch (_) {}

    // Fallback: construct from static join data
    entry ??= QueueEntry(
      id: widget.entryId,
      entryId: widget.entryId,
      shopId: widget.shop.id,
      shopName: widget.shop.name,
      token: widget.token,
      position: widget.position,
      peopleAhead: widget.position - 1,
      estimatedWaitMinutes: widget.estimatedWait,
      nowServingToken: widget.shop.currentToken,
      status: widget.position <= 3 ? QueueStatus.almostThere : QueueStatus.waiting,
    );

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => QueueStatusScreen(entry: entry!)),
    );
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _spinController.dispose();
    _entryController.dispose();
    _autoNavTimer?.cancel();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  Future<void> _notifyImComing() async {
    if (_isComing || _comingNotified) return;
    setState(() => _isComing = true);
    try {
      await QueueService.instance.notifyComing(widget.entryId);
      if (mounted) {
        setState(() { _isComing = false; _comingNotified = true; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_l.tr('shopNotifiedMsg', params: {'shop': widget.shop.name})),
            backgroundColor: AppColors.tertiary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isComing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isComing = false);
    }
  }

  void _cancelQueue() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _l.tr('leaveQueue'),
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          _l.tr('tokenCancelMsg', params: {'token': widget.token, 'shop': widget.shop.name}),
          style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_l.tr('stay'), style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _autoNavTimer?.cancel();
              try {
                await QueueService.instance.cancelQueue(widget.entryId);
              } on ApiException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
                  );
                  return;
                }
              } catch (_) {}
              if (mounted) Navigator.pop(context);
            },
            child: Text(_l.tr('leave'), style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerLow,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _l.tr('yourTokenTitle'),
                          style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                        ),
                        Text(
                          widget.shop.name,
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.tertiary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const PingDot(),
                        const SizedBox(width: 5),
                        Text(
                          _l.tr('live'),
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.tertiary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  children: [
                    // ── Token circle ────────────────────────────────────────
                    ScaleTransition(
                      scale: _entryAnim,
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _spinController,
                              builder: (context, child) => Transform.rotate(
                                angle: _spinController.value * 2 * pi,
                                child: CustomPaint(
                                  size: const Size(200, 200),
                                  painter: DashedCirclePainter(),
                                ),
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient135,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _l.tr('yourToken'),
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.token,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 52,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                    letterSpacing: -2,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.tertiaryFixed.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _l.tr('positionLabel', params: {'n': '${widget.position}'}),
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.tertiary,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Auto-navigate countdown banner
                    if (_countdown > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.timer_outlined, color: AppColors.primary, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Opening live tracker in $_countdown...',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),

                    // ── Queue info bento ─────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _StatCell(
                            icon: Icons.people_outline_rounded,
                            value: '${widget.position - 1}',
                            suffix: (widget.position - 1) == 1 ? _l.tr('person') : _l.tr('people'),
                            label: _l.tr('aheadOfYou'),
                            highlight: (widget.position - 1) <= 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCell(
                            icon: Icons.schedule_rounded,
                            value: '~${widget.estimatedWait}',
                            suffix: _l.tr('mins'),
                            label: _l.tr('estWaitTime'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Now serving ──────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.tertiaryFixed.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.tertiary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.how_to_reg_outlined, color: AppColors.tertiary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _l.tr('nowServing'),
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.tertiary),
                                ),
                                Text(
                                  'Token #${widget.shop.currentToken.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Notification reminder ────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.notifications_active_outlined, color: AppColors.primary, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _l.tr('stayNearbyHint'),
                              style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── I'm Coming button ────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: _comingNotified
                          ? Container(
                              height: 52,
                              decoration: BoxDecoration(
                                color: AppColors.tertiary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: AppColors.tertiary, size: 18),
                                    const SizedBox(width: 8),
                                    Text('Shop notified — on your way!', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.tertiary)),
                                  ],
                                ),
                              ),
                            )
                          : _isComing
                              ? Container(
                                  height: 52,
                                  decoration: BoxDecoration(gradient: AppColors.primaryGradient135, borderRadius: BorderRadius.circular(16)),
                                  child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
                                )
                              : GradientButton(
                                  label: _l.tr('imComing'),
                                  onPressed: _notifyImComing,
                                  icon: Icons.directions_walk_rounded,
                                ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _cancelQueue,
                        child: Text(
                          _l.tr('cancelQueue'),
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final String value;
  final String suffix;
  final String label;
  final bool highlight;

  const _StatCell({
    required this.icon,
    required this.value,
    required this.suffix,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primary.withValues(alpha: 0.06) : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: highlight ? Border.all(color: AppColors.primary.withValues(alpha: 0.2)) : null,
        boxShadow: [
          BoxShadow(color: AppColors.shadowPrimary, blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.onSurface),
                ),
                const WidgetSpan(child: SizedBox(width: 4)),
                TextSpan(
                  text: suffix,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
