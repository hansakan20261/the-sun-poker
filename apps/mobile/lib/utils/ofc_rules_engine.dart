import 'ofc_scorer.dart';

/// Client-side OFC rules enforcement utilities.
/// Handles dealing sequence, foul detection, Fantasyland, scoring, royalties.
class OFCRulesEngine {
  /// Get number of cards to deal for a given round (1-indexed).
  /// Round 1: 5 cards, Rounds 2-8: 1 card each. Total: 13 cards.
  static int cardsForRound(int round) {
    if (round == 1) return 5;
    if (round >= 2 && round <= 8) return 1;
    return 0;
  }

  /// Total rounds in an OFC hand.
  static const int totalRounds = 8;

  /// Validate hand strength ordering: Front < Middle < Back.
  /// Delegates to OFCScorer.isFoul.
  static bool isFoul(
    List<String> front,
    List<String> middle,
    List<String> back,
  ) {
    return OFCScorer.isFoul(front, middle, back);
  }

  /// Check Fantasyland qualification (QQ+ in front without foul).
  static bool qualifiesForFantasyland(
    List<String> front,
    List<String> middle,
    List<String> back,
  ) {
    return OFCScorer.qualifiesForFantasyland(front, middle, back);
  }

  /// In Fantasyland mode, player receives all 13 cards at once.
  static const int fantasylandCardCount = 13;

  /// Score a complete OFC hand between two players.
  /// Returns net points for player A.
  static int scoreHands({
    required List<String> aFront,
    required List<String> aMiddle,
    required List<String> aBack,
    required List<String> bFront,
    required List<String> bMiddle,
    required List<String> bBack,
  }) {
    return OFCScorer.compareHands(
      aFront: aFront,
      aMiddle: aMiddle,
      aBack: aBack,
      bFront: bFront,
      bMiddle: bMiddle,
      bBack: bBack,
    );
  }

  /// Calculate royalties for a single row.
  static int royaltiesForRow(List<String> cards, String row) {
    return OFCScorer.calculateRoyalties(cards, row);
  }

  /// Auto-place remaining cards when timer expires or player disconnects.
  static Map<String, List<String>> autoPlace({
    required List<String> unplacedCards,
    required List<String> currentFront,
    required List<String> currentMiddle,
    required List<String> currentBack,
  }) {
    return OFCScorer.autoPlace(
      unplacedCards: unplacedCards,
      currentFront: currentFront,
      currentMiddle: currentMiddle,
      currentBack: currentBack,
    );
  }

  /// Advance dealer for OFC (same as NLH — clockwise rotation).
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
}
