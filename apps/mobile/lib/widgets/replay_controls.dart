import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/thai_labels.dart';

/// Play/pause, speed, and navigation controls for hand replay.
///
/// Play/pause toggle, speed selector (1x/2x/3x), next/prev step buttons,
/// close button ("ปิด"). Auto-advance at selected speed when playing;
/// auto-pause at final step. Disable prev at step 0, next at last step.
/// Requirements: 2.1, 2.2, 2.3, 2.4
class ReplayControls extends StatefulWidget {
  final bool isPlaying;
  final int speed;
  final int currentStep;
  final int totalSteps;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<int> onSpeedChange;
  final VoidCallback onClose;

  const ReplayControls({
    super.key,
    required this.isPlaying,
    required this.speed,
    required this.currentStep,
    required this.totalSteps,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSpeedChange,
    required this.onClose,
  });

  @override
  State<ReplayControls> createState() => _ReplayControlsState();
}

class _ReplayControlsState extends State<ReplayControls> {
  Timer? _autoTimer;

  @override
  void didUpdateWidget(ReplayControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying ||
        widget.speed != oldWidget.speed) {
      _updateAutoAdvance();
    }
  }

  @override
  void initState() {
    super.initState();
    _updateAutoAdvance();
  }

  void _updateAutoAdvance() {
    _autoTimer?.cancel();
    _autoTimer = null;

    if (!widget.isPlaying) return;
    if (widget.currentStep >= widget.totalSteps - 1) return;

    final ms = switch (widget.speed) {
      2 => 500,
      3 => 333,
      _ => 1000,
    };

    _autoTimer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!mounted) {
        _autoTimer?.cancel();
        return;
      }
      // Auto-pause at final step
      if (widget.currentStep >= widget.totalSteps - 1) {
        _autoTimer?.cancel();
        widget.onPlayPause(); // pause
        return;
      }
      widget.onNext();
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  bool get _isFirstStep => widget.currentStep <= 0;
  bool get _isLastStep => widget.currentStep >= widget.totalSteps - 1;

  String get _speedLabel => switch (widget.speed) {
    2 => ThaiLabels.speed2x,
    3 => ThaiLabels.speed3x,
    _ => ThaiLabels.speed1x,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SunTheme.gold.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Close button
          _controlBtn(
            icon: Icons.close,
            label: ThaiLabels.close,
            onTap: widget.onClose,
          ),
          // Previous step
          _controlBtn(
            icon: Icons.skip_previous_rounded,
            onTap: _isFirstStep ? null : widget.onPrevious,
          ),
          // Play/Pause
          _controlBtn(
            icon: widget.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            label: widget.isPlaying ? ThaiLabels.pause : ThaiLabels.play,
            onTap: widget.onPlayPause,
            highlighted: true,
          ),
          // Next step
          _controlBtn(
            icon: Icons.skip_next_rounded,
            onTap: _isLastStep ? null : widget.onNext,
          ),
          // Speed selector
          GestureDetector(
            onTap: () {
              final next = switch (widget.speed) {
                1 => 2,
                2 => 3,
                _ => 1,
              };
              widget.onSpeedChange(next);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: SunTheme.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SunTheme.gold.withOpacity(0.3)),
              ),
              child: Text(
                _speedLabel,
                style: const TextStyle(
                  color: SunTheme.goldLight,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    String? label,
    VoidCallback? onTap,
    bool highlighted = false,
  }) {
    final enabled = onTap != null;
    final color = enabled
        ? (highlighted ? SunTheme.goldLight : Colors.white)
        : Colors.white.withOpacity(0.3);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          if (label != null)
            Text(label, style: TextStyle(color: color, fontSize: 9)),
        ],
      ),
    );
  }
}
