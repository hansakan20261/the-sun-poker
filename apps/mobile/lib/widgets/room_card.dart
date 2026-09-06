import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/number_formatter.dart';
import '../utils/thai_labels.dart';

/// City-themed room card for the lobby.
///
/// Displays city icon, Thai city name, blinds info, player count,
/// and buy-in badge with "ซื้อเข้าขั้นต่ำ" label.
///
/// Requirements: 9.1-9.9
class RoomCard extends StatelessWidget {
  final String cityName;
  final String cityIconUrl;
  final int smallBlind;
  final int bigBlind;
  final int ante;
  final int playerCount;
  final int maxPlayers;
  final int minBuyIn;
  final VoidCallback onTap;

  const RoomCard({
    super.key,
    required this.cityName,
    required this.cityIconUrl,
    required this.smallBlind,
    required this.bigBlind,
    required this.ante,
    required this.playerCount,
    required this.maxPlayers,
    required this.minBuyIn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: SunTheme.cardDecoration(
          radius: 14,
          bgColor: const Color(0xFF1A0505),
        ),
        child: Row(
          children: [
            // City icon (circular)
            _buildCityIcon(),
            const SizedBox(width: 12),
            // Room info
            Expanded(child: _buildRoomInfo()),
            // Buy-in badge
            _buildBuyInBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildCityIcon() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: SunTheme.goldLight, width: 2),
        boxShadow: [
          BoxShadow(color: SunTheme.goldLight.withOpacity(0.15), blurRadius: 8),
        ],
        image: const DecorationImage(
          image: AssetImage('assets/room_logo.jpg'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildRoomInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // City name
        Text(
          cityName,
          style: const TextStyle(
            color: SunTheme.goldLight,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        // Blinds info (OFC shows rate instead of blinds)
        Text(
          smallBlind == 0 && ante > 0
              ? 'เรท: ${NumberFormatter.formatWithCommas(ante)} | ซื้อเข้า: ${NumberFormatter.formatWithCommas(minBuyIn)}'
              : NumberFormatter.formatBlinds(smallBlind, bigBlind, ante),
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
        ),
        const SizedBox(height: 4),
        // Player count
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people, color: Colors.white.withOpacity(0.6), size: 14),
            const SizedBox(width: 4),
            Text(
              '$playerCount/$maxPlayers',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBuyInBadge() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: SunTheme.goldLight.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SunTheme.goldLight.withOpacity(0.4)),
          ),
          child: Text(
            NumberFormatter.formatAbbreviated(minBuyIn),
            style: const TextStyle(
              color: SunTheme.goldLight,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ThaiLabels.minBuyIn,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
        ),
      ],
    );
  }
}
