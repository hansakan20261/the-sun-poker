import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_coordinator.dart';
import 'package:the_sun_poker/services/animation/animation_timing_config.dart';
import 'package:the_sun_poker/services/animation/showdown_controller.dart';

void main() {
  group('ShowdownController', () {
    late ShowdownController controller;

    setUp(() {
      controller = ShowdownController();
    });

    tearDown(() {
      controller.dispose();
    });

    group('animateShowdown', () {
      test('completes without error', () async {
        final hands = [
          const ShowdownHand(seatIndex: 0, cards: ['Ah', 'Kh']),
          const ShowdownHand(seatIndex: 2, cards: ['Qs', 'Js']),
        ];

        await controller.animateShowdown(hands);

        expect(controller.isAnimating, isFalse);
      });

      test('reveals hands in order', () async {
        final hands = [
          const ShowdownHand(seatIndex: 1, cards: ['Ah', 'Kh']),
          const ShowdownHand(seatIndex: 3, cards: ['Qs', 'Js']),
          const ShowdownHand(seatIndex: 5, cards: ['Td', 'Tc']),
        ];

        final revealedSeatOrder = <int>[];

        controller.showdownState.addListener(() {
          final state = controller.showdownState.value;
          if (state != null &&
              state.phase == ShowdownRevealPhase.revealing &&
              state.currentSeatIndex >= 0 &&
              !revealedSeatOrder.contains(state.currentSeatIndex)) {
            revealedSeatOrder.add(state.currentSeatIndex);
          }
        });

        await controller.animateShowdown(hands);

        expect(revealedSeatOrder, [1, 3, 5]);
      });

      test('transitions through phases: idle → revealing → completed',
          () async {
        final hands = [
          const ShowdownHand(seatIndex: 0, cards: ['Ah', 'Kh']),
          const ShowdownHand(seatIndex: 2, cards: ['Qs', 'Js']),
        ];

        final phases = <ShowdownRevealPhase>[];

        controller.showdownState.addListener(() {
          final state = controller.showdownState.value;
          if (state != null && !phases.contains(state.phase)) {
            phases.add(state.phase);
          }
        });

        await controller.animateShowdown(hands);

        expect(phases, contains(ShowdownRevealPhase.idle));
        expect(phases, contains(ShowdownRevealPhase.revealing));
        expect(phases, contains(ShowdownRevealPhase.completed));
      });

      test('sets showdownState to completed after animation', () async {
        final hands = [
          const ShowdownHand(seatIndex: 0, cards: ['Ah', 'Kh']),
          const ShowdownHand(seatIndex: 4, cards: ['Qs', 'Js']),
        ];

        await controller.animateShowdown(hands);

        final state = controller.showdownState.value;
        expect(state, isNotNull);
        expect(state!.phase, ShowdownRevealPhase.completed);
        expect(state.revealedSeats, [0, 4]);
        expect(state.progress, 1.0);
      });

      test('revealedSeats accumulates during animation', () async {
        final hands = [
          const ShowdownHand(seatIndex: 1, cards: ['Ah', 'Kh']),
          const ShowdownHand(seatIndex: 3, cards: ['Qs', 'Js']),
          const ShowdownHand(seatIndex: 7, cards: ['Td', 'Tc']),
        ];

        final revealedSeatsCounts = <int>[];

        controller.showdownState.addListener(() {
          final state = controller.showdownState.value;
          if (state != null && state.phase == ShowdownRevealPhase.revealing) {
            revealedSeatsCounts.add(state.revealedSeats.length);
          }
        });

        await controller.animateShowdown(hands);

        // Should see increasing revealed seat counts.
        expect(revealedSeatsCounts, isNotEmpty);
        // Final state should have all 3 seats revealed.
        final finalState = controller.showdownState.value!;
        expect(finalState.revealedSeats.length, 3);
      });

      test('handles empty hands list gracefully', () async {
        await controller.animateShowdown([]);

        final state = controller.showdownState.value;
        expect(state, isNotNull);
        expect(state!.phase, ShowdownRevealPhase.completed);
        expect(state.progress, 1.0);
      });

      test('handles single hand', () async {
        final hands = [
          const ShowdownHand(
            seatIndex: 5,
            cards: ['Ah', 'Kh'],
            isWinner: true,
          ),
        ];

        await controller.animateShowdown(hands);

        final state = controller.showdownState.value;
        expect(state, isNotNull);
        expect(state!.phase, ShowdownRevealPhase.completed);
        expect(state.revealedSeats, [5]);
        expect(state.progress, 1.0);
      });
    });

    group('isAnimating tracking', () {
      test('isAnimating is true during animation and false after', () async {
        final hands = [
          const ShowdownHand(seatIndex: 0, cards: ['Ah', 'Kh']),
          const ShowdownHand(seatIndex: 2, cards: ['Qs', 'Js']),
        ];

        final future = controller.animateShowdown(hands);

        // Allow microtask to start processing.
        await Future.delayed(Duration.zero);
        expect(controller.isAnimating, isTrue);

        await future;
        expect(controller.isAnimating, isFalse);
      });
    });

    group('skip behavior', () {
      test('skip resolves to final state showing all hands revealed', () async {
        final hands = [
          const ShowdownHand(seatIndex: 0, cards: ['Ah', 'Kh']),
          const ShowdownHand(seatIndex: 2, cards: ['Qs', 'Js']),
          const ShowdownHand(seatIndex: 4, cards: ['Td', 'Tc']),
          const ShowdownHand(seatIndex: 6, cards: ['9d', '9c']),
        ];

        final future = controller.animateShowdown(hands);

        // Allow animation to start.
        await Future.delayed(Duration.zero);

        // Request skip.
        controller.skipCurrentAnimation();

        await future;

        expect(controller.isAnimating, isFalse);

        // Allow background processing to finish.
        await Future.delayed(const Duration(milliseconds: 600));

        final state = controller.showdownState.value;
        expect(state, isNotNull);
        expect(state!.phase, ShowdownRevealPhase.completed);
        expect(state.revealedSeats, [0, 2, 4, 6]);
        expect(state.progress, 1.0);
      });
    });

    group('ShowdownRevealState', () {
      test('copyWith creates a new instance with updated fields', () {
        const original = ShowdownRevealState(
          phase: ShowdownRevealPhase.idle,
          currentSeatIndex: -1,
          revealedSeats: [],
          progress: 0.0,
        );

        final updated = original.copyWith(
          phase: ShowdownRevealPhase.revealing,
          currentSeatIndex: 3,
          revealedSeats: [1],
          progress: 0.5,
        );

        expect(updated.phase, ShowdownRevealPhase.revealing);
        expect(updated.currentSeatIndex, 3);
        expect(updated.revealedSeats, [1]);
        expect(updated.progress, 0.5);
      });

      test('copyWith preserves unchanged fields', () {
        const original = ShowdownRevealState(
          phase: ShowdownRevealPhase.revealing,
          currentSeatIndex: 2,
          revealedSeats: [0, 1],
          progress: 0.6,
        );

        final updated = original.copyWith(progress: 0.8);

        expect(updated.phase, ShowdownRevealPhase.revealing);
        expect(updated.currentSeatIndex, 2);
        expect(updated.revealedSeats, [0, 1]);
        expect(updated.progress, 0.8);
      });
    });

    group('ShowdownRevealPhase', () {
      test('has all expected values', () {
        expect(ShowdownRevealPhase.values, [
          ShowdownRevealPhase.idle,
          ShowdownRevealPhase.revealing,
          ShowdownRevealPhase.completed,
        ]);
      });
    });

    group('animation timing', () {
      test('uses showdownFlipDuration of 350ms per card flip', () {
        expect(AnimationTimingConfig.showdownFlipDuration, 350);
      });

      test('uses showdownStaggerDelay of 200ms between reveals', () {
        expect(AnimationTimingConfig.showdownStaggerDelay, 200);
      });

      test('total duration scales with number of hands', () async {
        final hands = [
          const ShowdownHand(seatIndex: 0, cards: ['Ah', 'Kh']),
          const ShowdownHand(seatIndex: 2, cards: ['Qs', 'Js']),
          const ShowdownHand(seatIndex: 4, cards: ['Td', 'Tc']),
        ];

        final stopwatch = Stopwatch()..start();
        await controller.animateShowdown(hands);
        stopwatch.stop();

        // Expected: 3 flips × 350ms + 2 staggers × 200ms = 1450ms
        // Allow generous tolerance for test scheduling.
        final expectedMin =
            (3 * AnimationTimingConfig.showdownFlipDuration +
                    2 * AnimationTimingConfig.showdownStaggerDelay) -
                300;
        final expectedMax =
            (3 * AnimationTimingConfig.showdownFlipDuration +
                    2 * AnimationTimingConfig.showdownStaggerDelay) +
                300;

        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(expectedMin));
        expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(expectedMax));
      });
    });
  });
}
