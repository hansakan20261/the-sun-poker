import 'dart:async';

import 'package:flutter/widgets.dart';

import '../audio_manager.dart';
import '../haptic_service.dart';
import 'animation_coordinator.dart';
import 'animation_timing_config.dart';

/// The phase of a showdown reveal animation.
enum ShowdownRevealPhase {
  /// No showdown animation is active.
  idle,

  /// Hands are being revealed sequentially.
  revealing,

  /// All hands have been revealed.
  completed,
}

/// Represents the current state of the showdown reveal animation.
///
/// UI widgets observe this via [ShowdownController.showdownState] to render
/// card flip animations at the correct seat and timing.
class ShowdownRevealState {
  const ShowdownRevealState({
    required this.phase,
    this.currentSeatIndex = -1,
    this.revealedSeats = const [],
    this.progress = 0.0,
  });

  /// Current animation phase.
  final ShowdownRevealPhase phase;

  /// The seat index currently being revealed (-1 if none).
  final int currentSeatIndex;

  /// List of seat indices that have already been revealed.
  final List<int> revealedSeats;

  /// Overall animation progress from 0.0 (start) to 1.0 (complete).
  final double progress;

  /// Create a copy with updated fields.
  ShowdownRevealState copyWith({
    ShowdownRevealPhase? phase,
    int? currentSeatIndex,
    List<int>? revealedSeats,
    double? progress,
  }) {
    return ShowdownRevealState(
      phase: phase ?? this.phase,
      currentSeatIndex: currentSeatIndex ?? this.currentSeatIndex,
      revealedSeats: revealedSeats ?? this.revealedSeats,
      progress: progress ?? this.progress,
    );
  }
}

/// Controller responsible for orchestrating the showdown reveal animation.
///
/// Reveals each active player's hole cards sequentially with a 3D flip
/// animation. Staggers reveals with [AnimationTimingConfig.showdownStaggerDelay]
/// (200ms) between players. Each card flip takes
/// [AnimationTimingConfig.showdownFlipDuration] (350ms).
///
/// Integrates with [AudioManager] for card-flip sound on each reveal and
/// [HapticService] for light haptic feedback on each reveal.
///
/// Supports skip via [skipRequested] — if the user taps to skip, the animation
/// resolves immediately to the final state showing all hands revealed.
class ShowdownController extends AnimationCoordinator {
  ShowdownController();

  /// Notifier for the current showdown reveal state.
  /// UI widgets observe this to render card flip animations at the correct
  /// seat and timing during the showdown sequence.
  final ValueNotifier<ShowdownRevealState?> showdownState =
      ValueNotifier<ShowdownRevealState?>(null);

  // ─── Public API ──────────────────────────────────────────────────────

  /// Animate the showdown reveal for the given [hands].
  ///
  /// Reveals each hand sequentially with a 200ms stagger between players.
  /// Each card flip takes 350ms. Triggers card-flip sound and light haptic
  /// on each reveal.
  ///
  /// Returns a Future that completes when the animation finishes or is
  /// skipped.
  Future<void> animateShowdown(List<ShowdownHand> hands) {
    return _enqueueShowdown(() => _onPlayShowdownAnimation(hands));
  }

  // ─── Private Implementation ──────────────────────────────────────────

  /// Enqueue the showdown animation through the coordinator's queue.
  Future<void> _enqueueShowdown(Future<void> Function() action) {
    final completer = Completer<void>();
    _pendingShowdownAction = action;
    _pendingShowdownCompleter = completer;
    // Route through the base class queue using playShowdown.
    playShowdown(const []);
    return completer.future;
  }

  /// Pending showdown action to execute.
  Future<void> Function()? _pendingShowdownAction;

  /// Completer for the pending showdown animation.
  Completer<void>? _pendingShowdownCompleter;

  @override
  Future<void> onPlayShowdown(List<ShowdownHand> hands) async {
    if (_pendingShowdownAction != null) {
      final action = _pendingShowdownAction!;
      final completer = _pendingShowdownCompleter!;
      _pendingShowdownAction = null;
      _pendingShowdownCompleter = null;
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
      return;
    }
  }

  /// Execute the showdown reveal animation sequence.
  Future<void> _onPlayShowdownAnimation(List<ShowdownHand> hands) async {
    if (hands.isEmpty) {
      showdownState.value = const ShowdownRevealState(
        phase: ShowdownRevealPhase.completed,
        progress: 1.0,
      );
      return;
    }

    // Initialize showdown state.
    showdownState.value = const ShowdownRevealState(
      phase: ShowdownRevealPhase.idle,
      currentSeatIndex: -1,
      revealedSeats: [],
      progress: 0.0,
    );

    if (skipRequested) {
      _resolveToFinalState(hands);
      return;
    }

    // Transition to revealing phase.
    showdownState.value = showdownState.value!.copyWith(
      phase: ShowdownRevealPhase.revealing,
    );

    // Reveal each hand sequentially.
    final revealedSeats = <int>[];

    for (var i = 0; i < hands.length; i++) {
      if (skipRequested) {
        _resolveToFinalState(hands);
        return;
      }

      final hand = hands[i];
      final progress = (i + 1) / hands.length;

      // Update state to show current seat being revealed.
      showdownState.value = ShowdownRevealState(
        phase: ShowdownRevealPhase.revealing,
        currentSeatIndex: hand.seatIndex,
        revealedSeats: List.unmodifiable(revealedSeats),
        progress: progress,
      );

      // Trigger card-flip sound for this reveal.
      _playCardFlipSound();

      // Trigger light haptic for this reveal.
      _triggerRevealHaptic();

      // Wait for the card flip duration (350ms).
      await _waitForFlip();

      if (skipRequested) {
        _resolveToFinalState(hands);
        return;
      }

      // Mark this seat as revealed.
      revealedSeats.add(hand.seatIndex);

      // Update state with the newly revealed seat.
      showdownState.value = ShowdownRevealState(
        phase: ShowdownRevealPhase.revealing,
        currentSeatIndex: hand.seatIndex,
        revealedSeats: List.unmodifiable(revealedSeats),
        progress: progress,
      );

      // Wait for stagger delay before next reveal (200ms), except after last.
      if (i < hands.length - 1) {
        await _waitForStagger();

        if (skipRequested) {
          _resolveToFinalState(hands);
          return;
        }
      }
    }

    // All hands revealed — transition to completed.
    _resolveToFinalState(hands);
  }

  /// Wait for the card flip duration.
  Future<void> _waitForFlip() async {
    const steps = 7;
    final stepDuration = AnimationTimingConfig.showdownFlipDuration ~/ steps;

    for (var step = 0; step < steps; step++) {
      if (skipRequested) return;
      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Wait for the stagger delay between reveals.
  Future<void> _waitForStagger() async {
    const steps = 4;
    final stepDuration = AnimationTimingConfig.showdownStaggerDelay ~/ steps;

    for (var step = 0; step < steps; step++) {
      if (skipRequested) return;
      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Set the showdown state to its final completed state with all hands
  /// revealed.
  void _resolveToFinalState(List<ShowdownHand> hands) {
    final allSeats = hands.map((h) => h.seatIndex).toList();
    showdownState.value = ShowdownRevealState(
      phase: ShowdownRevealPhase.completed,
      currentSeatIndex: hands.isNotEmpty ? hands.last.seatIndex : -1,
      revealedSeats: List.unmodifiable(allSeats),
      progress: 1.0,
    );
  }

  /// Play the card-flip sound effect for each reveal.
  /// Silently no-ops if audio is unavailable or disabled.
  void _playCardFlipSound() {
    try {
      AudioManager.instance.play(SoundEffect.cardFlip).catchError((_) {});
    } catch (_) {
      // Non-critical — continue without sound.
    }
  }

  /// Trigger light haptic feedback for each card reveal.
  /// Silently no-ops if haptic is unavailable or disabled.
  void _triggerRevealHaptic() {
    try {
      HapticService.instance.lightImpact().catchError((_) {});
    } catch (_) {
      // Non-critical — continue without haptic.
    }
  }

  /// Dispose the controller and clean up resources.
  @override
  void dispose() {
    showdownState.dispose();
    super.dispose();
  }
}
