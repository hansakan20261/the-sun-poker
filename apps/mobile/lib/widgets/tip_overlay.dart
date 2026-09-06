import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/free_tips_engine.dart';
import '../utils/thai_labels.dart';

/// FREE TIPS recommendation overlay.
///
/// Displays recommended action with Thai explanation, highlights the
/// recommended action button with a pulsing gold border.
/// Dismisses on tap outside or close button (fade-out 200ms).
/// Error state: displays "ไม่สามารถวิเคราะห์ได้ในขณะนี้" and auto-dismisses
/// after 2000ms.
///
/// Requirements: 21.3, 21.8, 21.9, 21.10, 21.11
class TipOverlay extends StatefulWidget {
  final TipResult? tip;
  final VoidCallback onDismiss;

  const TipOverlay({super.key, required this.tip, required this.onDismiss});

  @override
  State<TipOverlay> createState() => _TipOverlayState();
}

class _TipOverlayState extends State<TipOverlay> with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  Timer? _autoDismissTimer;

  bool get _isError => widget.tip == null;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Pulsing gold border animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-dismiss error state after 2000ms
    if (_isError) {
      _autoDismissTimer = Timer(const Duration(milliseconds: 2000), _dismiss);
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _fadeController.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: GestureDetector(
        onTap: _dismiss, // Dismiss on tap outside
        child: Container(
          color: Colors.black54,
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Absorb taps on the card itself
              child: _isError ? _buildErrorCard() : _buildTipCard(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SunTheme.redDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade400),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300, size: 40),
          const SizedBox(height: 12),
          const Text(
            ThaiLabels.cannotAnalyze,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard() {
    final tip = widget.tip!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SunTheme.redDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SunTheme.gold.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: SunTheme.goldLight.withOpacity(0.2), blurRadius: 20),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.shield, color: Colors.red, size: 20),
                  SizedBox(width: 6),
                  Text(
                    'FREE TIPS',
                    style: TextStyle(
                      color: SunTheme.goldLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _dismiss,
                child: const Icon(Icons.close, color: Colors.white54, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Recommended action with pulsing gold border
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _actionColor(tip.action).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: SunTheme.goldLight.withOpacity(
                      _pulseAnimation.value,
                    ),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      tip.actionTh,
                      style: TextStyle(
                        color: _actionColor(tip.action),
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(tip.confidence * 100).toInt()}%',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // Reasoning
          Text(
            tip.reasoning,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'fold':
        return Colors.red.shade400;
      case 'call':
        return Colors.blue.shade300;
      case 'raise':
        return SunTheme.green;
      default:
        return Colors.white;
    }
  }
}

/// Minimal AnimatedBuilder for use with Listenable animations.
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
