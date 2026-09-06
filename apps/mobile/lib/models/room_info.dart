/// Room data for city-themed lobby cards.
class RoomInfo {
  final String id;
  final String cityName; // Thai city name
  final String cityIconUrl;
  final String gameType; // 'NLH', 'PLO', 'OFC', 'CRASH'
  final int smallBlind;
  final int bigBlind;
  final int ante;
  final int playerCount;
  final int maxPlayers;
  final int minBuyIn;

  const RoomInfo({
    required this.id,
    required this.cityName,
    required this.cityIconUrl,
    required this.gameType,
    required this.smallBlind,
    required this.bigBlind,
    required this.ante,
    required this.playerCount,
    required this.maxPlayers,
    required this.minBuyIn,
  });
}
