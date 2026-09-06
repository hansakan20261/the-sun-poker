import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/utils/ofc_scorer.dart';

void main() {
  group('OFCScorer.isFoul', () {
    test('returns false for valid ordering: front < middle < back', () {
      // Front: pair of 2s, Middle: two pair, Back: flush
      final front = ['2h', '2d', '5c'];
      final middle = ['Ah', 'Ad', 'Kh', 'Kd', '3c'];
      final back = ['2s', '4s', '6s', '8s', 'Ts'];
      expect(OFCScorer.isFoul(front, middle, back), false);
    });

    test('returns true when front >= middle', () {
      // Front: pair of Aces, Middle: pair of 2s with low kickers
      final front = ['Ah', 'Ad', '3c'];
      final middle = ['2h', '2d', '4c', '5s', '6h'];
      final back = ['Ks', 'Kd', 'Kc', '7h', '7d'];
      expect(OFCScorer.isFoul(front, middle, back), true);
    });

    test('returns true when middle >= back', () {
      // Front: high card, Middle: flush, Back: pair
      final front = ['2h', '5d', '7c'];
      final middle = ['Ah', 'Kh', 'Qh', 'Jh', '9h'];
      final back = ['3s', '3d', '4c', '6h', '8d'];
      expect(OFCScorer.isFoul(front, middle, back), true);
    });

    test('returns true when front equals middle in strength', () {
      // Front: trips 5s (rank 3), Middle: trips 5s (rank 3) — same rank = foul
      final front = ['5h', '5d', '5c'];
      final middle = ['5s', '4c', '4h', '4d', '6s'];
      final back = ['Ah', 'Ad', 'Ac', 'Kh', 'Kd'];
      expect(OFCScorer.isFoul(front, middle, back), true);
    });
  });

  group('OFCScorer.calculateRoyalties', () {
    group('front hand', () {
      test('returns 0 for pairs below 66', () {
        expect(OFCScorer.calculateRoyalties(['2h', '2d', '5c'], 'front'), 0);
        expect(OFCScorer.calculateRoyalties(['5h', '5d', '3c'], 'front'), 0);
      });

      test('returns correct royalties for pairs 66 through AA', () {
        expect(OFCScorer.calculateRoyalties(['6h', '6d', '2c'], 'front'), 1);
        expect(OFCScorer.calculateRoyalties(['7h', '7d', '2c'], 'front'), 2);
        expect(OFCScorer.calculateRoyalties(['8h', '8d', '2c'], 'front'), 3);
        expect(OFCScorer.calculateRoyalties(['9h', '9d', '2c'], 'front'), 4);
        expect(OFCScorer.calculateRoyalties(['Th', 'Td', '2c'], 'front'), 5);
        expect(OFCScorer.calculateRoyalties(['Jh', 'Jd', '2c'], 'front'), 6);
        expect(OFCScorer.calculateRoyalties(['Qh', 'Qd', '2c'], 'front'), 7);
        expect(OFCScorer.calculateRoyalties(['Kh', 'Kd', '2c'], 'front'), 8);
        expect(OFCScorer.calculateRoyalties(['Ah', 'Ad', '2c'], 'front'), 9);
      });

      test('returns correct royalties for trips', () {
        expect(OFCScorer.calculateRoyalties(['2h', '2d', '2c'], 'front'), 10);
        expect(OFCScorer.calculateRoyalties(['3h', '3d', '3c'], 'front'), 11);
        expect(OFCScorer.calculateRoyalties(['Ah', 'Ad', 'Ac'], 'front'), 22);
      });

      test('returns 0 for high card', () {
        expect(OFCScorer.calculateRoyalties(['Ah', 'Kd', '2c'], 'front'), 0);
      });
    });

    group('middle hand', () {
      test('returns 0 for high card, pair, two pair', () {
        expect(OFCScorer.calculateRoyalties(['Ah', 'Kd', 'Qc', 'Js', '9h'], 'middle'), 0);
        expect(OFCScorer.calculateRoyalties(['Ah', 'Ad', '3c', '5s', '7h'], 'middle'), 0);
        expect(OFCScorer.calculateRoyalties(['Ah', 'Ad', 'Kc', 'Ks', '7h'], 'middle'), 0);
      });

      test('returns 2 for three of a kind', () {
        expect(OFCScorer.calculateRoyalties(['5h', '5d', '5c', '2s', '3h'], 'middle'), 2);
      });

      test('returns 4 for straight', () {
        expect(OFCScorer.calculateRoyalties(['5h', '6d', '7c', '8s', '9h'], 'middle'), 4);
      });

      test('returns 8 for flush', () {
        expect(OFCScorer.calculateRoyalties(['2h', '4h', '6h', '8h', 'Th'], 'middle'), 8);
      });

      test('returns 12 for full house', () {
        expect(OFCScorer.calculateRoyalties(['5h', '5d', '5c', '3s', '3h'], 'middle'), 12);
      });

      test('returns 20 for four of a kind', () {
        expect(OFCScorer.calculateRoyalties(['5h', '5d', '5c', '5s', '3h'], 'middle'), 20);
      });

      test('returns 30 for straight flush', () {
        expect(OFCScorer.calculateRoyalties(['5h', '6h', '7h', '8h', '9h'], 'middle'), 30);
      });

      test('returns 50 for royal flush', () {
        expect(OFCScorer.calculateRoyalties(['Ah', 'Kh', 'Qh', 'Jh', 'Th'], 'middle'), 50);
      });
    });

    group('back hand', () {
      test('returns 0 for hands below straight', () {
        expect(OFCScorer.calculateRoyalties(['Ah', 'Kd', 'Qc', 'Js', '9h'], 'back'), 0);
        expect(OFCScorer.calculateRoyalties(['5h', '5d', '5c', '2s', '3h'], 'back'), 0);
      });

      test('returns 2 for straight', () {
        expect(OFCScorer.calculateRoyalties(['5h', '6d', '7c', '8s', '9h'], 'back'), 2);
      });

      test('returns 4 for flush', () {
        expect(OFCScorer.calculateRoyalties(['2h', '4h', '6h', '8h', 'Th'], 'back'), 4);
      });

      test('returns 6 for full house', () {
        expect(OFCScorer.calculateRoyalties(['5h', '5d', '5c', '3s', '3h'], 'back'), 6);
      });

      test('returns 10 for four of a kind', () {
        expect(OFCScorer.calculateRoyalties(['5h', '5d', '5c', '5s', '3h'], 'back'), 10);
      });

      test('returns 15 for straight flush', () {
        expect(OFCScorer.calculateRoyalties(['5h', '6h', '7h', '8h', '9h'], 'back'), 15);
      });

      test('returns 25 for royal flush', () {
        expect(OFCScorer.calculateRoyalties(['Ah', 'Kh', 'Qh', 'Jh', 'Th'], 'back'), 25);
      });
    });

    test('returns 0 for invalid row', () {
      expect(OFCScorer.calculateRoyalties(['Ah', 'Kh', 'Qh', 'Jh', 'Th'], 'invalid'), 0);
    });
  });

  group('OFCScorer.compareHands', () {
    test('returns 0 when both players foul', () {
      // Both have front >= middle (foul)
      final result = OFCScorer.compareHands(
        aFront: ['Ah', 'Ad', '3c'],
        aMiddle: ['2h', '2d', '4c', '5s', '6h'],
        aBack: ['Ks', 'Kd', 'Kc', '7h', '7d'],
        bFront: ['Kh', 'Kd', '3s'],
        bMiddle: ['2s', '2c', '4h', '5d', '6c'],
        bBack: ['As', 'Ac', 'Ah', '8h', '8d'],
      );
      expect(result, 0);
    });

    test('A wins +6 + royalties when B fouls', () {
      // A: valid hand, B: fouled
      final result = OFCScorer.compareHands(
        aFront: ['2h', '3d', '5c'],
        aMiddle: ['6h', '6d', '7c', '8s', '9h'],
        aBack: ['Ah', 'Ad', 'Kh', 'Kd', 'Qc'],
        bFront: ['Ah', 'Ad', '3c'],       // foul: front pair AA >= middle pair 2s
        bMiddle: ['2h', '2d', '4c', '5s', '6h'],
        bBack: ['Ks', 'Kd', 'Kc', '7h', '7d'],
      );
      // A gets +6 (scoop) + A's royalties
      expect(result, greaterThan(0));
      expect(result, greaterThanOrEqualTo(6));
    });

    test('B wins when A fouls (negative result)', () {
      final result = OFCScorer.compareHands(
        aFront: ['Ah', 'Ad', '3c'],       // foul
        aMiddle: ['2h', '2d', '4c', '5s', '6h'],
        aBack: ['Ks', 'Kd', 'Kc', '7h', '7d'],
        bFront: ['2h', '3d', '5c'],
        bMiddle: ['6h', '6d', '7c', '8s', '9h'],
        bBack: ['Ah', 'Ad', 'Kh', 'Kd', 'Qc'],
      );
      expect(result, lessThan(0));
      expect(result, lessThanOrEqualTo(-6));
    });

    test('scoring is zero-sum (A vs B + B vs A == 0)', () {
      final aFront = ['2h', '3d', '5c'];
      final aMiddle = ['6h', '6d', '7c', '7s', '9h'];
      final aBack = ['Ah', 'Ad', 'Kh', 'Kd', 'Qc'];
      final bFront = ['4h', '4d', '2c'];
      final bMiddle = ['8h', '8d', '9c', 'Ts', 'Jh'];
      final bBack = ['Qs', 'Qd', 'Qc', '3h', '3d'];

      final aVsB = OFCScorer.compareHands(
        aFront: aFront, aMiddle: aMiddle, aBack: aBack,
        bFront: bFront, bMiddle: bMiddle, bBack: bBack,
      );
      final bVsA = OFCScorer.compareHands(
        aFront: bFront, aMiddle: bMiddle, aBack: bBack,
        bFront: aFront, bMiddle: aMiddle, bBack: aBack,
      );
      expect(aVsB + bVsA, 0);
    });

    test('scoop bonus when winning all 3 rows', () {
      // A has clearly stronger hands in all rows
      final result = OFCScorer.compareHands(
        aFront: ['Ah', 'Kd', 'Qc'],       // High card AKQ
        aMiddle: ['Th', 'Td', 'Tc', '2s', '3h'], // Trips
        aBack: ['Jh', 'Jd', 'Jc', 'Js', '4h'],   // Quads
        bFront: ['2h', '3d', '4c'],        // High card 432
        bMiddle: ['5h', '5d', '6c', '7s', '8h'],  // Pair
        bBack: ['9h', '9d', 'Tc', 'Ts', '2c'],    // Two pair
      );
      // A wins all 3 rows: +3 base + 3 scoop = +6, plus royalty difference
      expect(result, greaterThanOrEqualTo(6));
    });
  });

  group('OFCScorer.qualifiesForFantasyland', () {
    test('returns true for QQ in front without foul', () {
      final result = OFCScorer.qualifiesForFantasyland(
        ['Qh', 'Qd', '2c'],
        ['5h', '6d', '7c', '8s', '9h'],       // straight (rank 4)
        ['Ah', 'Kh', 'Qh', 'Jh', 'Th'],       // royal flush (rank 9)
      );
      expect(result, true);
    });

    test('returns true for KK in front without foul', () {
      final result = OFCScorer.qualifiesForFantasyland(
        ['Kh', 'Kd', '2c'],
        ['5h', '6d', '7c', '8s', '9h'],       // straight (rank 4)
        ['Ah', 'Ad', 'Ac', '3d', '3c'],       // full house (rank 6)
      );
      expect(result, true);
    });

    test('returns true for AA in front without foul', () {
      final result = OFCScorer.qualifiesForFantasyland(
        ['Ah', 'Ad', '2c'],
        ['5h', '6d', '7c', '8s', '9h'],       // straight (rank 4)
        ['Kh', 'Kd', 'Kc', '3s', '3h'],      // full house (rank 6)
      );
      expect(result, true);
    });

    test('returns true for trips in front without foul', () {
      final result = OFCScorer.qualifiesForFantasyland(
        ['2h', '2d', '2c'],                   // trips (rank 3)
        ['5h', '6d', '7c', '8s', '9h'],       // straight (rank 4)
        ['Ah', 'Ad', 'Ac', 'Kd', 'Kc'],      // full house (rank 6)
      );
      expect(result, true);
    });

    test('returns false for JJ in front (below QQ)', () {
      final result = OFCScorer.qualifiesForFantasyland(
        ['Jh', 'Jd', '2c'],
        ['5h', '6d', '7c', '8s', '9h'],
        ['Ah', 'Ad', 'Kh', 'Kd', 'Qc'],
      );
      expect(result, false);
    });

    test('returns false for high card in front', () {
      final result = OFCScorer.qualifiesForFantasyland(
        ['Ah', 'Kd', 'Qc'],
        ['5h', '6d', '7c', '8s', '9h'],
        ['Jh', 'Jd', 'Jc', 'Js', '2h'],
      );
      expect(result, false);
    });

    test('returns false when QQ in front but hand fouls', () {
      // QQ in front but front >= middle (foul)
      final result = OFCScorer.qualifiesForFantasyland(
        ['Qh', 'Qd', 'Ac'],
        ['2h', '3d', '4c', '5s', '7h'],  // high card — weaker than QQ pair
        ['Ah', 'Ad', 'Kh', 'Kd', 'Qc'],
      );
      expect(result, false);
    });
  });

  group('OFCScorer.autoPlace', () {
    test('fills front first, then middle, then back', () {
      final result = OFCScorer.autoPlace(
        unplacedCards: ['Ah', 'Kd', 'Qc', 'Js', 'Th', '9d', '8c', '7s', '6h', '5d', '4c', '3s', '2h'],
        currentFront: [],
        currentMiddle: [],
        currentBack: [],
      );
      expect(result['front']!.length, 3);
      expect(result['middle']!.length, 5);
      expect(result['back']!.length, 5);
      expect(result['front'], ['Ah', 'Kd', 'Qc']);
      expect(result['middle'], ['Js', 'Th', '9d', '8c', '7s']);
      expect(result['back'], ['6h', '5d', '4c', '3s', '2h']);
    });

    test('respects partially filled rows', () {
      final result = OFCScorer.autoPlace(
        unplacedCards: ['Ah', 'Kd', 'Qc', 'Js'],
        currentFront: ['2h', '3d'],
        currentMiddle: ['4c', '5s', '6h', '7d', '8c'],
        currentBack: ['9h', 'Td'],
      );
      // Front needs 1 more, middle is full, back needs 3 more
      expect(result['front']!.length, 3);
      expect(result['middle']!.length, 5);
      expect(result['back']!.length, 5);
      expect(result['front'], ['2h', '3d', 'Ah']);
      expect(result['back'], ['9h', 'Td', 'Kd', 'Qc', 'Js']);
    });

    test('handles empty unplaced cards', () {
      final result = OFCScorer.autoPlace(
        unplacedCards: [],
        currentFront: ['Ah', 'Kd', 'Qc'],
        currentMiddle: ['Js', 'Th', '9d', '8c', '7s'],
        currentBack: ['6h', '5d', '4c', '3s', '2h'],
      );
      expect(result['front']!.length, 3);
      expect(result['middle']!.length, 5);
      expect(result['back']!.length, 5);
    });

    test('all unplaced cards appear exactly once in result', () {
      final unplaced = ['Ah', 'Kd', 'Qc', 'Js', 'Th'];
      final result = OFCScorer.autoPlace(
        unplacedCards: unplaced,
        currentFront: ['2h', '3d'],
        currentMiddle: ['4c', '5s', '6h'],
        currentBack: ['7d', '8c', '9h'],
      );
      final allCards = [
        ...result['front']!,
        ...result['middle']!,
        ...result['back']!,
      ];
      for (final card in unplaced) {
        expect(allCards.contains(card), true, reason: '$card should be placed');
      }
    });
  });

  group('OFCResult', () {
    test('can be constructed with all fields', () {
      const result = OFCResult(
        points: 15,
        royalties: 5,
        isFoul: false,
        description: '+15 แต้ม',
      );
      expect(result.points, 15);
      expect(result.royalties, 5);
      expect(result.isFoul, false);
      expect(result.description, '+15 แต้ม');
    });
  });
}
