/// OFC game state parsed from WebSocket game:state events.
class OFCGameState {
  final String phase; // 'waiting', 'dealing', 'placing', 'showdown'
  final int currentRound; // 1-8
  final Map<int, OFCPlayerState> players;
  final int? currentPlayerSeat;
  final bool isFantasyland;

  const OFCGameState({
    required this.phase,
    required this.currentRound,
    required this.players,
    this.currentPlayerSeat,
    required this.isFantasyland,
  });
}

/// Per-player state within an OFC game.
class OFCPlayerState {
  final String username;
  final String avatarUrl;
  final String countryFlag;
  final int chips;
  final List<String> hand; // Unplaced cards in current round
  final List<String> front; // Placed front hand cards (max 3)
  final List<String> middle; // Placed middle hand cards (max 5)
  final List<String> back; // Placed back hand cards (max 5)
  final int points; // Running point total
  final bool isFoul;
  final bool isFantasyland;

  const OFCPlayerState({
    required this.username,
    required this.avatarUrl,
    required this.countryFlag,
    required this.chips,
    required this.hand,
    required this.front,
    required this.middle,
    required this.back,
    required this.points,
    required this.isFoul,
    required this.isFantasyland,
  });
}
