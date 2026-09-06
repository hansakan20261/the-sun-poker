import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_timing_config.dart';
import 'package:the_sun_poker/services/animation/win_highlight_controller.dart';

void main() {
  group('WinHighlightController', () {
    late WinHighlightController controller;

    setUp(() {
      controller = WinHighlightController();
    });

    tearDown(() {
      controller.dispose();
    });

    group('animateWinHighlight', () {
      test('completes without error', () async {
        await controller.animateWinHighlight(
          seatIndex: 0,
          winningCards: ['Ah', 'Kh'],
        );

        expect(controller.isAnimating, isFalse);
      });

      test('transitions through phases: idle → glowing → completed', () async {
        final phases = <WinHighlightPhase>[];

        controller.highlightState.addListener(() {
          final state = controller.highlightState.value;
          if (state != null && !phases.contains(state.phase)) {
            phases.add(state.phase);
          }
        });

        await controller.animateWinHighlight(
          seatIndex: 2,
          winningCards: ['Qs', 'Js'],
        );

        expect(phases, contains(WinHighlightPhase.idle));
        expect(phases, contains(WinHighlightPhase.glowing));
        expect(phases, contains(WinHighlightPhase.completed));
      });

      test('glow intensity peaks during animation (near 1.0)', () async {
        double maxGlowIntensity = 0.0;

        controller.highlightState.addListener(() {
          final state = controller.highlightState.value;
          if (state != null && state.glowIntensity > maxGlowIntensity) {
            maxGlowIntensity = state.glowIntensity;
          }
        });

        await controller.animateWinHighlight(
          seatIndex: 3,
          winningCards: ['Td', 'Tc'],
        );

        // Sine curve peaks at sin(π/2) ≈ 1.0 at the midpoint.
        expect(maxGlowIntensity, greaterThan(0.95));
      });

      test('glow intensity returns to 0 after completion', () async {
        await controller.animateWinHighlight(
          seatIndex: 1,
          winningCards: ['Ah', 'Kh'],
        );

        final state = controller.highlightState.value;
        expect(state, isNotNull);
        expect(state!.phase, WinHighlightPhase.completed);
        expect(state.glowIntensity, 0.0);
      });

      test('sets winningSeatIndex correctly', () async {
        await controller.animateWinHighlight(
          seatIndex: 5,
          winningCards: ['9d', '9c'],
        );

        final state = controller.highlightState.value;
        expect(state, isNotNull);
        expect(state!.winningSeatIndex, 5);
      });

      test('progress reaches 1.0 on completion', () async {
        await controller.animateWinHighlight(
          seatIndex: 0,
          winningCards: ['Ah', 'Kh'],
        );

        final state = controller.highlightState.value;
        expect(state, isNotNull);
        expect(state!.progress, 1.0);
      });
    });

    group('isAnimating tracking', () {
      test('isAnimating is true during animation and false after', () async {
        final future = controller.animateWinHighlight(
          seatIndex: 0,
          winningCards: ['Ah', 'Kh'],
        );

        // Allow microtask to start processing.
        await Future.delayed(Duration.zero);
        expect(controller.isAnimating, isTrue);

        await future;
        expect(controller.isAnimating, isFalse);
      });
    });

    group('skip behavior', () {
      test('skip resolves to final state', () async {
        final future = controller.animateWinHighlight(
          seatIndex: 4,
          winningCards: ['Ah', 'Kh', 'Qh', 'Jh', 'Th'],
        );

        // Allow animation to start.
        await Future.delayed(Duration.zero);

        // Request skip.
        controller.skipCurrentAnimation();

        await future;

        expect(controller.isAnimating, isFalse);

        // Allow background processing to finish.
        await Future.delayed(const Duration(milliseconds: 100));

        final state = controller.highlightState.value;
        expect(state, isNotNull);
        expect(state!.phase, WinHighlightPhase.completed);
        expect(state.winningSeatIndex, 4);
        expect(state.glowIntensity, 0.0);
        expect(state.progress, 1.0);
      });
    });

    group('animation timing', () {
      test('uses winGlowPulse of 1000ms', () {
        expect(AnimationTimingConfig.winGlowPulse, 1000);
      });

      test('animation duration is approximately 1000ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateWinHighlight(
          seatIndex: 0,
          winningCards: ['Ah', 'Kh'],
        );
        stopwatch.stop();

        // Expected: ~1000ms. Allow generous tolerance for test scheduling.
        final expectedMin = AnimationTimingConfig.winGlowPulse - 300;
        final expectedMax = AnimationTimingConfig.winGlowPulse + 300;

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

    group('WinHighlightState', () {
      test('copyWith creates a new instance with updated fields', () {
        const original = WinHighlightState(
          phase: WinHighlightPhase.idle,
          winningSeatIndex: -1,
          glowIntensity: 0.0,
          progress: 0.0,
        );

        final updated = original.copyWith(
          phase: WinHighlightPhase.glowing,
          winningSeatIndex: 3,
          glowIntensity: 0.8,
          progress: 0.5,
        );

        expect(updated.phase, WinHighlightPhase.glowing);
        expect(updated.winningSeatIndex, 3);
        expect(updated.glowIntensity, 0.8);
        expect(updated.progress, 0.5);
      });

      test('copyWith preserves unchanged fields', () {
        const original = WinHighlightState(
          phase: WinHighlightPhase.glowing,
          winningSeatIndex: 2,
          glowIntensity: 0.7,
          progress: 0.6,
        );

        final updated = original.copyWith(progress: 0.8);

        expect(updated.phase, WinHighlightPhase.glowing);
        expect(updated.winningSeatIndex, 2);
        expect(updated.glowIntensity, 0.7);
        expect(updated.progress, 0.8);
      });
    });

    group('WinHighlightPhase', () {
      test('has all expected values', () {
        expect(WinHighlightPhase.values, [
          WinHighlightPhase.idle,
          WinHighlightPhase.glowing,
          WinHighlightPhase.completed,
        ]);
      });
    });
  });
}
