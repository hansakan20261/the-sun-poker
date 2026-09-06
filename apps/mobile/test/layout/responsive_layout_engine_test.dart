import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_sun_poker/layout/responsive_card_config.dart';
import 'package:the_sun_poker/layout/responsive_layout_engine.dart';

void main() {
  group('BreakpointTier classification', () {
    test('width 379 classifies as compact', () {
      expect(
        ResponsiveLayoutEngine.classifyTier(379),
        equals(BreakpointTier.compact),
      );
    });

    test('width 380 classifies as standard', () {
      expect(
        ResponsiveLayoutEngine.classifyTier(380),
        equals(BreakpointTier.standard),
      );
    });

    test('width 429 classifies as standard', () {
      expect(
        ResponsiveLayoutEngine.classifyTier(429),
        equals(BreakpointTier.standard),
      );
    });

    test('width 430 classifies as expanded', () {
      expect(
        ResponsiveLayoutEngine.classifyTier(430),
        equals(BreakpointTier.expanded),
      );
    });

    test('width 767 classifies as expanded', () {
      expect(
        ResponsiveLayoutEngine.classifyTier(767),
        equals(BreakpointTier.expanded),
      );
    });

    test('width 768 classifies as large', () {
      expect(
        ResponsiveLayoutEngine.classifyTier(768),
        equals(BreakpointTier.large),
      );
    });

    test('very small width (320) classifies as compact', () {
      expect(
        ResponsiveLayoutEngine.classifyTier(320),
        equals(BreakpointTier.compact),
      );
    });

    test('very large width (1366) classifies as large', () {
      expect(
        ResponsiveLayoutEngine.classifyTier(1366),
        equals(BreakpointTier.large),
      );
    });
  });

  group('Card sizes match spec for each tier', () {
    test('compact tier returns 36x50 player card', () {
      final engine = ResponsiveLayoutEngine(350);
      expect(engine.cardSize, equals(const Size(36, 50)));
    });

    test('standard tier returns 48x66 player card', () {
      final engine = ResponsiveLayoutEngine(400);
      expect(engine.cardSize, equals(const Size(48, 66)));
    });

    test('expanded tier returns 54x74 player card', () {
      final engine = ResponsiveLayoutEngine(500);
      expect(engine.cardSize, equals(const Size(54, 74)));
    });

    test('large tier returns 64x90 player card', () {
      final engine = ResponsiveLayoutEngine(800);
      expect(engine.cardSize, equals(const Size(64, 90)));
    });

    test('compact tier returns 18x25 opponent card', () {
      final engine = ResponsiveLayoutEngine(350);
      expect(engine.opponentCardSize, equals(const Size(18, 25)));
    });

    test('standard tier returns 22x32 opponent card', () {
      final engine = ResponsiveLayoutEngine(400);
      expect(engine.opponentCardSize, equals(const Size(22, 32)));
    });

    test('expanded tier returns 26x36 opponent card', () {
      final engine = ResponsiveLayoutEngine(500);
      expect(engine.opponentCardSize, equals(const Size(26, 36)));
    });

    test('large tier returns 32x44 opponent card', () {
      final engine = ResponsiveLayoutEngine(800);
      expect(engine.opponentCardSize, equals(const Size(32, 44)));
    });

    test('compact tier returns 28x39 community card', () {
      final engine = ResponsiveLayoutEngine(350);
      expect(engine.communityCardSize, equals(const Size(28, 39)));
    });

    test('standard tier returns 34x48 community card', () {
      final engine = ResponsiveLayoutEngine(400);
      expect(engine.communityCardSize, equals(const Size(34, 48)));
    });

    test('expanded tier returns 40x55 community card', () {
      final engine = ResponsiveLayoutEngine(500);
      expect(engine.communityCardSize, equals(const Size(40, 55)));
    });

    test('large tier returns 50x70 community card', () {
      final engine = ResponsiveLayoutEngine(800);
      expect(engine.communityCardSize, equals(const Size(50, 70)));
    });
  });

  group('Seat positions for 2-9 players', () {
    final screenSize = const Size(430, 800);

    for (int playerCount = 2; playerCount <= 9; playerCount++) {
      test('$playerCount players: all positions within 0-1 range', () {
        final engine = ResponsiveLayoutEngine(screenSize.width);
        final positions = engine.getSeatPositions(
          playerCount,
          screenSize,
          LayoutOrientation.portrait,
        );

        expect(positions.length, equals(playerCount));

        for (int i = 0; i < positions.length; i++) {
          expect(
            positions[i].dx,
            inInclusiveRange(0.0, 1.0),
            reason: 'Player $i x position out of range',
          );
          expect(
            positions[i].dy,
            inInclusiveRange(0.0, 1.0),
            reason: 'Player $i y position out of range',
          );
        }
      });
    }

    test('first seat (player) is at bottom center', () {
      final engine = ResponsiveLayoutEngine(screenSize.width);
      final positions = engine.getSeatPositions(
        4,
        screenSize,
        LayoutOrientation.portrait,
      );

      // First seat should be near bottom center (x ≈ 0.5, y > 0.7)
      expect(positions[0].dx, closeTo(0.5, 0.15));
      expect(positions[0].dy, greaterThan(0.7));
    });

    test('positions are distinct for all player counts', () {
      final engine = ResponsiveLayoutEngine(screenSize.width);

      for (int count = 2; count <= 9; count++) {
        final positions = engine.getSeatPositions(
          count,
          screenSize,
          LayoutOrientation.portrait,
        );

        // Check all positions are distinct
        for (int i = 0; i < positions.length; i++) {
          for (int j = i + 1; j < positions.length; j++) {
            final distance = (positions[i] - positions[j]).distance;
            expect(
              distance,
              greaterThan(0.01),
              reason:
                  'Seats $i and $j overlap for $count players',
            );
          }
        }
      }
    });

    test('landscape positions use wider x radius', () {
      final landscapeScreen = const Size(800, 430);
      final engine = ResponsiveLayoutEngine(landscapeScreen.width);

      final landscapePositions = engine.getSeatPositions(
        6,
        landscapeScreen,
        LayoutOrientation.landscape,
      );

      final portraitPositions = engine.getSeatPositions(
        6,
        const Size(430, 800),
        LayoutOrientation.portrait,
      );

      // In landscape, x spread should be wider
      final landscapeXSpread = landscapePositions
          .map((p) => p.dx)
          .reduce((a, b) => a > b ? a : b) -
          landscapePositions.map((p) => p.dx).reduce((a, b) => a < b ? a : b);

      final portraitXSpread = portraitPositions
          .map((p) => p.dx)
          .reduce((a, b) => a > b ? a : b) -
          portraitPositions.map((p) => p.dx).reduce((a, b) => a < b ? a : b);

      expect(landscapeXSpread, greaterThan(portraitXSpread));
    });
  });

  group('Table aspect ratio', () {
    test('landscape table has approximately 2:1 ratio', () {
      final engine = ResponsiveLayoutEngine(800);
      final tableSize = engine.getTableSize(
        const Size(800, 600),
        orientation: LayoutOrientation.landscape,
      );

      final ratio = tableSize.width / tableSize.height;
      // Should be approximately 2:1 within ±5% tolerance
      expect(ratio, closeTo(2.0, 0.1));
    });

    test('portrait table has approximately 1.5:1 ratio', () {
      final engine = ResponsiveLayoutEngine(430);
      final tableSize = engine.getTableSize(
        const Size(430, 800),
        orientation: LayoutOrientation.portrait,
      );

      final ratio = tableSize.width / tableSize.height;
      // Should be approximately 1.5:1 within ±5% tolerance
      expect(ratio, closeTo(1.5, 0.075));
    });

    test('table fits within screen bounds in landscape', () {
      final engine = ResponsiveLayoutEngine(800);
      const screen = Size(800, 600);
      final tableSize = engine.getTableSize(
        screen,
        orientation: LayoutOrientation.landscape,
      );

      expect(tableSize.width, lessThanOrEqualTo(screen.width));
      expect(tableSize.height, lessThanOrEqualTo(screen.height));
    });

    test('table fits within screen bounds in portrait', () {
      final engine = ResponsiveLayoutEngine(430);
      const screen = Size(430, 800);
      final tableSize = engine.getTableSize(
        screen,
        orientation: LayoutOrientation.portrait,
      );

      expect(tableSize.width, lessThanOrEqualTo(screen.width));
      expect(tableSize.height, lessThanOrEqualTo(screen.height));
    });

    test('table ratio within ±5% tolerance for various landscape sizes', () {
      final sizes = [
        const Size(768, 600),
        const Size(1024, 768),
        const Size(1366, 1024),
      ];

      for (final screen in sizes) {
        final engine = ResponsiveLayoutEngine(screen.width);
        final tableSize = engine.getTableSize(
          screen,
          orientation: LayoutOrientation.landscape,
        );

        final ratio = tableSize.width / tableSize.height;
        // 2:1 ± 5% means ratio should be between 1.9 and 2.1
        expect(
          ratio,
          inInclusiveRange(1.9, 2.1),
          reason: 'Landscape ratio out of tolerance for screen $screen',
        );
      }
    });

    test('table ratio within ±5% tolerance for various portrait sizes', () {
      final sizes = [
        const Size(320, 480),
        const Size(375, 667),
        const Size(430, 932),
      ];

      for (final screen in sizes) {
        final engine = ResponsiveLayoutEngine(screen.width);
        final tableSize = engine.getTableSize(
          screen,
          orientation: LayoutOrientation.portrait,
        );

        final ratio = tableSize.width / tableSize.height;
        // 1.5:1 ± 5% means ratio should be between 1.425 and 1.575
        expect(
          ratio,
          inInclusiveRange(1.425, 1.575),
          reason: 'Portrait ratio out of tolerance for screen $screen',
        );
      }
    });
  });

  group('Bounds checking', () {
    test('validates bounds for standard phone in portrait', () {
      final engine = ResponsiveLayoutEngine(390);
      final result = engine.validateBounds(
        playerCount: 6,
        screenSize: const Size(390, 844),
        orientation: LayoutOrientation.portrait,
      );
      expect(result, isTrue);
    });

    test('validates bounds for iPad in landscape', () {
      final engine = ResponsiveLayoutEngine(1024);
      final result = engine.validateBounds(
        playerCount: 9,
        screenSize: const Size(1024, 768),
        orientation: LayoutOrientation.landscape,
      );
      expect(result, isTrue);
    });

    test('validates bounds for minimum supported screen', () {
      final engine = ResponsiveLayoutEngine(320);
      final result = engine.validateBounds(
        playerCount: 2,
        screenSize: const Size(320, 480),
        orientation: LayoutOrientation.portrait,
      );
      expect(result, isTrue);
    });

    test('rejects screen width below minimum', () {
      final engine = ResponsiveLayoutEngine(300);
      final result = engine.validateBounds(
        playerCount: 4,
        screenSize: const Size(300, 500),
        orientation: LayoutOrientation.portrait,
      );
      expect(result, isFalse);
    });

    test('rejects screen width above maximum', () {
      final engine = ResponsiveLayoutEngine(1400);
      final result = engine.validateBounds(
        playerCount: 4,
        screenSize: const Size(1400, 900),
        orientation: LayoutOrientation.landscape,
      );
      expect(result, isFalse);
    });

    test('validates all player counts on supported screens', () {
      final screens = [
        const Size(320, 480),
        const Size(375, 667),
        const Size(390, 844),
        const Size(430, 932),
        const Size(768, 1024),
        const Size(1024, 768),
      ];

      for (final screen in screens) {
        final engine = ResponsiveLayoutEngine(screen.width);
        final orientation = screen.width > screen.height
            ? LayoutOrientation.landscape
            : LayoutOrientation.portrait;

        for (int count = 2; count <= 9; count++) {
          final result = engine.validateBounds(
            playerCount: count,
            screenSize: screen,
            orientation: orientation,
          );
          expect(
            result,
            isTrue,
            reason:
                'Bounds check failed for $count players on ${screen.width}x${screen.height}',
          );
        }
      }
    });
  });

  group('Animation scale', () {
    test('standard tier midpoint returns approximately 1.0', () {
      final engine = ResponsiveLayoutEngine(405);
      expect(engine.animationScale, closeTo(1.0, 0.01));
    });

    test('compact screen returns scale < 1.0', () {
      final engine = ResponsiveLayoutEngine(320);
      expect(engine.animationScale, lessThan(1.0));
    });

    test('large screen returns scale > 1.0', () {
      final engine = ResponsiveLayoutEngine(800);
      expect(engine.animationScale, greaterThan(1.0));
    });

    test('scale is clamped to minimum 0.5', () {
      final engine = ResponsiveLayoutEngine(100);
      expect(engine.animationScale, greaterThanOrEqualTo(0.5));
    });

    test('scale is clamped to maximum 2.0', () {
      final engine = ResponsiveLayoutEngine(2000);
      expect(engine.animationScale, lessThanOrEqualTo(2.0));
    });
  });

  group('Layout transition duration', () {
    test('layoutTransitionDuration is 300ms', () {
      expect(ResponsiveLayoutEngine.layoutTransitionDuration, equals(300));
    });
  });

  group('ResponsiveCardConfig', () {
    test('all tiers have player card entries', () {
      for (final tier in BreakpointTier.values) {
        expect(ResponsiveCardConfig.playerCard.containsKey(tier), isTrue);
      }
    });

    test('all tiers have opponent card entries', () {
      for (final tier in BreakpointTier.values) {
        expect(ResponsiveCardConfig.opponentCard.containsKey(tier), isTrue);
      }
    });

    test('all tiers have community card entries', () {
      for (final tier in BreakpointTier.values) {
        expect(ResponsiveCardConfig.communityCard.containsKey(tier), isTrue);
      }
    });

    test('player cards are larger than opponent cards at each tier', () {
      for (final tier in BreakpointTier.values) {
        final player = ResponsiveCardConfig.playerCard[tier]!;
        final opponent = ResponsiveCardConfig.opponentCard[tier]!;
        expect(player.width, greaterThan(opponent.width));
        expect(player.height, greaterThan(opponent.height));
      }
    });

    test('community cards are between opponent and player sizes', () {
      for (final tier in BreakpointTier.values) {
        final player = ResponsiveCardConfig.playerCard[tier]!;
        final opponent = ResponsiveCardConfig.opponentCard[tier]!;
        final community = ResponsiveCardConfig.communityCard[tier]!;
        expect(community.width, greaterThan(opponent.width));
        expect(community.width, lessThan(player.width));
        expect(community.height, greaterThan(opponent.height));
        expect(community.height, lessThan(player.height));
      }
    });

    test('card sizes increase with tier', () {
      final tiers = BreakpointTier.values;
      for (int i = 0; i < tiers.length - 1; i++) {
        final current = ResponsiveCardConfig.playerCard[tiers[i]]!;
        final next = ResponsiveCardConfig.playerCard[tiers[i + 1]]!;
        expect(next.width, greaterThan(current.width));
        expect(next.height, greaterThan(current.height));
      }
    });
  });
}
