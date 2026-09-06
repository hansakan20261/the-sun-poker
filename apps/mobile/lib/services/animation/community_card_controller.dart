import 'dart:async';

import 'package:flutter/widgets.dart';

import '../audio_manager.dart';
import 'animation_coordinator.dart';
import 'animation_timing_config.dart';

/// The phase of a community card animation.
enum CommunityCardPhase {
  /// No community card animation is active.
  idle,

  /// Cards are being animated (spread, slide, or pulse).
  animating,

  /// Animation has completed.
  completed,
}

/// The type of community card reveal.
enum CommunityCardType {
  /// Three cards dealt simultaneously with spread animation.
  flop,

  /// Single card sliding into position next to the flop.
  turn,

  /// Single card sliding into the final position.
  river,
}

/// Represents the current state of the community card animation.
///
/// UI widgets observe this via [CommunityCardController.communityCardState]
/// to render card spread/slide animations with scale pulse effects.
class CommunityCardState {
  const CommunityCardState({
    required this.phase,
    required this.cardType,
    this.progress = 0.0,
    this.scale = 1.0,
    this.revealedCards = const [],
  });

  /// Current animation phase.
  final CommunityCardPhase phase;

  /// The type of community card reveal being animated.
  final CommunityCardType cardType;

  /// Animation progress from 0.0 (start) to 1.0 (complete).
  final double progress;

  /// Current scale factor. Starts at 1.05 during pulse, settles to 1.0.
  final double scale;

  /// List of card IDs revealed so far.
  final List<String> revealedCards;

  /// Create a copy with updated fields.
  CommunityCardState copyWith({
    CommunityCardPhase? phase,
    CommunityCardType? cardType,
    double? progress,
    double? scale,
    List<String>? revealedCards,
  }) {
    return CommunityCardState(
      phase: phase ?? this.phase,
      cardType: cardType ?? this.cardType,
      progress: progress ?? this.progress,
      scale: scale ?? this.scale,
      revealedCards: revealedCards ?? this.revealedCards,
    );
  }
}

/// Controller responsible for orchestrating community card animations
/// (flop, turn, river).
///
/// - Flop: 3 cards appearing simultaneously with spread animation over 600ms
/// - Turn: single card sliding into position over 400ms
/// - River: single card sliding into final position over 400ms
///
/// Applies a brief scale-up pulse (1.05x → 1.0x) on each new card and
/// triggers card-flip sound via [AudioManager] on each reveal.
///
/// Supports skip via [skipRequested] — if the user taps to skip, the
/// animation resolves immediately to the completed state.
class CommunityCardController extends AnimationCoordinator {
  CommunityCardController();

  /// Scale pulse peak value applied to each new card.
  static const double scalePulsePeak = 1.05;

  /// Notifier for the current community card animation state.
  /// UI widgets observe this to render card spread/slide animations.
  final ValueNotifier<CommunityCardState?> communityCardState =
      ValueNotifier<CommunityCardState?>(null);

  /// All cards revealed across flop, turn, and river.
  final List<String> _allRevealedCards = [];

  // ─── Public API ──────────────────────────────────────────────────────

  /// Animate the flop: 3 cards appearing simultaneously with spread
  /// animation over 600ms.
  ///
  /// [cards] must contain exactly 3 card IDs (e.g., ["Ah", "Kd", "7c"]).
  ///
  /// Returns a Future that completes when the animation finishes or is
  /// skipped.
  Future<void> animateFlop({required List<String> cards}) {
    return _enqueueCommunityCard(
      () => _onPlayCommunityCardAnimation(
        CommunityCardType.flop,
        cards,
        AnimationTimingConfig.flopSpread,
      ),
    );
  }

  /// Animate the turn: single card sliding into position over 400ms.
  ///
  /// [card] is the card ID (e.g., "Qs").
  ///
  /// Returns a Future that completes when the animation finishes or is
  /// skipped.
  Future<void> animateTurn({required String card}) {
    return _enqueueCommunityCard(
      () => _onPlayCommunityCardAnimation(CommunityCardType.turn, [
        card,
      ], AnimationTimingConfig.turnSlide),
    );
  }

  /// Animate the river: single card sliding into final position over 400ms.
  ///
  /// [card] is the card ID (e.g., "Td").
  ///
  /// Returns a Future that completes when the animation finishes or is
  /// skipped.
  Future<void> animateRiver({required String card}) {
    return _enqueueCommunityCard(
      () => _onPlayCommunityCardAnimation(CommunityCardType.river, [
        card,
      ], AnimationTimingConfig.riverSlide),
    );
  }

  // ─── Private Implementation ──────────────────────────────────────────

  /// Sentinel value to identify community card animations in the queue.
  static const int _communitySentinel = -998;

  /// Pending community card action to execute.
  Future<void> Function()? _pendingCommunityAction;

  /// Completer for the pending community card animation.
  Completer<void>? _pendingCommunityCompleter;

  /// Enqueue the community card animation through the coordinator's queue.
  Future<void> _enqueueCommunityCard(Future<void> Function() action) {
    final completer = Completer<void>();
    _pendingCommunityAction = action;
    _pendingCommunityCompleter = completer;
    // Route through the base class queue using playChipAnimation with sentinel.
    playChipAnimation(Offset.zero, Offset.zero, _communitySentinel);
    return completer.future;
  }

  @override
  Future<void> onPlayChipAnimation(Offset from, Offset to, int amount) async {
    if (amount == _communitySentinel && _pendingCommunityAction != null) {
      final action = _pendingCommunityAction!;
      final completer = _pendingCommunityCompleter!;
      _pendingCommunityAction = null;
      _pendingCommunityCompleter = null;
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
      return;
    }
  }

  /// Execute the community card animation sequence.
  Future<void> _onPlayCommunityCardAnimation(
    CommunityCardType cardType,
    List<String> cards,
    int durationMs,
  ) async {
    // Initialize state.
    communityCardState.value = CommunityCardState(
      phase: CommunityCardPhase.idle,
      cardType: cardType,
      progress: 0.0,
      scale: scalePulsePeak,
      revealedCards: List.unmodifiable(_allRevealedCards),
    );

    if (skipRequested) {
      _resolveToFinalState(cardType, cards);
      return;
    }

    // Transition to animating phase.
    communityCardState.value = communityCardState.value!.copyWith(
      phase: CommunityCardPhase.animating,
    );

    // Trigger card-flip sound for the reveal.
    _playCardFlipSound();

    // Animate with scale pulse over the specified duration.
    await _animateWithScalePulse(cardType, cards, durationMs);

    // Complete.
    _resolveToFinalState(cardType, cards);
  }

  /// Animate the card reveal with a scale pulse (1.05x → 1.0x).
  ///
  /// The scale starts at [scalePulsePeak] (1.05) and settles to 1.0 over
  /// the animation duration. Progress goes from 0.0 to 1.0.
  Future<void> _animateWithScalePulse(
    CommunityCardType cardType,
    List<String> cards,
    int durationMs,
  ) async {
    const steps = 12;
    final stepDuration = durationMs ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final t = step / steps;
      // Scale pulse: starts at 1.05, linearly settles to 1.0.
      final scale = scalePulsePeak - (scalePulsePeak - 1.0) * t;

      communityCardState.value = CommunityCardState(
        phase: CommunityCardPhase.animating,
        cardType: cardType,
        progress: t,
        scale: scale,
        revealedCards: List.unmodifiable(_allRevealedCards),
      );

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Set the community card state to its final completed state.
  void _resolveToFinalState(CommunityCardType cardType, List<String> cards) {
    // Add newly revealed cards to the accumulated list.
    _allRevealedCards.addAll(cards);

    communityCardState.value = CommunityCardState(
      phase: CommunityCardPhase.completed,
      cardType: cardType,
      progress: 1.0,
      scale: 1.0,
      revealedCards: List.unmodifiable(_allRevealedCards),
    );
  }

  /// Play the card-flip sound effect for each community card reveal.
  /// Silently no-ops if audio is unavailable or disabled.
  void _playCardFlipSound() {
    try {
      AudioManager.instance.play(SoundEffect.cardFlip).catchError((_) {});
    } catch (_) {
      // Non-critical — continue without sound.
    }
  }

  /// Dispose the controller and clean up resources.
  @override
  void dispose() {
    communityCardState.dispose();
    super.dispose();
  }
}
