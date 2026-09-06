/// Timer color states for the turn indicator ring.
enum TimerColor { green, amber, red }

/// Pure utility for turn timer color and auto-action decisions.
class TimerLogic {
  /// Determine timer ring color based on remaining time percentage.
  ///
  /// - >50% → green
  /// - 25%–50% → amber
  /// - <25% → red
  static TimerColor getColor(int remainingSeconds, int totalSeconds) {
    assert(totalSeconds > 0, 'totalSeconds must be positive');
    final ratio = remainingSeconds / totalSeconds;
    if (ratio > 0.50) {
      return TimerColor.green;
    } else if (ratio >= 0.25) {
      return TimerColor.amber;
    } else {
      return TimerColor.red;
    }
  }

  /// Determine auto-action when timer expires.
  ///
  /// Returns 'fold' if a bet is pending, 'check' if no bet is pending.
  static String getAutoAction({required bool isBetPending}) {
    return isBetPending ? 'fold' : 'check';
  }

  /// Whether to play audio warning (3 seconds or fewer remaining).
  static bool shouldPlayWarning(int remainingSeconds) {
    return remainingSeconds <= 3;
  }
}
