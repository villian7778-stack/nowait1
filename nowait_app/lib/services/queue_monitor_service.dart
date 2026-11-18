import 'package:flutter/material.dart';

/// Kept so main.dart / home_screen.dart can keep calling it, but it no longer polls.
///
/// It used to ask the server for the customer's queue status every 10 s from anywhere in the
/// app to show the rating sheet; that sheet moved to the queue status screen (commit 9692475),
/// after which the poll only stored results nobody read - a request every 10 s for nothing.
/// The queue status screen still polls while it is open, and push notifications cover the rest.
class QueueMonitorService {
  static final QueueMonitorService instance = QueueMonitorService._();
  QueueMonitorService._();

  GlobalKey<NavigatorState>? navigatorKey;

  void start() {}

  void stop() {}
}
