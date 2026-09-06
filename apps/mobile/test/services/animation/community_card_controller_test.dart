import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_timing_config.dart';
import 'package:the_sun_poker/services/animation/community_card_controller.dart';

void main() {
  group('CommunityCardController', () {
    late CommunityCardController controller;

    setUp(() {
      controller = CommunityCardController();
    });

    tearDown(() {
      controller.dispose();
    });

    group('animateFlop', () {
      test('completes without error', () async {
        await controller.animateFlop(cards: ['Ah', 'Kd', '7c']);

        expect(controller.isAnimating, isFalse);
      });

      test('takes approximately 600ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateFlop(cards: ['Ah', 'Kd', '7c']);
        stopwatch.stop();

        // Expected: 600ms. Allow generous tolerance for test scheduling.
        final expectedMin = AnimationTimingConfig.flopSpread - 200;
        final expectedMax = AnimationTimingConfig.flopSpread + 200;

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(expectedMin),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(expectedMax),
        );
      });

      test('sets cardType to flop', () async {
        await controller.animateFlop(cards: ['Ah', 'Kd', '7c']);

        final state = controller.communityCardState.value;
        expect(state, isNotNull);
        expect(state!.cardType, CommunityCardType.flop);
      });
    });

    group('animateTurn', () {
      test('completes without error', () async {
        await controller.animateTurn(card: 'Qs');

        expect(controller.isAnimating, isFalse);
      });

      test('takes approximately 400ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateTurn(card: 'Qs');
        stopwatch.stop();

        final expectedMin = AnimationTimingConfig.turnSlide - 200;
        final expectedMax = AnimationTimingConfig.turnSlide + 200;

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(expectedMin),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(expectedMax),
        );
      });

      test('sets cardType to turn', () async {
        await controller.animateTurn(card: 'Qs');

        final state = controller.communityCardState.value;
        expect(state, isNotNull);
        expect(state!.cardType, CommunityCardType.turn);
      });
    });

    group('animateRiver', () {
      test('completes without error', () async {
        await controller.animateRiver(card: 'Td');

        expect(controller.isAnimating, isFalse);
      });

      test('takes approximately 400ms', () async {
        final stopwatch = Stopwatch()..start();
        await controller.animateRiver(card: 'Td');
        stopwatch.stop();

        final expectedMin = AnimationTimingConfig.riverSlide - 200;
        final expectedMax = AnimationTimingConfig.riverSlide + 200;

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(expectedMin),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(expectedMax),
        );
      });

      test('sets cardType to river', () async {
        await controller.animateRiver(card: 'Td');

        final state = controller.communityCardState.value;
        expect(state, isNotNull);
        expect(state!.cardType, CommunityCardType.river);
      });
    });

    group('scale pulse', () {
      test('scale starts at 1.05 during animation', () async {
        double? firstScale;

        controller.communityCardState.addListener(() {
          final state = controller.communityCardState.value;
          if (state != null &&
              state.phase == CommunityCardPhase.animating &&
              firstScale == null) {
            firstScale = state.scale;
          }
        });

        await controller.animateFlop(cards: ['Ah', 'Kd', '7c']);

        expect(firstScale, isNotNull);
        expect(firstScale, closeTo(1.05, 0.01));
      });

      test('scale settles to 1.0 at completion', () async {
        await controller.animateFlop(cards: ['Ah', 'Kd', '7c']);

        final state = controller.communityCardState.value;
        expect(state, isNotNull);
        expect(state!.scale, 1.0);
      });

      test('scale decreases from 1.05 toward 1.0 during animation', () async {
        final scales = <double>[];

        controller.communityCardState.addListener(() {
          final state = controller.communityCardState.value;
          if (state != null && state.phase == CommunityCardPhase.animating) {
            scales.add(state.scale);
          }
        });

        await controller.animateTurn(card: 'Qs');

        // Scales should be decreasing from ~1.05 toward 1.0.
        expect(scales, isNotEmpty);
        expect(scales.first, greaterThan(1.0));
        expect(scales.last, closeTo(1.0, 0.005));

        // Verify monotonically decreasing.
        for (var i = 1; i < scales.length; i++) {
          expect(scales[i], lessThanOrEqualTo(scales[i - 1]));
        }
      });
    });

    group('phase transitions', () {
      test('transitions through phases: idle → animating → completed',
          () async {
        final phases = <CommunityCardPhase>[];

        controller.communityCardState.addListener(() {
          final state = controller.communityCardState.value;
          if (state != null && !phases.contains(state.phase)) {
            phases.add(state.phase);
          }
        });

        await controller.animateFlop(cards: ['Ah', 'Kd', '7c']);

        expect(phases, contains(CommunityCardPhase.idle));
        expect(phases, contains(CommunityCardPhase.animating));
        expect(phases, contains(CommunityCardPhase.completed));
      });

      test('final state has phase completed', () async {
        await controller.animateRiver(card: 'Td');

        final state = controller.communityCardState.value;
        expect(state, isNotNull);
        expect(state!.phase, CommunityCardPhase.completed);
        expect(state.progress, 1.0);
      });
    });

    group('skip behavior', () {
      test('skip resolves to final state', () async {
        final future = controller.animateFlop(cards: ['Ah', 'Kd', '7c']);

        // Allow animation to start.
        await Future.delayed(Duration.zero);

        // Request skip.
        controller.skipCurrentAnimation();

        await future;

        expect(controller.isAnimating, isFalse);

        // Allow background processing to finish.
        await Future.delayed(const Duration(milliseconds: 100));

        final state = controller.communityCardState.value;
        expect(state, isNotNull);
        expect(state!.phase, CommunityCardPhase.completed);
        expect(state.progress, 1.0);
        expect(state.scale, 1.0);
        expect(state.revealedCards, ['Ah', 'Kd', '7c']);
      });
    });

    group('isAnimating tracking', () {
      test('isAnimating is true during animation and false after', () async {
        final future = controller.animateFlop(cards: ['Ah', 'Kd', '7c']);

        // Allow microtask to start processing.
        await Future.delayed(Duration.zero);
        expect(controller.isAnimating, isTrue);

        await future;
        expect(controller.isAnimating, isFalse);
      });
    });

    group('revealedCards accumulation', () {
      test('revealedCards accumulates across flop, turn, river', () async {
        await controller.animateFlop(cards: ['Ah', 'Kd', '7c']);

        var state = controller.communityCardState.value;
        expect(state!.revealedCards, ['Ah', 'Kd', '7c']);

        await controller.animateTurn(card: 'Qs');

        state = controller.communityCardState.value;
        expect(state!.revealedCards, ['Ah', 'Kd', '7c', 'Qs']);

        await controller.animateRiver(card: 'Td');

        state = controller.communityCardState.value;
        expect(state!.revealedCards, ['Ah', 'Kd', '7c', 'Qs', 'Td']);
      });

      test('revealedCards is empty before any animation', () {
        final state = controller.communityCardState.value;
        expect(state, isNull);
      });
    });

    group('CommunityCardState', () {
      test('copyWith creates a new instance with updated fields', () {
        const original = CommunityCardState(
          phase: CommunityCardPhase.idle,
          cardType: CommunityCardType.flop,
          progress: 0.0,
          scale: 1.05,
          revealedCards: [],
        );

        final updated = original.copyWith(
          phase: CommunityCardPhase.animating,
          progress: 0.5,
          scale: 1.025,
          revealedCards: ['Ah'],
        );

        expect(updated.phase, CommunityCardPhase.animating);
        expect(updated.cardType, CommunityCardType.flop);
        expect(updated.progress, 0.5);
        expect(updated.scale, 1.025);
        expect(updated.revealedCards, ['Ah']);
      });

      test('copyWith preserves unchanged fields', () {
        const original = CommunityCardState(
          phase: CommunityCardPhase.animating,
          cardType: CommunityCardType.turn,
          progress: 0.6,
          scale: 1.02,
          revealedCards: ['Ah', 'Kd', '7c'],
        );

        final updated = original.copyWith(progress: 0.8);

        expect(updated.phase, CommunityCardPhase.animating);
        expect(updated.cardType, CommunityCardType.turn);
        expect(updated.progress, 0.8);
        expect(updated.scale, 1.02);
        expect(updated.revealedCards, ['Ah', 'Kd', '7c']);
      });
    });

    group('CommunityCardPhase', () {
      test('has all expected values', () {
        expect(CommunityCardPhase.values, [
          CommunityCardPhase.idle,
          CommunityCardPhase.animating,
          CommunityCardPhase.completed,
        ]);
      });
    });

    group('CommunityCardType', () {
      test('has all expected values', () {
        expect(CommunityCardType.values, [
          CommunityCardType.flop,
          CommunityCardType.turn,
          CommunityCardType.river,
        ]);
      });
    });

    group('animation timing constants', () {
      test('flopSpread is 600ms', () {
        expect(AnimationTimingConfig.flopSpread, 600);
      });

      test('turnSlide is 400ms', () {
        expect(AnimationTimingConfig.turnSlide, 400);
      });

      test('riverSlide is 400ms', () {
        expect(AnimationTimingConfig.riverSlide, 400);
      });
    });
  });
}
