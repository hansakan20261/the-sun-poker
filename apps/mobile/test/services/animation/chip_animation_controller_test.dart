import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_timing_config.dart';
import 'package:the_sun_poker/services/animation/chip_animation_controller.dart';

void main() {
  group('ChipAnimationController', () {
    late ChipAnimationController controller;

    setUp(() {
      controller = ChipAnimationController(
        bigBlind: 10,
        largeBetMultiplier: 10,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    group('computeSpriteCount', () {
      test('returns 2 for bets below threshold', () {
        // Threshold = bigBlind * multiplier = 10 * 10 = 100
        expect(controller.computeSpriteCount(1), 2);
        expect(controller.computeSpriteCount(50), 2);
        expect(controller.computeSpriteCount(99), 2);
      });

      test('returns 5 for bets at or above threshold', () {
        // Threshold = 100
        expect(controller.computeSpriteCount(100), 5);
        expect(controller.computeSpriteCount(500), 5);
        expect(controller.computeSpriteCount(10000), 5);
      });

      test('returns 2 for zero or negative amounts', () {
        expect(controller.computeSpriteCount(0), 2);
        expect(controller.computeSpriteCount(-10), 2);
      });

      test('threshold is configurable via bigBlind and multiplier', () {
        final customController = ChipAnimationController(
          bigBlind: 50,
          largeBetMultiplier: 5,
        );

        // Threshold = 50 * 5 = 250
        expect(customController.computeSpriteCount(249), 2);
        expect(customController.computeSpriteCount(250), 5);
        expect(customController.computeSpriteCount(251), 5);

        customController.dispose();
      });

      test('uses default values when constructed with defaults', () {
        final defaultController = ChipAnimationController();

        // Default: bigBlind=10, multiplier=10, threshold=100
        expect(defaultController.largeBetThreshold, 100);
        expect(defaultController.computeSpriteCount(99), 2);
        expect(defaultController.computeSpriteCount(100), 5);

        defaultController.dispose();
      });
    });

    group('constants', () {
      test('smallBetSpriteCount is 2', () {
        expect(ChipAnimationController.smallBetSpriteCount, 2);
      });

      test('largeBetSpriteCount is 5', () {
        expect(ChipAnimationController.largeBetSpriteCount, 5);
      });
    });

    group('largeBetThreshold', () {
      test('is computed from bigBlind * largeBetMultiplier', () {
        expect(controller.largeBetThreshold, 100); // 10 * 10

        final ctrl2 = ChipAnimationController(
          bigBlind: 25,
          largeBetMultiplier: 4,
        );
        expect(ctrl2.largeBetThreshold, 100); // 25 * 4
        ctrl2.dispose();
      });
    });

    group('animateBet', () {
      test('completes without error', () async {
        await controller.animateBet(
          source: const Offset(100, 400),
          destination: const Offset(200, 200),
          amount: 50,
        );

        expect(controller.isAnimating, isFalse);
      });

      test('sets chip state to arrived after animation', () async {
        await controller.animateBet(
          source: const Offset(100, 400),
          destination: const Offset(200, 200),
          amount: 50,
        );

        final state = controller.chipState.value;
        expect(state, isNotNull);
        expect(state!.phase, ChipAnimationPhase.arrived);
        expect(state.position, const Offset(200, 200));
        expect(state.progress, 1.0);
      });

      test('uses correct sprite count for small bet', () async {
        await controller.animateBet(
          source: const Offset(0, 0),
          destination: const Offset(100, 100),
          amount: 20, // Below threshold of 100
        );

        final state = controller.chipState.value;
        expect(state!.spriteCount, 2);
      });

      test('uses correct sprite count for large bet', () async {
        await controller.animateBet(
          source: const Offset(0, 0),
          destination: const Offset(100, 100),
          amount: 200, // Above threshold of 100
        );

        final state = controller.chipState.value;
        expect(state!.spriteCount, 5);
      });

      test('isAnimating is true during animation and false after', () async {
        final future = controller.animateBet(
          source: const Offset(0, 0),
          destination: const Offset(100, 100),
          amount: 50,
        );

        // Allow microtask to start processing.
        await Future.delayed(Duration.zero);
        expect(controller.isAnimating, isTrue);

        await future;
        expect(controller.isAnimating, isFalse);
      });
    });

    group('skip behavior', () {
      test('skip resolves animation future promptly', () async {
        final future = controller.animateBet(
          source: const Offset(0, 0),
          destination: const Offset(200, 200),
          amount: 50,
        );

        // Allow animation to start.
        await Future.delayed(Duration.zero);

        // Request skip.
        controller.skipCurrentAnimation();

        await future;

        // After skip, isAnimating should be false (queue processed).
        expect(controller.isAnimating, isFalse);

        // Allow background flight loop to finish (each step is ~35ms,
        // up to 10 steps remaining = 350ms max).
        await Future.delayed(const Duration(milliseconds: 400));

        final state = controller.chipState.value;
        expect(state, isNotNull);
        expect(state!.phase, ChipAnimationPhase.arrived);
        expect(state.position, const Offset(200, 200));
        expect(state.progress, 1.0);
      });
    });

    group('animateAllIn', () {
      test('completes without error', () async {
        await controller.animateAllIn(
          source: const Offset(100, 400),
          destination: const Offset(200, 200),
          amount: 500,
        );

        expect(controller.isAnimating, isFalse);
      });

      test('sets allInState to completed after animation', () async {
        await controller.animateAllIn(
          source: const Offset(100, 400),
          destination: const Offset(200, 200),
          amount: 500,
        );

        final state = controller.allInState.value;
        expect(state, isNotNull);
        expect(state!.phase, AllInAnimationPhase.completed);
        expect(state.position, const Offset(200, 200));
        expect(state.progress, 1.0);
        expect(state.glowIntensity, 0.0);
      });

      test('transitions through pushing and glowing phases', () async {
        final phases = <AllInAnimationPhase>[];

        controller.allInState.addListener(() {
          final state = controller.allInState.value;
          if (state != null && !phases.contains(state.phase)) {
            phases.add(state.phase);
          }
        });

        await controller.animateAllIn(
          source: const Offset(0, 0),
          destination: const Offset(200, 200),
          amount: 500,
        );

        expect(phases, contains(AllInAnimationPhase.idle));
        expect(phases, contains(AllInAnimationPhase.pushing));
        expect(phases, contains(AllInAnimationPhase.glowing));
        expect(phases, contains(AllInAnimationPhase.completed));
      });

      test('glow intensity peaks during glowing phase', () async {
        double maxGlow = 0.0;

        controller.allInState.addListener(() {
          final state = controller.allInState.value;
          if (state != null && state.glowIntensity > maxGlow) {
            maxGlow = state.glowIntensity;
          }
        });

        await controller.animateAllIn(
          source: const Offset(0, 0),
          destination: const Offset(200, 200),
          amount: 500,
        );

        // Glow should peak near 1.0 (sine curve peaks at pi/2).
        expect(maxGlow, greaterThan(0.9));
      });

      test('glow intensity returns to 0 after completion', () async {
        await controller.animateAllIn(
          source: const Offset(0, 0),
          destination: const Offset(200, 200),
          amount: 500,
        );

        final state = controller.allInState.value;
        expect(state!.glowIntensity, 0.0);
      });

      test('skip resolves all-in animation to final state', () async {
        final future = controller.animateAllIn(
          source: const Offset(0, 0),
          destination: const Offset(200, 200),
          amount: 500,
        );

        // Allow animation to start.
        await Future.delayed(Duration.zero);

        // Request skip.
        controller.skipCurrentAnimation();

        await future;

        // Allow background loops to finish.
        await Future.delayed(const Duration(milliseconds: 1500));

        final state = controller.allInState.value;
        expect(state, isNotNull);
        expect(state!.phase, AllInAnimationPhase.completed);
        expect(state.position, const Offset(200, 200));
        expect(state.progress, 1.0);
      });

      test('isAnimating is true during all-in animation', () async {
        final future = controller.animateAllIn(
          source: const Offset(0, 0),
          destination: const Offset(200, 200),
          amount: 500,
        );

        // Allow microtask to start processing.
        await Future.delayed(Duration.zero);
        expect(controller.isAnimating, isTrue);

        await future;
        expect(controller.isAnimating, isFalse);
      });
    });

    group('AllInAnimationState', () {
      test('copyWith creates a new instance with updated fields', () {
        const original = AllInAnimationState(
          phase: AllInAnimationPhase.idle,
          position: Offset(0, 0),
        );

        final updated = original.copyWith(
          phase: AllInAnimationPhase.pushing,
          position: const Offset(50, 50),
          progress: 0.5,
          glowIntensity: 0.8,
        );

        expect(updated.phase, AllInAnimationPhase.pushing);
        expect(updated.position, const Offset(50, 50));
        expect(updated.progress, 0.5);
        expect(updated.glowIntensity, 0.8);
      });

      test('copyWith preserves unchanged fields', () {
        const original = AllInAnimationState(
          phase: AllInAnimationPhase.glowing,
          position: Offset(100, 100),
          progress: 1.0,
          glowIntensity: 0.5,
        );

        final updated = original.copyWith(glowIntensity: 0.9);

        expect(updated.phase, AllInAnimationPhase.glowing);
        expect(updated.position, const Offset(100, 100));
        expect(updated.progress, 1.0);
        expect(updated.glowIntensity, 0.9);
      });
    });

    group('AllInAnimationPhase', () {
      test('has all expected values', () {
        expect(AllInAnimationPhase.values, [
          AllInAnimationPhase.idle,
          AllInAnimationPhase.pushing,
          AllInAnimationPhase.glowing,
          AllInAnimationPhase.completed,
        ]);
      });
    });

    group('ChipAnimationState', () {
      test('copyWith creates a new instance with updated fields', () {
        const original = ChipAnimationState(
          phase: ChipAnimationPhase.waiting,
          position: Offset(0, 0),
          spriteCount: 2,
        );

        final updated = original.copyWith(
          phase: ChipAnimationPhase.flying,
          position: const Offset(50, 50),
          progress: 0.5,
        );

        expect(updated.phase, ChipAnimationPhase.flying);
        expect(updated.position, const Offset(50, 50));
        expect(updated.progress, 0.5);
        expect(updated.spriteCount, 2); // Unchanged.
      });

      test('copyWith preserves unchanged fields', () {
        const original = ChipAnimationState(
          phase: ChipAnimationPhase.flying,
          position: Offset(100, 100),
          spriteCount: 5,
          progress: 0.7,
        );

        final updated = original.copyWith(progress: 0.9);

        expect(updated.phase, ChipAnimationPhase.flying);
        expect(updated.position, const Offset(100, 100));
        expect(updated.spriteCount, 5);
        expect(updated.progress, 0.9);
      });
    });

    group('ChipAnimationPhase', () {
      test('has all expected values', () {
        expect(ChipAnimationPhase.values, [
          ChipAnimationPhase.waiting,
          ChipAnimationPhase.flying,
          ChipAnimationPhase.arrived,
        ]);
      });
    });

    group('animateWin', () {
      test('completes without error', () async {
        await controller.animateWin(
          potCenter: const Offset(200, 200),
          winnerSeat: const Offset(100, 400),
        );

        expect(controller.isAnimating, isFalse);
      });

      test('sets winChipState to arrived after animation', () async {
        await controller.animateWin(
          potCenter: const Offset(200, 200),
          winnerSeat: const Offset(100, 400),
        );

        final state = controller.winChipState.value;
        expect(state, isNotNull);
        expect(state!.phase, WinChipAnimationPhase.arrived);
        expect(state.position, const Offset(100, 400));
        expect(state.progress, 1.0);
      });

      test('always uses large sprite count (5) for win animations', () async {
        await controller.animateWin(
          potCenter: const Offset(200, 200),
          winnerSeat: const Offset(100, 400),
        );

        final state = controller.winChipState.value;
        expect(state!.spriteCount, 5);
      });

      test('transitions through idle, flying, and arrived phases', () async {
        final phases = <WinChipAnimationPhase>[];

        controller.winChipState.addListener(() {
          final state = controller.winChipState.value;
          if (state != null && !phases.contains(state.phase)) {
            phases.add(state.phase);
          }
        });

        await controller.animateWin(
          potCenter: const Offset(200, 200),
          winnerSeat: const Offset(100, 400),
        );

        expect(phases, contains(WinChipAnimationPhase.idle));
        expect(phases, contains(WinChipAnimationPhase.flying));
        expect(phases, contains(WinChipAnimationPhase.arrived));
      });

      test('isAnimating is true during win animation', () async {
        final future = controller.animateWin(
          potCenter: const Offset(200, 200),
          winnerSeat: const Offset(100, 400),
        );

        // Allow microtask to start processing.
        await Future.delayed(Duration.zero);
        expect(controller.isAnimating, isTrue);

        await future;
        expect(controller.isAnimating, isFalse);
      });

      test('skip resolves win animation to final state', () async {
        final future = controller.animateWin(
          potCenter: const Offset(200, 200),
          winnerSeat: const Offset(100, 400),
        );

        // Allow animation to start.
        await Future.delayed(Duration.zero);

        // Request skip.
        controller.skipCurrentAnimation();

        await future;

        // Allow background flight loop to finish.
        await Future.delayed(const Duration(milliseconds: 600));

        final state = controller.winChipState.value;
        expect(state, isNotNull);
        expect(state!.phase, WinChipAnimationPhase.arrived);
        expect(state.position, const Offset(100, 400));
        expect(state.progress, 1.0);
      });
    });

    group('WinChipAnimationState', () {
      test('copyWith creates a new instance with updated fields', () {
        const original = WinChipAnimationState(
          phase: WinChipAnimationPhase.idle,
          position: Offset(0, 0),
          spriteCount: 5,
        );

        final updated = original.copyWith(
          phase: WinChipAnimationPhase.flying,
          position: const Offset(50, 50),
          progress: 0.5,
        );

        expect(updated.phase, WinChipAnimationPhase.flying);
        expect(updated.position, const Offset(50, 50));
        expect(updated.progress, 0.5);
        expect(updated.spriteCount, 5); // Unchanged.
      });

      test('copyWith preserves unchanged fields', () {
        const original = WinChipAnimationState(
          phase: WinChipAnimationPhase.flying,
          position: Offset(100, 100),
          spriteCount: 5,
          progress: 0.7,
        );

        final updated = original.copyWith(progress: 0.9);

        expect(updated.phase, WinChipAnimationPhase.flying);
        expect(updated.position, const Offset(100, 100));
        expect(updated.spriteCount, 5);
        expect(updated.progress, 0.9);
      });
    });

    group('WinChipAnimationPhase', () {
      test('has all expected values', () {
        expect(WinChipAnimationPhase.values, [
          WinChipAnimationPhase.idle,
          WinChipAnimationPhase.flying,
          WinChipAnimationPhase.arrived,
        ]);
      });
    });

    group('animation timing', () {
      test('animateBet completes in approximately 350ms', () async {
        final stopwatch = Stopwatch()..start();

        await controller.animateBet(
          source: const Offset(0, 0),
          destination: const Offset(200, 200),
          amount: 50,
        );

        stopwatch.stop();

        // chipBetFlight = 350ms, allow ±150ms tolerance for test scheduling.
        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(AnimationTimingConfig.chipBetFlight - 150),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(AnimationTimingConfig.chipBetFlight + 150),
        );
      });

      test('animateWin completes in approximately 500ms', () async {
        final stopwatch = Stopwatch()..start();

        await controller.animateWin(
          potCenter: const Offset(200, 200),
          winnerSeat: const Offset(100, 400),
        );

        stopwatch.stop();

        // chipWinFlight = 500ms, allow ±150ms tolerance for test scheduling.
        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(AnimationTimingConfig.chipWinFlight - 150),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(AnimationTimingConfig.chipWinFlight + 150),
        );
      });

      test('bet animation step timing is approximately 35ms per step', () async {
        // chipBetFlight (350ms) / 10 steps = 35ms per step.
        const expectedStepDuration = AnimationTimingConfig.chipBetFlight ~/ 10;
        expect(expectedStepDuration, 35);

        // Verify the total animation time is consistent with step count.
        final stopwatch = Stopwatch()..start();

        await controller.animateBet(
          source: const Offset(0, 0),
          destination: const Offset(100, 100),
          amount: 50,
        );

        stopwatch.stop();

        // 10 steps × 35ms = 350ms expected total.
        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(10 * expectedStepDuration - 150),
        );
      });

      test('win animation step timing is approximately 41ms per step', () async {
        // chipWinFlight (500ms) / 12 steps = 41ms per step.
        const expectedStepDuration = AnimationTimingConfig.chipWinFlight ~/ 12;
        expect(expectedStepDuration, 41);

        // Verify the total animation time is consistent with step count.
        final stopwatch = Stopwatch()..start();

        await controller.animateWin(
          potCenter: const Offset(200, 200),
          winnerSeat: const Offset(100, 400),
        );

        stopwatch.stop();

        // 12 steps × 41ms = 492ms expected total.
        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(12 * expectedStepDuration - 150),
        );
      });
    });

    group('chip sprite count edge cases', () {
      test('threshold boundary: amount exactly at threshold returns 5', () {
        // Threshold = bigBlind * multiplier = 10 * 10 = 100
        expect(controller.computeSpriteCount(100), 5);
      });

      test('threshold boundary: amount one below threshold returns 2', () {
        expect(controller.computeSpriteCount(99), 2);
      });

      test('threshold boundary: amount one above threshold returns 5', () {
        expect(controller.computeSpriteCount(101), 5);
      });

      test('very large amounts still return 5', () {
        expect(controller.computeSpriteCount(1000000), 5);
      });

      test('amount of 1 returns 2 (minimum positive bet)', () {
        expect(controller.computeSpriteCount(1), 2);
      });
    });
  });
}
