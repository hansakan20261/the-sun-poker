import 'thai_labels.dart';

/// Represents a poker hand ranking with Thai and English names.
class HandRank {
  /// Rank value: 0=High Card, 1=Pair, 2=Two Pair, 3=Three of a Kind,
  /// 4=Straight, 5=Flush, 6=Full House, 7=Four of a Kind,
  /// 8=Straight Flush, 9=Royal Flush.
  final int rank;

  /// Thai name from [ThaiLabels.handNames].
  final String nameTh;

  /// English name for reference.
  final String nameEn;

  /// Kicker values for tie-breaking, ordered from most significant to least.
  final List<int> kickers;

  const HandRank({
    required this.rank,
    required this.nameTh,
    required this.nameEn,
    required this.kickers,
  });

  @override
  String toString() => 'HandRank($rank: $nameEn, kickers: $kickers)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HandRank &&
          rank == other.rank &&
          _listEquals(kickers, other.kickers);

  @override
  int get hashCode => rank.hashCode ^ kickers.hashCode;

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// English hand names indexed by rank.
const _englishNames = <int, String>{
  0: 'High Card',
  1: 'Pair',
  2: 'Two Pair',
  3: 'Three of a Kind',
  4: 'Straight',
  5: 'Flush',
  6: 'Full House',
  7: 'Four of a Kind',
  8: 'Straight Flush',
  9: 'Royal Flush',
};

/// Pure utility for evaluating poker hand strength and returning Thai hand names.
///
/// Card format: "Ah" = Ace of hearts, "Ks" = King of spades.
/// Suits: h (hearts), d (diamonds), c (clubs), s (spades).
/// Values: 2-9, T (10), J, Q, K, A.
class HandEvaluator {
  /// Parse a card string into (value, suit).
  /// Returns value as int: 2=2, ..., 9=9, T=10, J=11, Q=12, K=13, A=14.
  static int _parseValue(String card) {
    switch (card[0]) {
      case '2':
        return 2;
      case '3':
        return 3;
      case '4':
        return 4;
      case '5':
        return 5;
      case '6':
        return 6;
      case '7':
        return 7;
      case '8':
        return 8;
      case '9':
        return 9;
      case 'T':
        return 10;
      case 'J':
        return 11;
      case 'Q':
        return 12;
      case 'K':
        return 13;
      case 'A':
        return 14;
      default:
        throw ArgumentError('Invalid card value: ${card[0]}');
    }
  }

  static String _parseSuit(String card) => card[1];

  /// Build a [HandRank] from rank index and kickers.
  static HandRank _makeRank(int rank, List<int> kickers) {
    return HandRank(
      rank: rank,
      nameTh: ThaiLabels.handNames[rank] ?? '',
      nameEn: _englishNames[rank] ?? '',
      kickers: kickers,
    );
  }

  /// Evaluate the best 5-card hand from 5–7 cards (NLH).
  ///
  /// Finds the best possible 5-card combination from up to 7 cards.
  static HandRank evaluateBest5(List<String> cards) {
    assert(
      cards.length >= 5 && cards.length <= 7,
      'evaluateBest5 requires 5-7 cards, got ${cards.length}',
    );

    if (cards.length == 5) return evaluate5(cards);

    HandRank? best;
    final combos = _combinations(cards, 5);
    for (final combo in combos) {
      final rank = evaluate5(combo);
      if (best == null || compare(rank, best) > 0) {
        best = rank;
      }
    }
    return best!;
  }

  /// Evaluate an exact 5-card hand (OFC middle/back).
  static HandRank evaluate5(List<String> cards) {
    assert(cards.length == 5, 'evaluate5 requires exactly 5 cards');

    final values = cards.map(_parseValue).toList()..sort((a, b) => b - a);
    final suits = cards.map(_parseSuit).toList();

    final isFlush = suits.every((s) => s == suits[0]);
    final isStraight = _isStraight(values);
    final isWheel = _isWheel(values);

    // Count value occurrences
    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }

    // Sort groups by count desc, then value desc
    final groups = counts.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        return cmp != 0 ? cmp : b.key.compareTo(a.key);
      });

    // Royal Flush: A-K-Q-J-T all same suit
    if (isFlush && isStraight && values[0] == 14 && values[1] == 13) {
      return _makeRank(9, [14]);
    }

    // Straight Flush
    if (isFlush && (isStraight || isWheel)) {
      final high = isWheel ? 5 : values[0];
      return _makeRank(8, [high]);
    }

    // Four of a Kind
    if (groups[0].value == 4) {
      final quad = groups[0].key;
      final kicker = groups[1].key;
      return _makeRank(7, [quad, kicker]);
    }

    // Full House
    if (groups[0].value == 3 && groups[1].value == 2) {
      return _makeRank(6, [groups[0].key, groups[1].key]);
    }

    // Flush
    if (isFlush) {
      return _makeRank(5, values);
    }

    // Straight
    if (isStraight || isWheel) {
      final high = isWheel ? 5 : values[0];
      return _makeRank(4, [high]);
    }

    // Three of a Kind
    if (groups[0].value == 3) {
      final trip = groups[0].key;
      final kickers = groups.skip(1).map((e) => e.key).toList()
        ..sort((a, b) => b - a);
      return _makeRank(3, [trip, ...kickers]);
    }

    // Two Pair
    if (groups[0].value == 2 && groups[1].value == 2) {
      final highPair = groups[0].key > groups[1].key
          ? groups[0].key
          : groups[1].key;
      final lowPair = groups[0].key > groups[1].key
          ? groups[1].key
          : groups[0].key;
      final kicker = groups[2].key;
      return _makeRank(2, [highPair, lowPair, kicker]);
    }

    // One Pair
    if (groups[0].value == 2) {
      final pair = groups[0].key;
      final kickers = groups.skip(1).map((e) => e.key).toList()
        ..sort((a, b) => b - a);
      return _makeRank(1, [pair, ...kickers]);
    }

    // High Card
    return _makeRank(0, values);
  }

  /// Evaluate an exact 3-card hand (OFC front).
  ///
  /// Only High Card (0), Pair (1), and Three of a Kind (3) are possible.
  static HandRank evaluate3(List<String> cards) {
    assert(cards.length == 3, 'evaluate3 requires exactly 3 cards');

    final values = cards.map(_parseValue).toList()..sort((a, b) => b - a);

    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }

    final groups = counts.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        return cmp != 0 ? cmp : b.key.compareTo(a.key);
      });

    // Three of a Kind
    if (groups[0].value == 3) {
      return _makeRank(3, [groups[0].key]);
    }

    // Pair
    if (groups[0].value == 2) {
      final pair = groups[0].key;
      final kicker = groups[1].key;
      return _makeRank(1, [pair, kicker]);
    }

    // High Card
    return _makeRank(0, values);
  }

  /// Compare two [HandRank]s.
  ///
  /// Returns positive if [a] > [b], negative if [a] < [b], 0 if equal.
  /// Satisfies antisymmetry: compare(a,b) > 0 ⟹ compare(b,a) < 0.
  /// Satisfies reflexivity: compare(a,a) == 0.
  static int compare(HandRank a, HandRank b) {
    if (a.rank != b.rank) return a.rank - b.rank;

    // Compare kickers
    final len = a.kickers.length < b.kickers.length
        ? a.kickers.length
        : b.kickers.length;
    for (var i = 0; i < len; i++) {
      if (a.kickers[i] != b.kickers[i]) {
        return a.kickers[i] - b.kickers[i];
      }
    }
    return 0;
  }

  /// Get Thai hand name for display.
  ///
  /// Combines [holeCards] and [communityCards] and evaluates the best hand.
  static String getThaiHandName(
    List<String> holeCards,
    List<String> communityCards,
  ) {
    final allCards = [...holeCards, ...communityCards];
    if (allCards.length < 5) {
      // Not enough cards for a full hand evaluation; evaluate what we have
      if (allCards.length == 3) {
        return evaluate3(allCards).nameTh;
      }
      // For 2 or 4 cards, just return high card or pair if applicable
      return _evaluatePartial(allCards).nameTh;
    }
    return evaluateBest5(allCards).nameTh;
  }

  /// Evaluate a partial hand (2-4 cards) for display purposes.
  static HandRank _evaluatePartial(List<String> cards) {
    final values = cards.map(_parseValue).toList()..sort((a, b) => b - a);

    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }

    final groups = counts.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        return cmp != 0 ? cmp : b.key.compareTo(a.key);
      });

    if (groups[0].value >= 3) {
      return _makeRank(3, [groups[0].key]);
    }
    if (groups[0].value == 2 && groups.length >= 2 && groups[1].value == 2) {
      final highPair = groups[0].key > groups[1].key
          ? groups[0].key
          : groups[1].key;
      final lowPair = groups[0].key > groups[1].key
          ? groups[1].key
          : groups[0].key;
      return _makeRank(2, [highPair, lowPair]);
    }
    if (groups[0].value == 2) {
      final pair = groups[0].key;
      final kickers = groups.skip(1).map((e) => e.key).toList()
        ..sort((a, b) => b - a);
      return _makeRank(1, [pair, ...kickers]);
    }

    return _makeRank(0, values);
  }

  /// Check if sorted values form a straight (no wheel).
  static bool _isStraight(List<int> sortedDesc) {
    for (var i = 0; i < sortedDesc.length - 1; i++) {
      if (sortedDesc[i] - sortedDesc[i + 1] != 1) return false;
    }
    return true;
  }

  /// Check for A-2-3-4-5 wheel straight.
  static bool _isWheel(List<int> sortedDesc) {
    return sortedDesc[0] == 14 &&
        sortedDesc[1] == 5 &&
        sortedDesc[2] == 4 &&
        sortedDesc[3] == 3 &&
        sortedDesc[4] == 2;
  }

  /// Generate all combinations of [k] elements from [list].
  static List<List<String>> _combinations(List<String> list, int k) {
    final result = <List<String>>[];
    _combinationsHelper(list, k, 0, <String>[], result);
    return result;
  }

  static void _combinationsHelper(
    List<String> list,
    int k,
    int start,
    List<String> current,
    List<List<String>> result,
  ) {
    if (current.length == k) {
      result.add(List.of(current));
      return;
    }
    for (var i = start; i < list.length; i++) {
      current.add(list[i]);
      _combinationsHelper(list, k, i + 1, current, result);
      current.removeLast();
    }
  }
}
