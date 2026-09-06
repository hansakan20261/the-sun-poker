import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/timer_logic.dart';

/// Glowing animated ring with countdown timer around the active player's avatar.
///
/// Task 15.3: Enhanced with 3-tier color system (green/amber/red),
/// pulsing animation when red (<25%), audio warning at 3 seconds,
/// auto-action on timer expiry, and 300ms ring transition between players.
///
/// Requirements: 22.1–22.11
class TurnIndicator extends StatefulWidget {
  final Widget child;
  final bool isActive;
  final int totalSeconds;
  final int remainingSeconds;
  final VoidCallback? onTimeout;

  /// Whether a bet is pending (used for auto-action: fold vs check)
  final bool isBetPending;

  const TurnIndicator({
    super.key,
    required this.child,
    this.isActive = false,
    this.totalSeconds = 30,
    this.remainingSeconds = 30,
    this.onTimeout,
    this.isBetPending = false,
  });

  @override
  State<TurnIndicator> createState() => _TurnIndicatorState();
}

class _TurnIndicatorState extends State<TurnIndicator>
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _timeoutFired = false;
  bool _warningPlayed = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Pulsing animation for red state (<25%)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _updatePulse();
  }

  @override
  void didUpdateWidget(TurnIndicator old) {
    super.didUpdateWidget(old);
    // Reset timeout flag when turn changes
    if (widget.remainingSeconds != old.remainingSeconds &&
        widget.remainingSeconds > 0) {
      _timeoutFired = false;
    }
    // Reset warning when turn changes to a new player
    if (widget.isActive != old.isActive) {
      _warningPlayed = false;
    }

    // Task 15.3: Audio warning at 3 seconds (Req 22.7)
    if (widget.isActive &&
        TimerLogic.shouldPlayWarning(widget.remainingSeconds) &&
        !_warningPlayed) {
      _warningPlayed = true;
      _playWarningSound();
    }

    // Task 15.3: Auto-action on timer expiry (Req 22.8, 22.9)
    if (widget.isActive && widget.remainingSeconds <= 0 && !_timeoutFired) {
      _timeoutFired = true;
      widget.onTimeout?.call();
    }

    _updatePulse();
  }

  void _updatePulse() {
    if (widget.isActive && widget.totalSeconds > 0) {
      final color = TimerLogic.getColor(
        widget.remainingSeconds,
        widget.totalSeconds,
      );
      if (color == TimerColor.red) {
        if (!_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      } else {
        if (_pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.value = 0.0;
        }
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.value = 0.0;
      }
    }
  }

  void _playWarningSound() {
    // Haptic feedback as audio warning substitute (real audio requires assets)
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _glowController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Map TimerColor to Flutter Color
  Color _timerColorToColor(TimerColor tc) {
    switch (tc) {
      case TimerColor.green:
        return Colors.green;
      case TimerColor.amber:
        return Colors.amber;
      case TimerColor.red:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Task 15.3: Ring transition between players over 300ms (Req 22.10)
    return AnimatedOpacity(
      opacity: widget.isActive ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: widget.isActive
          ? AnimatedBuilder(
              animation: Listenable.merge([_glowController, _pulseAnimation]),
              builder: (_, __) {
                final fraction = widget.totalSeconds > 0
                    ? widget.remainingSeconds / widget.totalSeconds
                    : 0.0;
                // Task 15.3: 3-tier color via TimerLogic (Req 22.4–22.6)
                final timerColor = TimerLogic.getColor(
                  widget.remainingSeconds,
                  widget.totalSeconds > 0 ? widget.totalSeconds : 1,
                );
                final ringColor = _timerColorToColor(timerColor);

                // Task 15.3: Pulsing scale when red
                final scale = timerColor == TimerColor.red
                    ? _pulseAnimation.value
                    : 1.0;

                return Transform.scale(
                  scale: scale,
                  child: CustomPaint(
                    painter: _TurnRingPainter(
                      progress: _glowController.value,
                      fraction: fraction,
                      ringColor: ringColor,
                    ),
                    child: widget.child,
                  ),
                );
              },
            )
          : widget.child,
    );
  }
}

class _TurnRingPainter extends CustomPainter {
  final double progress;
  final double fraction;
  final Color ringColor;

  _TurnRingPainter({
    required this.progress,
    required this.fraction,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(size.width, size.height) / 2 + 4;

    // Glowing ring with SweepGradient
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..shader = SweepGradient(
        startAngle: progress * 2 * math.pi,
        endAngle: progress * 2 * math.pi + 2 * math.pi,
        colors: [
          ringColor.withOpacity(0.2),
          ringColor,
          ringColor.withOpacity(0.2),
        ],
        stops: const [0.0, 0.5, 1.0],
        tileMode: TileMode.clamp,
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, sweepPaint);

    // Countdown arc — depletes over turn time
    if (fraction > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = ringColor.withOpacity(0.8);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + 3),
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        arcPaint,
      );
    }

    // Outer glow
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..color = ringColor.withOpacity(
        0.15 + 0.1 * math.sin(progress * 2 * math.pi),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, radius, glowPaint);
  }

  @override
  bool shouldRepaint(_TurnRingPainter old) => true;
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({
    super.key,
    required Listenable animation,
    required this.builder,
  }) : super(listenable: animation);
  @override
  Widget build(BuildContext context) => builder(context, null);
}
