import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/utils/hand_evaluator.dart';

void main() {
  group('HandEvaluator.evaluate5', () {
    test('detects Royal Flush', () {
      final result = HandEvaluator.evaluate5(['Ah', 'Kh', 'Qh', 'Jh', 'Th']);
      expect(result.rank, 9);
      expect(result.nameEn, 'Royal Flush');
      expect(result.nameTh, 'รอยัลฟลัช');
    });

    test('detects Straight Flush', () {
      final result = HandEvaluator.evaluate5(['9s', '8s', '7s', '6s', '5s']);
      expect(result.rank, 8);
      expect(result.nameEn, 'Straight Flush');
      expect(result.kickers, [9]);
    });

    test('detects wheel Straight Flush (A-2-3-4-5)', () {
      final result = HandEvaluator.evaluate5(['Ad', '2d', '3d', '4d', '5d']);
      expect(result.rank, 8);
      expect(result.kickers, [5]);
    });

    test('detects Four of a Kind', () {
      final result = HandEvaluator.evaluate5(['Ks', 'Kh', 'Kd', 'Kc', '3h']);
      expect(result.rank, 7);
      expect(result.kickers, [13, 3]);
    });

    test('detects Full House', () {
      final result = HandEvaluator.evaluate5(['Jh', 'Jd', 'Jc', '4s', '4h']);
      expect(result.rank, 6);
      expect(result.kickers, [11, 4]);
    });

    test('detects Flush', () {
      final result = HandEvaluator.evaluate5(['Ah', 'Th', '7h', '4h', '2h']);
      expect(result.rank, 5);
      expect(result.kickers, [14, 10, 7, 4, 2]);
    });

    test('detects Straight', () {
      final result = HandEvaluator.evaluate5(['9h', '8d', '7c', '6s', '5h']);
      expect(result.rank, 4);
      expect(result.kickers, [9]);
    });

    test('detects wheel Straight (A-2-3-4-5)', () {
      final result = HandEvaluator.evaluate5(['Ah', '2d', '3c', '4s', '5h']);
      expect(result.rank, 4);
      expect(result.kickers, [5]);
    });

    test('detects Three of a Kind', () {
      final result = HandEvaluator.evaluate5(['8h', '8d', '8c', 'Ks', '3h']);
      expect(result.rank, 3);
      expect(result.kickers, [8, 13, 3]);
    });

    test('detects Two Pair', () {
      final result = HandEvaluator.evaluate5(['Ah', 'Ad', '7c', '7s', '3h']);
      expect(result.rank, 2);
      expect(result.kickers, [14, 7, 3]);
    });

    test('detects Pair', () {
      final result = HandEvaluator.evaluate5(['Qh', 'Qd', '9c', '5s', '2h']);
      expect(result.rank, 1);
      expect(result.kickers, [12, 9, 5, 2]);
    });

    test('detects High Card', () {
      final result = HandEvaluator.evaluate5(['Ah', 'Kd', '9c', '5s', '2h']);
      expect(result.rank, 0);
      expect(result.kickers, [14, 13, 9, 5, 2]);
    });
  });

  group('HandEvaluator.evaluateBest5', () {
    test('finds best hand from 7 cards', () {
      // Has a flush in hearts among the 7 cards
      final result = HandEvaluator.evaluateBest5(
        ['Ah', 'Kh', '9h', '5h', '2h', '3d', '7c'],
      );
      expect(result.rank, 5); // Flush
    });

    test('finds straight from 6 cards', () {
      final result = HandEvaluator.evaluateBest5(
        ['9h', '8d', '7c', '6s', '5h', '2d'],
      );
      expect(result.rank, 4); // Straight
    });

    test('finds full house from 7 cards', () {
      final result = HandEvaluator.evaluateBest5(
        ['Jh', 'Jd', 'Jc', '4s', '4h', '9d', '2c'],
      );
      expect(result.rank, 6); // Full House
    });

    test('works with exactly 5 cards', () {
      final result = HandEvaluator.evaluateBest5(
        ['Ah', 'Kh', 'Qh', 'Jh', 'Th'],
      );
      expect(result.rank, 9); // Royal Flush
    });
  });

  group('HandEvaluator.evaluate3', () {
    test('detects Three of a Kind', () {
      final result = HandEvaluator.evaluate3(['Ks', 'Kh', 'Kd']);
      expect(result.rank, 3);
      expect(result.nameTh, 'ทริปส์');
    });

    test('detects Pair', () {
      final result = HandEvaluator.evaluate3(['Ah', 'Ad', '5c']);
      expect(result.rank, 1);
      expect(result.kickers, [14, 5]);
    });

    test('detects High Card', () {
      final result = HandEvaluator.evaluate3(['Ah', 'Kd', '9c']);
      expect(result.rank, 0);
      expect(result.kickers, [14, 13, 9]);
    });
  });

  group('HandEvaluator.compare', () {
    test('higher rank wins', () {
      final flush = HandEvaluator.evaluate5(['Ah', 'Th', '7h', '4h', '2h']);
      final pair = HandEvaluator.evaluate5(['Ah', 'Ad', '9c', '5s', '2c']);
      expect(HandEvaluator.compare(flush, pair), greaterThan(0));
    });

    test('antisymmetry: compare(a,b) > 0 implies compare(b,a) < 0', () {
      final a = HandEvaluator.evaluate5(['Ah', 'Kh', 'Qh', 'Jh', 'Th']);
      final b = HandEvaluator.evaluate5(['2h', '3d', '5c', '7s', '9h']);
      expect(HandEvaluator.compare(a, b), greaterThan(0));
      expect(HandEvaluator.compare(b, a), lessThan(0));
    });

    test('reflexivity: compare(a,a) == 0', () {
      final a = HandEvaluator.evaluate5(['Ah', 'Kd', '9c', '5s', '2h']);
      expect(HandEvaluator.compare(a, a), 0);
    });

    test('same rank uses kickers for tie-breaking', () {
      final pairAces =
          HandEvaluator.evaluate5(['Ah', 'Ad', 'Kc', '5s', '2h']);
      final pairKings =
          HandEvaluator.evaluate5(['Kh', 'Kd', 'Qc', '5s', '2h']);
      expect(HandEvaluator.compare(pairAces, pairKings), greaterThan(0));
    });

    test('equal hands compare as 0', () {
      final a = HandEvaluator.evaluate5(['Ah', 'Kd', '9c', '5s', '2h']);
      final b = HandEvaluator.evaluate5(['As', 'Kc', '9h', '5d', '2c']);
      expect(HandEvaluator.compare(a, b), 0);
    });
  });

  group('HandEvaluator.getThaiHandName', () {
    test('returns Thai name for NLH hand', () {
      final name = HandEvaluator.getThaiHandName(
        ['Ah', 'Kh'],
        ['Qh', 'Jh', 'Th'],
      );
      expect(name, 'รอยัลฟลัช');
    });

    test('returns Thai name for pair with 2 hole cards only', () {
      final name = HandEvaluator.getThaiHandName(['Ah', 'Ad'], []);
      expect(name, 'คู่');
    });

    test('returns Thai name for 3-card hand', () {
      final name = HandEvaluator.getThaiHandName(['Ah', 'Ad', '5c'], []);
      expect(name, 'คู่');
    });
  });
}
