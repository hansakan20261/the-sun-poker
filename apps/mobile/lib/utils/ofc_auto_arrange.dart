/// Auto-arrange 13 cards into optimal Front(3), Middle(5), Back(5) for Chinese Poker.
/// Tries many strategies and picks the best valid (non-foul) arrangement.
/// Ensures back >= middle >= front in hand strength.
class OFCAutoArrange {
  static const _rankValues = {
    '2': 2,
    '3': 3,
    '4': 4,
    '5': 5,
    '6': 6,
    '7': 7,
    '8': 8,
    '9': 9,
    'T': 10,
    'J': 11,
    'Q': 12,
    'K': 13,
    'A': 14,
  };

  /// Returns {'front': [...], 'middle': [...], 'back': [...]} or null if impossible.
  static Map<String, List<String>>? arrange(List<String> hand) {
    if (hand.length != 13) return null;

    final sorted = List<String>.from(hand);
    sorted.sort(
      (a, b) => (_rankValues[b[0]] ?? 0).compareTo(_rankValues[a[0]] ?? 0),
    );

    final strategies = <Map<String, List<String>>>[];

    // Strategy 1: Simple split by rank — strongest 5 back, next 5 middle, weakest 3 front
    strategies.add({
      'back': sorted.sublist(0, 5),
      'middle': sorted.sublist(5, 10),
      'front': sorted.sublist(10, 13),
    });

    // Strategy 2: Weakest pair in front, rest split by rank
    final allPairs = _findAllPairs(sorted);
    for (final pair in allPairs) {
      final remaining = _removeCards(sorted, pair);
      if (remaining.length != 11) continue;
      // Pick weakest single card for front
      final front = [...pair, remaining.last];
      final rest = remaining.sublist(0, remaining.length - 1);
      if (rest.length == 10) {
        strategies.add({
          'back': rest.sublist(0, 5),
          'middle': rest.sublist(5, 10),
          'front': front,
        });
      }
    }

    // Strategy 3: Try putting strongest pair in back with 3 high kickers
    for (final pair in allPairs.reversed) {
      final remaining = _removeCards(sorted, pair);
      if (remaining.length != 11) continue;
      final back = [...pair, remaining[0], remaining[1], remaining[2]];
      final rest = remaining.sublist(3);
      if (rest.length == 8) {
        strategies.add({
          'back': back,
          'middle': rest.sublist(0, 5),
          'front': rest.sublist(5, 8),
        });
      }
    }

    // Strategy 4: Find trips — put in back, distribute rest
    final trips = _findTrips(sorted);
    for (final trip in trips) {
      final remaining = _removeCards(sorted, trip);
      if (remaining.length != 10) continue;
      final back = [...trip, remaining[0], remaining[1]];
      final rest = remaining.sublist(2);
      if (rest.length == 8) {
        strategies.add({
          'back': back,
          'middle': rest.sublist(0, 5),
          'front': rest.sublist(5, 8),
        });
      }
    }

    // Strategy 5: Two pairs in middle, pair in front
    if (allPairs.length >= 3) {
      final frontPair = allPairs.last; // weakest pair
      final midPairs = [
        allPairs[allPairs.length - 2],
        allPairs[allPairs.length - 3],
      ];
      final usedCards = [...frontPair, ...midPairs[0], ...midPairs[1]];
      final remaining = _removeCards(sorted, usedCards);
      if (remaining.length == 13 - usedCards.length) {
        final front = [...frontPair, remaining.last];
        final midCards = [...midPairs[0], ...midPairs[1]];
        final restForMid = _removeCards(remaining, [remaining.last]);
        // Back gets strongest remaining
        if (restForMid.length >= 1) {
          final back = restForMid.sublist(0, (restForMid.length).clamp(0, 5));
          final mid = midCards.length == 4
              ? [
                  ...midCards,
                  ...restForMid.sublist(5.clamp(0, restForMid.length)),
                ]
              : midCards;
          if (back.length == 5 && mid.length == 5 && front.length == 3) {
            strategies.add({'back': back, 'middle': mid, 'front': front});
          }
        }
      }
    }

    // Strategy 6: Reverse — weakest 5 in back (for edge cases)
    strategies.add({
      'back': sorted.sublist(8, 13).reversed.toList(),
      'middle': sorted.sublist(3, 8),
      'front': sorted.sublist(0, 3),
    });

    // Strategy 7: Balanced — spread pairs across rows
    final pairRanks = <int>{};
    for (final p in allPairs) pairRanks.add(_rankValues[p[0][0]] ?? 0);
    if (pairRanks.length >= 2) {
      final pairList = pairRanks.toList()..sort((a, b) => b.compareTo(a));
      // Strongest pair in back, weakest in front
      final backPairRank = pairList[0];
      final frontPairRank = pairList.last;
      final backPair = allPairs.firstWhere(
        (p) => (_rankValues[p[0][0]] ?? 0) == backPairRank,
      );
      final frontPair = allPairs.firstWhere(
        (p) => (_rankValues[p[0][0]] ?? 0) == frontPairRank,
      );
      if (backPair != frontPair) {
        final remaining = _removeCards(sorted, [...backPair, ...frontPair]);
        if (remaining.length == 9) {
          final back = [...backPair, remaining[0], remaining[1], remaining[2]];
          final middle = remaining.sublist(3, 8);
          final front = [...frontPair, remaining[8]];
          if (back.length == 5 && middle.length == 5 && front.length == 3) {
            strategies.add({'back': back, 'middle': middle, 'front': front});
          }
        }
      }
    }

    // Evaluate: pick best valid (non-foul) arrangement
    Map<String, List<String>>? best;
    int bestScore = -99999;

    for (final s in strategies) {
      if (s['front']!.length != 3 ||
          s['middle']!.length != 5 ||
          s['back']!.length != 5)
        continue;
      if (!_isValid(s)) continue;
      final score = _evaluateArrangement(s);
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }

    // If no valid strategy found, force a safe arrangement
    if (best == null) {
      best = _forceSafeArrangement(sorted);
    }

    return best;
  }

  /// Force a safe (non-foul) arrangement by brute-force trying front combinations
  static Map<String, List<String>>? _forceSafeArrangement(List<String> sorted) {
    // Try all C(13,3) = 286 front combinations, pick best valid
    Map<String, List<String>>? best;
    int bestScore = -99999;

    for (int i = 0; i < 13; i++) {
      for (int j = i + 1; j < 13; j++) {
        for (int k = j + 1; k < 13; k++) {
          final front = [sorted[i], sorted[j], sorted[k]];
          final remaining = <String>[];
          for (int x = 0; x < 13; x++) {
            if (x != i && x != j && x != k) remaining.add(sorted[x]);
          }
          // Split remaining 10: strongest 5 back, next 5 middle
          final back = remaining.sublist(0, 5);
          final middle = remaining.sublist(5, 10);
          final arr = {'front': front, 'middle': middle, 'back': back};
          if (!_isValid(arr)) continue;
          final score = _evaluateArrangement(arr);
          if (score > bestScore) {
            bestScore = score;
            best = arr;
          }
        }
      }
    }

    // Absolute fallback — just return simple split even if foul
    return best ??
        {
          'back': sorted.sublist(0, 5),
          'middle': sorted.sublist(5, 10),
          'front': sorted.sublist(10, 13),
        };
  }

  static bool _isValid(Map<String, List<String>> arr) {
    final backScore = _handStrength(arr['back']!, 5);
    final midScore = _handStrength(arr['middle']!, 5);
    final frontScore = _handStrength(arr['front']!, 3);
    return backScore >= midScore && midScore >= frontScore;
  }

  static int _evaluateArrangement(Map<String, List<String>> arr) {
    final backStr = _handStrength(arr['back']!, 5);
    final midStr = _handStrength(arr['middle']!, 5);
    final frontStr = _handStrength(arr['front']!, 3);

    // Weighted scoring: back is most important (wins/loses most points)
    // but also reward strong front (royalties for trips, pairs QQ+)
    // and penalize wasting high cards in weak positions
    int score = backStr * 4 + midStr * 3 + frontStr * 2;

    // Bonus for royalties potential:
    // Front: pair 66+ gets royalty, trips gets big royalty
    if (frontStr >= 400)
      score += 500; // trips in front = huge bonus
    else if (frontStr >= 200 + 12)
      score += 100; // pair QQ+
    else if (frontStr >= 200 + 11)
      score += 80; // pair JJ
    else if (frontStr >= 200 + 10)
      score += 60; // pair TT
    else if (frontStr >= 200 + 6)
      score += 30; // pair 66-99

    // Middle: bonus for strong hands (flush+, full house, quads)
    if (midStr >= 700)
      score += 200; // full house in middle
    else if (midStr >= 600)
      score += 100; // flush in middle
    else if (midStr >= 500)
      score += 80; // straight in middle
    else if (midStr >= 400)
      score += 50; // trips in middle

    // Back: bonus for very strong hands
    if (backStr >= 900)
      score += 300; // straight flush
    else if (backStr >= 800)
      score += 250; // quads
    else if (backStr >= 700)
      score += 150; // full house

    // Penalty for very weak back (high card or low pair)
    if (backStr < 200)
      score -= 200; // high card back = bad
    else if (backStr < 200 + 8)
      score -= 50; // low pair back

    return score;
  }

  static int _handStrength(List<String> cards, int size) {
    final ranks = cards.map((c) => _rankValues[c[0]] ?? 0).toList()
      ..sort((a, b) => b.compareTo(a));
    final suits = cards.map((c) => c.length > 1 ? c[1] : '').toList();
    final groups = _groupRanks(ranks);

    if (size == 3) {
      if (groups[0]['count'] == 3)
        return 4000 + (groups[0]['rank'] as int) * 10;
      if (groups[0]['count'] == 2)
        return 2000 +
            (groups[0]['rank'] as int) * 10 +
            (groups.length > 1 ? groups[1]['rank'] as int : 0);
      return ranks[0] * 10 + ranks[1];
    }

    final isFlush = suits.toSet().length == 1;
    final isStraight = _isStraight(ranks);

    if (isFlush && isStraight && ranks[0] == 14 && ranks[1] == 13)
      return 10000; // Royal flush
    if (isFlush && isStraight) return 9000 + ranks[0] * 10; // Straight flush
    if (groups[0]['count'] == 4)
      return 8000 +
          (groups[0]['rank'] as int) * 10 +
          (groups.length > 1 ? groups[1]['rank'] as int : 0); // Quads
    if (groups[0]['count'] == 3 && groups.length > 1 && groups[1]['count'] == 2)
      return 7000 +
          (groups[0]['rank'] as int) * 10 +
          (groups[1]['rank'] as int); // Full house
    if (isFlush)
      return 6000 + ranks[0] * 100 + ranks[1] * 10 + ranks[2]; // Flush
    if (isStraight) return 5000 + ranks[0] * 10; // Straight
    if (groups[0]['count'] == 3)
      return 4000 +
          (groups[0]['rank'] as int) * 10 +
          (groups.length > 1 ? groups[1]['rank'] as int : 0); // Trips
    if (groups[0]['count'] == 2 &&
        groups.length > 1 &&
        groups[1]['count'] == 2) {
      // Two pair — use both pair ranks + kicker for better comparison
      return 3000 +
          (groups[0]['rank'] as int) * 100 +
          (groups[1]['rank'] as int) * 10 +
          (groups.length > 2 ? groups[2]['rank'] as int : 0);
    }
    if (groups[0]['count'] == 2)
      return 2000 +
          (groups[0]['rank'] as int) * 100 +
          ranks
              .where((r) => r != groups[0]['rank'])
              .fold(0, (sum, r) => sum + r); // One pair
    return ranks[0] * 100 + ranks[1] * 10 + ranks[2]; // High card
  }

  static bool _isStraight(List<int> ranks) {
    if (ranks.length != 5) return false;
    for (int i = 0; i < 4; i++) {
      if (ranks[i] - ranks[i + 1] != 1) {
        if (i == 0 &&
            ranks[0] == 14 &&
            ranks[1] == 5 &&
            ranks[2] == 4 &&
            ranks[3] == 3 &&
            ranks[4] == 2)
          return true;
        return false;
      }
    }
    return true;
  }

  static List<Map<String, dynamic>> _groupRanks(List<int> ranks) {
    final map = <int, int>{};
    for (final r in ranks) map[r] = (map[r] ?? 0) + 1;
    final groups = map.entries
        .map((e) => {'rank': e.key, 'count': e.value})
        .toList();
    groups.sort((a, b) {
      final cmp = (b['count'] as int).compareTo(a['count'] as int);
      return cmp != 0 ? cmp : (b['rank'] as int).compareTo(a['rank'] as int);
    });
    return groups;
  }

  /// Find all pairs in sorted cards
  static List<List<String>> _findAllPairs(List<String> cards) {
    final pairs = <List<String>>[];
    for (int i = 0; i < cards.length - 1; i++) {
      if (cards[i][0] == cards[i + 1][0]) {
        pairs.add([cards[i], cards[i + 1]]);
        i++;
      }
    }
    return pairs;
  }

  /// Find all trips in sorted cards
  static List<List<String>> _findTrips(List<String> cards) {
    final trips = <List<String>>[];
    for (int i = 0; i < cards.length - 2; i++) {
      if (cards[i][0] == cards[i + 1][0] &&
          cards[i + 1][0] == cards[i + 2][0]) {
        trips.add([cards[i], cards[i + 1], cards[i + 2]]);
        i += 2;
      }
    }
    return trips;
  }

  /// Remove specific cards from a list
  static List<String> _removeCards(List<String> from, List<String> toRemove) {
    final remaining = List<String>.from(from);
    for (final c in toRemove) remaining.remove(c);
    return remaining;
  }

  static String getDescription(Map<String, List<String>> arr) {
    final backName = _handName(_handStrength(arr['back']!, 5));
    final midName = _handName(_handStrength(arr['middle']!, 5));
    final frontName = _handName(_handStrength(arr['front']!, 3));
    return 'กองหลัง: $backName | กองกลาง: $midName | กองหน้า: $frontName';
  }

  static String _handName(int strength) {
    if (strength >= 10000) return 'รอยัลฟลัช';
    if (strength >= 9000) return 'สเตรทฟลัช';
    if (strength >= 8000) return 'โฟร์ออฟอะไคนด์';
    if (strength >= 7000) return 'ฟูลเฮาส์';
    if (strength >= 6000) return 'ฟลัช';
    if (strength >= 5000) return 'สเตรท';
    if (strength >= 4000) return 'ทริปส์';
    if (strength >= 3000) return 'สองคู่';
    if (strength >= 2000) return 'คู่';
    return 'ไฮการ์ด';
  }
}
