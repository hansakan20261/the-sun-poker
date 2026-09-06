import 'dart:math';
import 'package:flutter/material.dart';

/// Draws a 3D-perspective poker table with depth, lighting, and realistic felt.
/// The table appears as if viewed from a slight top-down angle (2.5D).
class OvalTable extends StatelessWidget {
  const OvalTable({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _OvalTable3DPainter(), size: Size.infinite);
  }
}

class _OvalTable3DPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // 3D perspective: top edge slightly narrower than bottom
    // Subtle squeeze (82%) for natural look — not too extreme
    final railRx = w / 2 - 6;
    final railRy = h / 2 - 6;
    const topSqueeze = 0.82;

    // ── Layer 1: Table shadow (3D depth) ──
    final shadowPath = _perspectiveOvalPath(
      cx,
      cy + 8,
      railRx + 4,
      railRy + 4,
      topSqueeze,
    );
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // ── Layer 2: Table base (dark, below the rail) ──
    final basePath = _perspectiveOvalPath(
      cx,
      cy + 4,
      railRx + 2,
      railRy + 2,
      topSqueeze,
    );
    canvas.drawPath(
      basePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF1A0E08), const Color(0xFF0D0704)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // ── Layer 3: Rail (wood border with 3D lighting) ──
    final railPath = _perspectiveOvalPath(cx, cy, railRx, railRy, topSqueeze);
    final railPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF7A5233),
          const Color(0xFF5A3D2B),
          const Color(0xFF3A2518),
          const Color(0xFF2A1810),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(railPath, railPaint);

    // Rail highlight
    canvas.drawPath(
      railPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, -0.3),
          colors: [Colors.white.withOpacity(0.2), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ── Layer 4: Gold trim ──
    final goldPath = _perspectiveOvalPath(
      cx,
      cy,
      railRx - 7,
      railRy - 7,
      topSqueeze,
    );
    canvas.drawPath(
      goldPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFDAA520),
            Color(0xFFFFD700),
            Color(0xFFB8860B),
            Color(0xFFDAA520),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );

    // ── Layer 5: Felt (red playing surface) — thicker rail = smaller felt ──
    final feltPath = _perspectiveOvalPath(
      cx,
      cy,
      railRx - 14,
      railRy - 14,
      topSqueeze,
    );
    final feltRect = Rect.fromLTWH(10, 10, w - 20, h - 20);
    final feltPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.2),
        radius: 0.9,
        colors: [
          const Color(0xFF8B2020),
          const Color(0xFF6B1818),
          const Color(0xFF4A1010),
          const Color(0xFF2A0808),
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      ).createShader(feltRect);
    canvas.drawPath(feltPath, feltPaint);

    // ── Layer 6: Inner gold trim (drop zone boundary) ──
    final innerGoldPath = _perspectiveOvalPath(
      cx,
      cy,
      railRx - 18,
      railRy - 18,
      topSqueeze,
    );
    canvas.drawPath(
      innerGoldPath,
      Paint()
        ..color = const Color(0xFFDAA520).withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Layer 7: Felt highlight (top light) ──
    final highlightPath = _perspectiveOvalPath(
      cx,
      cy - h * 0.1,
      railRx * 0.5,
      railRy * 0.25,
      topSqueeze,
    );
    canvas.drawPath(
      highlightPath,
      Paint()
        ..shader =
            RadialGradient(
              colors: [Colors.white.withOpacity(0.06), Colors.transparent],
            ).createShader(
              Rect.fromCenter(
                center: Offset(cx, cy - h * 0.1),
                width: railRx,
                height: railRy * 0.5,
              ),
            ),
    );

    // ── Layer 8: Bottom shadow (depth) ──
    final shadowBottomPath = _perspectiveOvalPath(
      cx,
      cy + h * 0.15,
      railRx * 0.6,
      railRy * 0.2,
      1.0,
    );
    canvas.drawPath(
      shadowBottomPath,
      Paint()
        ..shader =
            RadialGradient(
              colors: [Colors.black.withOpacity(0.12), Colors.transparent],
            ).createShader(
              Rect.fromCenter(
                center: Offset(cx, cy + h * 0.15),
                width: railRx * 1.2,
                height: railRy * 0.4,
              ),
            ),
    );
  }

  /// Create a perspective oval path where top is slightly narrower than bottom.
  /// Uses proper ellipse math with horizontal squeeze at top.
  Path _perspectiveOvalPath(
    double cx,
    double cy,
    double rx,
    double ry,
    double squeeze,
  ) {
    final path = Path();
    // Draw a smooth perspective oval using many small segments
    // Top half has reduced horizontal radius (squeeze effect)
    const segments = 64;
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * 3.14159265;
      // Calculate squeeze factor based on vertical position
      // At top (angle = -pi/2): squeeze applied
      // At bottom (angle = pi/2): full width
      final sinA = sin(angle);
      final cosA = cos(angle);
      // Interpolate squeeze: 1.0 at bottom, [squeeze] at top
      final verticalFactor = (sinA + 1) / 2; // 0 at top, 1 at bottom
      final horizontalScale = squeeze + (1.0 - squeeze) * verticalFactor;

      final x = cx + rx * horizontalScale * cosA;
      final y = cy + ry * sinA;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
