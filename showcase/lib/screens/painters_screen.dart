import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Custom painting and transforms: a prize wheel drawn by a painter (arcs
/// with gradients, labels drawn rotated, a stroked rim, a path pointer with
/// a shadow, a blurred glow), turned by `Transform.rotate`, over a sweep
/// gradient, with a frosted-glass panel.
class PaintersScreen extends StatelessWidget {
  const PaintersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Painters')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: SweepGradient(
            colors: [Color(0xFFFFE0B2), Color(0xFFB3E5FC), Color(0xFFFFE0B2)],
            transform: GradientRotation(pi / 4),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 45,
              top: 40,
              child: Transform.rotate(
                angle: -pi / 5,
                child: const SizedBox(
                  width: 300,
                  height: 300,
                  child: CustomPaint(
                    painter: WheelPainter(['Red', 'Green', 'Blue', 'Gold']),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 40,
              height: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.3),
                    alignment: Alignment.center,
                    child: const Text('Frosted glass'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WheelPainter extends CustomPainter {
  const WheelPainter(this.labels);

  final List<String> labels;

  static const _colors = [
    Color(0xFFE57373),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFFFFD54F),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * pi / labels.length;

    // A soft glow behind the wheel: only pixels show a blur.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    for (var i = 0; i < labels.length; i++) {
      final start = -pi / 2 + i * sweep;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..shader = RadialGradient(
            colors: [_colors[i], _colors[i].withValues(alpha: 0.7)],
          ).createShader(rect),
      );
      final label = TextPainter(
        text: TextSpan(
          text: labels[i],
          // Text a painter draws has no theme: it names its font.
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final angle = start + sweep / 2;
      canvas
        ..save()
        ..translate(
          center.dx + radius * 0.6 * cos(angle),
          center.dy + radius * 0.6 * sin(angle),
        )
        ..rotate(angle + pi / 2)
        ..translate(-label.width / 2, -label.height / 2);
      label.paint(canvas, Offset.zero);
      canvas.restore();
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white,
    );
    final pointer = Path()
      ..moveTo(center.dx - 12, 0)
      ..lineTo(center.dx + 12, 0)
      ..lineTo(center.dx, 24)
      ..close();
    canvas
      ..drawShadow(pointer, Colors.black, 4, false)
      ..drawPath(pointer, Paint()..color = const Color(0xFF424242));
  }

  @override
  bool shouldRepaint(WheelPainter oldDelegate) => oldDelegate.labels != labels;
}
