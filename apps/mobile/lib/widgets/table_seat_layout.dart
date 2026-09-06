import 'dart:math';
import 'package:flutter/material.dart';
import 'oval_table.dart';

/// Shared layout widget — poker table centered on screen with ALL players
/// (including "me") positioned around the table edge.
///
/// Works in both portrait and landscape orientations.
/// The table is always centered. All 9 seats are on the ellipse perimeter.
///
/// Seat positions (clockwise from bottom center):
/// ```
///              P5    P6
///         P4                P7
///      P3                      P8
///         P2  ┌──────────┐  P9
///             │  TABLE   │
///             │ [center] │
///             └──────────┘
///                P1 (me)
/// ```
class TableSeatLayout extends StatelessWidget {
  final List<Widget> opponentWidgets;
  final Widget myWidget;
  final Widget? centerWidget;
  final Widget? dealerWidget; // Dealer avatar at top center of table
  final List<Widget> overlayWidgets;
  final double seatWidth;
  final double seatHeight;

  const TableSeatLayout({
    super.key,
    required this.opponentWidgets,
    required this.myWidget,
    this.centerWidget,
    this.dealerWidget,
    this.overlayWidgets = const [],
    this.seatWidth = 100.0,
    this.seatHeight = 90.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // ── Table fills most of the screen ──
        final tableW = w * 0.94;
        final tableH = h * 0.82;
        final tableLeft = (w - tableW) / 2;
        final tableTop = (h - tableH) / 2 - h * 0.04;

        // ── Ellipse center ──
        final cx = w / 2;
        final cy = h / 2 - h * 0.04;

        // ── Ellipse radii — seats sit ON the table edge ──
        final rx = tableW / 2 - seatWidth * 0.15; // seats overlap table edge
        final ry = tableH / 2 - seatHeight * 0.15;

        // ── All players on the ellipse (including me at bottom) ──
        final n = opponentWidgets.length.clamp(0, 8);
        final gap = n >= 6 ? 0.35 : 0.45;
        final startAngle = pi / 2 + gap;
        final endAngle = pi / 2 + (2 * pi) - gap;
        final step = n > 0 ? (endAngle - startAngle) / (n + 1) : 0.0;

        // ── Dealer reserved zone (top center) ──
        final dealerCenterX = w / 2;
        final dealerW = 70.0;
        final dealerH = 70.0;
        final dealerTop = tableTop - dealerH * 0.7;

        // ── Center content area ──
        final centerInset = min(tableW, tableH) * 0.22;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Dealer avatar — BEHIND table (rendered first, table covers lower body)
            if (dealerWidget != null)
              Positioned(
                left: (w - dealerW) / 2,
                top: tableTop - dealerH * 0.7,
                child: dealerWidget!,
              ),

            // 2. Oval table (covers dealer's lower body)
            Positioned(
              left: tableLeft,
              top: tableTop,
              width: tableW,
              height: tableH,
              child: const OvalTable(),
            ),

            // 3. Center content
            if (centerWidget != null)
              Positioned(
                left: tableLeft + centerInset * 1.5,
                right: w - tableLeft - tableW + centerInset * 1.5,
                top: tableTop + centerInset,
                bottom: h - tableTop - tableH + centerInset,
                child: centerWidget!,
              ),

            // 4. Opponent seats — positioned on table edge, avoiding dealer zone
            for (int i = 0; i < n; i++)
              _buildSeatAt(
                cx,
                cy,
                rx,
                ry,
                startAngle + step * (i + 1),
                w,
                h,
                opponentWidgets[i],
                dealerZone: dealerWidget != null
                    ? Rect.fromLTWH(
                        dealerCenterX - dealerW / 2 - 10,
                        dealerTop,
                        dealerW + 20,
                        dealerH,
                      )
                    : null,
              ),

            // 5. "Me" at bottom — flush with table bottom edge
            Positioned(
              left: (w - seatWidth) / 2,
              bottom: h - (tableTop + tableH) - 2,
              child: SizedBox(width: seatWidth, child: myWidget),
            ),

            // 6. Extra overlay widgets
            ...overlayWidgets,
          ],
        );
      },
    );
  }

  Widget _buildSeatAt(
    double cx,
    double cy,
    double rx,
    double ry,
    double angle,
    double maxW,
    double maxH,
    Widget child, {
    Rect? dealerZone,
  }) {
    var x = (cx + rx * cos(angle) - seatWidth / 2).clamp(0.0, maxW - seatWidth);
    // For top seats (angle between 3π/2 and π/2 going through 0), push them up more
    var rawY = cy + ry * sin(angle) - seatHeight / 2;
    var y = rawY.clamp(0.0, maxH - seatHeight);

    // Avoid dealer zone — if seat overlaps, push it aside
    if (dealerZone != null) {
      final seatRect = Rect.fromLTWH(x, y, seatWidth, seatHeight);
      if (seatRect.overlaps(dealerZone)) {
        // Push seat to left or right depending on which side it's on
        if (x < cx) {
          x = (dealerZone.left - seatWidth - 4).clamp(0.0, maxW - seatWidth);
        } else {
          x = (dealerZone.right + 4).clamp(0.0, maxW - seatWidth);
        }
      }
    }

    return Positioned(
      left: x,
      top: y,
      child: SizedBox(width: seatWidth, child: child),
    );
  }

  /// Static helper: calculate seat positions without building widgets.
  static List<Offset> calculatePositions({
    required double width,
    required double height,
    required int seatCount,
    double seatWidth = 100.0,
    double seatHeight = 90.0,
  }) {
    if (seatCount <= 0) return [];

    final tableW = width * 0.94;
    final tableH = height * 0.82;
    final cx = width / 2;
    final cy = height / 2 - height * 0.04;
    final rx = tableW / 2 - seatWidth * 0.15;
    final ry = tableH / 2 - seatHeight * 0.15;

    final n = seatCount.clamp(1, 8);
    final gap = n >= 6 ? 0.35 : 0.45;
    final startAngle = pi / 2 + gap;
    final endAngle = pi / 2 + (2 * pi) - gap;
    final step = (endAngle - startAngle) / (n + 1);

    final positions = <Offset>[];
    for (int i = 0; i < n; i++) {
      final angle = startAngle + step * (i + 1);
      final x = (cx + rx * cos(angle) - seatWidth / 2).clamp(
        0.0,
        width - seatWidth,
      );
      final y = (cy + ry * sin(angle) - seatHeight / 2).clamp(
        0.0,
        height - seatHeight,
      );
      positions.add(Offset(x, y));
    }
    return positions;
  }
}
