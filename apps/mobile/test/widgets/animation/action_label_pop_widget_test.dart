import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/widgets/animation/action_label_pop_widget.dart';

void main() {
  group('ActionLabelPopWidget', () {
    Widget buildTestWidget({
      PokerActionType actionType = PokerActionType.call,
      Duration popDuration = const Duration(milliseconds: 350),
      Duration displayDuration = const Duration(milliseconds: 100),
      Duration fadeOutDuration = const Duration(milliseconds: 100),
      VoidCallback? onComplete,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: ActionLabelPopWidget(
              actionType: actionType,
              popDuration: popDuration,
              displayDuration: displayDuration,
              fadeOutDuration: fadeOutDuration,
              onComplete: onComplete,
            ),
          ),
        ),
      );
    }

    group('rendering', () {
      testWidgets('displays correct label for CALL action', (tester) async {
        await tester.pumpWidget(buildTestWidget(actionType: PokerActionType.call));
        await tester.pump();

        expect(find.text('CALL'), findsOneWidget);
      });

      testWidgets('displays correct label for RAISE action', (tester) async {
        await tester.pumpWidget(buildTestWidget(actionType: PokerActionType.raise));
        await tester.pump();

        expect(find.text('RAISE'), findsOneWidget);
      });

      testWidgets('displays correct label for ALL IN action', (tester) async {
        await tester.pumpWidget(buildTestWidget(actionType: PokerActionType.allIn));
        await tester.pump();

        expect(find.text('ALL IN'), findsOneWidget);
      });

      testWidgets('displays correct label for CHECK action', (tester) async {
        await tester.pumpWidget(buildTestWidget(actionType: PokerActionType.check));
        await tester.pump();

        expect(find.text('CHECK'), findsOneWidget);
      });

      testWidgets('displays correct label for FOLD action', (tester) async {
        await tester.pumpWidget(buildTestWidget(actionType: PokerActionType.fold));
        await tester.pump();

        expect(find.text('FOLD'), findsOneWidget);
      });

      testWidgets('displays correct label for BLIND action', (tester) async {
        await tester.pumpWidget(buildTestWidget(actionType: PokerActionType.blind));
        await tester.pump();

        expect(find.text('BLIND'), findsOneWidget);
      });
    });

    group('pop-scale animation', () {
      testWidgets('reaches scale 1.0 after pop animation completes', (tester) async {
        await tester.pumpWidget(buildTestWidget(
          actionType: PokerActionType.call,
          popDuration: const Duration(milliseconds: 350),
          displayDuration: const Duration(milliseconds: 500),
          fadeOutDuration: const Duration(milliseconds: 200),
        ));

        // Pump through the pop animation.
        await tester.pump(const Duration(milliseconds: 350));

        // After pop completes, scale should be 1.0.
        final transform = tester.widget<Transform>(
          find.byKey(const ValueKey('action_label_scale')),
        );
        final scale = transform.transform.getMaxScaleOnAxis();
        expect(scale, closeTo(1.0, 0.05));
      });

      testWidgets('overshoots to approximately 1.2 during pop', (tester) async {
        await tester.pumpWidget(buildTestWidget(
          actionType: PokerActionType.raise,
          popDuration: const Duration(milliseconds: 350),
          displayDuration: const Duration(milliseconds: 500),
          fadeOutDuration: const Duration(milliseconds: 200),
        ));

        // Pump partway through the pop animation to catch the overshoot.
        double maxScale = 0.0;
        for (int ms = 10; ms <= 350; ms += 10) {
          await tester.pump(const Duration(milliseconds: 10));
          final transform = tester.widget<Transform>(
            find.byKey(const ValueKey('action_label_scale')),
          );
          final scale = transform.transform.getMaxScaleOnAxis();
          if (scale > maxScale) maxScale = scale;
        }

        // The maximum scale during the animation should exceed 1.0
        // (overshoot behavior).
        expect(maxScale, greaterThan(1.0));
        // And should be approximately 1.2 (within tolerance for curves).
        expect(maxScale, closeTo(1.2, 0.1));
      });

      testWidgets('scale increases from small to large during animation', (tester) async {
        await tester.pumpWidget(buildTestWidget(
          actionType: PokerActionType.call,
          popDuration: const Duration(milliseconds: 350),
          displayDuration: const Duration(milliseconds: 500),
          fadeOutDuration: const Duration(milliseconds: 200),
        ));

        // Check scale at early point in animation.
        await tester.pump(const Duration(milliseconds: 50));
        final transformEarly = tester.widget<Transform>(
          find.byKey(const ValueKey('action_label_scale')),
        );
        final earlyScale = transformEarly.transform.getMaxScaleOnAxis();

        // Pump to later point.
        await tester.pump(const Duration(milliseconds: 150));
        final transformLater = tester.widget<Transform>(
          find.byKey(const ValueKey('action_label_scale')),
        );
        final laterScale = transformLater.transform.getMaxScaleOnAxis();

        // Scale should increase over time.
        expect(laterScale, greaterThan(earlyScale));
      });
    });

    group('fade-out animation', () {
      testWidgets('fades out after full animation sequence', (tester) async {
        await tester.pumpWidget(buildTestWidget(
          actionType: PokerActionType.allIn,
          popDuration: const Duration(milliseconds: 100),
          displayDuration: const Duration(milliseconds: 100),
          fadeOutDuration: const Duration(milliseconds: 100),
        ));

        // Advance through the entire animation sequence.
        // The sequence is: pop(100ms) → delay(100ms) → fade(100ms).
        // We need to pump in stages to allow async continuations to fire.
        // Stage 1: Complete pop animation.
        await tester.pump(const Duration(milliseconds: 110));
        // Stage 2: Complete display delay timer.
        await tester.pump(const Duration(milliseconds: 110));
        // Stage 3: Complete fade animation.
        await tester.pump(const Duration(milliseconds: 110));

        // After full sequence, opacity should be 0.0.
        final opacityWidget = tester.widget<Opacity>(
          find.byKey(const ValueKey('action_label_opacity')),
        );
        expect(opacityWidget.opacity, closeTo(0.0, 0.01));
      });
    });

    group('onComplete callback', () {
      testWidgets('calls onComplete after full animation sequence',
          (tester) async {
        var completed = false;

        await tester.pumpWidget(buildTestWidget(
          actionType: PokerActionType.check,
          popDuration: const Duration(milliseconds: 100),
          displayDuration: const Duration(milliseconds: 100),
          fadeOutDuration: const Duration(milliseconds: 100),
          onComplete: () => completed = true,
        ));

        // Advance through the entire animation sequence in stages.
        await tester.pump(const Duration(milliseconds: 110)); // pop
        await tester.pump(const Duration(milliseconds: 110)); // display delay
        await tester.pump(const Duration(milliseconds: 110)); // fade
        await tester.pump(); // process final microtask

        expect(completed, isTrue);
      });
    });

    group('actionTypeFromString', () {
      test('converts "call" to PokerActionType.call', () {
        expect(
          ActionLabelPopWidget.actionTypeFromString('call'),
          PokerActionType.call,
        );
      });

      test('converts "raise" to PokerActionType.raise', () {
        expect(
          ActionLabelPopWidget.actionTypeFromString('raise'),
          PokerActionType.raise,
        );
      });

      test('converts "all_in" to PokerActionType.allIn', () {
        expect(
          ActionLabelPopWidget.actionTypeFromString('all_in'),
          PokerActionType.allIn,
        );
      });

      test('converts "check" to PokerActionType.check', () {
        expect(
          ActionLabelPopWidget.actionTypeFromString('check'),
          PokerActionType.check,
        );
      });

      test('converts "fold" to PokerActionType.fold', () {
        expect(
          ActionLabelPopWidget.actionTypeFromString('fold'),
          PokerActionType.fold,
        );
      });

      test('converts "blind" to PokerActionType.blind', () {
        expect(
          ActionLabelPopWidget.actionTypeFromString('blind'),
          PokerActionType.blind,
        );
      });

      test('returns null for unrecognized action', () {
        expect(ActionLabelPopWidget.actionTypeFromString('unknown'), isNull);
        expect(ActionLabelPopWidget.actionTypeFromString(null), isNull);
        expect(ActionLabelPopWidget.actionTypeFromString(''), isNull);
      });
    });

    group('getActionLabel', () {
      test('returns correct labels for all action types', () {
        expect(ActionLabelPopWidget.getActionLabel(PokerActionType.call), 'CALL');
        expect(ActionLabelPopWidget.getActionLabel(PokerActionType.raise), 'RAISE');
        expect(ActionLabelPopWidget.getActionLabel(PokerActionType.allIn), 'ALL IN');
        expect(ActionLabelPopWidget.getActionLabel(PokerActionType.check), 'CHECK');
        expect(ActionLabelPopWidget.getActionLabel(PokerActionType.fold), 'FOLD');
        expect(ActionLabelPopWidget.getActionLabel(PokerActionType.blind), 'BLIND');
      });
    });

    group('getActionColor', () {
      test('returns distinct colors for each action type', () {
        final colors = PokerActionType.values
            .map(ActionLabelPopWidget.getActionColor)
            .toSet();
        // All action types should have distinct colors.
        expect(colors.length, PokerActionType.values.length);
      });

      test('returns expected colors for key actions', () {
        expect(
          ActionLabelPopWidget.getActionColor(PokerActionType.call),
          Colors.blue.shade700,
        );
        expect(
          ActionLabelPopWidget.getActionColor(PokerActionType.raise),
          Colors.orange.shade800,
        );
        expect(
          ActionLabelPopWidget.getActionColor(PokerActionType.allIn),
          Colors.purple.shade700,
        );
        expect(
          ActionLabelPopWidget.getActionColor(PokerActionType.check),
          Colors.green.shade700,
        );
        expect(
          ActionLabelPopWidget.getActionColor(PokerActionType.fold),
          Colors.red.shade800,
        );
      });
    });
  });
}
