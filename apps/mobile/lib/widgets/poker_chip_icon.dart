import 'dart:math';
import 'package:flutter/material.dart';

/// Reusable poker chip icon that changes color based on balance amount.
/// Uses casino standard chip colors.
class PokerChipIcon extends StatelessWidget {
  final int amount;
  final double size;

  const PokerChipIcon({super.key, required this.amount, this.size = 30});

  // Chip color based on amount (casino standard)
  Color get _chipColor {
    if (amount >= 100000) return const Color(0xFF1A1A1A); // Black - 100K+
    if (amount >= 50000) return const Color(0xFF6A0DAD); // Purple - 50K+
    if (amount >= 10000) return const Color(0xFFFF8C00); // Orange - 10K+
    if (amount >= 5000) return const Color(0xFF1B1B1B); // Dark - 5K+
    if (amount >= 1000) return const Color(0xFF2E7D32); // Green - 1K+
    if (amount >= 500) return const Color(0xFFCC2222); // Red - 500+
    if (amount >= 100) return const Color(0xFF1565C0); // Blue - 100+
    return const Color(0xFFE0E0E0); // White - under 100
  }

  Color get _chipAccent {
    if (amount >= 100000) return const Color(0xFFFFD700); // Gold on black
    if (amount >= 50000) return const Color(0xFFE0E0E0); // White on purple
    if (amount >= 10000) return const Color(0xFFFFFFFF); // White on orange
    if (amount >= 5000) return const Color(0xFFFFD700); // Gold on dark
    if (amount >= 1000) return const Color(0xFFFFFFFF); // White on green
    if (amount >= 500) return const Color(0xFFFFFFFF); // White on red
    if (amount >= 100) return const Color(0xFFFFFFFF); // White on blue
    return const Color(0xFF333333); // Dark on white
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CasinoChipPainter(
          chipColor: _chipColor,
          accentColor: _chipAccent,
        ),
      ),
    );
  }
}

class _CasinoChipPainter extends CustomPainter {
  final Color chipColor;
  final Color accentColor;

  _CasinoChipPainter({required this.chipColor, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 1;

    // Shadow
    canvas.drawCircle(
      Offset(cx, cy + 1.5),
      r,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Main chip body
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [
            chipColor.withOpacity(0.9),
            chipColor,
            chipColor.withOpacity(0.7),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );

    // Edge ring (outer)
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = accentColor.withOpacity(0.8),
    );

    // Inner ring
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.65,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accentColor.withOpacity(0.5),
    );

    // Edge markings (8 dashes around the chip)
    final dashPaint = Paint()
      ..color = accentColor.withOpacity(0.9)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 8; i++) {
      final angle = i * pi * 2 / 8;
      final innerR = r * 0.82;
      final outerR = r * 0.98;
      canvas.drawLine(
        Offset(cx + innerR * cos(angle), cy + innerR * sin(angle)),
        Offset(cx + outerR * cos(angle), cy + outerR * sin(angle)),
        dashPaint,
      );
    }

    // Center highlight (3D shine)
    canvas.drawCircle(
      Offset(cx - r * 0.2, cy - r * 0.2),
      r * 0.2,
      Paint()
        ..shader =
            RadialGradient(
              colors: [Colors.white.withOpacity(0.25), Colors.transparent],
            ).createShader(
              Rect.fromCircle(
                center: Offset(cx - r * 0.2, cy - r * 0.2),
                radius: r * 0.2,
              ),
            ),
    );

    // Center text "C"
    final tp = TextPainter(
      text: TextSpan(
        text: 'C',
        style: TextStyle(
          color: accentColor,
          fontSize: r * 0.75,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CasinoChipPainter oldDelegate) =>
      chipColor != oldDelegate.chipColor ||
      accentColor != oldDelegate.accentColor;
}
