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
import 'shop_details_screen.dart';

class QueueStatusScreen extends StatefulWidget {
  final QueueEntry entry;

  const QueueStatusScreen({super.key, required this.entry});

  @override
  State<QueueStatusScreen> createState() => _QueueStatusScreenState();
}

class _QueueStatusScreenState extends State<QueueStatusScreen>
    with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  late QueueEntry _entry;
  Timer? _pollTimer;
  bool _isCancelling = false;
  bool _isComing = false;
  bool _comingNotified = false;
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _l.addListener(_onLocale);

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Poll every 10 seconds for live updates; cancel any stale timer first
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _spinController.dispose();
    _pulseController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  Future<void> _refresh() async {
    try {
      final entries =
          await QueueService.instance.getMyStatus(shopId: _entry.shopId);
      final updated = entries.where((e) => e.entryId == _entry.entryId).firstOrNull;
      if (updated != null && mounted) {
        setState(() => _entry = updated);
        // If done, pop back
        if (updated.status == QueueStatus.completed ||
            updated.status == QueueStatus.skipped ||
            updated.status == QueueStatus.cancelled) {
          _pollTimer?.cancel();
        }
      }
    } catch (_) {}
  }

  void _cancelQueue() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_l.tr('leaveQueue'),
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text(
          _l.tr('loseSpot', params: {'shop': _entry.shopName}),
          style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_l.tr('stay'),
                style: GoogleFonts.inter(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isCancelling = true);
              try {
                await QueueService.instance.cancelQueue(_entry.entryId);
                if (mounted) {
                  _pollTimer?.cancel();
                  // Show snackbar on the screen below before popping
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Queue cancelled successfully'),
                      backgroundColor: AppColors.tertiary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              } on ApiException catch (e) {
                if (mounted) {
                  setState(() => _isCancelling = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
                }
              } catch (_) {
                if (mounted) setState(() => _isCancelling = false);
              }
            },
            child: Text(_l.tr('leave'),
                style: GoogleFonts.inter(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _notifyComing() async {
    setState(() => _isComing = true);
    try {
      await QueueService.instance.notifyComing(_entry.entryId);
      if (mounted) {
        setState(() {
          _isComing = false;
          _comingNotified = true;
        });
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

  String get _displayStatusLabel {
    switch (_entry.status) {
      case QueueStatus.yourTurn:
        return _l.tr('itsYourTurn');
      case QueueStatus.almostThere:
        return _l.tr('almostThere');
      default:
        return _l.tr('aheadCount', params: {'n': '${_entry.peopleAhead}'});
    }
  }

  String get _statusBadgeText {
    switch (_entry.status) {
      case QueueStatus.yourTurn:
        return _l.tr('yourTurnBadge');
      case QueueStatus.almostThere:
        return _l.tr('top3');
      default:
        return _l.tr('waiting');
    }
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            title: Text(_l.tr('queueStatus'),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.tertiary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const PingDot(),
                    const SizedBox(width: 5),
                    Text(_l.tr('live'),
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.tertiary)),
                  ],
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              child: Column(
                children: [
                  // Shop header card
                  GestureDetector(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ShopDetailsScreen(
                                shopId: _entry.shopId))),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.shadowPrimary,
                              blurRadius: 12,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient135,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.storefront_rounded,
                                color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_entry.shopName,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.onSurface)),
                                Text(_l.tr('tapViewDetails'),
                                    style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: AppColors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Token display
                  _buildTokenDisplay(),
                  const SizedBox(height: 20),

                  // Stats bento
                  Row(
                    children: [
                      Expanded(
                          child: _StatCell(
                        icon: Icons.people_outline_rounded,
                        value: '${_entry.peopleAhead}',
                        suffix: _entry.peopleAhead == 1 ? _l.tr('guest') : _l.tr('guests'),
                        label: _l.tr('peopleAhead'),
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _StatCell(
                        icon: Icons.schedule_rounded,
                        value: '~${_entry.estimatedWaitMinutes}',
                        suffix: _l.tr('mins'),
                        label: _l.tr('estWaitTime'),
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Now serving
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.tertiaryFixed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.tertiary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.tertiary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.how_to_reg_outlined,
                              color: AppColors.tertiary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_l.tr('nowServing'),
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.tertiary)),
                            Text(
                              _entry.nowServingToken > 0
                                  ? 'Token #${_entry.nowServingToken.toString().padLeft(2, '0')}'
                                  : _l.tr('noneYet'),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          _displayStatusLabel,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _entry.status == QueueStatus.yourTurn
                                ? AppColors.tertiary
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

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
                                onPressed: _notifyComing,
                                icon: Icons.directions_walk_rounded,
                              ),
                  ),
                  const SizedBox(height: 10),
                  _isCancelling
                      ? const Center(child: CircularProgressIndicator())
                      : TextButton(
                          onPressed: _cancelQueue,
                          child: Text(
                            _l.tr('cancelQueue'),
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.error),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenDisplay() {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _spinController,
              builder: (context, child) => Transform.rotate(
                angle: _spinController.value * 2 * pi,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                        BorderSide(color: Colors.transparent, width: 0)),
                  ),
                  child: CustomPaint(painter: DashedCirclePainter()),
                ),
              ),
            ),
            ScaleTransition(
              scale: _pulseAnim,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient135,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _l.tr('yourToken'),
                      style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _entry.token,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: -2,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.tertiaryFixed.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusBadgeText,
                      style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.tertiary,
                          letterSpacing: 0.8),
                    ),
                  ),
                ],
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

  const _StatCell(
      {required this.icon,
      required this.value,
      required this.suffix,
      required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadowPrimary,
              blurRadius: 12,
              offset: const Offset(0, 3))
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
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface),
                ),
                const WidgetSpan(child: SizedBox(width: 3)),
                TextSpan(
                  text: suffix,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

