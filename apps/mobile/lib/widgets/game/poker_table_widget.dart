import 'package:flutter/material.dart';

/// A widget that renders the poker table with professional casino styling.
///
/// - Oval table with dark green gradient felt texture
/// - Raised wooden rail border with subtle shadow
/// - Active player seat glow highlight
/// - Dark ambient background with radial gradient spotlight
///
/// Requirements: 11.1, 11.2, 11.3, 11.4
class PokerTableWidget extends StatelessWidget {
  /// The seat index of the currently active player (for glow highlight).
  /// Null if no player is active.
  final int? activeSeatIndex;

  /// Total number of seats at the table.
  final int seatCount;

  const PokerTableWidget({super.key, this.activeSeatIndex, this.seatCount = 9});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PokerTablePainter(
        activeSeatIndex: activeSeatIndex,
        seatCount: seatCount,
      ),
      size: Size.infinite,
    );
  }
}

class _PokerTablePainter extends CustomPainter {
  final int? activeSeatIndex;
  final int seatCount;

  _PokerTablePainter({this.activeSeatIndex, this.seatCount = 9});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // ── Dark ambient background with radial gradient spotlight ──
    final bgRect = Rect.fromLTWH(0, 0, w, h);
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [
          const Color(0xFF1A2A1A), // subtle green tint in center
          const Color(0xFF0D1A0D),
          const Color(0xFF050A05),
          const Color(0xFF020402), // near-black edges
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, bgPaint);

    final railRx = w / 2 - 8;
    final railRy = h / 2 - 8;

    // ── Table shadow ──
    final shadowRect = Rect.fromCenter(
      center: Offset(cx, cy + 4),
      width: railRx * 2 + 6,
      height: railRy * 2 + 6,
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..color = Colors.black.withOpacity(0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // ── Raised wooden rail border ──
    final railRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: railRx * 2,
      height: railRy * 2,
    );
    final railPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6B4423), // lighter top
          const Color(0xFF4A2F17),
          const Color(0xFF3A2210),
          const Color(0xFF2A180A), // darker bottom
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(railRect);
    canvas.drawOval(railRect, railPaint);

    // Rail highlight (subtle shadow/shine)
    canvas.drawOval(
      railRect.deflate(1),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, -0.4),
          colors: [Colors.white.withOpacity(0.15), Colors.transparent],
        ).createShader(railRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // ── Dark green gradient felt texture ──
    final feltRect = railRect.deflate(10);
    final feltPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.2),
        radius: 0.85,
        colors: [
          const Color(0xFF1B5E20), // brighter green center
          const Color(0xFF145218),
          const Color(0xFF0D3B12),
          const Color(0xFF072A0A), // dark green edges
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      ).createShader(feltRect);
    canvas.drawOval(feltRect, feltPaint);

    // Felt subtle texture highlight
    final feltHighlight = Rect.fromCenter(
      center: Offset(cx, cy - feltRect.height * 0.12),
      width: feltRect.width * 0.5,
      height: feltRect.height * 0.25,
    );
    canvas.drawOval(
      feltHighlight,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.04), Colors.transparent],
        ).createShader(feltHighlight),
    );

    // ── Active player seat glow highlight ──
    if (activeSeatIndex != null) {
      _drawActiveSeatGlow(canvas, size, activeSeatIndex!);
    }
  }

  void _drawActiveSeatGlow(Canvas canvas, Size size, int seatIndex) {
    // Compute seat position on the ellipse
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width * 0.38;
    final ry = size.height * 0.38;

    final angle = (3.14159 / 2) + (2 * 3.14159 * seatIndex / seatCount);
    final seatX = cx + rx * _cos(angle);
    final seatY = cy + ry * _sin(angle);

    final glowRect = Rect.fromCenter(
      center: Offset(seatX, seatY),
      width: 60,
      height: 60,
    );

    canvas.drawOval(
      glowRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFEB3B).withOpacity(0.3),
            const Color(0xFFFFEB3B).withOpacity(0.1),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(glowRect),
    );
  }

  double _cos(double angle) => _cosValue(angle);
  double _sin(double angle) => _sinValue(angle);

  static double _cosValue(double angle) {
    // Simple cos using dart:math would require import, use approximation
    // Actually we can use the formula directly
    return _mathCos(angle);
  }

  static double _sinValue(double angle) {
    return _mathSin(angle);
  }

  // Inline math functions to avoid dart:math import in painter
  static double _mathCos(double x) {
    // Taylor series approximation (good enough for our use)
    x = x % (2 * 3.14159265358979);
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  static double _mathSin(double x) {
    x = x % (2 * 3.14159265358979);
    double result = x;
    double term = x;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _PokerTablePainter oldDelegate) {
    return oldDelegate.activeSeatIndex != activeSeatIndex ||
        oldDelegate.seatCount != seatCount;
  }
}
