import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../audio_manager.dart';
import '../haptic_service.dart';
import 'animation_coordinator.dart';
import 'animation_timing_config.dart';

/// Controller responsible for orchestrating the card deal animation sequence.
///
/// Computes clockwise deal order from the dealer seat position, animates cards
/// flying from the dealer to each target seat with stagger, scales cards from
/// 30% to 100% during flight for depth perspective, and plays a flip animation
/// on arrival.
///
/// Enforces a maximum total duration of 1500ms for 9 players by dynamically
/// adjusting the stagger delay when needed.
class DealAnimationController extends AnimationCoordinator {
  DealAnimationController({
    required this.dealerSeatIndex,
    required this.dealerPosition,
    this.totalSeats = 9,
  });

  /// The seat index (0-based) of the dealer.
  final int dealerSeatIndex;

  /// The screen position of the dealer (where cards fly from).
  final Offset dealerPosition;

  /// Total number of seats at the table (default 9).
  final int totalSeats;

  /// Scale at the start of the card flight (30%).
  static const double startScale = 0.3;

  /// Scale at the end of the card flight (100%).
  static const double endScale = 1.0;

  /// Notifier for the current animation state of each card being dealt.
  /// Key: index in the deal order, Value: current animation state.
  final ValueNotifier<Map<int, DealCardState>> cardStates =
      ValueNotifier<Map<int, DealCardState>>({});

  // ─── Public API ──────────────────────────────────────────────────────

  /// Compute the clockwise deal order starting from the first seat after
  /// the dealer.
  ///
  /// Given a list of [targets], returns them sorted in clockwise order
  /// starting from the seat immediately after [dealerSeatIndex].
  List<DealTarget> computeDealOrder(List<DealTarget> targets) {
    if (targets.isEmpty) return [];

    // Sort targets by their clockwise distance from the dealer.
    final sorted = List<DealTarget>.from(targets);
    sorted.sort((a, b) {
      final distA = _clockwiseDistance(dealerSeatIndex, a.seatIndex);
      final distB = _clockwiseDistance(dealerSeatIndex, b.seatIndex);
      return distA.compareTo(distB);
    });

    return sorted;
  }

  /// Compute the effective stagger delay for the given number of cards.
  ///
  /// If the default stagger (100ms) would cause the total duration to exceed
  /// [AnimationTimingConfig.dealMaxTotal] (1500ms), the stagger is reduced
  /// proportionally.
  ///
  /// Total duration formula:
  ///   flightDuration + (cardCount - 1) * stagger + flipDuration
  ///
  /// We need: flightDuration + (cardCount - 1) * stagger + flipDuration <= maxTotal
  /// So: stagger <= (maxTotal - flightDuration - flipDuration) / (cardCount - 1)
  int computeStaggerDelay(int cardCount) {
    if (cardCount <= 1) return AnimationTimingConfig.dealStaggerDelay;

    final maxStagger =
        (AnimationTimingConfig.dealMaxTotal -
            AnimationTimingConfig.dealFlightDuration -
            AnimationTimingConfig.dealFlipDuration) ~/
        (cardCount - 1);

    return math.min(AnimationTimingConfig.dealStaggerDelay, maxStagger);
  }

  /// Compute the total duration of the deal animation for the given card count.
  int computeTotalDuration(int cardCount) {
    if (cardCount <= 0) return 0;
    if (cardCount == 1) {
      return AnimationTimingConfig.dealFlightDuration +
          AnimationTimingConfig.dealFlipDuration;
    }

    final stagger = computeStaggerDelay(cardCount);
    return AnimationTimingConfig.dealFlightDuration +
        (cardCount - 1) * stagger +
        AnimationTimingConfig.dealFlipDuration;
  }

  // ─── AnimationCoordinator Override ───────────────────────────────────

  @override
  Future<void> onPlayDealSequence(List<DealTarget> targets) async {
    if (targets.isEmpty) return;

    final orderedTargets = computeDealOrder(targets);
    final stagger = computeStaggerDelay(orderedTargets.length);

    // Initialize card states.
    final states = <int, DealCardState>{};
    for (var i = 0; i < orderedTargets.length; i++) {
      states[i] = DealCardState(
        target: orderedTargets[i],
        phase: DealCardPhase.waiting,
        scale: startScale,
        position: dealerPosition,
      );
    }
    cardStates.value = Map.from(states);

    // Animate each card with stagger.
    for (var i = 0; i < orderedTargets.length; i++) {
      if (skipRequested) {
        _resolveRemainingCards(states, orderedTargets);
        return;
      }

      // Start flight for card i.
      states[i] = states[i]!.copyWith(phase: DealCardPhase.flying);
      cardStates.value = Map.from(states);

      // Trigger card-slide sound at start of each card flight (Req 15.1).
      _playDealSound();

      // Animate flight (scale from 30% to 100%, move from dealer to target).
      await _animateFlight(index: i, target: orderedTargets[i], states: states);

      if (skipRequested) {
        _resolveRemainingCards(states, orderedTargets);
        return;
      }

      // Play flip animation on arrival.
      states[i] = states[i]!.copyWith(
        phase: DealCardPhase.flipping,
        scale: endScale,
        position: orderedTargets[i].position,
      );
      cardStates.value = Map.from(states);

      // Trigger light haptic on card arrival at player seat (Req 16.2).
      _triggerArrivalHaptic();

      await _animateFlip(index: i, states: states);

      if (skipRequested) {
        _resolveRemainingCards(states, orderedTargets);
        return;
      }

      // Mark card as complete.
      states[i] = states[i]!.copyWith(phase: DealCardPhase.complete);
      cardStates.value = Map.from(states);

      // Wait stagger delay before next card (except for the last one).
      if (i < orderedTargets.length - 1 && !skipRequested) {
        await Future.delayed(Duration(milliseconds: stagger));
      }
    }
  }

  /// Set all incomplete cards to their final state when skip is requested.
  void _resolveRemainingCards(
    Map<int, DealCardState> states,
    List<DealTarget> orderedTargets,
  ) {
    for (var i = 0; i < orderedTargets.length; i++) {
      if (states[i]!.phase != DealCardPhase.complete) {
        states[i] = states[i]!.copyWith(
          phase: DealCardPhase.complete,
          scale: endScale,
          position: orderedTargets[i].position,
        );
      }
    }
    cardStates.value = Map.from(states);
  }

  /// Dispose the controller and clean up resources.
  @override
  void dispose() {
    cardStates.dispose();
    super.dispose();
  }

  // ─── Private Helpers ─────────────────────────────────────────────────

  /// Compute the clockwise distance from [from] to [to] seat.
  /// Distance of 0 means same seat; 1 means next seat clockwise.
  int _clockwiseDistance(int from, int to) {
    return (to - from + totalSeats) % totalSeats;
  }

  /// Animate the flight of a card from dealer to target position.
  /// Interpolates position and scale over [dealFlightDuration].
  Future<void> _animateFlight({
    required int index,
    required DealTarget target,
    required Map<int, DealCardState> states,
  }) async {
    const steps = 10;
    final stepDuration = AnimationTimingConfig.dealFlightDuration ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final t = step / steps;
      final currentPosition = Offset.lerp(dealerPosition, target.position, t)!;
      final currentScale = startScale + (endScale - startScale) * t;

      states[index] = states[index]!.copyWith(
        position: currentPosition,
        scale: currentScale,
      );
      cardStates.value = Map.from(states);

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Animate the flip of a card (350ms).
  Future<void> _animateFlip({
    required int index,
    required Map<int, DealCardState> states,
  }) async {
    // The flip is driven by the Rive state machine in production.
    // Here we simulate the duration for coordination purposes.
    const steps = 7;
    final stepDuration = AnimationTimingConfig.dealFlipDuration ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final flipProgress = step / steps;
      states[index] = states[index]!.copyWith(flipProgress: flipProgress);
      cardStates.value = Map.from(states);

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Play the card-slide sound effect at the start of each card flight.
  /// Silently no-ops if audio is unavailable or disabled.
  void _playDealSound() {
    try {
      // Fire-and-forget — don't await to avoid blocking the animation loop.
      AudioManager.instance.play(SoundEffect.cardDeal).catchError((_) {});
    } catch (_) {
      // Non-critical — continue without sound.
    }
  }

  /// Trigger light haptic feedback when a card arrives at the player seat.
  /// Silently no-ops if haptic is unavailable or disabled.
  void _triggerArrivalHaptic() {
    try {
      // Fire-and-forget — don't await to avoid blocking the animation loop.
      HapticService.instance.lightImpact().catchError((_) {});
    } catch (_) {
      // Non-critical — continue without haptic.
    }
  }
}

/// The phase of a single card in the deal animation.
enum DealCardPhase {
  /// Card has not started animating yet.
  waiting,

  /// Card is flying from dealer to target seat.
  flying,

  /// Card has arrived and is playing the flip animation.
  flipping,

  /// Card animation is complete.
  complete,
}

/// Represents the current animation state of a single card being dealt.
class DealCardState {
  const DealCardState({
    required this.target,
    required this.phase,
    required this.scale,
    required this.position,
    this.flipProgress = 0.0,
  });

  /// The deal target this card is heading to.
  final DealTarget target;

  /// Current animation phase.
  final DealCardPhase phase;

  /// Current scale (0.3 to 1.0 during flight).
  final double scale;

  /// Current screen position.
  final Offset position;

  /// Flip progress (0.0 to 1.0 during flip phase).
  final double flipProgress;

  /// Create a copy with updated fields.
  DealCardState copyWith({
    DealTarget? target,
    DealCardPhase? phase,
    double? scale,
    Offset? position,
    double? flipProgress,
  }) {
    return DealCardState(
      target: target ?? this.target,
      phase: phase ?? this.phase,
      scale: scale ?? this.scale,
      position: position ?? this.position,
      flipProgress: flipProgress ?? this.flipProgress,
    );
  }
}
