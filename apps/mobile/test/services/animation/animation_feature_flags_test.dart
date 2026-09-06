import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/services/animation/animation_feature_flags.dart';

void main() {
  group('AnimationFeatureFlags', () {
    group('default values', () {
      test('all flags default to true', () {
        final flags = AnimationFeatureFlags();

        expect(flags.useRiveAnimations, isTrue);
        expect(flags.useDealAnimation, isTrue);
        expect(flags.useChipAnimation, isTrue);
        expect(flags.useCelebrationAnimation, isTrue);
        expect(flags.useCountdownAnimation, isTrue);
        expect(flags.useResponsiveLayout, isTrue);
      });

      test('all resolved getters return true by default', () {
        final flags = AnimationFeatureFlags();

        expect(flags.isDealAnimationEnabled, isTrue);
        expect(flags.isChipAnimationEnabled, isTrue);
        expect(flags.isCelebrationAnimationEnabled, isTrue);
        expect(flags.isCountdownAnimationEnabled, isTrue);
        expect(flags.isResponsiveLayoutEnabled, isTrue);
      });
    });

    group('master toggle', () {
      test('disabling master toggle disables all resolved getters', () {
        final flags = AnimationFeatureFlags(useRiveAnimations: false);

        expect(flags.isDealAnimationEnabled, isFalse);
        expect(flags.isChipAnimationEnabled, isFalse);
        expect(flags.isCelebrationAnimationEnabled, isFalse);
        expect(flags.isCountdownAnimationEnabled, isFalse);
        expect(flags.isResponsiveLayoutEnabled, isFalse);
      });

      test(
          'master toggle false overrides individual flags even when they are true',
          () {
        final flags = AnimationFeatureFlags(
          useRiveAnimations: false,
          useDealAnimation: true,
          useChipAnimation: true,
          useCelebrationAnimation: true,
          useCountdownAnimation: true,
          useResponsiveLayout: true,
        );

        expect(flags.isDealAnimationEnabled, isFalse);
        expect(flags.isChipAnimationEnabled, isFalse);
        expect(flags.isCelebrationAnimationEnabled, isFalse);
        expect(flags.isCountdownAnimationEnabled, isFalse);
        expect(flags.isResponsiveLayoutEnabled, isFalse);
      });
    });

    group('per-phase flags', () {
      test('disabling deal flag only affects deal animation', () {
        final flags = AnimationFeatureFlags(useDealAnimation: false);

        expect(flags.isDealAnimationEnabled, isFalse);
        expect(flags.isChipAnimationEnabled, isTrue);
        expect(flags.isCelebrationAnimationEnabled, isTrue);
        expect(flags.isCountdownAnimationEnabled, isTrue);
        expect(flags.isResponsiveLayoutEnabled, isTrue);
      });

      test('disabling chip flag only affects chip animation', () {
        final flags = AnimationFeatureFlags(useChipAnimation: false);

        expect(flags.isDealAnimationEnabled, isTrue);
        expect(flags.isChipAnimationEnabled, isFalse);
        expect(flags.isCelebrationAnimationEnabled, isTrue);
        expect(flags.isCountdownAnimationEnabled, isTrue);
        expect(flags.isResponsiveLayoutEnabled, isTrue);
      });

      test('disabling celebration flag only affects celebration animation', () {
        final flags = AnimationFeatureFlags(useCelebrationAnimation: false);

        expect(flags.isDealAnimationEnabled, isTrue);
        expect(flags.isChipAnimationEnabled, isTrue);
        expect(flags.isCelebrationAnimationEnabled, isFalse);
        expect(flags.isCountdownAnimationEnabled, isTrue);
        expect(flags.isResponsiveLayoutEnabled, isTrue);
      });

      test('disabling countdown flag only affects countdown animation', () {
        final flags = AnimationFeatureFlags(useCountdownAnimation: false);

        expect(flags.isDealAnimationEnabled, isTrue);
        expect(flags.isChipAnimationEnabled, isTrue);
        expect(flags.isCelebrationAnimationEnabled, isTrue);
        expect(flags.isCountdownAnimationEnabled, isFalse);
        expect(flags.isResponsiveLayoutEnabled, isTrue);
      });

      test('disabling layout flag only affects responsive layout', () {
        final flags = AnimationFeatureFlags(useResponsiveLayout: false);

        expect(flags.isDealAnimationEnabled, isTrue);
        expect(flags.isChipAnimationEnabled, isTrue);
        expect(flags.isCelebrationAnimationEnabled, isTrue);
        expect(flags.isCountdownAnimationEnabled, isTrue);
        expect(flags.isResponsiveLayoutEnabled, isFalse);
      });
    });

    group('disableAll / enableAll', () {
      test('disableAll sets master toggle to false', () {
        final flags = AnimationFeatureFlags();
        flags.disableAll();

        expect(flags.useRiveAnimations, isFalse);
        expect(flags.isDealAnimationEnabled, isFalse);
        expect(flags.isChipAnimationEnabled, isFalse);
        expect(flags.isCelebrationAnimationEnabled, isFalse);
        expect(flags.isCountdownAnimationEnabled, isFalse);
        expect(flags.isResponsiveLayoutEnabled, isFalse);
      });

      test('enableAll sets all flags to true', () {
        final flags = AnimationFeatureFlags(
          useRiveAnimations: false,
          useDealAnimation: false,
          useChipAnimation: false,
          useCelebrationAnimation: false,
          useCountdownAnimation: false,
          useResponsiveLayout: false,
        );
        flags.enableAll();

        expect(flags.useRiveAnimations, isTrue);
        expect(flags.useDealAnimation, isTrue);
        expect(flags.useChipAnimation, isTrue);
        expect(flags.useCelebrationAnimation, isTrue);
        expect(flags.useCountdownAnimation, isTrue);
        expect(flags.useResponsiveLayout, isTrue);
        expect(flags.isDealAnimationEnabled, isTrue);
        expect(flags.isChipAnimationEnabled, isTrue);
        expect(flags.isCelebrationAnimationEnabled, isTrue);
        expect(flags.isCountdownAnimationEnabled, isTrue);
        expect(flags.isResponsiveLayoutEnabled, isTrue);
      });
    });

    group('copyWith', () {
      test('copyWith creates independent copy', () {
        final original = AnimationFeatureFlags();
        final copy = original.copyWith(useDealAnimation: false);

        expect(original.useDealAnimation, isTrue);
        expect(copy.useDealAnimation, isFalse);
      });

      test('copyWith preserves unspecified values', () {
        final original = AnimationFeatureFlags(
          useChipAnimation: false,
          useCountdownAnimation: false,
        );
        final copy = original.copyWith(useDealAnimation: false);

        expect(copy.useRiveAnimations, isTrue);
        expect(copy.useDealAnimation, isFalse);
        expect(copy.useChipAnimation, isFalse);
        expect(copy.useCelebrationAnimation, isTrue);
        expect(copy.useCountdownAnimation, isFalse);
        expect(copy.useResponsiveLayout, isTrue);
      });
    });

    group('equality', () {
      test('equal flags are equal', () {
        final a = AnimationFeatureFlags();
        final b = AnimationFeatureFlags();

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different flags are not equal', () {
        final a = AnimationFeatureFlags();
        final b = AnimationFeatureFlags(useDealAnimation: false);

        expect(a, isNot(equals(b)));
      });
    });

    group('toString', () {
      test('toString includes all flag values', () {
        final flags = AnimationFeatureFlags();
        final str = flags.toString();

        expect(str, contains('master: true'));
        expect(str, contains('deal: true'));
        expect(str, contains('chip: true'));
        expect(str, contains('celebration: true'));
        expect(str, contains('countdown: true'));
        expect(str, contains('layout: true'));
      });
    });
  });
}
