import 'package:flutter/material.dart';

/// 3D Perspective poker table layout.
///
/// Uses a background image of a 3D poker table and positions
/// player widgets at FIXED pixel-perfect positions matching
/// the chair locations in the image.
///
/// Seat positions are defined as percentages of screen width/height
/// and NEVER move regardless of how many players are seated.
class PerspectiveTableLayout extends StatelessWidget {
  final List<Widget> opponentWidgets;
  final Widget myWidget;
  final Widget? centerWidget;
  final Widget? dealerWidget;
  final List<Widget> overlayWidgets;
  final bool landscapeMode; // true = Chinese Poker (4 seats, landscape)
  final bool
  showTableBackground; // false = hide built-in table image (use custom bg)

  const PerspectiveTableLayout({
    super.key,
    required this.opponentWidgets,
    required this.myWidget,
    this.centerWidget,
    this.dealerWidget,
    this.overlayWidgets = const [],
    this.landscapeMode = false,
    this.showTableBackground = true,
  });

  // Perspective scale constants
  static const nearScale = 1.0;
  static const farScale = 0.65;

  /// Fixed seat positions as percentage of screen (x%, y%)
  /// These match the chair positions in the 3D table background image.
  /// Seat 5 (top-center) = Dealer position, not used for players.
  ///
  /// Layout (viewed from player's perspective):
  /// ```
  ///            [Dealer]
  ///      Seat4          Seat6
  ///   Seat3                Seat7
  ///  Seat2                  Seat8
  ///            [TABLE]
  ///              ME
  /// ```
  static const _seatPositions = [
    // Seat 2: left-near
    _FixedSeat(x: 0.01, y: 0.70, scale: 0.75),
    // Seat 3: left-mid
    _FixedSeat(x: 0.01, y: 0.47, scale: 0.75),
    // Seat 4: top-left — moved out 2 levels
    _FixedSeat(x: 0.08, y: 0.20, scale: 0.75),
    // Seat 6: top-right — moved out 2 levels
    _FixedSeat(x: 0.72, y: 0.20, scale: 0.75),
    // Seat 7: right-mid
    _FixedSeat(x: 0.65, y: 0.47, scale: 0.75),
    // Seat 8: right-near
    _FixedSeat(x: 0.65, y: 0.70, scale: 0.75),
    // Seat 9: extra
    _FixedSeat(x: 0.55, y: 0.75, scale: 0.75),
  ];

  /// Landscape 4-seat positions for Chinese Poker (3 opponents + me at bottom)
  /// Layout (landscape, viewed from player):
  /// ```
  ///   Seat2(left)    Seat3(top-center)    Seat4(right)
  ///                    [TABLE]
  ///                      ME
  /// ```
  /// Note: scale is applied dynamically based on screen height in build().
  static const _landscapeSeatPositions = [
    // Seat 2: left side (Alex) — ขยับไปทางซ้าย 3 ระดับ
    _FixedSeat(x: -0.06, y: 0.18, scale: 0.85),
    // Seat 3: top center
    _FixedSeat(x: 0.33, y: -0.02, scale: 0.85),
    // Seat 4: right side
    _FixedSeat(x: 0.68, y: 0.18, scale: 0.85),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final seats = landscapeMode ? _landscapeSeatPositions : _seatPositions;
        final n = opponentWidgets.length.clamp(0, seats.length);

        // ── Center content area (pot + community cards) ──
        final centerTop = landscapeMode ? h * 0.32 : h * 0.34;
        final centerH = landscapeMode ? h * 0.25 : h * 0.30;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Dealer at top-center (fixed)
            if (dealerWidget != null)
              Positioned(
                left: (w - 65) / 2,
                top: h * 0.08,
                child: Transform.scale(
                  scale: 0.6,
                  child: Opacity(opacity: 0.9, child: dealerWidget!),
                ),
              ),

            // 2. Table background image (3D poker table)
            if (showTableBackground)
              Positioned.fill(
                child: Image.asset(
                  landscapeMode
                      ? 'assets/chinese_table_bg.png'
                      : 'assets/poker_table_bg.png',
                  fit: BoxFit.fill,
                ),
              ),

            // 3. Center content (pot + community cards) — no extra transform here
            // Cards handle their own perspective tilt
            if (centerWidget != null)
              Positioned(
                left: w * 0.10,
                right: w * 0.10,
                top: centerTop,
                height: centerH,
                child: centerWidget!,
              ),

            // 4. Opponent seats — FIXED positions, locked to chair locations
            // ใช้ scale เท่ากับ "me" เพื่อให้กล่องสรุปขนาดเท่ากันทุกคน
            for (int i = 0; i < n; i++)
              Positioned(
                left: landscapeMode
                    ? (seats[i].x * w).clamp(0, w - 130)
                    : (seats[i].x * w).clamp(0, w - 100),
                top: landscapeMode
                    ? (seats[i].y * h).clamp(0, h - 60)
                    : (seats[i].y * h).clamp(0, h - 80),
                child: Transform.scale(
                  scale: landscapeMode
                      ? (h / 400).clamp(0.60, 0.95)
                      : (w / 430).clamp(0.6, 0.9),
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: landscapeMode
                        ? (w * 0.30).clamp(150, 260).toDouble()
                        : (w * 0.30).clamp(90, 140).toDouble(),
                    child: opponentWidgets[i],
                  ),
                ),
              ),

            // 5. "Me" at bottom center
            Builder(
              builder: (_) {
                final meWidth = landscapeMode
                    ? (w * 0.30).clamp(150.0, 260.0)
                    : 160.0;
                return Positioned(
                  left: landscapeMode ? (w - meWidth) / 2 : (w - 160) / 2,
                  bottom: landscapeMode ? 8 : 0,
                  child: Transform.scale(
                    scale: landscapeMode ? (h / 400).clamp(0.60, 0.95) : 1.0,
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: landscapeMode ? meWidth : 160,
                      child: myWidget,
                    ),
                  ),
                );
              },
            ),

            // 6. Overlays
            ...overlayWidgets,
          ],
        );
      },
    );
  }
}

/// Fixed seat position definition (percentage-based, locked).
class _FixedSeat {
  final double x; // 0.0 - 1.0 (percentage of screen width)
  final double y; // 0.0 - 1.0 (percentage of screen height)
  final double scale; // 0.5 - 1.0 (perspective scale)

  const _FixedSeat({required this.x, required this.y, required this.scale});
}
