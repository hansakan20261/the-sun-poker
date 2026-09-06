import 'package:flutter/material.dart';

import 'player_avatar_widget.dart';

/// Represents a single side pot with its amount and eligible players.
class SidePot {
  final int amount;
  final int eligiblePlayerCount;
  final String? label;

  const SidePot({
    required this.amount,
    required this.eligiblePlayerCount,
    this.label,
  });
}

/// A widget that displays side pots as separate labeled chip stacks near the main pot.
///
/// - Displays side pots as separate labeled chip stacks near main pot
/// - Labels with total amount and eligible player count
/// - Stacks vertically: main pot center, side pots offset above
///
/// Requirements: 19.1, 19.2, 19.3, 19.4, 19.5
class SidePotDisplay extends StatelessWidget {
  final int mainPotAmount;
  final List<SidePot> sidePots;

  const SidePotDisplay({
    super.key,
    required this.mainPotAmount,
    this.sidePots = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Side pots stacked above main pot
        ...sidePots.asMap().entries.map((entry) {
          final index = entry.key;
          final pot = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _SidePotChip(pot: pot, index: index + 1),
          );
        }),
        // Main pot at center/bottom
        _MainPotChip(amount: mainPotAmount),
      ],
    );
  }
}

/// Displays the main pot chip stack.
class _MainPotChip extends StatelessWidget {
  final int amount;

  const _MainPotChip({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFDAA520).withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Chip icon
          Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFDAA520)],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            PlayerAvatarWidget.abbreviateChipCount(amount),
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays a single side pot with label and eligible player count.
class _SidePotChip extends StatelessWidget {
  final SidePot pot;
  final int index;

  const _SidePotChip({required this.pot, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Side pot chip icon (different color from main)
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  _getSidePotColor(index),
                  _getSidePotColor(index).withOpacity(0.7),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            PlayerAvatarWidget.abbreviateChipCount(pot.amount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          // Eligible player count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${pot.eligiblePlayerCount}P',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns a distinct color for each side pot index.
  Color _getSidePotColor(int index) {
    const colors = [
      Color(0xFF42A5F5), // blue
      Color(0xFF66BB6A), // green
      Color(0xFFAB47BC), // purple
      Color(0xFFEF5350), // red
    ];
    return colors[(index - 1) % colors.length];
  }
}
