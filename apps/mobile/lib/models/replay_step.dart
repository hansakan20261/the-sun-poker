/// A single discrete action within a hand history replay.
class ReplayStep {
  final int stepIndex;
  final String playerName;
  final int playerSeat;
  final String actionType; // fold, call, raise, check, all_in
  final String actionLabelTh;
  final int amount;
  final String round; // preflop, flop, turn, river, showdown
  final List<String> communityCardsRevealed;
  final Map<int, List<String>> revealedHoleCards; // seat → cards

  const ReplayStep({
    required this.stepIndex,
    required this.playerName,
    required this.playerSeat,
    required this.actionType,
    required this.actionLabelTh,
    required this.amount,
    required this.round,
    required this.communityCardsRevealed,
    required this.revealedHoleCards,
  });
}
