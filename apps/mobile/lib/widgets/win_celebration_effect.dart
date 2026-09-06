import 'dart:math';
import 'package:flutter/material.dart';
import '../services/audio_manager.dart';

/// Coin rain animation for pot wins.
///
/// 2-second gold coin rain from top of screen.
/// Plays win celebration sound via AudioManager.
/// Only triggers for current player wins; checks mounted before animating.
/// Requirements: 20.1, 20.2, 20.3, 20.4
class WinCelebrationEffect extends StatefulWidget {
  final bool trigger;
  final VoidCallback? onComplete;

  const WinCelebrationEffect({
    super.key,
    required this.trigger,
    this.onComplete,
  });

  @override
  State<WinCelebrationEffect> createState() => _WinCelebrationEffectState();
}

class _WinCelebrationEffectState extends State<WinCelebrationEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<_Coin> _coins = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _coins = []);
        widget.onComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(WinCelebrationEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger && !oldWidget.trigger) {
      _playEffect();
    }
  }

  void _playEffect() {
    if (!mounted) return;
    // Generate coins
    _coins = List.generate(
      20,
      (_) => _Coin(
        x: _random.nextDouble(),
        delay: _random.nextDouble() * 0.4,
        speed: 0.6 + _random.nextDouble() * 0.4,
        size: 16.0 + _random.nextDouble() * 12.0,
        wobble: _random.nextDouble() * 2 * pi,
      ),
    );
    setState(() {});
    _controller.forward(from: 0.0);
    // Play win sound
    AudioManager.instance.play(SoundEffect.winCelebration);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_coins.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return IgnorePointer(
          child: SizedBox.expand(
            child: CustomPaint(
              painter: _CoinPainter(coins: _coins, progress: _controller.value),
            ),
          ),
        );
      },
    );
  }
}

class _Coin {
  final double x;
  final double delay;
  final double speed;
  final double size;
  final double wobble;

  const _Coin({
    required this.x,
    required this.delay,
    required this.speed,
    required this.size,
    required this.wobble,
  });
}

class _CoinPainter extends CustomPainter {
  final List<_Coin> coins;
  final double progress;

  _CoinPainter({required this.coins, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final coin in coins) {
      final adjustedProgress = ((progress - coin.delay) / coin.speed).clamp(
        0.0,
        1.0,
      );
      if (adjustedProgress <= 0) continue;

      final x =
          coin.x * size.width + sin(adjustedProgress * 6 + coin.wobble) * 15;
      final y = adjustedProgress * size.height * 1.1;
      final opacity = (1.0 - adjustedProgress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = Color.lerp(
          const Color(0xFFFFD700),
          const Color(0xFFDAA520),
          sin(adjustedProgress * 4 + coin.wobble).abs(),
        )!.withOpacity(opacity);

      canvas.drawCircle(Offset(x, y), coin.size / 2, paint);

      // Highlight
      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.4);
      canvas.drawCircle(
        Offset(x - coin.size * 0.15, y - coin.size * 0.15),
        coin.size * 0.2,
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CoinPainter old) => old.progress != progress;
}

/// Minimal AnimatedWidget helper.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) => builder(context, null);
}
