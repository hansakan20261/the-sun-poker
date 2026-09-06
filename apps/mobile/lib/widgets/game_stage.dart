import 'package:flutter/material.dart';

/// A fixed-design-size "stage" that scales its [child] as ONE rigid unit
/// to fit whatever space is actually available — the Flutter equivalent of
/// CSS `transform: scale(min(viewportW/designW, viewportH/designH))` on a
/// fixed-size canvas.
///
/// Why this exists:
/// Before this widget, each table element (opponent seat, my seat, cards,
/// score box) computed its own size independently from the raw device
/// width/height using different `.clamp()` formulas. On screens that were
/// both narrow AND short at once (e.g. 740x360 mobile landscape), those
/// formulas diverged from each other and cards/chips/names/result boxes
/// started overlapping.
///
/// [GameStage] fixes this at the root: everything inside [child] always
/// receives the SAME constant [designWidth] x [designHeight], regardless of
/// the real device size. All the existing percentage-based positions
/// (seat x/y as % of width/height) become fixed, mutually-consistent pixel
/// values. Only after layout is fully resolved does [GameStage] scale the
/// entire result uniformly with [FittedBox] — so the table, seats, cards
/// and chips all shrink/grow together, never independently, and the
/// original aspect ratio and relative positions are always preserved.
///
/// Seat positions and game logic are NOT touched by this widget — it only
/// changes what width/height the existing layout code perceives.
class GameStage extends StatelessWidget {
  /// Reference design width. Matches the aspect ratio of the table
  /// background art (chinese_table_bg.png, 1520x704 ≈ 2.16:1) and the
  /// original tuning targets already baked into PerspectiveTableLayout.
  final double designWidth;

  /// Reference design height.
  final double designHeight;

  final Widget child;

  const GameStage({
    super.key,
    required this.designWidth,
    required this.designHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        final scaleX = availableWidth / designWidth;
        final scaleY = availableHeight / designHeight;
        // Never scale ABOVE 1.0 — on large desktop screens we center the
        // design-sized stage with extra space around it instead of blowing
        // up cards/text beyond their authored size. Below 1.0 the whole
        // stage shrinks as one rigid unit, so nothing is squeezed
        // independently and nothing overlaps.
        final scale = [scaleX, scaleY, 1.0].reduce((a, b) => a < b ? a : b);

        return Center(
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: SizedBox(
              width: designWidth,
              height: designHeight,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Shows a "please rotate your device" fallback instead of squeezing the
/// game table when the available area is taller than it is wide.
///
/// This matters mainly for the web build: native iOS/Android lock the
/// screen to landscape via SystemChrome for this table, but that lock has
/// no effect in a browser (desktop window resize, mobile browser before
/// rotating, etc.), so a real portrait fallback is still needed there.
class LandscapeOnlyGate extends StatelessWidget {
  final Widget child;
  final String message;

  const LandscapeOnlyGate({
    super.key,
    required this.child,
    this.message = 'กรุณาหมุนหน้าจอเป็นแนวนอน\nเพื่อเล่นเกมไพ่สามกอง',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = constraints.maxHeight > constraints.maxWidth;
        if (!isPortrait) return child;
        return Container(
          color: const Color(0xFF1A0505),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.screen_rotation,
                color: Color(0xFFDAA520),
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
