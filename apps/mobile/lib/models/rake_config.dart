/// Rake configuration from the table config in game state.
class RakeConfig {
  /// Rake percentage (e.g. 5.0 for 5%).
  final double rakePercent;

  /// Maximum rake per hand.
  final int rakeCap;

  const RakeConfig({required this.rakePercent, required this.rakeCap});
}
