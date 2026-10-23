import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lightweight vector scene; rain and the umbrella move with the weather ticker.
class RaincoatWeatherPainter extends CustomPainter {
  final double phase;
  const RaincoatWeatherPainter(this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 90);
    final paint = Paint()..isAntiAlias = true;
    void line(Offset a, Offset b, Color color, double width) {
      paint
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(a, b, paint);
    }

    paint.color = const Color(0xff263d55);
    canvas.drawOval(const Rect.fromLTWH(22, 80, 63, 6), paint);
    for (var i = 0; i < 16; i++) {
      final x = (i * 23.0) % 100;
      final y = (i * 17 + phase / (2 * math.pi) * 240) % 90;
      line(
        Offset(x, y),
        Offset(x - 2, y + 5),
        const Color(0xff7ecaff).withValues(alpha: .65),
        1.3,
      );
    }
    canvas.save();
    canvas.translate(math.sin(phase) * 1.5, math.sin(phase) * .6);
    line(
      const Offset(44, 67),
      Offset(42 + math.sin(phase * 2), 80),
      const Color(0xff28384b),
      5,
    );
    line(
      const Offset(56, 67),
      Offset(58 - math.sin(phase * 2), 80),
      const Color(0xff28384b),
      5,
    );
    line(
      const Offset(39, 81),
      const Offset(45, 81),
      const Color(0xffef855d),
      5,
    );
    line(
      const Offset(56, 81),
      const Offset(62, 81),
      const Color(0xffef855d),
      5,
    );
    paint.color = const Color(0xffffcc52);
    final coat = Path()
      ..moveTo(41, 43)
      ..quadraticBezierTo(50, 39, 59, 43)
      ..lineTo(65, 70)
      ..quadraticBezierTo(50, 75, 35, 70)
      ..close();
    canvas.drawPath(coat, paint);
    line(
      const Offset(50, 48),
      const Offset(50, 70),
      const Color(0xffd79a26),
      1.2,
    );
    paint.color = const Color(0xffffcf52);
    canvas.drawOval(const Rect.fromLTWH(38, 27, 24, 27), paint);
    paint.color = const Color(0xffeeb48b);
    canvas.drawOval(const Rect.fromLTWH(44, 32, 15, 18), paint);
    paint.color = const Color(0xff243547);
    canvas.drawCircle(const Offset(54, 39), 1, paint);
    line(
      const Offset(57, 48),
      const Offset(69, 52),
      const Color(0xffffcc52),
      7,
    );
    line(
      const Offset(69, 52),
      const Offset(69, 45),
      const Color(0xffeeb48b),
      4,
    );
    line(
      const Offset(69, 17),
      const Offset(69, 54),
      const Color(0xffd8e4ed),
      1.8,
    );
    paint.color = const Color(0xff63b6db);
    final umbrella = Path()
      ..moveTo(38, 25)
      ..quadraticBezierTo(67, -9, 94, 25)
      ..quadraticBezierTo(87, 19, 80, 25)
      ..quadraticBezierTo(73, 19, 66, 25)
      ..quadraticBezierTo(59, 19, 52, 25)
      ..quadraticBezierTo(45, 19, 38, 25)
      ..close();
    canvas.drawPath(umbrella, paint);
    line(const Offset(67, 8), const Offset(67, 25), const Color(0xffabd9ec), 1);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RaincoatWeatherPainter oldDelegate) =>
      phase != oldDelegate.phase;
}
