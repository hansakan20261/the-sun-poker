import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_sun_poker/widgets/game/player_avatar_widget.dart';
import 'package:the_sun_poker/widgets/game/playing_card_widget.dart';

void main() {
  group('PlayerAvatarWidget.getAvatarBorderColor', () {
    test('active status returns green', () {
      final color = PlayerAvatarWidget.getAvatarBorderColor(PlayerStatus.active);
      expect(color, const Color(0xFF4CAF50));
    });

    test('turn status returns yellow', () {
      final color = PlayerAvatarWidget.getAvatarBorderColor(PlayerStatus.turn);
      expect(color, const Color(0xFFFFEB3B));
    });

    test('folded status returns gray', () {
      final color = PlayerAvatarWidget.getAvatarBorderColor(PlayerStatus.folded);
      expect(color, const Color(0xFF9E9E9E));
    });

    test('allIn status returns green', () {
      final color = PlayerAvatarWidget.getAvatarBorderColor(PlayerStatus.allIn);
      expect(color, const Color(0xFF4CAF50));
    });

    test('sittingOut status returns gray', () {
      final color = PlayerAvatarWidget.getAvatarBorderColor(PlayerStatus.sittingOut);
      expect(color, const Color(0xFF9E9E9E));
    });
  });

  group('PlayerAvatarWidget.abbreviateChipCount', () {
    test('values below 1000 shown as-is', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(0), '0');
      expect(PlayerAvatarWidget.abbreviateChipCount(1), '1');
      expect(PlayerAvatarWidget.abbreviateChipCount(999), '999');
    });

    test('exactly 1000 shown as 1K', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(1000), '1K');
    });

    test('1500 shown as 1.5K', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(1500), '1.5K');
    });

    test('10000 shown as 10K', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(10000), '10K');
    });

    test('999000 shown as 999K', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(999000), '999K');
    });

    test('exactly 1000000 shown as 1M', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(1000000), '1M');
    });

    test('1500000 shown as 1.5M', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(1500000), '1.5M');
    });

    test('10000000 shown as 10M', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(10000000), '10M');
    });

    test('negative values return 0', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(-1), '0');
      expect(PlayerAvatarWidget.abbreviateChipCount(-1000), '0');
    });

    test('2000 shown as 2K', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(2000), '2K');
    });

    test('2500000 shown as 2.5M', () {
      expect(PlayerAvatarWidget.abbreviateChipCount(2500000), '2.5M');
    });
  });

  group('PlayingCardWidget.getSuitColor', () {
    test('spade returns #1A1A1A (black)', () {
      expect(PlayingCardWidget.getSuitColor('s'), const Color(0xFF1A1A1A));
    });

    test('heart returns #D32F2F (red)', () {
      expect(PlayingCardWidget.getSuitColor('h'), const Color(0xFFD32F2F));
    });

    test('club returns #1B5E20 (dark green)', () {
      expect(PlayingCardWidget.getSuitColor('c'), const Color(0xFF1B5E20));
    });

    test('diamond returns #0D47A1 (dark blue)', () {
      expect(PlayingCardWidget.getSuitColor('d'), const Color(0xFF0D47A1));
    });

    test('unknown suit defaults to black', () {
      expect(PlayingCardWidget.getSuitColor('x'), const Color(0xFF1A1A1A));
    });
  });

  group('PlayingCardWidget.getRankDisplay', () {
    test('T maps to 10', () {
      expect(PlayingCardWidget.getRankDisplay('T'), '10');
    });

    test('J maps to J', () {
      expect(PlayingCardWidget.getRankDisplay('J'), 'J');
    });

    test('Q maps to Q', () {
      expect(PlayingCardWidget.getRankDisplay('Q'), 'Q');
    });

    test('K maps to K', () {
      expect(PlayingCardWidget.getRankDisplay('K'), 'K');
    });

    test('A maps to A', () {
      expect(PlayingCardWidget.getRankDisplay('A'), 'A');
    });

    test('numeric ranks pass through', () {
      expect(PlayingCardWidget.getRankDisplay('2'), '2');
      expect(PlayingCardWidget.getRankDisplay('9'), '9');
    });
  });
}
