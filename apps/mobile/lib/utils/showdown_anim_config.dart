/// Timing and layout constants for the showdown animation sequence.
class ShowdownAnimConfig {
  static const Duration cardFlipDuration = Duration(milliseconds: 400);
  static const Duration playerStaggerDelay = Duration(milliseconds: 500);
  static const Duration amountLabelAnimDuration = Duration(milliseconds: 300);
  static const Duration pauseAfterLabels = Duration(milliseconds: 300);
  static const Duration loserChipFlightDuration = Duration(milliseconds: 600);
  static const int loserChipCount = 3;
  static const Duration loserChipStagger = Duration(milliseconds: 100);
  static const Duration chipCountDownDuration = Duration(milliseconds: 600);
  static const Duration redFlashDuration = Duration(milliseconds: 400);
  static const double redFlashMaxOpacity = 0.4;
  static const Duration pauseAfterLoserDeduction = Duration(milliseconds: 200);
  static const int winnerChipCount = 5;
  static const Duration winnerChipStagger = Duration(milliseconds: 80);
  static const Duration winnerFlightTotalDuration = Duration(milliseconds: 800);
  static const double bezierControlPointOffset = 40.0;
  static const Duration pauseBeforePopup = Duration(milliseconds: 500);
  static const double perspectiveValue = 0.001;
}
