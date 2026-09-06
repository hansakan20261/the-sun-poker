import 'dart:math';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════
// 1. Pop-up Entrance — Scale + Bounce
// ═══════════════════════════════════════════════════════════

/// Wraps a child with scale-up + bounce entrance animation.
class PopupEntrance extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;

  const PopupEntrance({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
    this.delay = Duration.zero,
  });

  @override
  State<PopupEntrance> createState() => _PopupEntranceState();
}

class _PopupEntranceState extends State<PopupEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
  }
}

// ═══════════════════════════════════════════════════════════
// 2. Shimmer Glow Effect — for buttons
// ═══════════════════════════════════════════════════════════

/// Adds a shimmer/glow sweep effect over a button or widget.
class ShimmerGlow extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Color glowColor;

  const ShimmerGlow({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 2000),
    this.glowColor = const Color(0xFFFFD700),
  });

  @override
  State<ShimmerGlow> createState() => _ShimmerGlowState();
}

class _ShimmerGlowState extends State<ShimmerGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(-0.5 + 2.0 * _controller.value, 0),
              colors: [
                Colors.transparent,
                widget.glowColor.withOpacity(0.3),
                Colors.transparent,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 3. Action Text Pop — "จั่ว", "ทิ้ง", "เกิด", "น็อค"
// ═══════════════════════════════════════════════════════════

/// Shows action text that pops up and fades away.
class ActionTextPop extends StatefulWidget {
  final String text;
  final Color color;
  final VoidCallback? onComplete;

  const ActionTextPop({
    super.key,
    required this.text,
    this.color = const Color(0xFFFFD700),
    this.onComplete,
  });

  @override
  State<ActionTextPop> createState() => _ActionTextPopState();
}

class _ActionTextPopState extends State<ActionTextPop>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 20),
    ]).animate(_controller);

    _opacityAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: const Offset(0, -0.5),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward().then((_) => widget.onComplete?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: _opacityAnim.value,
          child: SlideTransition(
            position: _slideAnim,
            child: Transform.scale(
              scale: _scaleAnim.value,
              child: Text(
                widget.text,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 8),
                    Shadow(
                      color: widget.color.withOpacity(0.5),
                      blurRadius: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 4. Confetti / Winner Spotlight
// ═══════════════════════════════════════════════════════════

/// Simple confetti rain effect for winner celebration.
class ConfettiEffect extends StatefulWidget {
  final Duration duration;
  final VoidCallback? onComplete;

  const ConfettiEffect({
    super.key,
    this.duration = const Duration(seconds: 3),
    this.onComplete,
  });

  @override
  State<ConfettiEffect> createState() => _ConfettiEffectState();
}

class _ConfettiEffectState extends State<ConfettiEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ConfettiPiece> _pieces = [];
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    // Generate confetti pieces
    for (int i = 0; i < 40; i++) {
      _pieces.add(
        _ConfettiPiece(
          x: _rng.nextDouble(),
          speed: 0.3 + _rng.nextDouble() * 0.7,
          size: 4 + _rng.nextDouble() * 8,
          color: [
            const Color(0xFFFFD700),
            const Color(0xFFFF4444),
            const Color(0xFF44FF44),
            const Color(0xFF4444FF),
            const Color(0xFFFF44FF),
            Colors.white,
          ][_rng.nextInt(6)],
          rotation: _rng.nextDouble() * pi * 2,
          rotationSpeed: (_rng.nextDouble() - 0.5) * 4,
        ),
      );
    }

    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.forward().then((_) => widget.onComplete?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(
            pieces: _pieces,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class _ConfettiPiece {
  final double x, speed, size, rotation, rotationSpeed;
  final Color color;
  _ConfettiPiece({
    required this.x,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double progress;
  _ConfettiPainter({required this.pieces, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final y = -20 + (size.height + 40) * progress * p.speed;
      final x = p.x * size.width + sin(progress * pi * 4 + p.rotation) * 20;
      final opacity = progress < 0.8 ? 1.0 : (1.0 - (progress - 0.8) / 0.2);

      final paint = Paint()
        ..color = p.color.withOpacity(opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + progress * p.rotationSpeed * pi);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.progress != progress;
}

// ═══════════════════════════════════════════════════════════
// 5. Turn Indicator Glow — border flow animation
// ═══════════════════════════════════════════════════════════

/// Animated glowing border around the active player's avatar.
class GlowingBorder extends StatefulWidget {
  final Widget child;
  final Color color;
  final double borderWidth;
  final double borderRadius;

  const GlowingBorder({
    super.key,
    required this.child,
    this.color = Colors.greenAccent,
    this.borderWidth = 3,
    this.borderRadius = 50,
  });

  @override
  State<GlowingBorder> createState() => _GlowingBorderState();
}

class _GlowingBorderState extends State<GlowingBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = 4 + 8 * _controller.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.3 + 0.4 * _controller.value),
                blurRadius: glow,
                spreadRadius: glow * 0.3,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Helper: AnimatedBuilder (avoid conflict with other files)
// ═══════════════════════════════════════════════════════════

class AnimatedBuilder extends AnimatedWidget {
  final Widget? child;
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) => builder(context, child);
}
