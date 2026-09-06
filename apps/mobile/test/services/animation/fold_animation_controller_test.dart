import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_timing_config.dart';
import 'package:the_sun_poker/services/animation/fold_animation_controller.dart';

void main() {
  group('FoldAnimationController', () {
    late FoldAnimationController controller;
    const muckPosition = Offset(200, 200);

    setUp(() {
      controller = FoldAnimationController(muckPosition: muckPosition);
    });

    tearDown(() {
      controller.dispose();
    });

    group('animateFold', () {
      test('completes without error', () async {
        await controller.animateFold(
          playerPosition: const Offset(100, 400),
        );

        expect(controller.isAnimating, isFalse);
      });

      test('sets foldState to completed after animation', () async {
        await controller.animateFold(
          playerPosition: const Offset(100, 400),
        );

        final state = controller.foldState.value;
        expect(state, isNotNull);
        expect(state!.phase, FoldAnimationPhase.completed);
        expect(state.position, muckPosition);
        expect(state.opacity, 0.0);
        expect(state.progress, 1.0);
      });

      test('fades opacity from 1.0 to 0.0 during animation', () async {
        final opacities = <double>[];

        controller.foldState.addListener(() {
          final state = controller.foldState.value;
          if (state != null && state.phase == FoldAnimationPhase.sliding) {
            opacities.add(state.opacity);
          }
        });

        await controller.animateFold(
          playerPosition: const Offset(100, 400),
        );

        // Opacity should decrease monotonically during the slide.
        expect(opacities, isNotEmpty);
        for (var i = 1; i < opacities.length; i++) {
          expect(opacities[i], lessThanOrEqualTo(opacities[i - 1]));
        }

        // Final opacity should be 0.0.
        expect(opacities.last, closeTo(0.0, 0.01));
      });

      test('slides position from player seat toward muck area', () async {
        const playerPosition = Offset(50, 400);
        final positions = <Offset>[];

        controller.foldState.addListener(() {
          final state = controller.foldState.value;
          if (state != null && state.phase == FoldAnimationPhase.sliding) {
            positions.add(state.position);
          }
        });

        await controller.animateFold(playerPosition: playerPosition);

        // Position should move toward muck.
        expect(positions, isNotEmpty);
        // Last sliding position should be at or very near muck.
        expect(positions.last.dx, closeTo(muckPosition.dx, 1.0));
        expect(positions.last.dy, closeTo(muckPosition.dy, 1.0));
      });

      test('transitions through idle, sliding, and completed phases', () async {
        final phases = <FoldAnimationPhase>[];

        controller.foldState.addListener(() {
          final state = controller.foldState.value;
          if (state != null && !phases.contains(state.phase)) {
            phases.add(state.phase);
          }
        });

        await controller.animateFold(
          playerPosition: const Offset(100, 400),
        );

        expect(phases, contains(FoldAnimationPhase.idle));
        expect(phases, contains(FoldAnimationPhase.sliding));
        expect(phases, contains(FoldAnimationPhase.completed));
      });

      test('isAnimating is true during animation and false after', () async {
        final future = controller.animateFold(
          playerPosition: const Offset(100, 400),
        );

        // Allow microtask to start processing.
        await Future.delayed(Duration.zero);
        expect(controller.isAnimating, isTrue);

        await future;
        expect(controller.isAnimating, isFalse);
      });

      test('progress increases from 0.0 to 1.0', () async {
        final progressValues = <double>[];

        controller.foldState.addListener(() {
          final state = controller.foldState.value;
          if (state != null && state.phase == FoldAnimationPhase.sliding) {
            progressValues.add(state.progress);
          }
        });

        await controller.animateFold(
          playerPosition: const Offset(100, 400),
        );

        expect(progressValues, isNotEmpty);
        // Progress should increase monotonically.
        for (var i = 1; i < progressValues.length; i++) {
          expect(progressValues[i], greaterThanOrEqualTo(progressValues[i - 1]));
        }
        // Final progress should be 1.0.
        expect(progressValues.last, closeTo(1.0, 0.01));
      });
    });

    group('skip behavior', () {
      test('skip resolves animation future promptly', () async {
        final future = controller.animateFold(
          playerPosition: const Offset(100, 400),
        );

        // Allow animation to start.
        await Future.delayed(Duration.zero);

        // Request skip.
        controller.skipCurrentAnimation();

        await future;

        expect(controller.isAnimating, isFalse);

        // Allow background loop to finish.
        await Future.delayed(const Duration(milliseconds: 400));

        final state = controller.foldState.value;
        expect(state, isNotNull);
        expect(state!.phase, FoldAnimationPhase.completed);
        expect(state.position, muckPosition);
        expect(state.opacity, 0.0);
        expect(state.progress, 1.0);
      });
    });

    group('FoldAnimationState', () {
      test('copyWith creates a new instance with updated fields', () {
        const original = FoldAnimationState(
          phase: FoldAnimationPhase.idle,
          position: Offset(0, 0),
        );

        final updated = original.copyWith(
          phase: FoldAnimationPhase.sliding,
          position: const Offset(50, 50),
          opacity: 0.5,
          progress: 0.5,
        );

        expect(updated.phase, FoldAnimationPhase.sliding);
        expect(updated.position, const Offset(50, 50));
        expect(updated.opacity, 0.5);
        expect(updated.progress, 0.5);
      });

      test('copyWith preserves unchanged fields', () {
        const original = FoldAnimationState(
          phase: FoldAnimationPhase.sliding,
          position: Offset(100, 100),
          opacity: 0.7,
          progress: 0.3,
        );

        final updated = original.copyWith(opacity: 0.4);

        expect(updated.phase, FoldAnimationPhase.sliding);
        expect(updated.position, const Offset(100, 100));
        expect(updated.opacity, 0.4);
        expect(updated.progress, 0.3);
      });
    });

    group('FoldAnimationPhase', () {
      test('has all expected values', () {
        expect(FoldAnimationPhase.values, [
          FoldAnimationPhase.idle,
          FoldAnimationPhase.sliding,
          FoldAnimationPhase.completed,
        ]);
      });
    });

    group('animation timing', () {
      test('animateFold completes in approximately 300ms', () async {
        final stopwatch = Stopwatch()..start();

        await controller.animateFold(
          playerPosition: const Offset(100, 400),
        );

        stopwatch.stop();

        // foldSlide = 300ms, allow ±150ms tolerance for test scheduling.
        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(AnimationTimingConfig.foldSlide - 150),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(AnimationTimingConfig.foldSlide + 150),
        );
      });

      test('fold animation step timing is approximately 30ms per step', () async {
        // foldSlide (300ms) / 10 steps = 30ms per step.
        const expectedStepDuration = AnimationTimingConfig.foldSlide ~/ 10;
        expect(expectedStepDuration, 30);

        // Verify the total animation time is consistent with step count.
        final stopwatch = Stopwatch()..start();

        await controller.animateFold(
          playerPosition: const Offset(100, 400),
        );

        stopwatch.stop();

        // 10 steps × 30ms = 300ms expected total.
        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(10 * expectedStepDuration - 150),
        );
      });
    });
  });
}
