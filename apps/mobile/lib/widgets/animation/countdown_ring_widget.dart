import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import '../../services/animation/animation_service.dart';
import '../../services/animation/countdown_ring_controller.dart';
import '../../services/animation/rive_asset_key.dart';
import '../../services/audio_manager.dart';
import '../../services/haptic_service.dart';

/// A widget that displays an animated countdown ring around a player's avatar.
///
/// Loads the `countdown_ring.riv` artboard via [AnimationService] and
/// delegates countdown logic to [CountdownRingController]. Falls back to
/// a [CustomPaint]-based ring if the Rive asset fails to load.
///
/// The ring depletes over the turn duration, changing color at thresholds:
/// - Green: > 10 seconds remaining
/// - Yellow: 6–10 seconds remaining
/// - Red with pulse: ≤ 5 seconds remaining
///
/// Sound and haptic feedback are triggered automatically:
/// - Urgent tick sound on each second when ≤ 5 seconds remain
/// - Light haptic tick on each second when ≤ 3 seconds remain
///
/// Usage:
/// ```dart
/// CountdownRingWidget(
///   turnDuration: 30,
///   size: 80.0,
///   onExpired: () => handleAutoFold(),
///   child: PlayerAvatar(...),
/// )
/// ```
class CountdownRingWidget extends StatefulWidget {
  const CountdownRingWidget({
    super.key,
    required this.turnDuration,
    this.size = 80.0,
    this.strokeWidth = 4.0,
    this.onExpired,
    this.autoStart = true,
    this.child,
  });

  /// Total turn duration in seconds.
  final int turnDuration;

  /// Size of the ring (width and height).
  final double size;

  /// Stroke width of the ring.
  final double strokeWidth;

  /// Called when the timer expires. Use this to trigger auto-fold (poker)
  /// or auto-arrange (Chinese poker).
  final VoidCallback? onExpired;

  /// Whether to start the countdown immediately on mount.
  final bool autoStart;

  /// Child widget displayed inside the ring (typically a player avatar).
  final Widget? child;

  @override
  State<CountdownRingWidget> createState() => CountdownRingWidgetState();
}

class CountdownRingWidgetState extends State<CountdownRingWidget>
    with SingleTickerProviderStateMixin {
  late final CountdownRingController _controller;
  Artboard? _artboard;
  StateMachineController? _stateMachineController;
  bool _riveLoaded = false;

  // Pulse animation for the red state.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _controller = CountdownRingController(
      onTickSound: _onTickSound,
      onTickHaptic: _onTickHaptic,
      onExpired: widget.onExpired,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to state changes for pulse animation control.
    _controller.state.addListener(_onStateChanged);

    _loadRiveAsset();

    if (widget.autoStart) {
      _controller.start(widget.turnDuration);
    }
  }

  @override
  void didUpdateWidget(CountdownRingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turnDuration != widget.turnDuration) {
      _controller.start(widget.turnDuration);
    }
  }

  @override
  void dispose() {
    _controller.state.removeListener(_onStateChanged);
    _controller.dispose();
    _pulseController.dispose();
    _stateMachineController?.dispose();
    super.dispose();
  }

  /// Start the countdown manually (if [autoStart] is false).
  void start([int? duration]) {
    _controller.start(duration ?? widget.turnDuration);
  }

  /// Stop the countdown without triggering expiry.
  void stop() {
    _controller.stop();
  }

  // ─── Private ─────────────────────────────────────────────────────────

  void _onStateChanged() {
    final state = _controller.state.value;

    // Control pulse animation.
    if (state.isPulsing && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!state.isPulsing && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }

    // Update Rive state machine inputs if available.
    if (_stateMachineController != null) {
      _updateRiveInputs(state);
    }

    // Trigger rebuild for CustomPaint fallback.
    if (mounted) setState(() {});
  }

  void _onTickSound(int secondsRemaining) {
    AudioManager.instance.play(SoundEffect.countdownUrgent);
  }

  void _onTickHaptic(int secondsRemaining) {
    HapticService.instance.tick();
  }

  Future<void> _loadRiveAsset() async {
    try {
      final artboard = await AnimationService.instance.getRiveArtboard(
        RiveAssetKey.countdownRing,
      );

      if (!mounted) return;

      if (artboard == null) {
        setState(() {});
        return;
      }

      final controller = StateMachineController.fromArtboard(
        artboard,
        'State Machine 1',
      );

      if (controller != null) {
        artboard.addController(controller);
        _stateMachineController = controller;
      }

      setState(() {
        _artboard = artboard;
        _riveLoaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _updateRiveInputs(CountdownRingState state) {
    if (_stateMachineController == null) return;

    final service = AnimationService.instance;

    // Set progress (0.0 to 1.0).
    service.fireStateMachineInput(
      _stateMachineController!,
      'progress',
      state.progress,
    );

    // Set color state (0=green, 1=yellow, 2=red).
    service.fireStateMachineInput(
      _stateMachineController!,
      'colorState',
      state.color.index.toDouble(),
    );

    // Set pulsing.
    service.fireStateMachineInput(
      _stateMachineController!,
      'isPulsing',
      state.isPulsing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ringState = _controller.state.value;

    Widget ringWidget;

    if (_riveLoaded && _artboard != null) {
      // Use Rive animation.
      ringWidget = SizedBox(
        width: widget.size,
        height: widget.size,
        child: Rive(artboard: _artboard!, fit: BoxFit.contain),
      );
    } else {
      // Fallback: CustomPaint ring.
      ringWidget = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final scale = ringState.isPulsing ? _pulseAnimation.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _CountdownRingPainter(
                progress: ringState.progress,
                color: _colorForState(ringState.color),
                strokeWidth: widget.strokeWidth,
              ),
            ),
          );
        },
      );
    }

    if (widget.child != null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ringWidget,
            Padding(
              padding: EdgeInsets.all(widget.strokeWidth + 2),
              child: widget.child!,
            ),
          ],
        ),
      );
    }

    return ringWidget;
  }

  Color _colorForState(CountdownRingColor color) {
    switch (color) {
      case CountdownRingColor.green:
        return const Color(0xFF4CAF50);
      case CountdownRingColor.yellow:
        return const Color(0xFFFFC107);
      case CountdownRingColor.red:
        return const Color(0xFFF44336);
    }
  }
}

/// Custom painter that draws a circular countdown ring.
class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  /// Progress from 1.0 (full circle) to 0.0 (empty).
  final double progress;

  /// Ring color.
  final Color color;

  /// Stroke width of the ring.
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;

    // Background track.
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc.
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * math.pi * progress;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, // Start from top.
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CountdownRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
