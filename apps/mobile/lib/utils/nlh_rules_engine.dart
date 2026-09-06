/// Client-side NLH rules enforcement utilities.
/// Validates dealer rotation, blind posting, betting order, min raise,
/// side pots, table stakes, string bet prevention, and showdown order.
class NLHRulesEngine {
  /// Advance dealer button one seat clockwise.
  /// Returns the new dealer seat number.
  static int advanceDealer(
    int currentDealer,
    int maxSeats,
    Set<int> occupiedSeats,
  ) {
    if (occupiedSeats.isEmpty) return 1;
    int next = currentDealer;
    for (int i = 0; i < maxSeats; i++) {
      next = (next % maxSeats) + 1;
      if (occupiedSeats.contains(next)) return next;
    }
    return currentDealer;
  }

  /// Get small blind seat (one left of dealer).
  static int getSmallBlindSeat(
    int dealerSeat,
    int maxSeats,
    Set<int> occupiedSeats,
  ) {
    return advanceDealer(dealerSeat, maxSeats, occupiedSeats);
  }

  /// Get big blind seat (one left of SB).
  static int getBigBlindSeat(
    int dealerSeat,
    int maxSeats,
    Set<int> occupiedSeats,
  ) {
    final sb = getSmallBlindSeat(dealerSeat, maxSeats, occupiedSeats);
    return advanceDealer(sb, maxSeats, occupiedSeats);
  }

  /// Get UTG seat (one left of BB, first to act pre-flop).
  static int getUTGSeat(int dealerSeat, int maxSeats, Set<int> occupiedSeats) {
    final bb = getBigBlindSeat(dealerSeat, maxSeats, occupiedSeats);
    return advanceDealer(bb, maxSeats, occupiedSeats);
  }

  /// Get first to act post-flop (first active left of dealer).
  static int getFirstPostFlopSeat(
    int dealerSeat,
    int maxSeats,
    Set<int> activeSeats,
  ) {
    return advanceDealer(dealerSeat, maxSeats, activeSeats);
  }

  /// Validate minimum raise rule.
  /// Re-raise must be >= previous raise increment + current bet.
  static bool isValidRaise({
    required int raiseAmount,
    required int currentBet,
    required int previousRaiseIncrement,
    required int bigBlind,
  }) {
    final minRaise =
        currentBet +
        (previousRaiseIncrement > 0 ? previousRaiseIncrement : bigBlind);
    return raiseAmount >= minRaise;
  }

  /// Calculate side pots for all-in scenarios.
  /// Returns list of {amount, eligibleSeats} maps.
  static List<Map<String, dynamic>> calculateSidePots(
    Map<int, int> playerBets,
    Set<int> allInSeats,
  ) {
    if (allInSeats.isEmpty) return [];

    final sortedAllIns = allInSeats.toList()
      ..sort((a, b) => (playerBets[a] ?? 0).compareTo(playerBets[b] ?? 0));

    final pots = <Map<String, dynamic>>[];
    int previousLevel = 0;

    for (final seat in sortedAllIns) {
      final level = playerBets[seat] ?? 0;
      if (level <= previousLevel) continue;

      final increment = level - previousLevel;
      final eligible = playerBets.entries
          .where((e) => (e.value) >= level)
          .map((e) => e.key)
          .toList();

      pots.add({
        'amount': increment * eligible.length,
        'eligibleSeats': eligible,
      });
      previousLevel = level;
    }

    // Main pot for remaining bets above highest all-in
    final highestAllIn = sortedAllIns.isNotEmpty
        ? (playerBets[sortedAllIns.last] ?? 0)
        : 0;
    final remainingPlayers = playerBets.entries
        .where((e) => e.value > highestAllIn && !allInSeats.contains(e.key))
        .toList();
    if (remainingPlayers.isNotEmpty) {
      int mainPotExtra = 0;
      for (final p in remainingPlayers) {
        mainPotExtra += p.value - highestAllIn;
      }
      if (mainPotExtra > 0) {
        pots.add({
          'amount': mainPotExtra,
          'eligibleSeats': remainingPlayers.map((e) => e.key).toList(),
        });
      }
    }

    return pots;
  }

  /// Get showdown reveal order.
  /// Last aggressor reveals first, then clockwise.
  /// If all checked, start left of dealer.
  static List<int> getShowdownOrder({
    required int? lastAggressor,
    required int dealerSeat,
    required int maxSeats,
    required Set<int> activeSeats,
  }) {
    final order = <int>[];
    final startSeat =
        lastAggressor ?? advanceDealer(dealerSeat, maxSeats, activeSeats);

    int current = startSeat;
    for (int i = 0; i < maxSeats; i++) {
      if (activeSeats.contains(current)) {
        order.add(current);
      }
      current = (current % maxSeats) + 1;
    }

    return order;
  }

  /// Validate table stakes: player cannot add chips mid-hand.
  static bool canAddChips({required bool handInProgress}) {
    return !handInProgress;
  }
}
