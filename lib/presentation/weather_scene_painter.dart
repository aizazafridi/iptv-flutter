import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'raincoat_weather_painter.dart';

/// Matching illustrated scenes share one ticker and remain static with reduced motion.
class WeatherScenePainter extends CustomPainter {
  final int code;
  final double phase;
  const WeatherScenePainter(this.code, this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    if (code >= 95) {
      RaincoatWeatherPainter(phase).paint(canvas, size);
      canvas.save();
      canvas.scale(size.width / 100, size.height / 90);
      final flash = (math.sin(phase * 2) > .7) ? 1.0 : .25;
      canvas.drawPath(
        Path()
          ..moveTo(22, 9)
          ..lineTo(12, 28)
          ..lineTo(21, 26)
          ..lineTo(16, 42)
          ..lineTo(33, 20)
          ..lineTo(23, 22)
          ..close(),
        Paint()..color = const Color(0xffffe18a).withValues(alpha: flash),
      );
      canvas.restore();
      return;
    }
    canvas.save();
    canvas.scale(size.width / 100, size.height / 90);
    final snow = code >= 71 && code <= 77 || code == 85 || code == 86;
    final fog = code == 45 || code == 48;
    final sunny = code <= 1;
    final partly = code == 2;
    final paint = Paint()..isAntiAlias = true;
    void line(Offset a, Offset b, Color color, double width) {
      paint
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(a, b, paint);
    }

    void cloud(double x, double y, Color color) {
      paint.color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y + 8, 43, 13),
          const Radius.circular(7),
        ),
        paint,
      );
      canvas.drawCircle(Offset(x + 14, y + 8), 10, paint);
      canvas.drawCircle(Offset(x + 28, y + 6), 12, paint);
    }

    if (sunny || partly) {
      canvas.save();
      canvas.translate(25, 22);
      canvas.rotate(phase * .2);
      paint.color = const Color(0xffffcb5a);
      canvas.drawCircle(Offset.zero, 11 + math.sin(phase) * .6, paint);
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        line(
          Offset(math.cos(angle) * 15, math.sin(angle) * 15),
          Offset(math.cos(angle) * 19, math.sin(angle) * 19),
          const Color(0xfff7b950),
          2,
        );
      }
      canvas.restore();
    }
    if (!sunny && !fog) {
      cloud(44 + math.sin(phase) * 5, 8, const Color(0xffb2c7da));
    }
    if (code == 3) cloud(6 + math.cos(phase) * 4, 20, const Color(0xff7796b0));
    if (snow) {
      for (var i = 0; i < 10; i++) {
        final x = (i * 29.0 + math.sin(phase + i) * 4) % 100;
        final y = (i * 19 + phase / (math.pi * 2) * 90) % 90;
        line(Offset(x - 2, y), Offset(x + 2, y), Colors.white70, 1);
        line(Offset(x, y - 2), Offset(x, y + 2), Colors.white70, 1);
      }
    }
    paint.color = snow ? const Color(0xff91afc5) : const Color(0xff263d55);
    canvas.drawOval(const Rect.fromLTWH(21, 81, 63, 5), paint);
    canvas.save();
    canvas.translate(math.sin(phase) * 1.5, 0);
    line(
      const Offset(45, 65),
      Offset(42 + math.sin(phase * 2) * 2, 79),
      const Color(0xff273f57),
      5,
    );
    line(
      const Offset(55, 65),
      Offset(58 - math.sin(phase * 2) * 2, 79),
      const Color(0xff273f57),
      5,
    );
    line(
      const Offset(38, 80),
      const Offset(45, 80),
      const Color(0xffe8af65),
      4,
    );
    line(
      const Offset(56, 80),
      const Offset(62, 80),
      const Color(0xffe8af65),
      4,
    );
    final coat = snow ? const Color(0xffd86a6a) : const Color(0xffe9b854);
    paint.color = coat;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(39, 44, 22, 26),
        const Radius.circular(6),
      ),
      paint,
    );
    line(const Offset(41, 49), Offset(33, 61 + math.sin(phase) * 2), coat, 6);
    line(const Offset(59, 49), Offset(67, 59 - math.sin(phase) * 2), coat, 6);
    paint.color = const Color(0xffefb791);
    canvas.drawCircle(const Offset(50, 35), 10, paint);
    paint.color = const Color(0xff4a3c35);
    canvas.drawArc(
      const Rect.fromLTWH(40, 24, 20, 19),
      math.pi,
      math.pi,
      true,
      paint,
    );
    paint.color = const Color(0xff263543);
    canvas.drawCircle(const Offset(54, 35), .9, paint);
    if (sunny) {
      line(
        const Offset(44, 34),
        const Offset(56, 34),
        const Color(0xff263543),
        3,
      );
    }
    if (snow || fog) {
      line(
        const Offset(41, 28),
        const Offset(59, 28),
        const Color(0xff72bac8),
        5,
      );
      paint.color = const Color(0xff72bac8);
      canvas.drawCircle(const Offset(50, 23), 6, paint);
      line(
        const Offset(41, 45),
        const Offset(59, 45),
        const Color(0xff72bac8),
        4,
      );
      line(
        const Offset(57, 45),
        Offset(64 + math.sin(phase) * 2, 54),
        const Color(0xff72bac8),
        4,
      );
    }
    canvas.restore();
    if (fog) {
      for (var i = 0; i < 4; i++) {
        final x = 5 + math.sin(phase + i) * 6;
        line(
          Offset(x, 17 + i * 17.0),
          Offset(x + 78, 17 + i * 17.0),
          const Color(0xffc4d3dc).withValues(alpha: .35),
          4,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WeatherScenePainter oldDelegate) =>
      phase != oldDelegate.phase || code != oldDelegate.code;
}
