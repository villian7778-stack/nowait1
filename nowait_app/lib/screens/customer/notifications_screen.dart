import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/notification_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  /// Set to false for the owner view — hides the Promotions tab.
  final bool showPromoTab;

  const NotificationsScreen({super.key, this.showPromoTab = true});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  final _l = LocaleService.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.showPromoTab ? 2 : 1,
      vsync: this,
    );
    _l.addListener(_onLocale);
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final res = await NotificationService.instance.getNotifications();
      final list = (res['notifications'] as List)
          .map((n) => NotificationModel.fromJson(n))
          .toList();
      if (mounted) setState(() { _notifications = list; _isLoading = false; });
      // Mark all as read in background
      NotificationService.instance.markAllRead().catchError((_) {});
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _l.removeListener(_onLocale);
    _tabController.dispose();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // Queue: everything that is strictly operational
    final _queueTypes = {
      NotificationType.yourTurn,
      NotificationType.almostThere,
      NotificationType.skipped,
      NotificationType.coming,
    };
    final queueNotifs = _notifications.where((n) => _queueTypes.contains(n.type)).toList();
    // Promotions: scheme offers + featured promotion notifications
    final promoNotifs = _notifications
        .where((n) => n.type == NotificationType.promotion || n.type == NotificationType.scheme)
        .toList();
    final unreadQueue = queueNotifs.where((n) => !n.isRead).length;
    final unreadPromo = promoNotifs.where((n) => !n.isRead).length;

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
        title: Text(_l.tr('notifications'), style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_l.tr('queueTab')),
                  if (unreadQueue > 0) ...[
                    const SizedBox(width: 6),
                    _UnreadBadge(count: unreadQueue),
                  ],
                ],
              ),
            ),
            if (widget.showPromoTab)
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_l.tr('promotionsTab')),
                    if (unreadPromo > 0) ...[
                      const SizedBox(width: 6),
                      _UnreadBadge(count: unreadPromo),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _QueueNotifTab(notifications: queueNotifs),
                if (widget.showPromoTab) _PromoNotifTab(notifications: promoNotifs),
              ],
            ),
    );
  }
}

class _QueueNotifTab extends StatelessWidget {
  final List<NotificationModel> notifications;

  const _QueueNotifTab({required this.notifications});

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;
    if (notifications.isEmpty) {
      return _emptyState(l.tr('noQueueNotif'), Icons.notifications_none_outlined);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(l.tr('liveStatus')),
        const SizedBox(height: 10),
        ...notifications
            .where((n) => !n.isRead)
            .map((n) => _NotifTile(notif: n)),
        if (notifications.any((n) => n.isRead)) ...[
          const SizedBox(height: 16),
          _sectionHeader(l.tr('recentActivity')),
          const SizedBox(height: 10),
          ...notifications
              .where((n) => n.isRead)
              .map((n) => _NotifTile(notif: n)),
        ],
      ],
    );
  }
}

class _PromoNotifTab extends StatelessWidget {
  final List<NotificationModel> notifications;

  const _PromoNotifTab({required this.notifications});

  @override
  Widget build(BuildContext context) {
    final l = LocaleService.instance;

    if (notifications.isEmpty) {
      return _emptyState(l.tr('noPromos'), Icons.local_offer_outlined);
    }

    final schemeNotifs = notifications.where((n) => n.type == NotificationType.scheme).toList();
    final promoNotifs  = notifications.where((n) => n.type == NotificationType.promotion).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (schemeNotifs.isNotEmpty) ...[
          _sectionHeader('SCHEME OFFERS'),
          const SizedBox(height: 10),
          ...schemeNotifs.map((n) => _NotifTile(notif: n)),
          const SizedBox(height: 16),
        ],
        if (promoNotifs.isNotEmpty) ...[
          _sectionHeader('FEATURED PROMOTIONS'),
          const SizedBox(height: 10),
          ...promoNotifs.map((n) => _NotifTile(notif: n)),
        ],
        if (schemeNotifs.isEmpty && promoNotifs.isNotEmpty)
          const SizedBox.shrink(),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient135,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

Widget _sectionHeader(String title) {
  return Text(
    title.toUpperCase(),
    style: GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: AppColors.onSurfaceVariant,
    ),
  );
}

Widget _emptyState(String message, IconData icon) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: AppColors.onSurfaceVariant.withValues(alpha: 0.3)),
        const SizedBox(height: 12),
        Text(message, style: GoogleFonts.inter(fontSize: 15, color: AppColors.onSurfaceVariant)),
      ],
    ),
  );
}

class _NotifTile extends StatelessWidget {
  final NotificationModel notif;

  const _NotifTile({required this.notif});

  (IconData, Color, Color) get _iconData {
    switch (notif.type) {
      case NotificationType.yourTurn:
        return (Icons.check_circle_outline_rounded, AppColors.tertiary, AppColors.tertiaryFixed.withValues(alpha: 0.3));
      case NotificationType.almostThere:
        return (Icons.notification_important_outlined, AppColors.primary, AppColors.primary.withValues(alpha: 0.1));
      case NotificationType.skipped:
        return (Icons.skip_next_rounded, AppColors.error, AppColors.errorContainer);
      case NotificationType.promotion:
        return (Icons.star_outline_rounded, AppColors.secondary, AppColors.secondary.withValues(alpha: 0.1));
      case NotificationType.scheme:
        return (Icons.local_offer_outlined, AppColors.primary, AppColors.primary.withValues(alpha: 0.1));
      case NotificationType.coming:
        return (Icons.directions_walk_rounded, AppColors.primary, AppColors.primary.withValues(alpha: 0.1));
    }
  }

  String _timeAgo() {
    final diff = DateTime.now().difference(notif.time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, bgColor) = _iconData;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: notif.isRead ? AppColors.surfaceContainerLow : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: notif.isRead
            ? []
            : [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notif.title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      _timeAgo(),
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notif.body,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!notif.isRead) ...[
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
