import 'dart:async';
import 'package:flutter/material.dart';

/// Slowly scrolls a horizontal row of cards on its own: one card every [interval], back to the
/// start after the last one. Wrap the row's scrollable and give both the same [controller].
///
/// It stays still while the person touches or drags the row (and for [resumeAfter] afterwards),
/// when everything already fits, when another screen covers this one, and when the phone asks for
/// reduced motion.
class AutoScroll extends StatefulWidget {
  final ScrollController controller;
  /// Distance of one move: card width + the gap between cards.
  final double step;
  final Duration interval;
  final Duration resumeAfter;
  final Widget child;

  const AutoScroll({
    super.key,
    required this.controller,
    required this.step,
    required this.child,
    this.interval = const Duration(seconds: 3),
    this.resumeAfter = const Duration(seconds: 6),
  });

  @override
  State<AutoScroll> createState() => _AutoScrollState();
}

class _AutoScrollState extends State<AutoScroll> {
  Timer? _timer;
  DateTime _pausedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pause() => _pausedUntil = DateTime.now().add(widget.resumeAfter);

  void _tick() {
    if (!mounted || DateTime.now().isBefore(_pausedUntil)) return;
    final c = widget.controller;
    if (!c.hasClients || c.positions.length != 1) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    if (!TickerMode.of(context)) return; // e.g. a hidden tab
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return; // another screen is on top
    final pos = c.position;
    if (pos.maxScrollExtent <= 0 || pos.isScrollingNotifier.value || widget.step <= 0) return;

    final atEnd = pos.pixels >= pos.maxScrollExtent - 1;
    final target = atEnd
        ? 0.0
        // Snap to the next card so a card never stops half-cut at the left edge.
        : (((pos.pixels + widget.step) / widget.step).round() * widget.step).clamp(0.0, pos.maxScrollExtent);
    // Quick, crisp move (about half a second per card); the way back to the first card takes a
    // little longer the further it is, so it glides instead of jumping.
    final distance = (target - pos.pixels).abs();
    final ms = (distance / widget.step * 550).clamp(500.0, 1100.0).round();
    c.animateTo(target, duration: Duration(milliseconds: ms), curve: Curves.easeInOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _pause(),
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (n) {
          if (n.dragDetails != null) _pause(); // the person is scrolling it
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
