import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final String shopCategory;

  const QueueStatusScreen({super.key, required this.entry, this.shopCategory = ''});

  @override
  State<QueueStatusScreen> createState() => _QueueStatusScreenState();
}

class _QueueStatusScreenState extends State<QueueStatusScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _spinController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  late QueueEntry _entry;
  late String _shopCategory;
  List<PublicQueueItem> _queueList = [];
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _countdownSeconds = 0;   // remaining seconds for the currently-serving customer
  int? _lastServingToken;       // detect when serving changes
  bool _isCancelling = false;
  bool _isComing = false;
  bool _comingNotified = false;
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _shopCategory = widget.shopCategory;
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

    WidgetsBinding.instance.addObserver(this);
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    _refreshPublicQueue();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _l.removeListener(_onLocale);
    _spinController.dispose();
    _pulseController.dispose();
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  Future<void> _refresh() async {
    await Future.wait([
      _refreshMyStatus(),
      _refreshPublicQueue(),
    ]);
  }

  Future<void> _refreshMyStatus() async {
    try {
      final entries =
          await QueueService.instance.getMyStatus(shopId: _entry.shopId);
      final updated =
          entries.where((e) => e.entryId == _entry.entryId).firstOrNull;
      if (updated != null && mounted) {
        setState(() => _entry = updated);
        if (updated.status == QueueStatus.completed ||
            updated.status == QueueStatus.skipped ||
            updated.status == QueueStatus.cancelled) {
          _pollTimer?.cancel();
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshPublicQueue() async {
    try {
      final data =
          await QueueService.instance.getPublicShopQueue(_entry.shopId);
      final items = (data['queue'] as List? ?? [])
          .map((e) => PublicQueueItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() => _queueList = items);
      await _updateCountdown(items);
    } catch (_) {}
  }

  Future<void> _updateCountdown(List<PublicQueueItem> items) async {
    final serving = items.where((i) => i.status == 'serving').firstOrNull;
    if (serving == null) {
      _countdownTimer?.cancel();
      if (mounted) setState(() { _countdownSeconds = 0; _lastServingToken = null; });
      _clearCountdownStorage();
      return;
    }
    if (serving.tokenNumber != _lastServingToken) {
      _lastServingToken = serving.tokenNumber;
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getInt('cntdwn_token_${_entry.shopId}');
      final startMs = prefs.getInt('cntdwn_start_${_entry.shopId}');
      final durSecs = prefs.getInt('cntdwn_dur_${_entry.shopId}');
      int initialSecs;
      if (savedToken == serving.tokenNumber && startMs != null && durSecs != null) {
        // App was backgrounded/killed — compute remaining from wall-clock elapsed
        final elapsed = (DateTime.now().millisecondsSinceEpoch - startMs) ~/ 1000;
        initialSecs = (durSecs - elapsed).clamp(0, durSecs);
      } else {
        // Truly new serving token
        initialSecs = serving.totalDurationMinutes * 60;
        _saveCountdownToStorage(serving.tokenNumber, initialSecs);
      }
      _startCountdown(initialSecs);
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    if (!mounted) return;
    setState(() => _countdownSeconds = seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() { if (_countdownSeconds > 0) _countdownSeconds--; });
    });
  }

  void _saveCountdownToStorage(int token, int durationSecs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cntdwn_token_${_entry.shopId}', token);
    await prefs.setInt('cntdwn_start_${_entry.shopId}', DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt('cntdwn_dur_${_entry.shopId}', durationSecs);
  }

  void _clearCountdownStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cntdwn_token_${_entry.shopId}');
    await prefs.remove('cntdwn_start_${_entry.shopId}');
    await prefs.remove('cntdwn_dur_${_entry.shopId}');
  }

  /// Remaining wait seconds for a given queue item, based on live countdown.
  /// Serving item → _countdownSeconds.
  /// Waiting item → _countdownSeconds + sum of durations of all waiting items ahead.
  int _waitSecondsFor(PublicQueueItem item) {
    if (item.status == 'serving') return _countdownSeconds;
    final waitingAhead = _queueList
        .where((i) => i.status == 'waiting' && i.tokenNumber < item.tokenNumber)
        .fold(0, (sum, i) => sum + i.totalDurationMinutes * 60);
    return _countdownSeconds + waitingAhead;
  }

  void _cancelQueue() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_l.tr('leaveQueue'),
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _l.tr('loseSpot', params: {'shop': _entry.shopName}),
              style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'After cancelling, you will not be able to join any queue at any shop for 2 hours.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Queue cancelled. You cannot join any queue for 2 hours.'),
                      backgroundColor: AppColors.onSurfaceVariant,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              } on ApiException catch (e) {
                if (mounted) {
                  setState(() => _isCancelling = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(e.message),
                          backgroundColor: AppColors.error));
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

  // Live estimated wait for the current user in minutes.
  // Uses the countdown-based seconds when the serving countdown is active,
  // otherwise sums durations from the queue list, falls back to server value.
  int get _actualEstimatedWait {
    if (_queueList.isEmpty) return _entry.estimatedWaitMinutes;
    final myItem = _queueList
        .where((item) => item.tokenNumber ==
            (int.tryParse(_entry.token.replaceAll('#', '')) ?? -1))
        .firstOrNull;
    if (myItem == null) return _entry.estimatedWaitMinutes;
    final seconds = _waitSecondsFor(myItem);
    if (seconds > 0) return (seconds / 60).ceil();
    // Fallback: sum static durations
    final myTokenNum = int.tryParse(_entry.token.replaceAll('#', '')) ?? -1;
    return _queueList
        .where((item) => item.tokenNumber < myTokenNum)
        .fold(0, (sum, item) => sum + item.totalDurationMinutes);
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
              icon:
                  const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
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

                  // Selected services card
                  if (_entry.selectedServiceNames.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.shadowPrimary,
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.content_cut_rounded,
                                  size: 14, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                'Your Services',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              if (_entry.totalServiceCost != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.tertiary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '₹${_entry.totalServiceCost!.toStringAsFixed(0)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.tertiary,
                                    ),
                                  ),
                                )
                              else if (_entry.totalDurationMinutes != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${_entry.totalDurationMinutes} min',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _entry.selectedServiceNames
                                .map((name) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.2)),
                                      ),
                                      child: Text(
                                        name,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Stats bento
                  Row(
                    children: [
                      Expanded(
                          child: _StatCell(
                        icon: Icons.people_outline_rounded,
                        value: '${_entry.peopleAhead}',
                        suffix: _entry.peopleAhead == 1
                            ? _l.tr('guest')
                            : _l.tr('guests'),
                        label: _l.tr('peopleAhead'),
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _StatCell(
                        icon: Icons.schedule_rounded,
                        value: '~$_actualEstimatedWait',
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
                      color:
                          AppColors.tertiaryFixed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color:
                              AppColors.tertiary.withValues(alpha: 0.2)),
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

                  // ── Queue List ──────────────────────────────────────────
                  if (_queueList.isNotEmpty) ...[
                    _buildQueueList(),
                    const SizedBox(height: 20),
                  ],

                  // Coming / cancel buttons
                  SizedBox(
                    width: double.infinity,
                    child: _comingNotified
                        ? Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.tertiary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: AppColors.tertiary, size: 18),
                                  const SizedBox(width: 8),
                                  Text('Shop notified — on your way!',
                                      style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.tertiary)),
                                ],
                              ),
                            ),
                          )
                        : _isComing
                            ? Container(
                                height: 52,
                                decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient135,
                                    borderRadius:
                                        BorderRadius.circular(16)),
                                child: const Center(
                                    child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2))),
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

  Widget _buildQueueList() {
    final myTokenNum = int.tryParse(_entry.token.replaceAll('#', '')) ?? -1;
    // Show only people ahead of the user (token <= mine) — this includes serving and the user's own row
    final visible = _queueList
        .where((item) => item.tokenNumber <= myTokenNum)
        .toList();
    final totalInLine = _queueList.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Queue',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
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
                '$totalInLine in line',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const Spacer(),
            const PingDot(),
            const SizedBox(width: 4),
            Text(
              'Live',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.tertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: (visible.length * 72.0).clamp(72.0, 280.0),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                for (int i = 0; i < visible.length; i++) ...[
                  _QueueListRow(
                    item: visible[i],
                    isMe: visible[i].tokenNumber == myTokenNum,
                    isServing: visible[i].status == 'serving',
                    position: visible[i].position > 0 ? visible[i].position : i + 1,
                    waitSeconds: _waitSecondsFor(visible[i]),
                    shopCategory: _shopCategory,
                  ),
                  // Extra breathing room after the user's own row
                  if (visible[i].tokenNumber == myTokenNum)
                    const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
      ],
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
                      'QUEUE POSITION',
                      style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_entry.position}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          AppColors.tertiaryFixed.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Token ${_entry.token}',
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

// ── Queue list row ────────────────────────────────────────────────────────────

class _QueueListRow extends StatelessWidget {
  final PublicQueueItem item;
  final bool isMe;
  final bool isServing;
  final int position;
  final int waitSeconds; // live countdown in seconds
  final String shopCategory;

  const _QueueListRow({
    required this.item,
    required this.isMe,
    required this.isServing,
    required this.position,
    required this.waitSeconds,
    this.shopCategory = '',
  });

  static String _ordinal(int n) {
    if (n == 1) return '1st';
    if (n == 2) return '2nd';
    if (n == 3) return '3rd';
    return '${n}th';
  }

  static String _formatCountdown(int seconds) {
    if (seconds <= 0) return '0m';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    if (s == 0) return '${m}m';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  /// Category icon takes priority; falls back to service-name heuristic.
  @override
  Widget build(BuildContext context) {
    final Color accentColor;
    final Color bgColor;
    final Color borderColor;

    if (isServing) {
      accentColor = AppColors.tertiary;
      bgColor = AppColors.tertiary.withValues(alpha: 0.14);
      borderColor = AppColors.tertiary.withValues(alpha: 0.4);
    } else if (isMe) {
      accentColor = AppColors.error;
      bgColor = AppColors.error.withValues(alpha: 0.12);
      borderColor = AppColors.error.withValues(alpha: 0.45);
    } else {
      accentColor = AppColors.primary;
      bgColor = AppColors.primary.withValues(alpha: 0.06);
      borderColor = AppColors.primary.withValues(alpha: 0.18);
    }

    final hasCountdown = waitSeconds > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isMe ? 1.5 : 1),
        boxShadow: isMe || isServing
            ? [BoxShadow(color: accentColor.withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 2))]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            // ── Left: token + position ──
            Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '#${item.tokenNumber}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _ordinal(position),
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: accentColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // ── Middle: service icon + name + status ──
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text('👤', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.serviceNames.isEmpty
                              ? 'No service'
                              : item.serviceNames.length == 1
                                  ? item.serviceNames[0]
                                  : '${item.serviceNames.length} services selected',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isServing
                                    ? '● Now Serving'
                                    : isMe
                                        ? '● You'
                                        : '● Waiting',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── Right: live countdown ──
            if (hasCountdown)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: isServing ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _formatCountdown(waitSeconds),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isServing ? 'remaining' : 'wait',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            else if (item.totalDurationMinutes > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.outline.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${item.totalDurationMinutes}m',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
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
