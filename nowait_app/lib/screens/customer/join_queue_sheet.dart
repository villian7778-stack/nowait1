import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/queue_service.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import 'queue_status_screen.dart';

class JoinQueueSheet extends StatefulWidget {
  final ShopModel shop;

  const JoinQueueSheet({super.key, required this.shop});

  @override
  State<JoinQueueSheet> createState() => _JoinQueueSheetState();
}

class _JoinQueueSheetState extends State<JoinQueueSheet> {
  final Set<String> _selectedIds = {};
  bool _isJoining = false;
  final _l = LocaleService.instance;

  List<ServiceModel> get _services => widget.shop.services;
  bool get _hasServices => _services.isNotEmpty;
  bool get _canJoin => !_hasServices || _selectedIds.isNotEmpty;

  int get _totalDuration => _services
      .where((s) => _selectedIds.contains(s.id))
      .fold(0, (sum, s) => sum + s.durationMinutes);

  double get _totalPrice => _services
      .where((s) => _selectedIds.contains(s.id))
      .fold(0.0, (sum, s) => sum + s.price);

  int get _estimatedPosition => widget.shop.queueCount + 1;

  String get _positionOrdinal {
    final n = _estimatedPosition;
    if (n == 1) return '1st';
    if (n == 2) return '2nd';
    if (n == 3) return '3rd';
    return '${n}th';
  }

  int get _estimatedWait {
    if (_selectedIds.isEmpty) {
      return widget.shop.avgWaitMinutes + (widget.shop.queueCount * widget.shop.avgWaitMinutes);
    }
    return widget.shop.queueCount * _totalDuration;
  }

  Future<void> _confirmJoin() async {
    setState(() => _isJoining = true);
    try {
      final entry = await QueueService.instance.joinQueue(
        widget.shop.id,
        serviceIds: _selectedIds.toList(),
      );
      if (mounted) Navigator.pop(context, entry);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isJoining = false);
      if (e.statusCode == 409) {
        // Distinguish same-shop vs cross-shop 409
        if (e.message.contains('another shop')) {
          _showCrossShopDialog(e.message);
        } else {
          _showAlreadyInQueueDialog();
        }
      } else if (e.statusCode == 403) {
        _showBanDialog(e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  // Same-shop duplicate: offer to navigate to existing queue status
  Future<void> _showAlreadyInQueueDialog() async {
    final goToQueue = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Already in Queue',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'You are already in the queue at ${widget.shop.name}. Would you like to view your queue status?',
          style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Stay Here',
                style: GoogleFonts.inter(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('View Queue',
                style: GoogleFonts.inter(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (goToQueue == true && mounted) {
      try {
        final entries = await QueueService.instance
            .getMyStatus(shopId: widget.shop.id);
        final existing = entries.isNotEmpty ? entries.first : null;
        if (existing != null && mounted) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => QueueStatusScreen(entry: existing)),
          );
        }
      } catch (_) {
        if (mounted) Navigator.pop(context);
      }
    }
  }

  // Cross-shop duplicate: user is in a queue at a different shop
  void _showCrossShopDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Already in a Queue',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK',
                style: GoogleFonts.inter(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // 2-hour cancellation cooldown is active
  void _showBanDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.timer_off_outlined,
                  color: AppColors.error, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'Queue Join Restricted',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK',
                style: GoogleFonts.inter(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 40,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shop label + title
                  Text(
                    widget.shop.name,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hasServices ? 'Select Services' : _l.tr('joinQueue'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (_hasServices) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Choose one or more services to continue',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Service selection list
                  if (_hasServices) ...[
                    ..._services.map((service) => _ServiceTile(
                          service: service,
                          selected: _selectedIds.contains(service.id),
                          onTap: () => setState(() {
                            if (_selectedIds.contains(service.id)) {
                              _selectedIds.remove(service.id);
                            } else {
                              _selectedIds.add(service.id);
                            }
                          }),
                        )),
                    const SizedBox(height: 16),
                  ],

                  // Summary row
                  if (_selectedIds.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient135,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          _SummaryChip(
                            icon: Icons.currency_rupee_rounded,
                            label: '₹${_totalPrice.toStringAsFixed(0)}',
                            sublabel: 'Total price',
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${_selectedIds.length} service${_selectedIds.length == 1 ? '' : 's'}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'selected',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Position + wait info
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCell(
                          icon: Icons.people_outline_rounded,
                          value: _positionOrdinal,
                          label: 'in line',
                          gradient: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoCell(
                          icon: Icons.schedule_rounded,
                          value: '~$_estimatedWait min',
                          label: _l.tr('estimatedWait'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Live updates banner
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
                          child: const Icon(
                            Icons.notifications_active_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _l.tr('liveUpdatesEnabled'),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              Text(
                                _l.tr('liveUpdatesSubtitle'),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.tertiary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Action buttons pinned at bottom
          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: _isJoining
                      ? Container(
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient135,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        )
                      : Opacity(
                          opacity: _canJoin ? 1.0 : 0.45,
                          child: GradientButton(
                            label: _hasServices && _selectedIds.isEmpty
                                ? 'Select a Service to Continue'
                                : _l.tr('confirmJoin'),
                            onPressed: _canJoin ? () => _confirmJoin() : () {},
                            icon: Icons.check_rounded,
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _isJoining ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      _l.tr('cancel'),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final ServiceModel service;
  final bool selected;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.outline.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowPrimary,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Check circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selected ? AppColors.primaryGradient135 : null,
                color: selected ? null : Colors.transparent,
                border: selected
                    ? null
                    : Border.all(color: AppColors.outline.withValues(alpha: 0.4)),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 12),
            // Name + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (service.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      service.description,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Duration + price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${service.price.toStringAsFixed(0)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.primary : AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${service.durationMinutes} min',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;

  const _SummaryChip({required this.icon, required this.label, required this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 14),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              sublabel,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool gradient;

  const _InfoCell({
    required this.icon,
    required this.value,
    required this.label,
    this.gradient = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient ? AppColors.primaryGradient135 : null,
        color: gradient ? null : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowPrimary,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: gradient ? Colors.white : AppColors.primary, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: gradient ? Colors.white : AppColors.onSurface,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: gradient ? Colors.white70 : AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
