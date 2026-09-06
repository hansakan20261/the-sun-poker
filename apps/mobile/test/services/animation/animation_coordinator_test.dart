import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_coordinator.dart';

/// A test subclass that tracks animation calls and allows controlled completion.
class TestAnimationCoordinator extends AnimationCoordinator {
  final List<String> executedAnimations = [];
  final List<Completer<void>> animationCompleters = [];

  /// If true, animations complete immediately.
  bool autoComplete = true;

  /// Duration to simulate for animations when autoComplete is true.
  Duration simulatedDuration = Duration.zero;

  @override
  Future<void> onPlayDealSequence(List<DealTarget> targets) async {
    executedAnimations.add('deal:${targets.length}');
    if (autoComplete && simulatedDuration > Duration.zero) {
      await Future.delayed(simulatedDuration);
    } else if (!autoComplete) {
      final completer = Completer<void>();
      animationCompleters.add(completer);
      await completer.future;
    }
  }

  @override
  Future<void> onPlayChipAnimation(Offset from, Offset to, int amount) async {
    executedAnimations.add('chip:$amount');
    if (autoComplete && simulatedDuration > Duration.zero) {
      await Future.delayed(simulatedDuration);
    } else if (!autoComplete) {
      final completer = Completer<void>();
      animationCompleters.add(completer);
      await completer.future;
    }
  }

  @override
  Future<void> onPlayShowdown(List<ShowdownHand> hands) async {
    executedAnimations.add('showdown:${hands.length}');
    if (autoComplete && simulatedDuration > Duration.zero) {
      await Future.delayed(simulatedDuration);
    } else if (!autoComplete) {
      final completer = Completer<void>();
      animationCompleters.add(completer);
      await completer.future;
    }
  }

  @override
  Future<void> onPlayCelebration(int winningSeat, int potAmount) async {
    executedAnimations.add('celebration:$winningSeat:$potAmount');
    if (autoComplete && simulatedDuration > Duration.zero) {
      await Future.delayed(simulatedDuration);
    } else if (!autoComplete) {
      final completer = Completer<void>();
      animationCompleters.add(completer);
      await completer.future;
    }
  }
}

void main() {
  group('AnimationCoordinator', () {
    late TestAnimationCoordinator coordinator;

    setUp(() {
      coordinator = TestAnimationCoordinator();
    });

    tearDown(() {
      coordinator.dispose();
    });

    group('isAnimating state tracking', () {
      test('isAnimating is false initially', () {
        expect(coordinator.isAnimating, isFalse);
      });

      test('isAnimating is true while animation is playing', () async {
        coordinator.autoComplete = false;

        // Start an animation but don't await it.
        final future = coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);

        // Allow microtask to process.
        await Future.delayed(Duration.zero);

        expect(coordinator.isAnimating, isTrue);

        // Complete the animation.
        coordinator.animationCompleters.first.complete();
        await future;

        expect(coordinator.isAnimating, isFalse);
      });

      test('isAnimating becomes false after animation completes', () async {
        coordinator.autoComplete = true;

        await coordinator.playChipAnimation(
          const Offset(0, 0),
          const Offset(100, 100),
          500,
        );

        expect(coordinator.isAnimating, isFalse);
      });
    });

    group('skipCurrentAnimation', () {
      test('skipCurrentAnimation resolves pending animation immediately',
          () async {
        coordinator.autoComplete = false;

        final future = coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);

        // Allow microtask to process.
        await Future.delayed(Duration.zero);
        expect(coordinator.isAnimating, isTrue);

        // Skip the animation.
        coordinator.skipCurrentAnimation();
        await future;

        expect(coordinator.isAnimating, isFalse);
      });

      test('skipCurrentAnimation sets skipRequested flag', () async {
        coordinator.autoComplete = false;

        coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);

        await Future.delayed(Duration.zero);

        expect(coordinator.skipRequested, isFalse);
        coordinator.skipCurrentAnimation();
        expect(coordinator.skipRequested, isTrue);
      });

      test('skipCurrentAnimation is no-op when not animating', () {
        expect(coordinator.isAnimating, isFalse);
        coordinator.skipCurrentAnimation(); // Should not throw.
        expect(coordinator.isAnimating, isFalse);
      });
    });

    group('animation queue', () {
      test('animations execute sequentially', () async {
        coordinator.autoComplete = true;

        await coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(0, 0)),
        ]);
        await coordinator.playChipAnimation(
          const Offset(0, 0),
          const Offset(100, 100),
          200,
        );

        expect(coordinator.executedAnimations, ['deal:1', 'chip:200']);
      });

      test('queue processes in order', () async {
        coordinator.autoComplete = false;

        final future1 = coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(0, 0)),
        ]);
        final future2 = coordinator.playChipAnimation(
          const Offset(0, 0),
          const Offset(100, 100),
          300,
        );

        await Future.delayed(Duration.zero);

        // Only the first animation should have started.
        expect(coordinator.executedAnimations, ['deal:1']);

        // Complete the first animation.
        coordinator.animationCompleters[0].complete();
        await future1;

        // Allow the second to start.
        await Future.delayed(Duration.zero);
        expect(coordinator.executedAnimations, ['deal:1', 'chip:300']);

        // Complete the second.
        coordinator.animationCompleters[1].complete();
        await future2;
      });

      test('queue skips intermediate animations when exceeding max depth',
          () async {
        coordinator.autoComplete = false;

        // Start first animation (blocks the queue).
        final future1 = coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(0, 0)),
        ]);

        await Future.delayed(Duration.zero);

        // Queue up more than maxQueueDepth animations.
        // Queue: [chip:100]
        final future2 = coordinator.playChipAnimation(
          const Offset(0, 0),
          const Offset(50, 50),
          100,
        );
        // Queue: [chip:100, chip:200]
        final future3 = coordinator.playChipAnimation(
          const Offset(0, 0),
          const Offset(60, 60),
          200,
        );
        // Queue: [chip:100, chip:200, chip:300]
        final future4 = coordinator.playChipAnimation(
          const Offset(0, 0),
          const Offset(70, 70),
          300,
        );
        // This 4th queued item triggers skipping: chip:100 is removed.
        // Queue becomes: [chip:200, chip:300, chip:400]
        final future5 = coordinator.playChipAnimation(
          const Offset(0, 0),
          const Offset(80, 80),
          400,
        );

        await Future.delayed(Duration.zero);

        // future2 (chip:100) should already be completed (skipped).
        await future2;

        // Complete the first animation (deal).
        coordinator.animationCompleters[0].complete();
        await future1;

        // Allow queue processing to continue.
        await Future.delayed(Duration.zero);

        // Complete remaining animations as they execute.
        for (var i = 1; i < coordinator.animationCompleters.length; i++) {
          if (!coordinator.animationCompleters[i].isCompleted) {
            coordinator.animationCompleters[i].complete();
          }
          await Future.delayed(Duration.zero);
        }

        await Future.wait([future3, future4, future5]);

        // chip:100 was skipped (never executed), the rest executed.
        expect(coordinator.executedAnimations, contains('deal:1'));
        expect(coordinator.executedAnimations, isNot(contains('chip:100')));
        expect(coordinator.executedAnimations, contains('chip:400'));
      });

      test('maxQueueDepth is 3', () {
        expect(AnimationCoordinator.maxQueueDepth, 3);
      });
    });

    group('dispose', () {
      test('dispose completes all pending animations', () async {
        coordinator.autoComplete = false;

        final future1 = coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(0, 0)),
        ]);
        final future2 = coordinator.playChipAnimation(
          const Offset(0, 0),
          const Offset(100, 100),
          500,
        );

        await Future.delayed(Duration.zero);

        coordinator.dispose();

        // Both futures should complete without hanging.
        await future1;
        await future2;

        expect(coordinator.isAnimating, isFalse);
      });

      test('dispose prevents new animations from being queued', () async {
        coordinator.dispose();

        await coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(0, 0)),
        ]);

        expect(coordinator.executedAnimations, isEmpty);
      });
    });

    group('DealTarget model', () {
      test('DealTarget stores seat index and position', () {
        const target = DealTarget(
          seatIndex: 3,
          position: Offset(150, 200),
          cardId: 'Ah',
        );

        expect(target.seatIndex, 3);
        expect(target.position, const Offset(150, 200));
        expect(target.cardId, 'Ah');
      });

      test('DealTarget cardId is optional', () {
        const target = DealTarget(
          seatIndex: 0,
          position: Offset(0, 0),
        );

        expect(target.cardId, isNull);
      });
    });

    group('ShowdownHand model', () {
      test('ShowdownHand stores seat, cards, and winner flag', () {
        const hand = ShowdownHand(
          seatIndex: 2,
          cards: ['Ah', 'Kh'],
          isWinner: true,
        );

        expect(hand.seatIndex, 2);
        expect(hand.cards, ['Ah', 'Kh']);
        expect(hand.isWinner, isTrue);
      });

      test('ShowdownHand isWinner defaults to false', () {
        const hand = ShowdownHand(
          seatIndex: 0,
          cards: ['2c', '3d'],
        );

        expect(hand.isWinner, isFalse);
      });
    });
  });
}
