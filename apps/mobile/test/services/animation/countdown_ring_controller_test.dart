import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/countdown_ring_controller.dart';

void main() {
  group('CountdownRingController', () {
    late CountdownRingController controller;
    late List<int> soundTicks;
    late List<int> hapticTicks;
    late int expiredCount;

    setUp(() {
      soundTicks = [];
      hapticTicks = [];
      expiredCount = 0;

      controller = CountdownRingController(
        onTickSound: (seconds) => soundTicks.add(seconds),
        onTickHaptic: (seconds) => hapticTicks.add(seconds),
        onExpired: () => expiredCount++,
      );
    });

    tearDown(() {
      controller.stop(); // Ensure timer is cancelled before dispose.
    });

    group('initial state', () {
      test('starts with default idle state', () {
        final state = controller.state.value;
        expect(state.secondsRemaining, 0);
        expect(state.totalDuration, 0);
        expect(state.progress, 1.0);
        expect(state.color, CountdownRingColor.green);
        expect(state.isPulsing, false);
        expect(state.isExpired, false);
      });

      test('isRunning is false before start', () {
        expect(controller.isRunning, false);
      });
    });

    group('start', () {
      testWidgets('sets initial state correctly', (tester) async {
        controller.start(30);

        final state = controller.state.value;
        expect(state.secondsRemaining, 30);
        expect(state.totalDuration, 30);
        expect(state.progress, 1.0);
        expect(state.color, CountdownRingColor.green);
        expect(state.isPulsing, false);
        expect(state.isExpired, false);
        expect(controller.isRunning, true);

        controller.stop();
      });

      test('handles zero duration by expiring immediately', () {
        controller.start(0);

        expect(controller.state.value.isExpired, true);
        expect(expiredCount, 1);
        expect(controller.isRunning, false);
      });

      test('handles negative duration by expiring immediately', () {
        controller.start(-5);

        expect(controller.state.value.isExpired, true);
        expect(expiredCount, 1);
        expect(controller.isRunning, false);
      });

      testWidgets('stops previous countdown when starting a new one', (tester) async {
        controller.start(30);
        expect(controller.isRunning, true);

        controller.start(20);
        expect(controller.state.value.totalDuration, 20);
        expect(controller.state.value.secondsRemaining, 20);

        controller.stop();
      });
    });

    group('color transitions', () {
      testWidgets('color is green when > 10 seconds remain', (tester) async {
        controller.start(30);

        // Tick down to 11 seconds (19 ticks).
        for (int i = 0; i < 19; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(controller.state.value.secondsRemaining, 11);
        expect(controller.state.value.color, CountdownRingColor.green);

        controller.stop();
      });

      testWidgets('color changes to yellow at 10 seconds', (tester) async {
        controller.start(30);

        // Tick down to 10 seconds (20 ticks).
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(controller.state.value.secondsRemaining, 10);
        expect(controller.state.value.color, CountdownRingColor.yellow);

        controller.stop();
      });

      testWidgets('color stays yellow at 6 seconds', (tester) async {
        controller.start(30);

        // Tick down to 6 seconds (24 ticks).
        for (int i = 0; i < 24; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(controller.state.value.secondsRemaining, 6);
        expect(controller.state.value.color, CountdownRingColor.yellow);

        controller.stop();
      });

      testWidgets('color changes to red at 5 seconds', (tester) async {
        controller.start(30);

        // Tick down to 5 seconds (25 ticks).
        for (int i = 0; i < 25; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(controller.state.value.secondsRemaining, 5);
        expect(controller.state.value.color, CountdownRingColor.red);

        controller.stop();
      });

      testWidgets('color is red at 1 second', (tester) async {
        controller.start(30);

        // Tick down to 1 second (29 ticks).
        for (int i = 0; i < 29; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(controller.state.value.secondsRemaining, 1);
        expect(controller.state.value.color, CountdownRingColor.red);

        controller.stop();
      });

      testWidgets('starts yellow when total duration is 10', (tester) async {
        controller.start(10);

        expect(controller.state.value.color, CountdownRingColor.yellow);

        controller.stop();
      });

      testWidgets('starts red when total duration is 5', (tester) async {
        controller.start(5);

        expect(controller.state.value.color, CountdownRingColor.red);

        controller.stop();
      });
    });

    group('isPulsing', () {
      testWidgets('isPulsing is false when > 5 seconds remain', (tester) async {
        controller.start(30);

        // Tick to 6 seconds (24 ticks).
        for (int i = 0; i < 24; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(controller.state.value.secondsRemaining, 6);
        expect(controller.state.value.isPulsing, false);

        controller.stop();
      });

      testWidgets('isPulsing activates at 5 seconds', (tester) async {
        controller.start(30);

        // Tick to 5 seconds (25 ticks).
        for (int i = 0; i < 25; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(controller.state.value.secondsRemaining, 5);
        expect(controller.state.value.isPulsing, true);

        controller.stop();
      });

      testWidgets('isPulsing stays true at 1 second', (tester) async {
        controller.start(30);

        // Tick to 1 second (29 ticks).
        for (int i = 0; i < 29; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(controller.state.value.secondsRemaining, 1);
        expect(controller.state.value.isPulsing, true);

        controller.stop();
      });

      testWidgets('isPulsing is true from start when duration <= 5', (tester) async {
        controller.start(5);

        expect(controller.state.value.isPulsing, true);

        controller.stop();
      });
    });

    group('sound tick callback', () {
      testWidgets('fires on each second when <= 5 seconds remain', (tester) async {
        controller.start(8);

        // Tick 3 times: 8 -> 7 -> 6 -> 5
        for (int i = 0; i < 3; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        // At 5 seconds, sound should fire.
        expect(soundTicks, [5]);

        // Tick to 4.
        await tester.pump(const Duration(seconds: 1));
        expect(soundTicks, [5, 4]);

        // Tick to 3.
        await tester.pump(const Duration(seconds: 1));
        expect(soundTicks, [5, 4, 3]);

        // Tick to 2.
        await tester.pump(const Duration(seconds: 1));
        expect(soundTicks, [5, 4, 3, 2]);

        // Tick to 1.
        await tester.pump(const Duration(seconds: 1));
        expect(soundTicks, [5, 4, 3, 2, 1]);

        // Tick to 0 (expiry) — timer stops itself.
        await tester.pump(const Duration(seconds: 1));
        expect(soundTicks, [5, 4, 3, 2, 1, 0]);
      });

      testWidgets('does not fire when > 5 seconds remain', (tester) async {
        controller.start(15);

        // Tick 4 times: 15 -> 14 -> 13 -> 12 -> 11
        for (int i = 0; i < 4; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(soundTicks, isEmpty);

        controller.stop();
      });
    });

    group('haptic tick callback', () {
      testWidgets('fires on each second when <= 3 seconds remain', (tester) async {
        controller.start(6);

        // Tick 3 times: 6 -> 5 -> 4 -> 3
        for (int i = 0; i < 3; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        // At 3 seconds, haptic should fire.
        expect(hapticTicks, [3]);

        // Tick to 2.
        await tester.pump(const Duration(seconds: 1));
        expect(hapticTicks, [3, 2]);

        // Tick to 1.
        await tester.pump(const Duration(seconds: 1));
        expect(hapticTicks, [3, 2, 1]);

        // Tick to 0 (expiry) — timer stops itself.
        await tester.pump(const Duration(seconds: 1));
        expect(hapticTicks, [3, 2, 1, 0]);
      });

      testWidgets('does not fire when > 3 seconds remain', (tester) async {
        controller.start(10);

        // Tick 5 times: 10 -> 9 -> 8 -> 7 -> 6 -> 5
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        // At 5 seconds, only sound fires, not haptic.
        expect(hapticTicks, isEmpty);

        controller.stop();
      });
    });

    group('onExpired callback', () {
      testWidgets('fires when timer reaches 0', (tester) async {
        controller.start(3);

        // Tick 3 times to reach 0.
        for (int i = 0; i < 3; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(expiredCount, 1);
        expect(controller.state.value.isExpired, true);
        expect(controller.isRunning, false);
      });

      testWidgets('fires exactly once', (tester) async {
        controller.start(2);

        // Tick to 0.
        for (int i = 0; i < 2; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        // Extra ticks should not fire again (timer already stopped).
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(expiredCount, 1);
      });
    });

    group('stop', () {
      testWidgets('cancels the countdown', (tester) async {
        controller.start(10);

        // Tick 3 times.
        for (int i = 0; i < 3; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(controller.state.value.secondsRemaining, 7);

        controller.stop();
        expect(controller.isRunning, false);

        // Further ticks should not change state.
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(controller.state.value.secondsRemaining, 7);
        expect(expiredCount, 0);
      });
    });

    group('progress', () {
      testWidgets('decreases from 1.0 to 0.0 over duration', (tester) async {
        controller.start(4);

        expect(controller.state.value.progress, 1.0);

        await tester.pump(const Duration(seconds: 1));
        expect(controller.state.value.progress, closeTo(0.75, 0.01));

        await tester.pump(const Duration(seconds: 1));
        expect(controller.state.value.progress, closeTo(0.5, 0.01));

        await tester.pump(const Duration(seconds: 1));
        expect(controller.state.value.progress, closeTo(0.25, 0.01));

        // Final tick expires the timer.
        await tester.pump(const Duration(seconds: 1));
        expect(controller.state.value.progress, 0.0);
      });
    });

    group('dispose', () {
      testWidgets('stops the timer and prevents further updates', (tester) async {
        // Use a separate controller for this test to avoid double-dispose in tearDown.
        final disposableController = CountdownRingController(
          onExpired: () => expiredCount++,
        );

        disposableController.start(10);

        await tester.pump(const Duration(seconds: 1));
        expect(disposableController.state.value.secondsRemaining, 9);

        disposableController.dispose();

        // Further ticks should not crash or update state.
        await tester.pump(const Duration(seconds: 1));
        // No assertion needed — just verifying no crash.
      });
    });

    group('CountdownRingState', () {
      test('copyWith creates new instance with updated fields', () {
        const original = CountdownRingState(
          secondsRemaining: 10,
          totalDuration: 30,
          progress: 0.33,
          color: CountdownRingColor.yellow,
          isPulsing: false,
          isExpired: false,
        );

        final updated = original.copyWith(
          secondsRemaining: 5,
          color: CountdownRingColor.red,
          isPulsing: true,
        );

        expect(updated.secondsRemaining, 5);
        expect(updated.totalDuration, 30);
        expect(updated.progress, 0.33);
        expect(updated.color, CountdownRingColor.red);
        expect(updated.isPulsing, true);
        expect(updated.isExpired, false);
      });

      test('copyWith preserves unchanged fields', () {
        const original = CountdownRingState(
          secondsRemaining: 20,
          totalDuration: 30,
          progress: 0.67,
          color: CountdownRingColor.green,
          isPulsing: false,
          isExpired: false,
        );

        final updated = original.copyWith(progress: 0.5);

        expect(updated.secondsRemaining, 20);
        expect(updated.totalDuration, 30);
        expect(updated.progress, 0.5);
        expect(updated.color, CountdownRingColor.green);
        expect(updated.isPulsing, false);
        expect(updated.isExpired, false);
      });
    });

    group('CountdownRingColor', () {
      test('has all expected values', () {
        expect(CountdownRingColor.values, [
          CountdownRingColor.green,
          CountdownRingColor.yellow,
          CountdownRingColor.red,
        ]);
      });
    });

    group('timer expiry auto-actions integration', () {
      testWidgets('onExpired can be used for poker auto-fold', (tester) async {
        bool autoFolded = false;
        final pokerController = CountdownRingController(
          onExpired: () => autoFolded = true,
        );

        pokerController.start(3);

        for (int i = 0; i < 3; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(autoFolded, true);
        // Timer already stopped on expiry, no need to call stop().
      });

      testWidgets('onExpired can be used for Chinese poker auto-arrange', (tester) async {
        bool autoArranged = false;
        final chineseController = CountdownRingController(
          onExpired: () => autoArranged = true,
        );

        chineseController.start(2);

        for (int i = 0; i < 2; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(autoArranged, true);
        // Timer already stopped on expiry, no need to call stop().
      });
    });
  });
}
