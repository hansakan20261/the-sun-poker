/// Pure utility class for computing raise amounts from slider positions
/// and pot-fraction presets.
///
/// All methods return values clamped to [minRaise, maxRaise].
class BetCalculator {
  /// Linear interpolation from slider value (0.0–1.0) to raise amount.
  /// amount = minRaise + ((maxRaise - minRaise) * sliderValue), clamped.
  static int fromSlider({
    required double sliderValue,
    required int minRaise,
    required int maxRaise,
  }) {
    if (minRaise >= maxRaise) return minRaise;
    final amount =
        minRaise +
        ((maxRaise - minRaise) * sliderValue.clamp(0.0, 1.0)).round();
    return amount.clamp(minRaise, maxRaise);
  }

  /// Pot-fraction raise: callAmount + fraction × (currentPot + callAmount), clamped.
  static int fromPotFraction({
    required double fraction,
    required int currentPot,
    required int callAmount,
    required int minRaise,
    required int maxRaise,
  }) {
    final potAfterCall = currentPot + callAmount;
    final amount = callAmount + (potAfterCall * fraction).round();
    return amount.clamp(minRaise, maxRaise);
  }

  /// Simplified pot-fraction preset: (fraction × potSize), clamped to [minRaise, maxRaise].
  ///
  /// Used by the Preset_Bet_Buttons ("1/3", "1/2", "2/3", "กองกลาง") to quickly
  /// set a bet amount as a fraction of the current pot.
  static int fromPotFractionPreset({
    required double fraction,
    required int potSize,
    required int minRaise,
    required int maxRaise,
  }) {
    final amount = (fraction * potSize).round();
    return amount.clamp(minRaise, maxRaise);
  }

  /// All-in: returns the player's total remaining chips.
  static int allIn({required int playerChips}) => playerChips;

  /// Preset labels for pot-fraction bet buttons displayed in the Betting_Action_Bar.
  /// Maps a display label to its corresponding pot fraction value.
  static const Map<String, double> potFractionPresets = {
    '1/3': 1.0 / 3.0,
    '1/2': 1.0 / 2.0,
    '2/3': 2.0 / 3.0,
    'กองกลาง': 1.0, // Pot
  };

  /// Ordered list of preset labels for UI rendering.
  static const List<String> presetLabels = ['1/3', '1/2', '2/3', 'กองกลาง'];

  /// Snap a raw bet amount to the nearest multiple of [bigBlind].
  ///
  /// - If the snapped value < [minRaise], snap up to the next BB multiple ≥ [minRaise].
  /// - If the snapped value > [maxRaise], use [maxRaise].
  /// - Exception: [playerChips] (all-in) is always valid regardless of snap.
  static int snapToGrid({
    required int rawAmount,
    required int bigBlind,
    required int minRaise,
    required int maxRaise,
    required int playerChips,
  }) {
    // All-in is always valid
    if (rawAmount >= playerChips) return playerChips;

    final bb = bigBlind < 1 ? 1 : bigBlind;

    // Snap to nearest BB multiple
    int snapped = ((rawAmount + bb ~/ 2) ~/ bb) * bb;

    // If snapped below minRaise, snap up to next BB multiple ≥ minRaise
    if (snapped < minRaise) {
      snapped = ((minRaise + bb - 1) ~/ bb) * bb;
    }

    // Clamp to maxRaise
    if (snapped > maxRaise) {
      snapped = maxRaise;
    }

    return snapped;
  }
}
