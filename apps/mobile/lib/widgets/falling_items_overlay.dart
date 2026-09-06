import 'dart:math';
import 'package:flutter/material.dart';

/// Falling cards, coins, and banknotes animation overlay.
/// Manages its own AnimationController — just drop it into a Stack.
class FallingItemsOverlay extends StatefulWidget {
  const FallingItemsOverlay({super.key});

  @override
  State<FallingItemsOverlay> createState() => _FallingItemsOverlayState();
}

class _FallingItemsOverlayState extends State<FallingItemsOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<_Item> _items;
  final _rng = Random();

  static const _cardFaces = [
    'A♠',
    'K♥',
    'Q♦',
    'J♣',
    '10♥',
    '9♠',
    'A♥',
    'K♠',
    'Q♣',
    'J♦',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();

    _items = List.generate(
      28,
      (i) => _Item(
        x: _rng.nextDouble(),
        delay: _rng.nextDouble(),
        size: 16.0 + _rng.nextDouble() * 20,
        type: i % 3,
        rotSpeed: (_rng.nextDouble() - 0.5) * 5,
        swayAmp: 10 + _rng.nextDouble() * 20,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final size = MediaQuery.of(context).size;
          return SizedBox.expand(
            child: Stack(
              clipBehavior: Clip.none,
              children: _items.asMap().entries.map((e) {
                final i = e.key;
                final item = e.value;
                final t = (_ctrl.value + item.delay) % 1.0;
                final y = -item.size * 2 + t * (size.height + item.size * 4);
                final x =
                    size.width * item.x + sin(t * pi * 2 + i) * item.swayAmp;
                final opacity =
                    (t < 0.05 ? t / 0.05 : (t > 0.9 ? (1 - t) / 0.1 : 1.0)) *
                    0.55;
                final rot = t * item.rotSpeed * pi * 2;

                return Positioned(
                  left: x,
                  top: y,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: rot,
                      child: _buildItem(item, i),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildItem(_Item item, int i) {
    switch (item.type) {
      case 0: // Playing card
        final face = _cardFaces[i % _cardFaces.length];
        final isRed = face.contains('♥') || face.contains('♦');
        return Container(
          width: item.size * 0.72,
          height: item.size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4),
            ],
          ),
          child: Center(
            child: Text(
              face.substring(face.length - 1),
              style: TextStyle(
                color: isRed ? Colors.red.shade700 : Colors.black87,
                fontSize: item.size * 0.38,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

      case 1: // Gold coin
        return Container(
          width: item.size,
          height: item.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFFFFE082), Color(0xFFFFD700), Color(0xFFB8860B)],
              stops: [0.0, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.5),
                blurRadius: 6,
              ),
            ],
          ),
          child: Center(
            child: Text(
              'C',
              style: TextStyle(
                color: const Color(0xFF7A5000),
                fontSize: item.size * 0.44,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

      default: // Banknote
        return Container(
          width: item.size * 1.7,
          height: item.size * 0.9,
          decoration: BoxDecoration(
            color: const Color(0xFF1B5E20),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF4CAF50).withOpacity(0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4),
            ],
          ),
          child: Center(
            child: Text('💵', style: TextStyle(fontSize: item.size * 0.42)),
          ),
        );
    }
  }
}

class _Item {
  final double x, delay, size, rotSpeed, swayAmp;
  final int type;
  const _Item({
    required this.x,
    required this.delay,
    required this.size,
    required this.type,
    required this.rotSpeed,
    required this.swayAmp,
  });
}
