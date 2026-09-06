import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_coordinator.dart';
import 'package:the_sun_poker/services/animation/animation_action_blocker.dart';

/// A test subclass that allows controlled animation completion.
class _TestCoordinator extends AnimationCoordinator {
  bool autoComplete = true;
  final List<Completer<void>> completers = [];

  @override
  Future<void> onPlayDealSequence(List<DealTarget> targets) async {
    if (!autoComplete) {
      final c = Completer<void>();
      completers.add(c);
      await c.future;
    }
  }
}

/// A test class that uses the AnimationActionBlocker mixin.
class _TestActionBlocker with AnimationActionBlocker {
  @override
  AnimationCoordinator? animationCoordinator;

  _TestActionBlocker({this.animationCoordinator});
}

void main() {
  group('AnimationActionBlocker', () {
    late _TestCoordinator coordinator;
    late _TestActionBlocker blocker;

    setUp(() {
      coordinator = _TestCoordinator();
      coordinator.autoComplete = false;
      blocker = _TestActionBlocker(animationCoordinator: coordinator);
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('areActionsBlocked is false when no animation is playing', () {
      expect(blocker.areActionsBlocked, isFalse);
    });

    test('areActionsBlocked is true when animation is playing', () async {
      // Start an animation that won't auto-complete
      coordinator.playDealSequence([
        const DealTarget(seatIndex: 0, position: Offset(100, 100)),
      ]);

      // Allow microtask queue to process
      await Future.delayed(Duration.zero);

      expect(coordinator.isAnimating, isTrue);
      expect(blocker.areActionsBlocked, isTrue);
    });

    test('areActionsBlocked is false after animation completes', () async {
      coordinator.playDealSequence([
        const DealTarget(seatIndex: 0, position: Offset(100, 100)),
      ]);

      await Future.delayed(Duration.zero);
      expect(blocker.areActionsBlocked, isTrue);

      // Complete the animation
      coordinator.completers.first.complete();
      await Future.delayed(Duration.zero);

      expect(blocker.areActionsBlocked, isFalse);
    });

    test('areActionsBlocked is false after animation is skipped', () async {
      coordinator.playDealSequence([
        const DealTarget(seatIndex: 0, position: Offset(100, 100)),
      ]);

      await Future.delayed(Duration.zero);
      expect(blocker.areActionsBlocked, isTrue);

      // Skip the animation
      coordinator.skipCurrentAnimation();
      await Future.delayed(Duration.zero);

      expect(blocker.areActionsBlocked, isFalse);
    });

    test('areActionsBlocked is false when coordinator is null', () {
      final nullBlocker = _TestActionBlocker(animationCoordinator: null);
      expect(nullBlocker.areActionsBlocked, isFalse);
    });

    group('tryExecuteAction', () {
      test('allows action when no animation is playing', () {
        var executed = false;
        final result = blocker.tryExecuteAction('fold', () => executed = true);

        expect(result, isTrue);
        expect(executed, isTrue);
      });

      test('blocks fold action when animation is playing', () async {
        coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);
        await Future.delayed(Duration.zero);

        var executed = false;
        final result = blocker.tryExecuteAction('fold', () => executed = true);

        expect(result, isFalse);
        expect(executed, isFalse);
      });

      test('blocks call action when animation is playing', () async {
        coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);
        await Future.delayed(Duration.zero);

        var executed = false;
        final result = blocker.tryExecuteAction('call', () => executed = true);

        expect(result, isFalse);
        expect(executed, isFalse);
      });

      test('blocks raise action when animation is playing', () async {
        coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);
        await Future.delayed(Duration.zero);

        var executed = false;
        final result = blocker.tryExecuteAction('raise', () => executed = true);

        expect(result, isFalse);
        expect(executed, isFalse);
      });

      test('blocks all_in action when animation is playing', () async {
        coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);
        await Future.delayed(Duration.zero);

        var executed = false;
        final result = blocker.tryExecuteAction('all_in', () => executed = true);

        expect(result, isFalse);
        expect(executed, isFalse);
      });

      test('blocks check action when animation is playing', () async {
        coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);
        await Future.delayed(Duration.zero);

        var executed = false;
        final result = blocker.tryExecuteAction('check', () => executed = true);

        expect(result, isFalse);
        expect(executed, isFalse);
      });

      test('allows action after animation completes', () async {
        coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);
        await Future.delayed(Duration.zero);

        // Verify blocked
        var executed = false;
        blocker.tryExecuteAction('fold', () => executed = true);
        expect(executed, isFalse);

        // Complete animation
        coordinator.completers.first.complete();
        await Future.delayed(Duration.zero);

        // Verify unblocked
        executed = false;
        final result = blocker.tryExecuteAction('fold', () => executed = true);
        expect(result, isTrue);
        expect(executed, isTrue);
      });

      test('allows action after animation is skipped', () async {
        coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);
        await Future.delayed(Duration.zero);

        // Verify blocked
        var executed = false;
        blocker.tryExecuteAction('raise', () => executed = true);
        expect(executed, isFalse);

        // Skip animation
        coordinator.skipCurrentAnimation();
        await Future.delayed(Duration.zero);

        // Verify unblocked
        executed = false;
        final result = blocker.tryExecuteAction('raise', () => executed = true);
        expect(result, isTrue);
        expect(executed, isTrue);
      });

      test('allows non-betting actions even during animation', () async {
        coordinator.playDealSequence([
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ]);
        await Future.delayed(Duration.zero);

        // Non-betting actions like 'chat' or 'emoji' should not be blocked
        var executed = false;
        final result = blocker.tryExecuteAction('chat', () => executed = true);

        expect(result, isTrue);
        expect(executed, isTrue);
      });
    });
  });
}
