/// Data parsed from the game:result WebSocket event for showdown.
class ShowdownResultData {
  final List<ShowdownPlayerResult> players;
  final List<String> communityCards;
  final int potAmount;
  final int rakeAmount;
  const ShowdownResultData({
    required this.players,
    required this.communityCards,
    required this.potAmount,
    required this.rakeAmount,
  });
}

class ShowdownPlayerResult {
  final int seat;
  final String username;
  final String? avatarUrl;
  final List<String> holeCards;
  final String handNameTh;
  final int handRank;
  final bool isWinner;
  final bool isFolded;
  final int amountChange;
  const ShowdownPlayerResult({
    required this.seat,
    required this.username,
    this.avatarUrl,
    required this.holeCards,
    required this.handNameTh,
    required this.handRank,
    required this.isWinner,
    required this.isFolded,
    required this.amountChange,
  });
}
