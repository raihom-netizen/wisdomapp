import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Marcador de dia no calendário: quadrado/retângulo colorido para destacar plantão ou compromisso.
/// 1 frente = quadrado cheio; 2 = meio a meio; 3 = pizza.
class CalendarDayMarker extends StatelessWidget {
  final List<Color> colors;

  const CalendarDayMarker({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) return const SizedBox.shrink();
    if (colors.length == 1) {
      final v = AppColors.vividShift(colors.first);
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: v,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: v.withValues(alpha: 0.55),
                blurRadius: 5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      );
    }
    if (colors.length == 2) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CustomPaint(
            painter: _HalfSquarePainter(
              AppColors.vividShift(colors[0]),
              AppColors.vividShift(colors[1]),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        width: 14,
        height: 14,
        child: CustomPaint(
          painter: _PizzaSquarePainter(
            colors.take(3).map(AppColors.vividShift).toList(),
          ),
        ),
      ),
    );
  }
}

/// Quadrado dividido ao meio (vertical) — destaca plantões/compromissos.
class _HalfSquarePainter extends CustomPainter {
  final Color left;
  final Color right;

  _HalfSquarePainter(this.left, this.right);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final centerX = size.width / 2;

    final leftPath = Path()
      ..moveTo(0, 0)
      ..lineTo(centerX, 0)
      ..lineTo(centerX, size.height)
      ..lineTo(0, size.height)
      ..close();

    final rightPath = Path()
      ..moveTo(centerX, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(centerX, size.height)
      ..close();

    canvas.drawPath(leftPath, Paint()..color = left);
    canvas.drawPath(rightPath, Paint()..color = right);

    canvas.drawRect(rect, Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5);
  }

  @override
  bool shouldRepaint(covariant _HalfSquarePainter oldDelegate) =>
      oldDelegate.left != left || oldDelegate.right != right;
}

/// Quadrado estilo pizza (3 fatias triangulares).
class _PizzaSquarePainter extends CustomPainter {
  final List<Color> colors;

  _PizzaSquarePainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    const sweep = 2 * math.pi / 3;

    for (int i = 0; i < colors.length; i++) {
      final startAngle = -math.pi / 2 + (i * sweep);
      final endAngle = startAngle + sweep;
      final p1 = Offset(center.dx + (w / 2) * math.cos(startAngle), center.dy + (h / 2) * math.sin(startAngle));
      final p2 = Offset(center.dx + (w / 2) * math.cos(endAngle), center.dy + (h / 2) * math.sin(endAngle));
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = colors[i]);
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5);
  }

  @override
  bool shouldRepaint(covariant _PizzaSquarePainter oldDelegate) =>
      oldDelegate.colors != colors;
}
