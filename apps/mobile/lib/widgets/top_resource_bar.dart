import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/number_formatter.dart';

/// Top resource bar displaying VIP badge, energy, gems, and coins.
///
/// Requirements: 1.1-1.6
class TopResourceBar extends StatelessWidget {
  final int vipLevel;
  final int energy;
  final int gems;
  final int coins;
  final VoidCallback onAddCoins;

  const TopResourceBar({
    super.key,
    required this.vipLevel,
    required this.energy,
    required this.gems,
    required this.coins,
    required this.onAddCoins,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SunTheme.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // VIP badge
          _buildVipBadge(),
          const SizedBox(width: 12),
          // Energy
          _buildResourceItem(
            icon: Icons.bolt,
            iconColor: Colors.amber,
            value: energy.toString(),
          ),
          const SizedBox(width: 12),
          // Gems
          _buildResourceItem(
            icon: Icons.diamond,
            iconColor: Colors.cyanAccent,
            value: gems.toString(),
          ),
          const Spacer(),
          // Coins with add button
          _buildCoinSection(),
        ],
      ),
    );
  }

  Widget _buildVipBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SunTheme.gold, SunTheme.goldLight],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield, color: SunTheme.redDark, size: 16),
          const SizedBox(width: 4),
          Text(
            'VIP $vipLevel',
            style: const TextStyle(
              color: SunTheme.redDark,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceItem({
    required IconData icon,
    required Color iconColor,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildCoinSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.monetization_on,
            color: SunTheme.goldLight,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            NumberFormatter.formatAbbreviated(coins),
            style: const TextStyle(
              color: SunTheme.goldLight,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onAddCoins,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: SunTheme.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}
