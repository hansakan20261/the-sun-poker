import 'hand_evaluator.dart';

/// Result of an OFC hand comparison for a single player.
class OFCResult {
  /// Net points from hand comparison (positive = win, negative = loss).
  final int points;

  /// Total royalty bonus points earned.
  final int royalties;

  /// Whether the player's hands violate strength ordering.
  final bool isFoul;

  /// Thai description of the result (e.g., "+15 แต้ม" or "ฟาวล์").
  final String description;

  const OFCResult({
    required this.points,
    required this.royalties,
    required this.isFoul,
    required this.description,
  });
}

/// Pure utility for OFC scoring, royalties, and foul detection.
///
/// Card format: "Ah" = Ace of hearts, "Ks" = King of spades.
/// Suits: h (hearts), d (diamonds), c (clubs), s (spades).
/// Values: 2-9, T (10), J, Q, K, A.
class OFCScorer {
  /// Check if three hands violate strength ordering (foul).
  ///
  /// Returns true if front >= middle or middle >= back in hand strength.
  /// A non-foul requires strict ordering: front < middle < back.
  static bool isFoul(
    List<String> front,
    List<String> middle,
    List<String> back,
  ) {
    final frontRank = HandEvaluator.evaluate3(front);
    final middleRank = HandEvaluator.evaluate5(middle);
    final backRank = HandEvaluator.evaluate5(back);

    // Front (3-card) vs Middle (5-card): compare ranks.
    // front >= middle means foul.
    if (_compare3vs5(frontRank, middleRank) >= 0) return true;

    // Middle vs Back: both 5-card hands, direct comparison.
    if (HandEvaluator.compare(middleRank, backRank) >= 0) return true;

    return false;
  }

  /// Compare a 3-card hand rank against a 5-card hand rank.
  ///
  /// For OFC foul detection, we compare the raw rank values.
  /// A 3-card hand can only be High Card (0), Pair (1), or Trips (3).
  /// If the 3-card rank >= 5-card rank, it's a foul.
  /// If ranks are equal, compare kickers for tie-breaking.
  static int _compare3vs5(HandRank front3, HandRank middle5) {
    if (front3.rank != middle5.rank) return front3.rank - middle5.rank;
    // Same rank category — compare kickers
    final len = front3.kickers.length < middle5.kickers.length
        ? front3.kickers.length
        : middle5.kickers.length;
    for (var i = 0; i < len; i++) {
      if (front3.kickers[i] != middle5.kickers[i]) {
        return front3.kickers[i] - middle5.kickers[i];
      }
    }
    return 0;
  }

  /// Calculate royalty points for a hand in a specific row.
  ///
  /// [cards] — the cards in the row.
  /// [row] — one of 'front', 'middle', 'back'.
  /// Returns a non-negative integer representing royalty points.
  static int calculateRoyalties(List<String> cards, String row) {
    switch (row) {
      case 'front':
        return _frontRoyalties(cards);
      case 'middle':
        return _middleRoyalties(cards);
      case 'back':
        return _backRoyalties(cards);
      default:
        return 0;
    }
  }

  /// Front hand royalties (3 cards).
  ///
  /// Pairs: 66=+1, 77=+2, 88=+3, 99=+4, TT=+5, JJ=+6, QQ=+7, KK=+8, AA=+9
  /// Trips: 222=+10, 333=+11, ..., AAA=+22
  static int _frontRoyalties(List<String> cards) {
    if (cards.length != 3) return 0;

    final rank = HandEvaluator.evaluate3(cards);

    // Three of a Kind: 222=+10, 333=+11, ..., AAA=+22
    if (rank.rank == 3) {
      final tripValue = rank.kickers[0]; // The trip card value
      // 2=10, 3=11, ..., A(14)=22 → value + 8
      return tripValue + 8;
    }

    // Pair: 66=+1, 77=+2, ..., AA=+9
    if (rank.rank == 1) {
      final pairValue = rank.kickers[0]; // The pair card value
      // Only pairs 6+ earn royalties
      if (pairValue >= 6) {
        // 6=1, 7=2, ..., A(14)=9 → value - 5
        return pairValue - 5;
      }
    }

    return 0;
  }

  /// Middle hand royalties (5 cards).
  ///
  /// Three of a Kind=+2, Straight=+4, Flush=+8, Full House=+12,
  /// Four of a Kind=+20, Straight Flush=+30, Royal Flush=+50
  static int _middleRoyalties(List<String> cards) {
    if (cards.length != 5) return 0;

    final rank = HandEvaluator.evaluate5(cards);

    switch (rank.rank) {
      case 3:
        return 2; // Three of a Kind
      case 4:
        return 4; // Straight
      case 5:
        return 8; // Flush
      case 6:
        return 12; // Full House
      case 7:
        return 20; // Four of a Kind
      case 8:
        return 30; // Straight Flush
      case 9:
        return 50; // Royal Flush
      default:
        return 0; // High Card, Pair, Two Pair
    }
  }

  /// Back hand royalties (5 cards).
  ///
  /// Straight=+2, Flush=+4, Full House=+6, Four of a Kind=+10,
  /// Straight Flush=+15, Royal Flush=+25
  static int _backRoyalties(List<String> cards) {
    if (cards.length != 5) return 0;

    final rank = HandEvaluator.evaluate5(cards);

    switch (rank.rank) {
      case 4:
        return 2; // Straight
      case 5:
        return 4; // Flush
      case 6:
        return 6; // Full House
      case 7:
        return 10; // Four of a Kind
      case 8:
        return 15; // Straight Flush
      case 9:
        return 25; // Royal Flush
      default:
        return 0; // High Card, Pair, Two Pair, Three of a Kind
    }
  }

  /// Compare two players' OFC hands, returning net points for player A.
  ///
  /// Scoring rules:
  /// - Each row is compared. Winner of each row gets +1, loser gets -1.
  /// - If one player wins all 3 rows, they get a "scoop" bonus of +3 extra (total +6).
  /// - Fouled player loses all 3 rows automatically.
  /// - Royalties are added/subtracted between players.
  ///
  /// Returns net points for player A (positive = A wins, negative = B wins).
  static int compareHands({
    required List<String> aFront,
    required List<String> aMiddle,
    required List<String> aBack,
    required List<String> bFront,
    required List<String> bMiddle,
    required List<String> bBack,
  }) {
    final aFouled = isFoul(aFront, aMiddle, aBack);
    final bFouled = isFoul(bFront, bMiddle, bBack);

    // Both fouled: 0 points, no royalties
    if (aFouled && bFouled) return 0;

    // A fouled: B wins all 3 rows + scoop
    if (aFouled) {
      final bRoyalties = _totalRoyalties(bFront, bMiddle, bBack);
      // B wins 3 rows (+3) + scoop (+3) = +6 for B, plus B's royalties
      return -(6 + bRoyalties);
    }

    // B fouled: A wins all 3 rows + scoop
    if (bFouled) {
      final aRoyalties = _totalRoyalties(aFront, aMiddle, aBack);
      // A wins 3 rows (+3) + scoop (+3) = +6 for A, plus A's royalties
      return 6 + aRoyalties;
    }

    // Neither fouled: compare each row
    int aPoints = 0;

    // Compare front hands (3-card)
    final frontA = HandEvaluator.evaluate3(aFront);
    final frontB = HandEvaluator.evaluate3(bFront);
    final frontCmp = HandEvaluator.compare(frontA, frontB);
    if (frontCmp > 0) {
      aPoints += 1;
    } else if (frontCmp < 0) {
      aPoints -= 1;
    }

    // Compare middle hands (5-card)
    final middleA = HandEvaluator.evaluate5(aMiddle);
    final middleB = HandEvaluator.evaluate5(bMiddle);
    final middleCmp = HandEvaluator.compare(middleA, middleB);
    if (middleCmp > 0) {
      aPoints += 1;
    } else if (middleCmp < 0) {
      aPoints -= 1;
    }

    // Compare back hands (5-card)
    final backA = HandEvaluator.evaluate5(aBack);
    final backB = HandEvaluator.evaluate5(bBack);
    final backCmp = HandEvaluator.compare(backA, backB);
    if (backCmp > 0) {
      aPoints += 1;
    } else if (backCmp < 0) {
      aPoints -= 1;
    }

    // Scoop bonus: if one player wins all 3 rows, +3 extra
    if (aPoints == 3) {
      aPoints += 3; // Total +6
    } else if (aPoints == -3) {
      aPoints -= 3; // Total -6
    }

    // Add royalty difference
    final aRoyalties = _totalRoyalties(aFront, aMiddle, aBack);
    final bRoyalties = _totalRoyalties(bFront, bMiddle, bBack);
    aPoints += aRoyalties - bRoyalties;

    return aPoints;
  }

  /// Calculate total royalties across all three rows.
  static int _totalRoyalties(
    List<String> front,
    List<String> middle,
    List<String> back,
  ) {
    return _frontRoyalties(front) +
        _middleRoyalties(middle) +
        _backRoyalties(back);
  }

  /// Check Fantasyland qualification: QQ or better in front hand without foul.
  ///
  /// Returns true if the front hand contains a pair of Queens or better
  /// (QQ, KK, AA, or any trips) AND the three hands do not foul.
  static bool qualifiesForFantasyland(
    List<String> front,
    List<String> middle,
    List<String> back,
  ) {
    // Must not foul
    if (isFoul(front, middle, back)) return false;

    final frontRank = HandEvaluator.evaluate3(front);

    // Trips always qualify (rank 3)
    if (frontRank.rank == 3) return true;

    // Pair of QQ or better (rank 1, pair value >= 12)
    if (frontRank.rank == 1 && frontRank.kickers[0] >= 12) return true;

    return false;
  }

  /// Auto-place remaining cards in available slots.
  ///
  /// Fills front first (up to 3), then middle (up to 5), then back (up to 5),
  /// left-to-right (i.e., in order of the unplaced cards list).
  ///
  /// Returns a map with keys 'front', 'middle', 'back' containing the
  /// complete card lists after placement.
  static Map<String, List<String>> autoPlace({
    required List<String> unplacedCards,
    required List<String> currentFront,
    required List<String> currentMiddle,
    required List<String> currentBack,
  }) {
    final front = List<String>.from(currentFront);
    final middle = List<String>.from(currentMiddle);
    final back = List<String>.from(currentBack);

    for (final card in unplacedCards) {
      if (front.length < 3) {
        front.add(card);
      } else if (middle.length < 5) {
        middle.add(card);
      } else if (back.length < 5) {
        back.add(card);
      }
      // If all rows are full, card is silently dropped (shouldn't happen
      // with valid 13-card total).
    }

    return {'front': front, 'middle': middle, 'back': back};
  }
}
