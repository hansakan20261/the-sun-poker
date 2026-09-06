/// Timing configuration for all game animations (values in milliseconds).
///
/// These constants match the design spec and are used by animation controllers
/// to ensure consistent timing across the app.
class AnimationTimingConfig {
  AnimationTimingConfig._();

  // ─── Poker Deal ────────────────────────────────────────────────────────
  /// Duration of a single card flight from dealer to player seat.
  static const int dealFlightDuration = 500;

  /// Duration of the card flip animation on arrival.
  static const int dealFlipDuration = 350;

  /// Stagger delay between dealing each card.
  static const int dealStaggerDelay = 100;

  /// Maximum total duration for dealing to a full table (9 players).
  static const int dealMaxTotal = 1500;

  // ─── Chips ─────────────────────────────────────────────────────────────
  /// Duration of chip flight from player to pot (bet).
  static const int chipBetFlight = 350;

  /// Duration of chip flight from pot to winner.
  static const int chipWinFlight = 500;

  /// Duration of chip transfer between players (Chinese Poker scoring).
  static const int chipTransferFlight = 400;

  /// Duration of the all-in push animation (more dramatic than normal bet).
  static const int allInPushFlight = 600;

  /// Duration of the all-in glow effect after chips arrive.
  static const int allInGlowDuration = 800;

  // ─── Showdown ──────────────────────────────────────────────────────────
  /// Duration of each card flip during showdown.
  static const int showdownFlipDuration = 350;

  /// Stagger delay between revealing each player's hand.
  static const int showdownStaggerDelay = 200;

  // ─── Chinese Poker ─────────────────────────────────────────────────────
  /// Stagger delay when dealing 13 cards.
  static const int chineseCardStagger = 100;

  /// Duration of card placement from hand to row.
  static const int chineseCardPlace = 250;

  /// Duration of card return from row to hand.
  static const int chineseCardReturn = 200;

  /// Duration of reset (all cards return simultaneously).
  static const int chineseResetAll = 300;

  /// Stagger delay for auto-arrange cascading animation.
  static const int chineseAutoArrangeStagger = 50;

  /// Pause between row reveals during Chinese Poker showdown.
  static const int chineseRowPause = 800;

  // ─── Celebrations ──────────────────────────────────────────────────────
  /// Duration of confetti particle effect on win.
  static const int confettiDuration = 2000;

  /// Duration of golden glow pulse on winning cards.
  static const int winGlowPulse = 1000;

  // ─── UI Transitions ────────────────────────────────────────────────────
  /// Duration of screen slide-in/slide-out transitions.
  static const int screenTransition = 300;

  /// Duration of table and seats fade-in after loading.
  static const int tableFadeIn = 400;

  /// Duration of layout animation on orientation change.
  static const int layoutRotation = 300;

  // ─── Fold ──────────────────────────────────────────────────────────────
  /// Duration of fold card slide toward muck.
  static const int foldSlide = 300;

  // ─── Community Cards ───────────────────────────────────────────────────
  /// Duration of flop spread animation (3 cards).
  static const int flopSpread = 600;

  /// Duration of turn card slide.
  static const int turnSlide = 400;

  /// Duration of river card slide.
  static const int riverSlide = 400;

  // ─── Scoring (Chinese Poker) ───────────────────────────────────────────
  /// Duration of score count-up number animation.
  static const int scoreCountUp = 500;
}
