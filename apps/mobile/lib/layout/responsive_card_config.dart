import 'dart:ui';

/// Breakpoint tiers for responsive layout classification.
///
/// Each tier corresponds to a range of screen widths:
/// - [compact]: width < 380dp (iPhone SE class devices)
/// - [standard]: 380–430dp (iPhone 14/15)
/// - [expanded]: 430–768dp (iPhone Plus/Pro Max)
/// - [large]: >= 768dp (iPad)
enum BreakpointTier { compact, standard, expanded, large }

/// Static card size configuration maps per breakpoint tier.
///
/// Defines the dimensions for player cards, opponent cards, and community cards
/// at each breakpoint tier, matching the design spec.
class ResponsiveCardConfig {
  ResponsiveCardConfig._();

  /// Player's own card dimensions per breakpoint tier.
  static const Map<BreakpointTier, Size> playerCard = {
    BreakpointTier.compact: Size(36, 50),
    BreakpointTier.standard: Size(48, 66),
    BreakpointTier.expanded: Size(54, 74),
    BreakpointTier.large: Size(64, 90),
  };

  /// Opponent card dimensions per breakpoint tier.
  static const Map<BreakpointTier, Size> opponentCard = {
    BreakpointTier.compact: Size(18, 25),
    BreakpointTier.standard: Size(22, 32),
    BreakpointTier.expanded: Size(26, 36),
    BreakpointTier.large: Size(32, 44),
  };

  /// Community card dimensions per breakpoint tier.
  static const Map<BreakpointTier, Size> communityCard = {
    BreakpointTier.compact: Size(28, 39),
    BreakpointTier.standard: Size(34, 48),
    BreakpointTier.expanded: Size(40, 55),
    BreakpointTier.large: Size(50, 70),
  };
}
