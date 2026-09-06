import 'dart:async';

import 'package:flutter/widgets.dart';

import 'animation_coordinator.dart';
import 'animation_timing_config.dart';

/// The phase of a fold card animation.
enum FoldAnimationPhase {
  /// Cards have not started animating yet.
  idle,

  /// Cards are sliding toward the muck area with fade-out.
  sliding,

  /// Animation is complete (cards are invisible / removed).
  completed,
}

/// Represents the current animation state of a fold card animation.
///
/// UI widgets observe this via [FoldAnimationController.foldState] to render
/// the cards at the correct position and opacity during the fold sequence.
class FoldAnimationState {
  const FoldAnimationState({
    required this.phase,
    required this.position,
    this.opacity = 1.0,
    this.progress = 0.0,
  });

  /// Current animation phase.
  final FoldAnimationPhase phase;

  /// Current screen position of the cards.
  final Offset position;

  /// Current opacity of the cards (1.0 = fully visible, 0.0 = invisible).
  final double opacity;

  /// Animation progress from 0.0 (start) to 1.0 (complete).
  final double progress;

  /// Create a copy with updated fields.
  FoldAnimationState copyWith({
    FoldAnimationPhase? phase,
    Offset? position,
    double? opacity,
    double? progress,
  }) {
    return FoldAnimationState(
      phase: phase ?? this.phase,
      position: position ?? this.position,
      opacity: opacity ?? this.opacity,
      progress: progress ?? this.progress,
    );
  }
}

/// Controller responsible for orchestrating the fold card animation.
///
/// Animates player cards sliding from the player's seat position toward the
/// muck area (typically the center/dealer area) with a simultaneous fade-out
/// over [AnimationTimingConfig.foldSlide] (300ms).
///
/// Exposes animation state via [foldState] ValueNotifier for the UI to observe
/// and render cards at the interpolated position and opacity.
///
/// Supports skip via [skipRequested] — if the user taps to skip, the animation
/// resolves immediately to the final state.
class FoldAnimationController extends AnimationCoordinator {
  FoldAnimationController({required this.muckPosition});

  /// The screen position of the muck area (where folded cards slide toward).
  /// Typically the center of the table or near the dealer.
  final Offset muckPosition;

  /// Notifier for the current fold animation state.
  /// UI widgets observe this to render cards at the correct position and
  /// opacity during the fold sequence.
  final ValueNotifier<FoldAnimationState?> foldState =
      ValueNotifier<FoldAnimationState?>(null);

  // ─── Public API ──────────────────────────────────────────────────────

  /// Animate a fold from [playerPosition] toward the [muckPosition].
  ///
  /// Cards slide from the player's seat toward the muck area while fading
  /// out from opacity 1.0 to 0.0 over [AnimationTimingConfig.foldSlide]
  /// (300ms).
  ///
  /// Returns a Future that completes when the animation finishes or is
  /// skipped.
  Future<void> animateFold({required Offset playerPosition}) {
    return _enqueueFold(() => _onPlayFoldAnimation(playerPosition));
  }

  // ─── Private Implementation ──────────────────────────────────────────

  /// Enqueue the fold animation through the coordinator's queue.
  Future<void> _enqueueFold(Future<void> Function() action) {
    final completer = Completer<void>();
    _pendingFoldAction = action;
    _pendingFoldCompleter = completer;
    // Route through the base class queue using playChipAnimation with a
    // sentinel value, similar to how all-in is handled in ChipAnimationController.
    playChipAnimation(Offset.zero, Offset.zero, _foldSentinel);
    return completer.future;
  }

  /// Sentinel value to identify fold animations in the queue.
  static const int _foldSentinel = -888;

  /// Pending fold action to execute.
  Future<void> Function()? _pendingFoldAction;

  /// Completer for the pending fold animation.
  Completer<void>? _pendingFoldCompleter;

  @override
  Future<void> onPlayChipAnimation(Offset from, Offset to, int amount) async {
    if (amount == _foldSentinel && _pendingFoldAction != null) {
      final action = _pendingFoldAction!;
      final completer = _pendingFoldCompleter!;
      _pendingFoldAction = null;
      _pendingFoldCompleter = null;
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
      return;
    }
  }

  /// Execute the fold animation sequence.
  Future<void> _onPlayFoldAnimation(Offset playerPosition) async {
    // Initialize fold state.
    foldState.value = FoldAnimationState(
      phase: FoldAnimationPhase.idle,
      position: playerPosition,
      opacity: 1.0,
      progress: 0.0,
    );

    if (skipRequested) {
      _resolveToFinalState();
      return;
    }

    // Transition to sliding phase.
    foldState.value = foldState.value!.copyWith(
      phase: FoldAnimationPhase.sliding,
    );

    // Animate slide + fade over foldSlide duration (300ms).
    await _animateSlideFade(from: playerPosition);

    // Resolve to final state.
    _resolveToFinalState();
  }

  /// Animate the card slide from [from] toward [muckPosition] while fading
  /// out. Duration: [AnimationTimingConfig.foldSlide] (300ms).
  ///
  /// Position is interpolated linearly from player seat to muck area.
  /// Opacity is interpolated linearly from 1.0 to 0.0.
  Future<void> _animateSlideFade({required Offset from}) async {
    const steps = 10;
    final stepDuration = AnimationTimingConfig.foldSlide ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final t = step / steps;
      final currentPosition = Offset.lerp(from, muckPosition, t)!;
      final currentOpacity = 1.0 - t; // Fade from 1.0 to 0.0.

      foldState.value = FoldAnimationState(
        phase: FoldAnimationPhase.sliding,
        position: currentPosition,
        opacity: currentOpacity,
        progress: t,
      );

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Set the fold state to its final completed state (invisible, at muck).
  void _resolveToFinalState() {
    foldState.value = FoldAnimationState(
      phase: FoldAnimationPhase.completed,
      position: muckPosition,
      opacity: 0.0,
      progress: 1.0,
    );
  }

  /// Dispose the controller and clean up resources.
  @override
  void dispose() {
    foldState.dispose();
    super.dispose();
  }
}
