import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_coordinator.dart';
import 'package:the_sun_poker/services/animation/animation_feature_flags.dart';
import 'package:the_sun_poker/services/animation/animation_wiring.dart';

/// Test coordinator that tracks which animations were triggered.
class _TestCoordinator extends AnimationCoordinator {
  final List<String> calls = [];

  @override
  Future<void> onPlayDealSequence(List<DealTarget> targets) async {
    calls.add('deal:${targets.length}');
  }

  @override
  Future<void> onPlayChipAnimation(Offset from, Offset to, int amount) async {
    calls.add('chip:$amount');
  }

  @override
  Future<void> onPlayShowdown(List<ShowdownHand> hands) async {
    calls.add('showdown:${hands.length}');
  }

  @override
  Future<void> onPlayCelebration(int winningSeat, int potAmount) async {
    calls.add('celebration:$winningSeat:$potAmount');
  }
}

void main() {
  group('AnimationWiring', () {
    late _TestCoordinator coordinator;
    late AnimationFeatureFlags flags;
    late AnimationWiring wiring;

    setUp(() {
      coordinator = _TestCoordinator();
      flags = AnimationFeatureFlags();
      wiring = AnimationWiring(coordinator: coordinator, featureFlags: flags);
    });

    tearDown(() {
      wiring.dispose();
      coordinator.dispose();
    });

    group('phase change routing', () {
      test('preflop phase triggers deal animation', () async {
        final targets = [
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
          const DealTarget(seatIndex: 1, position: Offset(200, 100)),
        ];

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: targets,
        );

        expect(coordinator.calls, ['deal:2']);
      });

      test('showdown phase triggers showdown animation', () async {
        final hands = [
          const ShowdownHand(seatIndex: 0, cards: ['Ah', 'Kh']),
          const ShowdownHand(seatIndex: 1, cards: ['Qs', 'Js']),
        ];

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.showdown,
          showdownHands: hands,
        );

        expect(coordinator.calls, ['showdown:2']);
      });

      test('result phase triggers celebration animation', () async {
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.result,
          winningSeat: 3,
          potAmount: 5000,
        );

        expect(coordinator.calls, ['celebration:3:5000']);
      });

      test('waiting phase does not trigger any animation', () async {
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.waiting,
        );

        expect(coordinator.calls, isEmpty);
      });

      test('flop/turn/river phases do not trigger coordinator animations',
          () async {
        await wiring.onPhaseChange(newPhase: AnimationGamePhase.flop);
        await wiring.onPhaseChange(newPhase: AnimationGamePhase.turn);
        await wiring.onPhaseChange(newPhase: AnimationGamePhase.river);

        expect(coordinator.calls, isEmpty);
      });
    });

    group('duplicate phase suppression', () {
      test('same phase does not trigger animation twice', () async {
        final targets = [
          const DealTarget(seatIndex: 0, position: Offset(100, 100)),
        ];

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: targets,
        );
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: targets,
        );

        expect(coordinator.calls, ['deal:1']);
      });
    });

    group('feature flag control', () {
      test('disabled deal flag skips deal animation', () async {
        flags.useDealAnimation = false;

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: [
            const DealTarget(seatIndex: 0, position: Offset(100, 100)),
          ],
        );

        expect(coordinator.calls, isEmpty);
      });

      test('disabled master toggle skips deal animation', () async {
        flags.useRiveAnimations = false;

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: [
            const DealTarget(seatIndex: 0, position: Offset(100, 100)),
          ],
        );

        expect(coordinator.calls, isEmpty);
      });

      test('disabled celebration flag skips showdown animation', () async {
        flags.useCelebrationAnimation = false;

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.showdown,
          showdownHands: [
            const ShowdownHand(seatIndex: 0, cards: ['Ah', 'Kh']),
          ],
        );

        expect(coordinator.calls, isEmpty);
      });

      test('disabled celebration flag skips result celebration', () async {
        flags.useCelebrationAnimation = false;

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.result,
          winningSeat: 0,
          potAmount: 1000,
        );

        expect(coordinator.calls, isEmpty);
      });

      test('disabled chip flag skips bet animation', () async {
        flags.useChipAnimation = false;

        await wiring.onBetPlaced(
          fromSeat: const Offset(100, 100),
          toPot: const Offset(200, 200),
          amount: 500,
        );

        expect(coordinator.calls, isEmpty);
      });

      test('enabled chip flag triggers bet animation', () async {
        await wiring.onBetPlaced(
          fromSeat: const Offset(100, 100),
          toPot: const Offset(200, 200),
          amount: 500,
        );

        expect(coordinator.calls, ['chip:500']);
      });
    });

    group('reconnection handling', () {
      test('reconnection mode skips animations', () async {
        wiring.setReconnecting(true);

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: [
            const DealTarget(seatIndex: 0, position: Offset(100, 100)),
          ],
        );

        expect(coordinator.calls, isEmpty);
      });

      test('reconnection mode is cleared after first phase change', () async {
        wiring.setReconnecting(true);

        // First call — skipped.
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: [
            const DealTarget(seatIndex: 0, position: Offset(100, 100)),
          ],
        );

        expect(wiring.isReconnecting, isFalse);

        // Second call — should trigger (different phase).
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.showdown,
          showdownHands: [
            const ShowdownHand(seatIndex: 0, cards: ['Ah', 'Kh']),
          ],
        );

        expect(coordinator.calls, ['showdown:1']);
      });

      test('onReconnect sets reconnection mode', () {
        wiring.onReconnect();
        expect(wiring.isReconnecting, isTrue);
      });

      test('onBetPlaced is skipped during reconnection', () async {
        wiring.setReconnecting(true);

        await wiring.onBetPlaced(
          fromSeat: const Offset(0, 0),
          toPot: const Offset(100, 100),
          amount: 200,
        );

        expect(coordinator.calls, isEmpty);
      });
    });

    group('null parameter handling', () {
      test('preflop with null targets does not trigger deal', () async {
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: null,
        );

        expect(coordinator.calls, isEmpty);
      });

      test('preflop with empty targets does not trigger deal', () async {
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: [],
        );

        expect(coordinator.calls, isEmpty);
      });

      test('result with null winningSeat does not trigger celebration',
          () async {
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.result,
          winningSeat: null,
          potAmount: 1000,
        );

        expect(coordinator.calls, isEmpty);
      });

      test('result with null potAmount does not trigger celebration', () async {
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.result,
          winningSeat: 0,
          potAmount: null,
        );

        expect(coordinator.calls, isEmpty);
      });

      test('showdown with null hands does not trigger showdown', () async {
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.showdown,
          showdownHands: null,
        );

        expect(coordinator.calls, isEmpty);
      });
    });

    group('dispose', () {
      test('disposed wiring does not trigger animations', () async {
        wiring.dispose();

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: [
            const DealTarget(seatIndex: 0, position: Offset(100, 100)),
          ],
        );

        expect(coordinator.calls, isEmpty);
      });

      test('disposed wiring does not trigger bet animations', () async {
        wiring.dispose();

        await wiring.onBetPlaced(
          fromSeat: const Offset(0, 0),
          toPot: const Offset(100, 100),
          amount: 500,
        );

        expect(coordinator.calls, isEmpty);
      });
    });

    group('previousPhase tracking', () {
      test('previousPhase is null initially', () {
        expect(wiring.previousPhase, isNull);
      });

      test('previousPhase is updated after phase change', () async {
        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.preflop,
          dealTargets: [
            const DealTarget(seatIndex: 0, position: Offset(100, 100)),
          ],
        );

        expect(wiring.previousPhase, AnimationGamePhase.preflop);
      });

      test('previousPhase is updated even during reconnection', () async {
        wiring.setReconnecting(true);

        await wiring.onPhaseChange(
          newPhase: AnimationGamePhase.showdown,
        );

        expect(wiring.previousPhase, AnimationGamePhase.showdown);
      });
    });
  });
}
