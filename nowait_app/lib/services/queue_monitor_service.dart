import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/queue_service.dart';

/// Global background service that polls for queue status changes while the
/// customer is anywhere in the app. When any active entry transitions to
/// [QueueStatus.completed], it shows the rating sheet via the root navigator.
class QueueMonitorService {
  static final QueueMonitorService instance = QueueMonitorService._();
  QueueMonitorService._();

  /// Set this to MaterialApp's navigatorKey before calling [start].
  GlobalKey<NavigatorState>? navigatorKey;

  Timer? _timer;

  // Tracks the last known status for each entry.
  final Map<String, QueueStatus> _prevStatuses = {};

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
  }

  Future<void> _poll() async {
    try {
      final entries = await QueueService.instance.getMyStatus();
      for (final entry in entries) {
        _prevStatuses[entry.entryId] = entry.status;
      }
    } catch (_) {}
  }
}
