import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Stops double taps on the app's main buttons: while an async onPressed is still running, further
/// taps are ignored, so a slow network can't send "Pay", "Join queue" or "Create shop" twice. (A
/// callback that opens a dialog or a new screen needs nothing extra: the new route covers the
/// button before a second tap can land.)
class _TapGuard {
  bool busy = false;

  /// Runs [action] unless the previous one is still in progress; [onBusy] is told when that changes.
  Future<void> run(FutureOr<void> Function() action, void Function(bool busy) onBusy) async {
    if (busy) return;
    final result = action();
    if (result is Future) {
      busy = true;
      onBusy(true);
      try {
        await result;
      } finally {
        busy = false;
        onBusy(false);
      }
    }
  }
}

class GradientButton extends StatefulWidget {
  final String label;
  final FutureOr<void> Function() onPressed;
  final IconData? icon;
  final double height;
  final double borderRadius;
  final EdgeInsets? padding;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.borderRadius = 24,
    this.padding,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;
  final _guard = _TapGuard();

  void _onBusy(bool busy) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final busy = _guard.busy;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        _guard.run(widget.onPressed, _onBusy);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed && !busy ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedOpacity(
          opacity: busy ? 0.7 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: widget.height,
            padding: widget.padding,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient135,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowPrimary,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                ] else if (widget.icon != null) ...[
                  Icon(widget.icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatefulWidget {
  final String label;
  final FutureOr<void> Function() onPressed;
  final IconData? icon;
  final double height;

  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
  });

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  final _guard = _TapGuard();

  void _onBusy(bool busy) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final busy = _guard.busy;
    return SizedBox(
      height: widget.height,
      child: TextButton(
        onPressed: () => _guard.run(widget.onPressed, _onBusy),
        style: TextButton.styleFrom(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          minimumSize: const Size(double.infinity, 52),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
            ] else if (widget.icon != null) ...[
              Icon(widget.icon, size: 20),
              const SizedBox(width: 8),
            ],
            Text(
              widget.label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
