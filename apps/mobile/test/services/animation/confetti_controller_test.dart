import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_timing_config.dart';
import 'package:the_sun_poker/services/animation/confetti_controller.dart';

void main() {
  group('ConfettiController', () {
    late ConfettiController controller;

    setUp(() {
      controller = ConfettiController();
    });

    tearDown(() {
      controller.dispose();
    });

    group('playConfettiCelebration', () {
      test('completes without error', () async {
        await controller.playConfettiCelebration(winningSeat: 0);

        expect(controller.isAnimating, isFalse);
      });

      test('transitions through phases: idle → playing → completed', () async {
        final phases = <ConfettiPhase>[];

        controller.confettiState.addListener(() {
          final state = controller.confettiState.value;
          if (state != null && !phases.contains(state.phase)) {
            phases.add(state.phase);
          }
        });

        await controller.playConfettiCelebration(winningSeat: 2);

        expect(phases, contains(ConfettiPhase.idle));
        expect(phases, contains(ConfettiPhase.playing));
        expect(phases, contains(ConfettiPhase.completed));
      });

      test('progress reaches 1.0 on completion', () async {
        await controller.playConfettiCelebration(winningSeat: 0);

        final state = controller.confettiState.value;
        expect(state, isNotNull);
        expect(state!.progress, 1.0);
      });

      test('progress increases linearly during animation', () async {
        final progressValues = <double>[];

        controller.confettiState.addListener(() {
          final state = controller.confettiState.value;
          if (state != null && state.phase == ConfettiPhase.playing) {
            progressValues.add(state.progress);
          }
        });

        await controller.playConfettiCelebration(winningSeat: 1);

        // Verify progress values are monotonically increasing.
        for (var i = 1; i < progressValues.length; i++) {
          expect(progressValues[i], greaterThan(progressValues[i - 1]));
        }
      });

      test('final state has completed phase', () async {
        await controller.playConfettiCelebration(winningSeat: 3);

        final state = controller.confettiState.value;
        expect(state, isNotNull);
        expect(state!.phase, ConfettiPhase.completed);
      });
    });

    group('isAnimating tracking', () {
      test('isAnimating is true during animation and false after', () async {
        final future = controller.playConfettiCelebration(winningSeat: 0);

        // Allow microtask to start processing.
        await Future.delayed(Duration.zero);
        expect(controller.isAnimating, isTrue);

        await future;
        expect(controller.isAnimating, isFalse);
      });
    });

    group('skip behavior', () {
      test('skip resolves to final state', () async {
        final future = controller.playConfettiCelebration(winningSeat: 4);

        // Allow animation to start.
        await Future.delayed(Duration.zero);

        // Request skip.
        controller.skipCurrentAnimation();

        await future;

        expect(controller.isAnimating, isFalse);

        // Allow background processing to finish.
        await Future.delayed(const Duration(milliseconds: 100));

        final state = controller.confettiState.value;
        expect(state, isNotNull);
        expect(state!.phase, ConfettiPhase.completed);
        expect(state.progress, 1.0);
      });
    });

    group('animation timing', () {
      test('uses confettiDuration of 2000ms', () {
        expect(AnimationTimingConfig.confettiDuration, 2000);
      });

      test('animation duration is approximately 2000ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.playConfettiCelebration(winningSeat: 0);
        stopwatch.stop();

        // Expected: ~2000ms. Allow generous tolerance for test scheduling.
        final expectedMin = AnimationTimingConfig.confettiDuration - 500;
        final expectedMax = AnimationTimingConfig.confettiDuration + 500;

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(expectedMin),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(expectedMax),
        );
      });
    });

    group('ConfettiState', () {
      test('copyWith creates a new instance with updated fields', () {
        const original = ConfettiState(
          phase: ConfettiPhase.idle,
          progress: 0.0,
        );

        final updated = original.copyWith(
          phase: ConfettiPhase.playing,
          progress: 0.5,
        );

        expect(updated.phase, ConfettiPhase.playing);
        expect(updated.progress, 0.5);
      });

      test('copyWith preserves unchanged fields', () {
        const original = ConfettiState(
          phase: ConfettiPhase.playing,
          progress: 0.6,
        );

        final updated = original.copyWith(progress: 0.8);

        expect(updated.phase, ConfettiPhase.playing);
        expect(updated.progress, 0.8);
      });
    });

    group('ConfettiPhase', () {
      test('has all expected values', () {
        expect(ConfettiPhase.values, [
          ConfettiPhase.idle,
          ConfettiPhase.playing,
          ConfettiPhase.completed,
        ]);
      });
    });
  });
}
