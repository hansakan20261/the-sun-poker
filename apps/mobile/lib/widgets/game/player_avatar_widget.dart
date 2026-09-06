import 'package:flutter/material.dart';

/// Player status enum for avatar border color mapping.
enum PlayerStatus { active, turn, folded, allIn, sittingOut }

/// A widget that displays a player avatar with status-colored border,
/// chip count, and optional dealer chip indicator.
///
/// Requirements: 13.1, 13.3, 13.4, 13.5
class PlayerAvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final PlayerStatus status;
  final int chipCount;
  final bool isDealer;
  final double size;

  const PlayerAvatarWidget({
    super.key,
    this.avatarUrl,
    this.status = PlayerStatus.active,
    this.chipCount = 0,
    this.isDealer = false,
    this.size = 52,
  });

  /// Returns the border color for a given player status.
  ///
  /// - active → green
  /// - turn → yellow
  /// - folded → gray
  /// - allIn → green
  /// - sittingOut → gray
  static Color getAvatarBorderColor(PlayerStatus status) {
    switch (status) {
      case PlayerStatus.active:
        return const Color(0xFF4CAF50); // green
      case PlayerStatus.turn:
        return const Color(0xFFFFEB3B); // yellow
      case PlayerStatus.folded:
        return const Color(0xFF9E9E9E); // gray
      case PlayerStatus.allIn:
        return const Color(0xFF4CAF50); // green
      case PlayerStatus.sittingOut:
        return const Color(0xFF9E9E9E); // gray
    }
  }

  /// Abbreviates a chip count for display.
  ///
  /// - Values < 1000 are shown as-is (e.g., "999")
  /// - Values 1000–999999 are shown as "XK" or "X.YK" (e.g., "1K", "1.5K")
  /// - Values >= 1000000 are shown as "XM" or "X.YM" (e.g., "1M", "1.5M")
  static String abbreviateChipCount(int count) {
    if (count < 0) return '0';
    if (count < 1000) return count.toString();
    if (count < 1000000) {
      final k = count / 1000.0;
      if (k == k.roundToDouble() && k.round() == k.toInt()) {
        return '${k.toInt()}K';
      }
      // Show one decimal place, remove trailing zero
      final formatted = k.toStringAsFixed(1);
      if (formatted.endsWith('.0')) {
        return '${formatted.substring(0, formatted.length - 2)}K';
      }
      return '${formatted}K';
    }
    // >= 1,000,000
    final m = count / 1000000.0;
    if (m == m.roundToDouble() && m.round() == m.toInt()) {
      return '${m.toInt()}M';
    }
    final formatted = m.toStringAsFixed(1);
    if (formatted.endsWith('.0')) {
      return '${formatted.substring(0, formatted.length - 2)}M';
    }
    return '${formatted}M';
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = getAvatarBorderColor(status);
    final isSittingOut = status == PlayerStatus.sittingOut;
    final avatarOpacity = isSittingOut ? 0.5 : 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Avatar with colored border
            Opacity(
              opacity: avatarOpacity,
              child: Container(
                width: size + 6,
                height: size + 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 3),
                  boxShadow: [
                    if (status == PlayerStatus.turn)
                      BoxShadow(
                        color: borderColor.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: ClipOval(
                  child: avatarUrl != null
                      ? Image.network(
                          avatarUrl!,
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _defaultAvatar(),
                        )
                      : _defaultAvatar(),
                ),
              ),
            ),
            // Dealer chip indicator
            if (isDealer) Positioned(right: -4, top: -4, child: _DealerChip()),
          ],
        ),
        const SizedBox(height: 4),
        // Chip count display
        Text(
          abbreviateChipCount(chipCount),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _defaultAvatar() {
    return Container(
      width: size,
      height: size,
      color: Colors.grey.shade800,
      child: Icon(Icons.person, color: Colors.grey.shade400, size: size * 0.6),
    );
  }
}

/// Animated dealer "D" chip widget.
class _DealerChip extends StatefulWidget {
  @override
  State<_DealerChip> createState() => _DealerChipState();
}

class _DealerChipState extends State<_DealerChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFFD700),
          border: Border.all(color: const Color(0xFFDAA520), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'D',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
