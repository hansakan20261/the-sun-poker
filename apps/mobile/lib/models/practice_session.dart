enum SpectatorState { notSpectating, spectating, waitingForBB }

class PracticeSession {
  int demoChips;
  final String gameType;
  final List<BotPlayer> bots;
  PracticeSession({
    this.demoChips = 10000,
    required this.gameType,
    required this.bots,
  });
  void resetChips() => demoChips = 10000;
}

class BotPlayer {
  final String displayName;
  final String avatarAsset;
  int chips;
  final int seat;
  BotPlayer({
    required this.displayName,
    required this.avatarAsset,
    required this.chips,
    required this.seat,
  });
}

class SessionFlags {
  static bool welcomePopupShown = false;
}
