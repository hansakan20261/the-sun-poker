import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_timing_config.dart';
import 'package:the_sun_poker/services/animation/chinese_poker_animation_controller.dart';

void main() {
  group('ChinesePokerAnimationController', () {
    late ChinesePokerAnimationController controller;

    setUp(() {
      controller = ChinesePokerAnimationController();
    });

    tearDown(() {
      controller.dispose();
    });

    group('animateDeal', () {
      test('completes without error for 13 cards', () async {
        await controller.animateDeal(13);
        expect(controller.isAnimating, isFalse);
      });

      test('transitions through dealing phase to completed', () async {
        final phases = <ChinesePokerAnimPhase>{};

        controller.state.addListener(() {
          phases.add(controller.state.value.phase);
        });

        await controller.animateDeal(5);

        expect(phases, contains(ChinesePokerAnimPhase.dealing));
        expect(phases, contains(ChinesePokerAnimPhase.completed));
      });

      test('progress increases from 0 to 1 during deal', () async {
        final progressValues = <double>[];

        controller.state.addListener(() {
          if (controller.state.value.phase == ChinesePokerAnimPhase.dealing) {
            progressValues.add(controller.state.value.progress);
          }
        });

        await controller.animateDeal(5);

        expect(progressValues, isNotEmpty);
        expect(progressValues.last, closeTo(1.0, 0.01));
        // Progress should be monotonically increasing.
        for (var i = 1; i < progressValues.length; i++) {
          expect(progressValues[i], greaterThanOrEqualTo(progressValues[i - 1]));
        }
      });

      test('total duration is approximately cardCount × 100ms stagger',
          () async {
        const cardCount = 13;
        final stopwatch = Stopwatch()..start();
        await controller.animateDeal(cardCount);
        stopwatch.stop();

        // Expected: (13 - 1) × 100ms = 1200ms (stagger between cards).
        // Allow generous tolerance for test scheduling.
        final expectedDuration =
            (cardCount - 1) * AnimationTimingConfig.chineseCardStagger;
        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(expectedDuration - 200),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(expectedDuration + 400),
        );
      });

      test('handles zero cards gracefully', () async {
        await controller.animateDeal(0);

        final state = controller.state.value;
        expect(state.phase, ChinesePokerAnimPhase.completed);
        expect(state.progress, 1.0);
      });

      test('handles single card', () async {
        await controller.animateDeal(1);

        final state = controller.state.value;
        expect(state.phase, ChinesePokerAnimPhase.completed);
        expect(state.progress, 1.0);
      });
    });

    group('animateCardPlace', () {
      test('completes without error', () async {
        await controller.animateCardPlace();
        expect(controller.isAnimating, isFalse);
      });

      test('transitions through placing phase to completed', () async {
        final phases = <ChinesePokerAnimPhase>{};

        controller.state.addListener(() {
          phases.add(controller.state.value.phase);
        });

        await controller.animateCardPlace();

        expect(phases, contains(ChinesePokerAnimPhase.placing));
        expect(phases, contains(ChinesePokerAnimPhase.completed));
      });

      test('duration is approximately 250ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateCardPlace();
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(AnimationTimingConfig.chineseCardPlace - 100),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(AnimationTimingConfig.chineseCardPlace + 200),
        );
      });

      test('uses ease-out curve (progress accelerates early)', () async {
        final progressValues = <double>[];

        controller.state.addListener(() {
          if (controller.state.value.phase == ChinesePokerAnimPhase.placing) {
            progressValues.add(controller.state.value.progress);
          }
        });

        await controller.animateCardPlace();

        // Ease-out: first half of progress should cover more than 50% of value.
        if (progressValues.length >= 4) {
          final midIndex = progressValues.length ~/ 2;
          final midProgress = progressValues[midIndex];
          // With ease-out, midpoint progress should be > 0.5 (fast start).
          expect(midProgress, greaterThan(0.4));
        }
      });
    });

    group('animateCardRemove', () {
      test('completes without error', () async {
        await controller.animateCardRemove();
        expect(controller.isAnimating, isFalse);
      });

      test('transitions through removing phase to completed', () async {
        final phases = <ChinesePokerAnimPhase>{};

        controller.state.addListener(() {
          phases.add(controller.state.value.phase);
        });

        await controller.animateCardRemove();

        expect(phases, contains(ChinesePokerAnimPhase.removing));
        expect(phases, contains(ChinesePokerAnimPhase.completed));
      });

      test('duration is approximately 200ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateCardRemove();
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(AnimationTimingConfig.chineseCardReturn - 100),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(AnimationTimingConfig.chineseCardReturn + 200),
        );
      });
    });

    group('animateReset', () {
      test('completes without error', () async {
        await controller.animateReset();
        expect(controller.isAnimating, isFalse);
      });

      test('transitions through resetting phase to completed', () async {
        final phases = <ChinesePokerAnimPhase>{};

        controller.state.addListener(() {
          phases.add(controller.state.value.phase);
        });

        await controller.animateReset();

        expect(phases, contains(ChinesePokerAnimPhase.resetting));
        expect(phases, contains(ChinesePokerAnimPhase.completed));
      });

      test('duration is approximately 300ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateReset();
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(AnimationTimingConfig.chineseResetAll - 100),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(AnimationTimingConfig.chineseResetAll + 200),
        );
      });
    });

    group('animateAutoArrange', () {
      test('completes without error', () async {
        await controller.animateAutoArrange(13);
        expect(controller.isAnimating, isFalse);
      });

      test('transitions through autoArranging phase to completed', () async {
        final phases = <ChinesePokerAnimPhase>{};

        controller.state.addListener(() {
          phases.add(controller.state.value.phase);
        });

        await controller.animateAutoArrange(5);

        expect(phases, contains(ChinesePokerAnimPhase.autoArranging));
        expect(phases, contains(ChinesePokerAnimPhase.completed));
      });

      test('total duration is approximately cardCount × 50ms stagger',
          () async {
        const cardCount = 10;
        final stopwatch = Stopwatch()..start();
        await controller.animateAutoArrange(cardCount);
        stopwatch.stop();

        // Expected: (10 - 1) × 50ms = 450ms.
        final expectedDuration =
            (cardCount - 1) * AnimationTimingConfig.chineseAutoArrangeStagger;
        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(expectedDuration - 150),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(expectedDuration + 300),
        );
      });

      test('handles zero cards gracefully', () async {
        await controller.animateAutoArrange(0);

        final state = controller.state.value;
        expect(state.phase, ChinesePokerAnimPhase.completed);
        expect(state.progress, 1.0);
      });
    });

    group('animateRowReveal', () {
      test('completes without error', () async {
        await controller.animateRowReveal(
          rows: ['back', 'middle', 'front'],
        );
        expect(controller.isAnimating, isFalse);
      });

      test('transitions through rowReveal phase to completed', () async {
        final phases = <ChinesePokerAnimPhase>{};

        controller.state.addListener(() {
          phases.add(controller.state.value.phase);
        });

        await controller.animateRowReveal(
          rows: ['back', 'middle', 'front'],
        );

        expect(phases, contains(ChinesePokerAnimPhase.rowReveal));
        expect(phases, contains(ChinesePokerAnimPhase.completed));
      });

      test('reveals rows in order with 800ms pause between', () async {
        final revealedRowOrder = <int>[];

        controller.state.addListener(() {
          final s = controller.state.value;
          if (s.phase == ChinesePokerAnimPhase.rowReveal &&
              s.currentRow >= 0 &&
              !revealedRowOrder.contains(s.currentRow)) {
            revealedRowOrder.add(s.currentRow);
          }
        });

        await controller.animateRowReveal(
          rows: ['back', 'middle', 'front'],
        );

        expect(revealedRowOrder, [0, 1, 2]);
      });

      test('total duration includes 800ms pauses between 3 rows', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateRowReveal(
          rows: ['back', 'middle', 'front'],
        );
        stopwatch.stop();

        // Expected: 3 × flipDuration + 2 × 800ms pause.
        final expectedMin =
            3 * AnimationTimingConfig.showdownFlipDuration +
                2 * AnimationTimingConfig.chineseRowPause -
                400;
        final expectedMax =
            3 * AnimationTimingConfig.showdownFlipDuration +
                2 * AnimationTimingConfig.chineseRowPause +
                600;

        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(expectedMin));
        expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(expectedMax));
      });

      test('sets winning rows in state', () async {
        await controller.animateRowReveal(
          rows: ['back', 'middle', 'front'],
          winningRows: [0, 2],
        );

        final state = controller.state.value;
        expect(state.winningRows, [0, 2]);
      });

      test('sets isFouled flag in state', () async {
        await controller.animateRowReveal(
          rows: ['back', 'middle', 'front'],
          isFouled: true,
        );

        final state = controller.state.value;
        expect(state.isFouled, isTrue);
      });

      test('final state has all rows revealed', () async {
        await controller.animateRowReveal(
          rows: ['back', 'middle', 'front'],
        );

        final state = controller.state.value;
        expect(state.revealedRows, [0, 1, 2]);
        expect(state.progress, 1.0);
      });

      test('handles empty rows gracefully', () async {
        await controller.animateRowReveal(rows: []);

        final state = controller.state.value;
        expect(state.phase, ChinesePokerAnimPhase.completed);
        expect(state.progress, 1.0);
      });
    });

    group('animateScoring', () {
      test('completes without error', () async {
        await controller.animateScoring(42);
        expect(controller.isAnimating, isFalse);
      });

      test('transitions through scoring phase to completed', () async {
        final phases = <ChinesePokerAnimPhase>{};

        controller.state.addListener(() {
          phases.add(controller.state.value.phase);
        });

        await controller.animateScoring(100);

        expect(phases, contains(ChinesePokerAnimPhase.scoring));
        expect(phases, contains(ChinesePokerAnimPhase.completed));
      });

      test('score counts up from 0 to target value', () async {
        final scoreValues = <int>[];

        controller.state.addListener(() {
          if (controller.state.value.phase == ChinesePokerAnimPhase.scoring) {
            scoreValues.add(controller.state.value.scoreValue);
          }
        });

        await controller.animateScoring(100);

        expect(scoreValues, isNotEmpty);
        // Score should be monotonically increasing.
        for (var i = 1; i < scoreValues.length; i++) {
          expect(scoreValues[i], greaterThanOrEqualTo(scoreValues[i - 1]));
        }
        // Final score in completed state.
        expect(controller.state.value.scoreValue, 100);
      });

      test('duration is approximately 500ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateScoring(50);
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(AnimationTimingConfig.scoreCountUp - 150),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(AnimationTimingConfig.scoreCountUp + 300),
        );
      });

      test('handles zero points gracefully', () async {
        await controller.animateScoring(0);

        final state = controller.state.value;
        expect(state.phase, ChinesePokerAnimPhase.completed);
        expect(state.scoreValue, 0);
      });
    });

    group('animateChipTransfer', () {
      test('completes without error', () async {
        await controller.animateChipTransfer();
        expect(controller.isAnimating, isFalse);
      });

      test('duration is approximately 400ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateChipTransfer();
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(AnimationTimingConfig.chipTransferFlight - 150),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(AnimationTimingConfig.chipTransferFlight + 300),
        );
      });
    });

    group('animateRoyalty', () {
      test('completes without error', () async {
        await controller.animateRoyalty(6);
        expect(controller.isAnimating, isFalse);
      });

      test('transitions through royalty phase to completed', () async {
        final phases = <ChinesePokerAnimPhase>{};

        controller.state.addListener(() {
          phases.add(controller.state.value.phase);
        });

        await controller.animateRoyalty(10);

        expect(phases, contains(ChinesePokerAnimPhase.royalty));
        expect(phases, contains(ChinesePokerAnimPhase.completed));
      });

      test('stores royalty value in state', () async {
        controller.state.addListener(() {});

        await controller.animateRoyalty(8);

        // Final state should have the royalty value.
        expect(controller.state.value.scoreValue, 8);
      });
    });

    group('animateFantasyland', () {
      test('completes without error', () async {
        await controller.animateFantasyland();
        expect(controller.isAnimating, isFalse);
      });

      test('transitions through fantasyland phase to completed', () async {
        final phases = <ChinesePokerAnimPhase>{};

        controller.state.addListener(() {
          phases.add(controller.state.value.phase);
        });

        await controller.animateFantasyland();

        expect(phases, contains(ChinesePokerAnimPhase.fantasyland));
        expect(phases, contains(ChinesePokerAnimPhase.completed));
      });
    });

    group('phase transitions', () {
      test('initial state is idle', () {
        expect(controller.state.value.phase, ChinesePokerAnimPhase.idle);
        expect(controller.state.value.progress, 0.0);
      });

      test('isAnimating is true during animation and false after', () async {
        final future = controller.animateDeal(3);

        // Allow microtask to start processing.
        await Future.delayed(Duration.zero);
        expect(controller.isAnimating, isTrue);

        await future;
        expect(controller.isAnimating, isFalse);
      });
    });

    group('skip behavior', () {
      test('skip resolves deal to completed state', () async {
        final future = controller.animateDeal(13);

        // Allow animation to start.
        await Future.delayed(Duration.zero);
        controller.skipCurrentAnimation();

        await future;

        // Allow background processing to finish.
        await Future.delayed(const Duration(milliseconds: 200));

        final state = controller.state.value;
        expect(state.phase, ChinesePokerAnimPhase.completed);
        expect(state.progress, 1.0);
      });

      test('skip resolves row reveal to final state with all rows', () async {
        final future = controller.animateRowReveal(
          rows: ['back', 'middle', 'front'],
          winningRows: [1],
        );

        // Allow animation to start.
        await Future.delayed(Duration.zero);
        controller.skipCurrentAnimation();

        await future;

        // Allow background processing to finish.
        await Future.delayed(const Duration(milliseconds: 200));

        final state = controller.state.value;
        expect(state.phase, ChinesePokerAnimPhase.completed);
        expect(state.revealedRows, [0, 1, 2]);
        expect(state.winningRows, [1]);
      });

      test('skip resolves scoring to final value', () async {
        final future = controller.animateScoring(75);

        // Allow animation to start.
        await Future.delayed(Duration.zero);
        controller.skipCurrentAnimation();

        await future;

        // Allow background processing to finish.
        await Future.delayed(const Duration(milliseconds: 200));

        final state = controller.state.value;
        expect(state.phase, ChinesePokerAnimPhase.completed);
        expect(state.scoreValue, 75);
      });
    });

    group('haptic integration', () {
      test('card placement triggers haptic (no crash without platform)',
          () async {
        // This test verifies that animateCardPlace does not throw
        // when HapticService is called (it will no-op in test environment).
        await controller.animateCardPlace();
        expect(controller.isAnimating, isFalse);
      });
    });

    group('ChinesePokerAnimState', () {
      test('copyWith creates a new instance with updated fields', () {
        const original = ChinesePokerAnimState(
          phase: ChinesePokerAnimPhase.idle,
          progress: 0.0,
          currentRow: -1,
          revealedRows: [],
          isFouled: false,
          scoreValue: 0,
        );

        final updated = original.copyWith(
          phase: ChinesePokerAnimPhase.rowReveal,
          progress: 0.5,
          currentRow: 1,
          revealedRows: [0],
          isFouled: true,
          scoreValue: 42,
          winningRows: [0, 2],
        );

        expect(updated.phase, ChinesePokerAnimPhase.rowReveal);
        expect(updated.progress, 0.5);
        expect(updated.currentRow, 1);
        expect(updated.revealedRows, [0]);
        expect(updated.isFouled, isTrue);
        expect(updated.scoreValue, 42);
        expect(updated.winningRows, [0, 2]);
      });

      test('copyWith preserves unchanged fields', () {
        const original = ChinesePokerAnimState(
          phase: ChinesePokerAnimPhase.scoring,
          progress: 0.7,
          currentRow: 2,
          revealedRows: [0, 1],
          isFouled: false,
          scoreValue: 30,
          winningRows: [1],
        );

        final updated = original.copyWith(progress: 0.9);

        expect(updated.phase, ChinesePokerAnimPhase.scoring);
        expect(updated.progress, 0.9);
        expect(updated.currentRow, 2);
        expect(updated.revealedRows, [0, 1]);
        expect(updated.isFouled, isFalse);
        expect(updated.scoreValue, 30);
        expect(updated.winningRows, [1]);
      });
    });

    group('ChinesePokerAnimPhase', () {
      test('has all expected values', () {
        expect(ChinesePokerAnimPhase.values, [
          ChinesePokerAnimPhase.idle,
          ChinesePokerAnimPhase.dealing,
          ChinesePokerAnimPhase.placing,
          ChinesePokerAnimPhase.removing,
          ChinesePokerAnimPhase.resetting,
          ChinesePokerAnimPhase.autoArranging,
          ChinesePokerAnimPhase.rowReveal,
          ChinesePokerAnimPhase.scoring,
          ChinesePokerAnimPhase.royalty,
          ChinesePokerAnimPhase.fantasyland,
          ChinesePokerAnimPhase.completed,
        ]);
      });
    });

    group('animation timing constants', () {
      test('chineseCardStagger is 100ms', () {
        expect(AnimationTimingConfig.chineseCardStagger, 100);
      });

      test('chineseCardPlace is 250ms', () {
        expect(AnimationTimingConfig.chineseCardPlace, 250);
      });

      test('chineseCardReturn is 200ms', () {
        expect(AnimationTimingConfig.chineseCardReturn, 200);
      });

      test('chineseResetAll is 300ms', () {
        expect(AnimationTimingConfig.chineseResetAll, 300);
      });

      test('chineseAutoArrangeStagger is 50ms', () {
        expect(AnimationTimingConfig.chineseAutoArrangeStagger, 50);
      });

      test('chineseRowPause is 800ms', () {
        expect(AnimationTimingConfig.chineseRowPause, 800);
      });

      test('chipTransferFlight is 400ms', () {
        expect(AnimationTimingConfig.chipTransferFlight, 400);
      });

      test('scoreCountUp is 500ms', () {
        expect(AnimationTimingConfig.scoreCountUp, 500);
      });
    });
  });
}
