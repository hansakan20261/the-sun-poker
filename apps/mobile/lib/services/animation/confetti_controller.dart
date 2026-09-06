import 'dart:async';

import 'package:flutter/widgets.dart';

import '../haptic_service.dart';
import 'animation_coordinator.dart';
import 'animation_service.dart';
import 'animation_timing_config.dart';
import 'rive_asset_key.dart';

/// The phase of a confetti celebration animation.
enum ConfettiPhase {
  /// No confetti animation is active.
  idle,

  /// Confetti particles are playing.
  playing,

  /// Confetti animation has completed.
  completed,
}

/// Represents the current state of the confetti celebration animation.
///
/// UI widgets observe this via [ConfettiController.confettiState] to render
/// confetti particle effects using the celebration.riv artboard.
class ConfettiState {
  const ConfettiState({required this.phase, this.progress = 0.0});

  /// Current animation phase.
  final ConfettiPhase phase;

  /// Overall animation progress from 0.0 (start) to 1.0 (complete).
  final double progress;

  /// Create a copy with updated fields.
  ConfettiState copyWith({ConfettiPhase? phase, double? progress}) {
    return ConfettiState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
    );
  }
}

/// Controller responsible for orchestrating the confetti celebration effect.
///
/// Plays a confetti particle effect lasting
/// [AnimationTimingConfig.confettiDuration] (2000ms) when a player wins.
/// Triggers a success haptic pattern (three short pulses) at the start.
/// Loads the celebration.riv artboard via [AnimationService] (fire-and-forget).
///
/// Progress increases linearly from 0 to 1 over the duration.
///
/// Supports skip via [skipRequested] — if the user taps to skip, the
/// animation resolves immediately to the completed state.
class ConfettiController extends AnimationCoordinator {
  ConfettiController();

  /// Notifier for the current confetti celebration state.
  /// UI widgets observe this to render confetti particle effects.
  final ValueNotifier<ConfettiState?> confettiState =
      ValueNotifier<ConfettiState?>(null);

  // ─── Public API ──────────────────────────────────────────────────────

  /// Play the confetti celebration effect for the given [winningSeat].
  ///
  /// Triggers success haptic pattern at the start, loads celebration.riv
  /// artboard (fire-and-forget), and plays confetti particles over 2000ms.
  ///
  /// Returns a Future that completes when the animation finishes or is
  /// skipped.
  Future<void> playConfettiCelebration({required int winningSeat}) {
    return _enqueueCelebration(() => _onPlayConfettiAnimation(winningSeat));
  }

  // ─── Private Implementation ──────────────────────────────────────────

  /// Sentinel value to identify confetti animations in the queue.
  static const int _confettiSentinel = -998;

  /// Pending confetti action to execute.
  Future<void> Function()? _pendingConfettiAction;

  /// Completer for the pending confetti animation.
  Completer<void>? _pendingConfettiCompleter;

  /// Enqueue the confetti animation through the coordinator's queue.
  Future<void> _enqueueCelebration(Future<void> Function() action) {
    final completer = Completer<void>();
    _pendingConfettiAction = action;
    _pendingConfettiCompleter = completer;
    // Route through the base class queue using playChipAnimation with sentinel.
    playChipAnimation(Offset.zero, Offset.zero, _confettiSentinel);
    return completer.future;
  }

  @override
  Future<void> onPlayChipAnimation(Offset from, Offset to, int amount) async {
    if (amount == _confettiSentinel && _pendingConfettiAction != null) {
      final action = _pendingConfettiAction!;
      final completer = _pendingConfettiCompleter!;
      _pendingConfettiAction = null;
      _pendingConfettiCompleter = null;
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
      return;
    }
  }

  /// Execute the confetti celebration animation sequence.
  Future<void> _onPlayConfettiAnimation(int winningSeat) async {
    // Initialize confetti state.
    confettiState.value = const ConfettiState(
      phase: ConfettiPhase.idle,
      progress: 0.0,
    );

    if (skipRequested) {
      _resolveToFinalState();
      return;
    }

    // Trigger success haptic pattern (three short pulses) at the start.
    _triggerSuccessHaptic();

    // Load celebration.riv artboard (fire-and-forget, non-blocking).
    _loadCelebrationArtboard();

    // Transition to playing phase.
    confettiState.value = const ConfettiState(
      phase: ConfettiPhase.playing,
      progress: 0.0,
    );

    // Animate confetti over confettiDuration (2000ms).
    await _animateConfetti();

    // Complete.
    _resolveToFinalState();
  }

  /// Animate confetti progress linearly from 0 to 1 over confettiDuration.
  Future<void> _animateConfetti() async {
    const steps = 40; // 40 steps for smooth 2000ms animation (50ms per step).
    final stepDuration = AnimationTimingConfig.confettiDuration ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final progress = step / steps;

      confettiState.value = ConfettiState(
        phase: ConfettiPhase.playing,
        progress: progress,
      );

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Set the confetti state to its final completed state.
  void _resolveToFinalState() {
    confettiState.value = const ConfettiState(
      phase: ConfettiPhase.completed,
      progress: 1.0,
    );
  }

  /// Trigger success haptic pattern (three short pulses).
  /// Silently no-ops if haptic is unavailable or disabled.
  void _triggerSuccessHaptic() {
    try {
      HapticService.instance.successPattern().catchError((_) {});
    } catch (_) {
      // Non-critical — continue without haptic.
    }
  }

  /// Load celebration.riv artboard via AnimationService (fire-and-forget).
  /// This is non-blocking — the animation proceeds regardless of load result.
  void _loadCelebrationArtboard() {
    try {
      AnimationService.instance
          .getRiveArtboard(RiveAssetKey.celebration)
          .catchError((_) => null);
    } catch (_) {
      // Non-critical — continue without artboard.
    }
  }

  /// Dispose the controller and clean up resources.
  @override
  void dispose() {
    confettiState.dispose();
    super.dispose();
  }
}
