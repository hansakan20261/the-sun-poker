import 'package:flutter/material.dart';

/// Small circular "D" dealer chip indicator.
class DealerButton extends StatelessWidget {
  final double size;
  const DealerButton({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFE0E0E0)],
        ),
        border: Border.all(color: const Color(0xFF333333), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'D',
          style: TextStyle(
            color: Colors.black,
            fontSize: size * 0.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// Small blind / big blind text badge.
class BlindIndicator extends StatelessWidget {
  final String label; // "SB" or "BB"
  const BlindIndicator({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final isSB = label == 'SB';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isSB ? const Color(0xFF1565C0) : const Color(0xFFE65100),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 7,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
