import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/queue_service.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import 'salon_list_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<VisitHistory> _history = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await QueueService.instance.getHistory();
      if (mounted) setState(() { _history = data; _isLoading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Failed to load history'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Visit History', style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
                    const SizedBox(height: 4),
                    Text('Your past queue visits', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text(_error!, style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            else if (_history.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_rounded, size: 64, color: AppColors.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text('No visits yet', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Text('Join a queue to see your visit history here', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SalonListScreen()),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient135,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text('Find a Shop', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _HistoryCard(visit: _history[i]),
                    childCount: _history.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final VisitHistory visit;

  const _HistoryCard({required this.visit});

  Color get _statusColor {
    switch (visit.status) {
      case 'completed': return AppColors.tertiary;
      case 'skipped': return AppColors.error;
      case 'cancelled': return AppColors.onSurfaceVariant;
      default: return AppColors.primary;
    }
  }

  String get _statusLabel {
    switch (visit.status) {
      case 'completed': return 'Served';
      case 'skipped': return 'Skipped';
      case 'cancelled': return 'Cancelled';
      default: return visit.status;
    }
  }

  IconData get _statusIcon {
    switch (visit.status) {
      case 'completed': return Icons.check_circle_rounded;
      case 'skipped': return Icons.skip_next_rounded;
      case 'cancelled': return Icons.cancel_rounded;
      default: return Icons.schedule_rounded;
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.shadowPrimary, blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Category icon container
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient135,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _categoryEmoji(visit.shopCategory),
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(visit.shopName, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${visit.shopCity} · ${visit.shopCategory}', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon, size: 13, color: _statusColor),
                      const SizedBox(width: 4),
                      Text(_statusLabel, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Details row
            Row(
              children: [
                _DetailChip(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Token #${visit.tokenNumber.toString().padLeft(2, '0')}',
                ),
                const SizedBox(width: 8),
                _DetailChip(
                  icon: Icons.calendar_today_outlined,
                  label: _formatDate(visit.joinedAt),
                ),
                const SizedBox(width: 8),
                _DetailChip(
                  icon: Icons.access_time_rounded,
                  label: _formatTime(visit.joinedAt),
                ),
              ],
            ),

            if (visit.serviceName != null || visit.actualServiceMinutes != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (visit.serviceName != null) ...[
                    _DetailChip(icon: Icons.content_cut_rounded, label: visit.serviceName!),
                    const SizedBox(width: 8),
                  ],
                  if (visit.actualServiceMinutes != null)
                    _DetailChip(icon: Icons.timer_outlined, label: '${visit.actualServiceMinutes} min'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _categoryEmoji(String category) {
    const map = {
      'Salon': '✂️',
      'Barbershop': '💈',
      'Clinic': '🏥',
      'Hospital': '🏨',
      'Bank': '🏦',
      'Restaurant': '🍽️',
      'Spa': '💆',
      'Gym': '💪',
      'Pharmacy': '💊',
      'Laundry': '👕',
    };
    return map[category] ?? '🏪';
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
