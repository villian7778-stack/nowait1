import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Rotating dashed circle decoration painted around the queue token number.
class DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.3)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 2;
    const dashCount = 20;
    const dashLength = 0.12;
    const gapLength = 0.2;
    const total = dashLength + gapLength;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * total * pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashLength * pi,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
