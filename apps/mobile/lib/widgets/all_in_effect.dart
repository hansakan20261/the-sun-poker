import 'package:flutter/material.dart';
import '../utils/thai_labels.dart';

/// Radial glow/flash animation for all-in actions.
///
/// 600ms radial glow expanding from avatar center.
/// Displays "หมดหน้าตัก" text above the player seat during effect.
/// Trigger from [trigger] boolean; checks mounted before animating.
/// Requirements: 19.1, 19.2, 19.3, 19.4
class AllInEffect extends StatefulWidget {
  final Widget child;
  final bool trigger;

  const AllInEffect({super.key, required this.child, required this.trigger});

  @override
  State<AllInEffect> createState() => _AllInEffectState();
}

class _AllInEffectState extends State<AllInEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowScale;
  late Animation<double> _glowOpacity;
  bool _showLabel = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _glowScale = Tween<double>(
      begin: 0.5,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _glowOpacity = Tween<double>(
      begin: 0.8,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showLabel = false);
      }
    });
  }

  @override
  void didUpdateWidget(AllInEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger && !oldWidget.trigger) {
      _playEffect();
    }
  }

  void _playEffect() {
    if (!mounted) return;
    setState(() => _showLabel = true);
    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Radial glow
        AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            if (!_controller.isAnimating && !_showLabel) {
              return const SizedBox.shrink();
            }
            return Transform.scale(
              scale: _glowScale.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.redAccent.withOpacity(_glowOpacity.value),
                      Colors.orangeAccent.withOpacity(_glowOpacity.value * 0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        // Child widget (player avatar)
        widget.child,
        // "หมดหน้าตัก" label above
        if (_showLabel)
          Positioned(
            top: -22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                ThaiLabels.allIn,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Minimal AnimatedWidget helper (matches pattern from result_overlay.dart).
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
