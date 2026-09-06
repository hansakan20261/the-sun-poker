import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'animation_coordinator.dart';
import 'animation_timing_config.dart';

/// The phase of a winning hand highlight animation.
enum WinHighlightPhase {
  /// No highlight animation is active.
  idle,

  /// Golden glow is pulsing on the winning cards.
  glowing,

  /// Highlight animation has completed.
  completed,
}

/// Represents the current state of the winning hand highlight animation.
///
/// UI widgets observe this via [WinHighlightController.highlightState] to
/// render a golden glow pulse on the winning cards using a Rive state machine.
class WinHighlightState {
  const WinHighlightState({
    required this.phase,
    this.winningSeatIndex = -1,
    this.glowIntensity = 0.0,
    this.progress = 0.0,
  });

  /// Current animation phase.
  final WinHighlightPhase phase;

  /// The seat index of the winning player (-1 if none).
  final int winningSeatIndex;

  /// Glow effect intensity from 0.0 (off) to 1.0 (full brightness).
  /// UI can observe this to drive a Rive state machine golden glow input.
  final double glowIntensity;

  /// Overall animation progress from 0.0 (start) to 1.0 (complete).
  final double progress;

  /// Create a copy with updated fields.
  WinHighlightState copyWith({
    WinHighlightPhase? phase,
    int? winningSeatIndex,
    double? glowIntensity,
    double? progress,
  }) {
    return WinHighlightState(
      phase: phase ?? this.phase,
      winningSeatIndex: winningSeatIndex ?? this.winningSeatIndex,
      glowIntensity: glowIntensity ?? this.glowIntensity,
      progress: progress ?? this.progress,
    );
  }
}

/// Controller responsible for orchestrating the winning hand highlight
/// animation.
///
/// Applies a golden glow pulse animation to the winning cards using a sine
/// curve over [AnimationTimingConfig.winGlowPulse] (1000ms). The glow
/// intensity goes from 0 → 1 → 0 (one full pulse).
///
/// Supports skip via [skipRequested] — if the user taps to skip, the
/// animation resolves immediately to the completed state.
class WinHighlightController extends AnimationCoordinator {
  WinHighlightController();

  /// Notifier for the current win highlight state.
  /// UI widgets observe this to render the golden glow pulse on winning cards.
  final ValueNotifier<WinHighlightState?> highlightState =
      ValueNotifier<WinHighlightState?>(null);

  // ─── Public API ──────────────────────────────────────────────────────

  /// Animate the winning hand highlight for the given [seatIndex].
  ///
  /// Pulses a golden glow intensity using a sine curve over 1000ms
  /// (winGlowPulse). The glow goes from 0 → 1 → 0 (one full pulse).
  /// [winningCards] identifies which cards to highlight.
  ///
  /// Returns a Future that completes when the animation finishes or is
  /// skipped.
  Future<void> animateWinHighlight({
    required int seatIndex,
    required List<String> winningCards,
  }) {
    return _enqueueHighlight(
      () => _onPlayWinHighlightAnimation(seatIndex, winningCards),
    );
  }

  // ─── Private Implementation ──────────────────────────────────────────

  /// Sentinel value to identify win highlight animations in the queue.
  static const int _highlightSentinel = -997;

  /// Pending highlight action to execute.
  Future<void> Function()? _pendingHighlightAction;

  /// Completer for the pending highlight animation.
  Completer<void>? _pendingHighlightCompleter;

  /// Enqueue the highlight animation through the coordinator's queue.
  Future<void> _enqueueHighlight(Future<void> Function() action) {
    final completer = Completer<void>();
    _pendingHighlightAction = action;
    _pendingHighlightCompleter = completer;
    // Route through the base class queue using playChipAnimation with sentinel.
    playChipAnimation(Offset.zero, Offset.zero, _highlightSentinel);
    return completer.future;
  }

  @override
  Future<void> onPlayChipAnimation(Offset from, Offset to, int amount) async {
    if (amount == _highlightSentinel && _pendingHighlightAction != null) {
      final action = _pendingHighlightAction!;
      final completer = _pendingHighlightCompleter!;
      _pendingHighlightAction = null;
      _pendingHighlightCompleter = null;
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
      return;
    }
  }

  /// Execute the win highlight animation sequence.
  Future<void> _onPlayWinHighlightAnimation(
    int seatIndex,
    List<String> winningCards,
  ) async {
    // Initialize highlight state.
    highlightState.value = WinHighlightState(
      phase: WinHighlightPhase.idle,
      winningSeatIndex: seatIndex,
      glowIntensity: 0.0,
      progress: 0.0,
    );

    if (skipRequested) {
      _resolveToFinalState(seatIndex);
      return;
    }

    // Transition to glowing phase.
    highlightState.value = highlightState.value!.copyWith(
      phase: WinHighlightPhase.glowing,
    );

    // Animate golden glow pulse over winGlowPulse (1000ms).
    await _animateGlowPulse(seatIndex);

    // Complete.
    _resolveToFinalState(seatIndex);
  }

  /// Animate the golden glow pulse using a sine curve.
  /// Duration: [AnimationTimingConfig.winGlowPulse] (1000ms).
  /// Glow intensity: 0 → 1 → 0 (one full sine pulse).
  Future<void> _animateGlowPulse(int seatIndex) async {
    const steps = 20; // 20 steps for smooth 1000ms animation (50ms per step).
    final stepDuration = AnimationTimingConfig.winGlowPulse ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final t = step / steps;
      // Sine curve for smooth pulse: peaks at 0.5 (t=0.5 → sin(π/2)=1.0),
      // returns to 0 at t=1.0 (sin(π)=0.0).
      final glowIntensity = math.sin(t * math.pi);

      highlightState.value = WinHighlightState(
        phase: WinHighlightPhase.glowing,
        winningSeatIndex: seatIndex,
        glowIntensity: glowIntensity,
        progress: t,
      );

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Set the highlight state to its final completed state.
  void _resolveToFinalState(int seatIndex) {
    highlightState.value = WinHighlightState(
      phase: WinHighlightPhase.completed,
      winningSeatIndex: seatIndex,
      glowIntensity: 0.0,
      progress: 1.0,
    );
  }

  /// Dispose the controller and clean up resources.
  @override
  void dispose() {
    highlightState.dispose();
    super.dispose();
  }
}
