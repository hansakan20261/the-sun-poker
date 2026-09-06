import 'dart:math';
import 'dart:ui';

import 'responsive_card_config.dart';

export 'responsive_card_config.dart' show BreakpointTier, ResponsiveCardConfig;

/// Orientation enum for layout calculations.
///
/// Uses a simple enum instead of Flutter's widget-based Orientation
/// to keep this class fully testable without Flutter widgets.
enum LayoutOrientation { portrait, landscape }

/// Computes layout dimensions based on screen size.
///
/// Replaces fixed `CardSizeConfig` with dynamic breakpoint-based sizing.
/// This class is a pure computation engine — no Flutter widget dependencies.
/// It uses only `dart:ui` types (Size, Offset) for dimensions and positions.
class ResponsiveLayoutEngine {
  /// Creates a layout engine for the given screen width.
  ResponsiveLayoutEngine(this._screenWidth);

  final double _screenWidth;

  /// Width thresholds for breakpoint tier classification.
  static const double _compactThreshold = 380.0;
  static const double _standardThreshold = 430.0;
  static const double _expandedThreshold = 768.0;

  /// Supported screen dimension ranges.
  static const double minScreenWidth = 320.0;
  static const double maxScreenWidth = 1366.0;
  static const double minScreenHeight = 480.0;
  static const double maxScreenHeight = 1024.0;

  /// Duration for layout transition animation on orientation change (ms).
  /// References AnimationTimingConfig.layoutRotation.
  static const int layoutTransitionDuration = 300;

  /// Classifies a screen width into exactly one [BreakpointTier].
  ///
  /// - width < 380dp → compact
  /// - 380 <= width < 430dp → standard
  /// - 430 <= width < 768dp → expanded
  /// - width >= 768dp → large
  static BreakpointTier classifyTier(double width) {
    if (width < _compactThreshold) return BreakpointTier.compact;
    if (width < _standardThreshold) return BreakpointTier.standard;
    if (width < _expandedThreshold) return BreakpointTier.expanded;
    return BreakpointTier.large;
  }

  /// Current breakpoint tier based on screen width.
  BreakpointTier get currentTier => classifyTier(_screenWidth);

  /// Player card dimensions for the current tier.
  Size get cardSize => ResponsiveCardConfig.playerCard[currentTier]!;

  /// Opponent card dimensions for the current tier (smaller).
  Size get opponentCardSize => ResponsiveCardConfig.opponentCard[currentTier]!;

  /// Community card dimensions for the current tier.
  Size get communityCardSize =>
      ResponsiveCardConfig.communityCard[currentTier]!;

  /// Scale factor for animations based on screen size.
  ///
  /// Normalized to 1.0 at the standard tier midpoint (405dp).
  /// Smaller screens get smaller scale, larger screens get larger scale.
  double get animationScale {
    const referenceMidpoint = 405.0; // midpoint of standard tier
    return (_screenWidth / referenceMidpoint).clamp(0.5, 2.0);
  }

  /// Computes the table oval dimensions for the given screen size.
  ///
  /// - Landscape: approximately 2:1 width-to-height ratio
  /// - Portrait: approximately 1.5:1 width-to-height ratio
  ///
  /// The table occupies ~80% of the available screen area to leave room
  /// for UI elements around the edges.
  Size getTableSize(Size screenSize, {LayoutOrientation? orientation}) {
    final effectiveOrientation = orientation ?? _inferOrientation(screenSize);

    // Table occupies ~80% of screen dimensions
    const tableFraction = 0.80;

    double tableWidth;
    double tableHeight;

    if (effectiveOrientation == LayoutOrientation.landscape) {
      // Landscape: ~2:1 ratio
      tableWidth = screenSize.width * tableFraction;
      tableHeight = tableWidth / 2.0;
      // Ensure height doesn't exceed available screen height
      if (tableHeight > screenSize.height * tableFraction) {
        tableHeight = screenSize.height * tableFraction;
        tableWidth = tableHeight * 2.0;
      }
    } else {
      // Portrait: ~1.5:1 ratio
      tableWidth = screenSize.width * tableFraction;
      tableHeight = tableWidth / 1.5;
      // Ensure height doesn't exceed available screen height
      if (tableHeight > screenSize.height * tableFraction) {
        tableHeight = screenSize.height * tableFraction;
        tableWidth = tableHeight * 1.5;
      }
    }

    return Size(tableWidth, tableHeight);
  }

  /// Computes seat positions as normalized 0–1 offsets for N players.
  ///
  /// The player's own seat is at the bottom center.
  /// Other seats are distributed around an ellipse in clockwise order.
  ///
  /// [playerCount] must be between 2 and 9 inclusive.
  /// Returns a list of [Offset] values where each x,y is in the range [0, 1].
  List<Offset> getSeatPositions(
    int playerCount,
    Size screenSize,
    LayoutOrientation orientation,
  ) {
    assert(
      playerCount >= 2 && playerCount <= 9,
      'Player count must be between 2 and 9',
    );

    final positions = <Offset>[];

    // Ellipse parameters (normalized to 0-1 space)
    const centerX = 0.5;
    const centerY = 0.5;

    // Ellipse radii — leave margin for card rendering
    double radiusX;
    double radiusY;

    if (orientation == LayoutOrientation.landscape) {
      radiusX = 0.38;
      radiusY = 0.35;
    } else {
      radiusX = 0.35;
      radiusY = 0.38;
    }

    // Start angle: bottom center (π/2 = 270° in standard math, but we use
    // clockwise from bottom). In standard math coordinates where 0 is right
    // and angles go counter-clockwise, bottom is at π/2 (90°).
    // We distribute clockwise, so we subtract the angle.
    const startAngle = pi / 2; // bottom center

    for (int i = 0; i < playerCount; i++) {
      // Distribute seats clockwise around the ellipse
      final angle = startAngle + (2 * pi * i / playerCount);
      final x = centerX + radiusX * cos(angle);
      final y = centerY + radiusY * sin(angle);

      positions.add(Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)));
    }

    return positions;
  }

  /// Validates that all computed positions and dimensions stay within
  /// the screen bounds for the given configuration.
  ///
  /// Returns true if no element would clip or overflow.
  bool validateBounds({
    required int playerCount,
    required Size screenSize,
    required LayoutOrientation orientation,
  }) {
    // Validate screen size is within supported range
    if (screenSize.width < minScreenWidth ||
        screenSize.width > maxScreenWidth) {
      return false;
    }
    if (screenSize.height < minScreenHeight ||
        screenSize.height > maxScreenHeight) {
      return false;
    }

    // Validate table fits within screen
    final tableSize = getTableSize(screenSize, orientation: orientation);
    if (tableSize.width > screenSize.width ||
        tableSize.height > screenSize.height) {
      return false;
    }

    // Validate all seat positions are within bounds
    final seats = getSeatPositions(playerCount, screenSize, orientation);
    final tier = classifyTier(screenSize.width);
    final cardDimensions = ResponsiveCardConfig.playerCard[tier]!;

    for (final seat in seats) {
      // Convert normalized position to pixel position
      final pixelX = seat.dx * screenSize.width;
      final pixelY = seat.dy * screenSize.height;

      // Check that card at this position doesn't overflow
      // Card is centered on the seat position
      final cardLeft = pixelX - cardDimensions.width / 2;
      final cardTop = pixelY - cardDimensions.height / 2;
      final cardRight = pixelX + cardDimensions.width / 2;
      final cardBottom = pixelY + cardDimensions.height / 2;

      if (cardLeft < 0 ||
          cardTop < 0 ||
          cardRight > screenSize.width ||
          cardBottom > screenSize.height) {
        return false;
      }
    }

    return true;
  }

  /// Infers orientation from screen dimensions.
  static LayoutOrientation _inferOrientation(Size screenSize) {
    return screenSize.width > screenSize.height
        ? LayoutOrientation.landscape
        : LayoutOrientation.portrait;
  }
}
