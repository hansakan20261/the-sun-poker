import 'dart:async';

import 'package:flutter/foundation.dart';

/// Color state of the countdown ring.
enum CountdownRingColor {
  /// Normal time remaining (> 10 seconds).
  green,

  /// Warning time (6–10 seconds remaining).
  yellow,

  /// Critical time (≤ 5 seconds remaining).
  red,
}

/// Immutable state snapshot of the countdown ring.
class CountdownRingState {
  const CountdownRingState({
    required this.secondsRemaining,
    required this.totalDuration,
    required this.progress,
    required this.color,
    required this.isPulsing,
    required this.isExpired,
  });

  /// Seconds left on the countdown.
  final int secondsRemaining;

  /// Total duration of the countdown in seconds.
  final int totalDuration;

  /// Progress from 1.0 (full) to 0.0 (empty).
  final double progress;

  /// Current ring color based on time remaining.
  final CountdownRingColor color;

  /// Whether the ring should pulse (true when ≤ 5 seconds).
  final bool isPulsing;

  /// Whether the timer has expired (reached 0).
  final bool isExpired;

  CountdownRingState copyWith({
    int? secondsRemaining,
    int? totalDuration,
    double? progress,
    CountdownRingColor? color,
    bool? isPulsing,
    bool? isExpired,
  }) {
    return CountdownRingState(
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      totalDuration: totalDuration ?? this.totalDuration,
      progress: progress ?? this.progress,
      color: color ?? this.color,
      isPulsing: isPulsing ?? this.isPulsing,
      isExpired: isExpired ?? this.isExpired,
    );
  }
}

/// Callback signatures for countdown ring events.
typedef CountdownTickCallback = void Function(int secondsRemaining);
typedef CountdownExpiredCallback = void Function();

/// Controller for the countdown ring logic.
///
/// Manages a periodic timer that ticks once per second, computing
/// color transitions, pulsing state, and triggering sound/haptic
/// callbacks at the appropriate thresholds.
///
/// This controller is fully testable without Flutter widgets — it uses
/// [Timer.periodic] for the countdown and [ValueNotifier] for state
/// observation.
class CountdownRingController {
  CountdownRingController({
    this.onTickSound,
    this.onTickHaptic,
    this.onExpired,
  });

  /// Called on each second when ≤ 5 seconds remain (urgent tick sound).
  final CountdownTickCallback? onTickSound;

  /// Called on each second when ≤ 3 seconds remain (haptic tick).
  final CountdownTickCallback? onTickHaptic;

  /// Called when the timer reaches 0 (expiry auto-action).
  final CountdownExpiredCallback? onExpired;

  /// Observable state of the countdown ring.
  final ValueNotifier<CountdownRingState> state = ValueNotifier(
    const CountdownRingState(
      secondsRemaining: 0,
      totalDuration: 0,
      progress: 1.0,
      color: CountdownRingColor.green,
      isPulsing: false,
      isExpired: false,
    ),
  );

  Timer? _timer;
  bool _disposed = false;

  /// Whether the countdown is currently running.
  bool get isRunning => _timer != null && _timer!.isActive;

  /// Start the countdown for [totalSeconds].
  ///
  /// If a countdown is already running, it is stopped first.
  void start(int totalSeconds) {
    if (_disposed) return;
    stop();

    if (totalSeconds <= 0) {
      // Immediately expire for invalid durations.
      state.value = CountdownRingState(
        secondsRemaining: 0,
        totalDuration: 0,
        progress: 0.0,
        color: CountdownRingColor.red,
        isPulsing: false,
        isExpired: true,
      );
      onExpired?.call();
      return;
    }

    // Set initial state.
    state.value = CountdownRingState(
      secondsRemaining: totalSeconds,
      totalDuration: totalSeconds,
      progress: 1.0,
      color: _computeColor(totalSeconds),
      isPulsing: _computeIsPulsing(totalSeconds),
      isExpired: false,
    );

    // Start periodic timer that ticks every second.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _onTick();
    });
  }

  /// Stop the countdown without triggering expiry.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Dispose the controller and release resources.
  void dispose() {
    _disposed = true;
    stop();
    state.dispose();
  }

  // ─── Private ─────────────────────────────────────────────────────────

  void _onTick() {
    if (_disposed) return;

    final current = state.value;
    final newSeconds = current.secondsRemaining - 1;

    if (newSeconds <= 0) {
      // Timer expired.
      _timer?.cancel();
      _timer = null;

      state.value = current.copyWith(
        secondsRemaining: 0,
        progress: 0.0,
        color: CountdownRingColor.red,
        isPulsing: false,
        isExpired: true,
      );

      // Fire sound/haptic for the final second before expiry.
      if (current.secondsRemaining <= 5) {
        onTickSound?.call(0);
      }
      if (current.secondsRemaining <= 3) {
        onTickHaptic?.call(0);
      }

      onExpired?.call();
      return;
    }

    // Update state.
    final progress = newSeconds / current.totalDuration;
    final color = _computeColor(newSeconds);
    final isPulsing = _computeIsPulsing(newSeconds);

    state.value = current.copyWith(
      secondsRemaining: newSeconds,
      progress: progress,
      color: color,
      isPulsing: isPulsing,
    );

    // Trigger sound callback when ≤ 5 seconds remain.
    if (newSeconds <= 5) {
      onTickSound?.call(newSeconds);
    }

    // Trigger haptic callback when ≤ 3 seconds remain.
    if (newSeconds <= 3) {
      onTickHaptic?.call(newSeconds);
    }
  }

  /// Compute the ring color based on seconds remaining.
  static CountdownRingColor _computeColor(int secondsRemaining) {
    if (secondsRemaining <= 5) return CountdownRingColor.red;
    if (secondsRemaining <= 10) return CountdownRingColor.yellow;
    return CountdownRingColor.green;
  }

  /// Compute whether the ring should pulse (≤ 5 seconds).
  static bool _computeIsPulsing(int secondsRemaining) {
    return secondsRemaining <= 5;
  }
}
