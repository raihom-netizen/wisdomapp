import 'package:flutter/material.dart';

/// Sparkline leve (sem dependência de chart): série 0..1 normalizada na altura.
class FinanceSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  final double width;

  const FinanceSparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 22,
    this.width = 72,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      width: width,
      child: CustomPaint(
        painter: _SparkPainter(values: values, color: color),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparkPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    var minV = values.first;
    var maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final span = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);
    final n = values.length;
    final dx = size.width / (n - 1);
    final path = Path();
    for (var i = 0; i < n; i++) {
      final t = (values[i] - minV) / span;
      final y = size.height - (t * (size.height - 4)) - 2;
      final x = i * dx;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
