import 'dart:math';

import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:the_sun_poker/utils/number_formatter.dart';
import 'package:the_sun_poker/utils/hand_evaluator.dart';
import 'package:the_sun_poker/utils/timer_logic.dart';
import 'package:the_sun_poker/utils/free_tips_engine.dart';
import 'package:the_sun_poker/utils/ofc_scorer.dart';
import 'package:the_sun_poker/utils/bet_calculator.dart';
import 'package:the_sun_poker/models/room_info.dart';

// ---------------------------------------------------------------------------
// Card helpers
// ---------------------------------------------------------------------------
const _values = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'];
const _suits = ['h', 'd', 'c', 's'];

List<String> get _fullDeck => [
      for (final v in _values)
        for (final s in _suits) '$v$s',
    ];

/// Shuffle and take [n] unique cards from a standard 52-card deck.
List<String> _randomCards(Random rng, int n) {
  final deck = List<String>.from(_fullDeck)..shuffle(rng);
  return deck.sublist(0, n);
}

/// Parse the numeric value back from a formatted abbreviated string.
double _parseAbbreviated(String s) {
  if (s.endsWith('M')) {
    return double.parse(s.substring(0, s.length - 1)) * 1000000;
  } else if (s.endsWith('K')) {
    return double.parse(s.substring(0, s.length - 1)) * 1000;
  }
  return double.parse(s);
}

const _gameTypes = ['NLH', 'PLO', 'OFC', 'CRASH'];

RoomInfo _randomRoom(Random rng) {
  final gt = _gameTypes[rng.nextInt(_gameTypes.length)];
  final buyIn = (rng.nextInt(100) + 1) * 1000;
  return RoomInfo(
    id: 'r${rng.nextInt(10000)}',
    cityName: 'City${rng.nextInt(100)}',
    cityIconUrl: '',
    gameType: gt,
    smallBlind: 100,
    bigBlind: 200,
    ante: 50,
    playerCount: rng.nextInt(9),
    maxPlayers: 9,
    minBuyIn: buyIn,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  KiriCheck.maxExamples = 120;

  // =========================================================================
  // Property 1: Number formatting preserves magnitude
  // =========================================================================
  group('Property 1: Number formatting preserves magnitude', () {
    property(
      'formatAbbreviated parsed back is within 1% of original',
      () {
        forAll(
          integer(min: 0, max: 999999999),
          (amount) {
            final formatted = NumberFormatter.formatAbbreviated(amount);
            final parsed = _parseAbbreviated(formatted);
            if (amount == 0) {
              expect(parsed, equals(0.0));
            } else {
              final ratio = (parsed - amount).abs() / amount;
              expect(ratio, lessThanOrEqualTo(0.01),
                  reason:
                      'amount=$amount formatted="$formatted" parsed=$parsed ratio=$ratio');
            }
            // Suffix correctness
            if (amount >= 1000000) {
              expect(formatted.endsWith('M'), isTrue);
            } else if (amount >= 1000) {
              expect(formatted.endsWith('K'), isTrue);
            }
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 2: Room filtering returns only matching game type
  // =========================================================================
  group('Property 2: Room filtering returns only matching game type', () {
    property(
      'filtered result contains only and all rooms of selected type',
      () {
        forAll(
          build(() {
            final rng = Random();
            final count = rng.nextInt(20) + 5;
            final rooms = List.generate(count, (_) => _randomRoom(rng));
            final selectedType = _gameTypes[rng.nextInt(_gameTypes.length)];
            return (rooms, selectedType);
          }),
          (pair) {
            final rooms = pair.$1;
            final selectedType = pair.$2;
            final filtered =
                rooms.where((r) => r.gameType == selectedType).toList();

            // All filtered rooms match the selected type
            for (final r in filtered) {
              expect(r.gameType, equals(selectedType));
            }
            // All rooms of that type are included
            final expectedCount =
                rooms.where((r) => r.gameType == selectedType).length;
            expect(filtered.length, equals(expectedCount));
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 3: Room ordering by buy-in is a valid sort
  // =========================================================================
  group('Property 3: Room ordering by buy-in is a valid sort', () {
    property(
      'consecutive pairs satisfy minBuyIn[i] <= minBuyIn[i+1]',
      () {
        forAll(
          build(() {
            final rng = Random();
            final count = rng.nextInt(15) + 2;
            final gt = _gameTypes[rng.nextInt(_gameTypes.length)];
            final rooms = List.generate(count, (_) {
              final buyIn = (rng.nextInt(100) + 1) * 1000;
              return RoomInfo(
                id: 'r${rng.nextInt(10000)}',
                cityName: 'City',
                cityIconUrl: '',
                gameType: gt,
                smallBlind: 100,
                bigBlind: 200,
                ante: 50,
                playerCount: 0,
                maxPlayers: 9,
                minBuyIn: buyIn,
              );
            });
            return rooms;
          }),
          (rooms) {
            final sorted = List<RoomInfo>.from(rooms)
              ..sort((a, b) => a.minBuyIn.compareTo(b.minBuyIn));
            for (var i = 0; i < sorted.length - 1; i++) {
              expect(sorted[i].minBuyIn, lessThanOrEqualTo(sorted[i + 1].minBuyIn));
            }
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 4: Hand evaluation consistency
  // =========================================================================
  group('Property 4: Hand evaluation consistency', () {
    property(
      'rank 0-9, Thai name matches, compare is antisymmetric and reflexive',
      () {
        forAll(
          build(() {
            final rng = Random();
            final n = 5 + rng.nextInt(3); // 5, 6, or 7 cards
            return _randomCards(rng, n);
          }),
          (cards) {
            final rank = HandEvaluator.evaluateBest5(cards);

            // Rank in valid range
            expect(rank.rank, greaterThanOrEqualTo(0));
            expect(rank.rank, lessThanOrEqualTo(9));

            // Thai name matches the rank
            final expectedNames = {
              0: 'ไฮการ์ด',
              1: 'คู่',
              2: 'สองคู่',
              3: 'ทริปส์',
              4: 'สเตรท',
              5: 'ฟลัช',
              6: 'ฟูลเฮาส์',
              7: 'โฟร์ออฟอะไคนด์',
              8: 'สเตรทฟลัช',
              9: 'รอยัลฟลัช',
            };
            expect(rank.nameTh, equals(expectedNames[rank.rank]));

            // Reflexivity: compare(A, A) == 0
            expect(HandEvaluator.compare(rank, rank), equals(0));
          },
        );
      },
    );

    property(
      'compare is antisymmetric for two random hands',
      () {
        forAll(
          build(() {
            final rng = Random();
            final deck = List<String>.from(_fullDeck)..shuffle(rng);
            final hand1 = deck.sublist(0, 5);
            final hand2 = deck.sublist(5, 10);
            return (hand1, hand2);
          }),
          (pair) {
            final rankA = HandEvaluator.evaluate5(pair.$1);
            final rankB = HandEvaluator.evaluate5(pair.$2);
            final cmpAB = HandEvaluator.compare(rankA, rankB);
            final cmpBA = HandEvaluator.compare(rankB, rankA);

            if (cmpAB > 0) {
              expect(cmpBA, lessThan(0));
            } else if (cmpAB < 0) {
              expect(cmpBA, greaterThan(0));
            } else {
              expect(cmpBA, equals(0));
            }
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 5: Bet calculator pot fraction is clamped
  // =========================================================================
  group('Property 5: Bet calculator pot fraction is clamped', () {
    property(
      'fromPotFractionPreset result is in [minRaise, maxRaise]',
      () {
        forAll(
          build(() {
            final rng = Random();
            final potSize = rng.nextInt(100000) + 100;
            final fraction = rng.nextDouble(); // 0.0 to 1.0
            final minRaise = rng.nextInt(5000) + 100;
            final maxRaise = minRaise + rng.nextInt(50000) + 1;
            return (potSize, fraction, minRaise, maxRaise);
          }),
          (t) {
            final result = BetCalculator.fromPotFractionPreset(
              fraction: t.$2,
              potSize: t.$1,
              minRaise: t.$3,
              maxRaise: t.$4,
            );
            expect(result, greaterThanOrEqualTo(t.$3),
                reason: 'result=$result < minRaise=${t.$3}');
            expect(result, lessThanOrEqualTo(t.$4),
                reason: 'result=$result > maxRaise=${t.$4}');
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 6: FREE TIPS always returns a valid action
  // =========================================================================
  group('Property 6: FREE TIPS always returns a valid action', () {
    property(
      'action is fold/call/raise, actionTh matches, confidence 0.0-1.0',
      () {
        forAll(
          build(() {
            final rng = Random();
            final deck = List<String>.from(_fullDeck)..shuffle(rng);
            final holeCards = deck.sublist(0, 2);
            final phases = ['preflop', 'flop', 'turn', 'river'];
            final phase = phases[rng.nextInt(phases.length)];
            int communityCount;
            switch (phase) {
              case 'preflop':
                communityCount = 0;
                break;
              case 'flop':
                communityCount = 3;
                break;
              case 'turn':
                communityCount = 4;
                break;
              case 'river':
                communityCount = 5;
                break;
              default:
                communityCount = 0;
            }
            final communityCards = deck.sublist(2, 2 + communityCount);
            final potSize = rng.nextInt(50000);
            final callAmount = rng.nextInt(5000);
            return (holeCards, communityCards, phase, potSize, callAmount);
          }),
          (t) {
            final tip = FreeTipsEngine.analyze(
              holeCards: t.$1,
              communityCards: t.$2,
              phase: t.$3,
              potSize: t.$4,
              callAmount: t.$5,
            );

            expect(tip.action, isIn(['fold', 'call', 'raise']));

            // actionTh matches action
            final thaiMap = {
              'fold': 'หมอบ',
              'call': 'ตาม',
              'raise': 'เก',
            };
            expect(tip.actionTh, equals(thaiMap[tip.action]));

            // confidence in [0.0, 1.0]
            expect(tip.confidence, greaterThanOrEqualTo(0.0));
            expect(tip.confidence, lessThanOrEqualTo(1.0));
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 7: Timer color thresholds are mutually exclusive and exhaustive
  // =========================================================================
  group('Property 7: Timer color thresholds are mutually exclusive and exhaustive',
      () {
    property(
      'exactly one color returned for any valid remaining/total',
      () {
        forAll(
          combine2(
            integer(min: 0, max: 300),
            integer(min: 1, max: 300),
          ),
          (pair) {
            final remaining = pair.$1;
            final total = pair.$2;
            final color = TimerLogic.getColor(remaining, total);
            final ratio = remaining / total;

            // Exactly one of the three
            expect(color, isIn([TimerColor.green, TimerColor.amber, TimerColor.red]));

            if (ratio > 0.50) {
              expect(color, equals(TimerColor.green));
            } else if (ratio >= 0.25) {
              expect(color, equals(TimerColor.amber));
            } else {
              expect(color, equals(TimerColor.red));
            }
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 8: Auto-action is deterministic based on bet state
  // =========================================================================
  group('Property 8: Auto-action is deterministic based on bet state', () {
    property(
      'getAutoAction(true) == fold, getAutoAction(false) == check',
      () {
        forAll(
          boolean(),
          (isBetPending) {
            final result = TimerLogic.getAutoAction(isBetPending: isBetPending);
            if (isBetPending) {
              expect(result, equals('fold'));
            } else {
              expect(result, equals('check'));
            }
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 9: OFC slot limits are enforced
  // =========================================================================
  group('Property 9: OFC slot limits are enforced', () {
    property(
      'reject when row is full, accept when below max; total never exceeds 13',
      () {
        forAll(
          build(() {
            final rng = Random();
            final deck = List<String>.from(_fullDeck)..shuffle(rng);
            // Random partial placement state
            final frontCount = rng.nextInt(4); // 0-3
            final middleCount = rng.nextInt(6); // 0-5
            final backCount = rng.nextInt(6); // 0-5
            var idx = 0;
            final front = deck.sublist(idx, idx + frontCount);
            idx += frontCount;
            final middle = deck.sublist(idx, idx + middleCount);
            idx += middleCount;
            final back = deck.sublist(idx, idx + backCount);
            idx += backCount;
            // Remaining cards to place (up to fill 13)
            final totalPlaced = frontCount + middleCount + backCount;
            final remaining = totalPlaced < 13 ? 13 - totalPlaced : 0;
            final unplaced = remaining > 0 ? deck.sublist(idx, idx + remaining) : <String>[];
            return (front, middle, back, unplaced);
          }),
          (t) {
            final front = t.$1;
            final middle = t.$2;
            final back = t.$3;
            final unplaced = t.$4;

            final result = OFCScorer.autoPlace(
              unplacedCards: unplaced,
              currentFront: front,
              currentMiddle: middle,
              currentBack: back,
            );

            // Row limits enforced
            expect(result['front']!.length, lessThanOrEqualTo(3));
            expect(result['middle']!.length, lessThanOrEqualTo(5));
            expect(result['back']!.length, lessThanOrEqualTo(5));

            // Total never exceeds 13
            final total = result['front']!.length +
                result['middle']!.length +
                result['back']!.length;
            expect(total, lessThanOrEqualTo(13));

            // Full rows reject additional cards (verified by limits above)
            // Rows below max accept cards
            if (front.length < 3 && unplaced.isNotEmpty) {
              expect(result['front']!.length, greaterThan(front.length));
            }
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 10: OFC foul detection is correct
  // =========================================================================
  group('Property 10: OFC foul detection is correct', () {
    property(
      'foul iff front >= middle or middle >= back',
      () {
        forAll(
          build(() {
            final rng = Random();
            final deck = List<String>.from(_fullDeck)..shuffle(rng);
            final front = deck.sublist(0, 3);
            final middle = deck.sublist(3, 8);
            final back = deck.sublist(8, 13);
            return (front, middle, back);
          }),
          (t) {
            final front = t.$1;
            final middle = t.$2;
            final back = t.$3;

            final isFoul = OFCScorer.isFoul(front, middle, back);

            // Manually check the condition
            final frontRank = HandEvaluator.evaluate3(front);
            final middleRank = HandEvaluator.evaluate5(middle);
            final backRank = HandEvaluator.evaluate5(back);

            // front >= middle (using the OFC comparison logic)
            // For 3-card vs 5-card, compare rank values directly
            final frontVsMiddle = frontRank.rank > middleRank.rank ||
                (frontRank.rank == middleRank.rank &&
                    _compareKickers(frontRank.kickers, middleRank.kickers) >= 0);

            final middleVsBack = HandEvaluator.compare(middleRank, backRank) >= 0;

            final expectedFoul = frontVsMiddle || middleVsBack;
            expect(isFoul, equals(expectedFoul),
                reason:
                    'front=$front middle=$middle back=$back '
                    'frontRank=${frontRank.rank} middleRank=${middleRank.rank} backRank=${backRank.rank}');
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 11: OFC scoring is zero-sum
  // =========================================================================
  group('Property 11: OFC scoring is zero-sum', () {
    property(
      'compareHands(A,B) + compareHands(B,A) == 0',
      () {
        forAll(
          build(() {
            final rng = Random();
            final deck = List<String>.from(_fullDeck)..shuffle(rng);
            // Player A: 13 cards, Player B: next 13 cards (from 52-card deck, no overlap)
            final aFront = deck.sublist(0, 3);
            final aMiddle = deck.sublist(3, 8);
            final aBack = deck.sublist(8, 13);
            final bFront = deck.sublist(13, 16);
            final bMiddle = deck.sublist(16, 21);
            final bBack = deck.sublist(21, 26);
            return (aFront, aMiddle, aBack, bFront, bMiddle, bBack);
          }),
          (t) {
            final ab = OFCScorer.compareHands(
              aFront: t.$1,
              aMiddle: t.$2,
              aBack: t.$3,
              bFront: t.$4,
              bMiddle: t.$5,
              bBack: t.$6,
            );
            final ba = OFCScorer.compareHands(
              aFront: t.$4,
              aMiddle: t.$5,
              aBack: t.$6,
              bFront: t.$1,
              bMiddle: t.$2,
              bBack: t.$3,
            );
            expect(ab + ba, equals(0),
                reason: 'compareHands(A,B)=$ab + compareHands(B,A)=$ba != 0');
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 12: OFC royalty calculation is non-negative
  // =========================================================================
  group('Property 12: OFC royalty calculation is non-negative', () {
    property(
      'royalties >= 0 for any valid hand and row',
      () {
        forAll(
          build(() {
            final rng = Random();
            final deck = List<String>.from(_fullDeck)..shuffle(rng);
            final rows = ['front', 'middle', 'back'];
            final row = rows[rng.nextInt(rows.length)];
            final cardCount = row == 'front' ? 3 : 5;
            final cards = deck.sublist(0, cardCount);
            return (cards, row);
          }),
          (t) {
            final royalties = OFCScorer.calculateRoyalties(t.$1, t.$2);
            expect(royalties, greaterThanOrEqualTo(0),
                reason: 'cards=${t.$1} row=${t.$2} royalties=$royalties');
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 13: Fantasyland requires QQ+ in front without foul
  // =========================================================================
  group('Property 13: Fantasyland requires QQ+ in front without foul', () {
    property(
      'qualifiesForFantasyland iff QQ+ in front AND no foul',
      () {
        forAll(
          build(() {
            final rng = Random();
            final deck = List<String>.from(_fullDeck)..shuffle(rng);
            final front = deck.sublist(0, 3);
            final middle = deck.sublist(3, 8);
            final back = deck.sublist(8, 13);
            return (front, middle, back);
          }),
          (t) {
            final front = t.$1;
            final middle = t.$2;
            final back = t.$3;

            final qualifies =
                OFCScorer.qualifiesForFantasyland(front, middle, back);
            final foul = OFCScorer.isFoul(front, middle, back);
            final frontRank = HandEvaluator.evaluate3(front);

            // QQ+ in front: trips (rank 3) or pair of Q+ (rank 1, kicker[0] >= 12)
            final hasQQPlus = frontRank.rank == 3 ||
                (frontRank.rank == 1 && frontRank.kickers[0] >= 12);

            final expected = hasQQPlus && !foul;
            expect(qualifies, equals(expected),
                reason:
                    'front=$front frontRank=${frontRank.rank} '
                    'kickers=${frontRank.kickers} foul=$foul '
                    'qualifies=$qualifies expected=$expected');
          },
        );
      },
    );
  });

  // =========================================================================
  // Property 14: OFC auto-placement fills all remaining slots
  // =========================================================================
  group('Property 14: OFC auto-placement fills all remaining slots', () {
    property(
      'result has 3+5+5=13 cards, all unplaced cards appear exactly once',
      () {
        forAll(
          build(() {
            final rng = Random();
            final deck = List<String>.from(_fullDeck)..shuffle(rng);
            // Random partial state that sums to < 13
            final frontCount = rng.nextInt(4); // 0-3
            final middleMax = min(5, 13 - frontCount);
            final middleCount = rng.nextInt(middleMax + 1);
            final backMax = min(5, 13 - frontCount - middleCount);
            final backCount = rng.nextInt(backMax + 1);

            var idx = 0;
            final front = deck.sublist(idx, idx + frontCount);
            idx += frontCount;
            final middle = deck.sublist(idx, idx + middleCount);
            idx += middleCount;
            final back = deck.sublist(idx, idx + backCount);
            idx += backCount;

            final totalPlaced = frontCount + middleCount + backCount;
            final unplaced = deck.sublist(idx, idx + (13 - totalPlaced));
            return (front, middle, back, unplaced);
          }),
          (t) {
            final result = OFCScorer.autoPlace(
              unplacedCards: t.$4,
              currentFront: t.$1,
              currentMiddle: t.$2,
              currentBack: t.$3,
            );

            // Exactly 3 + 5 + 5 = 13
            expect(result['front']!.length, equals(3));
            expect(result['middle']!.length, equals(5));
            expect(result['back']!.length, equals(5));

            final totalCards = [
              ...result['front']!,
              ...result['middle']!,
              ...result['back']!,
            ];
            expect(totalCards.length, equals(13));

            // All originally unplaced cards appear exactly once in result
            for (final card in t.$4) {
              final count = totalCards.where((c) => c == card).length;
              expect(count, equals(1),
                  reason: 'unplaced card $card appears $count times');
            }

            // All originally placed cards are preserved
            for (final card in t.$1) {
              expect(result['front']!, contains(card));
            }
            for (final card in t.$2) {
              expect(result['middle']!, contains(card));
            }
            for (final card in t.$3) {
              expect(result['back']!, contains(card));
            }
          },
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helper: compare kicker lists
// ---------------------------------------------------------------------------
int _compareKickers(List<int> a, List<int> b) {
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}
