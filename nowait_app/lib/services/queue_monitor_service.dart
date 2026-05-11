import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/queue_service.dart';
import '../widgets/rating_review_sheet.dart';

/// Global background service that polls for queue status changes while the
/// customer is anywhere in the app. When any active entry transitions to
/// [QueueStatus.completed], it shows the rating sheet via the root navigator.
class QueueMonitorService {
  static final QueueMonitorService instance = QueueMonitorService._();
  QueueMonitorService._();

  /// Set this to MaterialApp's navigatorKey before calling [start].
  GlobalKey<NavigatorState>? navigatorKey;

  Timer? _timer;

  // Tracks the last known status for each entry so we can detect transitions.
  final Map<String, QueueStatus> _prevStatuses = {};

  // Guards against showing the sheet more than once per entry.
  final Set<String> _shownForEntries = {};

  /// Start polling. Safe to call multiple times — cancels any existing timer.
  void start() {
    _timer?.cancel();
    _poll(); // immediate first check
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  /// Stop polling and reset state. Call on logout or when owner logs in.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _prevStatuses.clear();
    _shownForEntries.clear();
  }

  Future<void> _poll() async {
    try {
      final entries = await QueueService.instance.getMyStatus();
      for (final entry in entries) {
        final prev = _prevStatuses[entry.entryId];
        _prevStatuses[entry.entryId] = entry.status;

        // Only show for COMPLETED (served by owner).
        // Skipped, cancelled, etc. never receive the rating popup.
        final wasServed = entry.status == QueueStatus.completed;
        final isNewTransition = prev != null && prev != QueueStatus.completed;
        final notYetShown = !_shownForEntries.contains(entry.entryId);

        if (wasServed && isNewTransition && notYetShown) {
          _shownForEntries.add(entry.entryId);
          _showSheet(entry);
        }
      }
    } catch (_) {}
  }

  void _showSheet(QueueEntry entry) {
    final key = navigatorKey;
    if (key == null) return;

    // Brief delay so any in-progress route animation finishes first.
    Future.delayed(const Duration(milliseconds: 600), () {
      final context = key.currentContext;
      if (context == null) return;

      showRatingReviewSheet(
        context,
        shopName: entry.shopName,
        shopId: entry.shopId,
        queueEntryId: entry.entryId,
      );
    });
  }
}
