import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import 'animation_coordinator.dart';
import 'animation_feature_flags.dart';
import 'animation_service.dart';

/// Game phases as understood by the animation layer.
///
/// Maps to the server's game state phases. The animation layer reads these
/// to decide which animation sequence to trigger.
enum AnimationGamePhase {
  waiting,
  preflop,
  flop,
  turn,
  river,
  showdown,
  result,
}

/// Wires the [AnimationCoordinator] to game state changes.
///
/// This class acts as the bridge between the game state manager (which
/// receives Socket.IO events via [GameSocket]) and the animation layer.
/// It listens for phase transitions and triggers the appropriate animation
/// sequences through the coordinator.
///
/// Key design principles:
/// - **GameSocket remains unchanged** — this class observes state, not socket events directly
/// - **AudioManager remains unchanged** — sound triggers are routed through animation callbacks
/// - **Feature flags control routing** — each phase checks its flag before triggering Rive animations
/// - **Reconnection-aware** — skips animations on reconnect to render current state immediately
class AnimationWiring {
  AnimationWiring({required this.coordinator, required this.featureFlags});

  /// The animation coordinator that executes animation sequences.
  final AnimationCoordinator coordinator;

  /// Feature flags controlling which phases use the new Rive animations.
  final AnimationFeatureFlags featureFlags;

  /// The previous game phase, used to detect transitions.
  AnimationGamePhase? _previousPhase;

  /// Whether the current state update is from a reconnection event.
  /// When true, animations are skipped and the final state is rendered directly.
  bool _isReconnecting = false;

  /// Whether the wiring has been disposed.
  bool _disposed = false;

  // ─── Public API ──────────────────────────────────────────────────────

  /// Whether the wiring is currently in reconnection mode (skip animations).
  bool get isReconnecting => _isReconnecting;

  /// The last known game phase.
  AnimationGamePhase? get previousPhase => _previousPhase;

  /// Mark the next state update as a reconnection event.
  ///
  /// When set, the next call to [onPhaseChange] will skip all animations
  /// and render the current state directly (Req 17.5).
  void setReconnecting(bool value) {
    _isReconnecting = value;
  }

  /// Called when the game phase changes.
  ///
  /// Routes the phase transition to the appropriate animation sequence
  /// based on feature flags. If [_isReconnecting] is true, skips all
  /// animations and clears the reconnection flag.
  ///
  /// Parameters:
  /// - [newPhase]: The new game phase from the server state update.
  /// - [dealTargets]: Card deal targets (required for preflop phase).
  /// - [communityCardCount]: Number of community cards for flop/turn/river.
  /// - [winningSeat]: The winning player's seat (for result phase).
  /// - [potAmount]: The pot amount (for result phase celebration).
  /// - [showdownHands]: Hands to reveal during showdown.
  Future<void> onPhaseChange({
    required AnimationGamePhase newPhase,
    List<DealTarget>? dealTargets,
    int? communityCardCount,
    int? winningSeat,
    int? potAmount,
    List<ShowdownHand>? showdownHands,
  }) async {
    if (_disposed) return;

    // Skip animations on reconnection — render final state directly.
    if (_isReconnecting) {
      _previousPhase = newPhase;
      _isReconnecting = false;
      developer.log(
        'Reconnection: skipping animations for phase $newPhase',
        name: 'AnimationWiring',
      );
      return;
    }

    // Only trigger animations on actual phase transitions.
    if (newPhase == _previousPhase) return;

    final oldPhase = _previousPhase;
    _previousPhase = newPhase;

    developer.log(
      'Phase transition: $oldPhase → $newPhase',
      name: 'AnimationWiring',
    );

    switch (newPhase) {
      case AnimationGamePhase.preflop:
        await _handleDealPhase(dealTargets);
        break;
      case AnimationGamePhase.flop:
      case AnimationGamePhase.turn:
      case AnimationGamePhase.river:
        // Community card animations are handled by the community card
        // controller directly — no coordinator routing needed here.
        break;
      case AnimationGamePhase.showdown:
        await _handleShowdownPhase(showdownHands);
        break;
      case AnimationGamePhase.result:
        await _handleResultPhase(winningSeat, potAmount);
        break;
      case AnimationGamePhase.waiting:
        // No animation needed for waiting phase.
        break;
    }
  }

  /// Called when a player places a bet.
  ///
  /// Routes through feature flags to trigger chip animation if enabled.
  Future<void> onBetPlaced({
    required Offset fromSeat,
    required Offset toPot,
    required int amount,
  }) async {
    if (_disposed || _isReconnecting) return;

    if (featureFlags.isChipAnimationEnabled) {
      await coordinator.playChipAnimation(fromSeat, toPot, amount);
    }
  }

  /// Called when the game disconnects.
  ///
  /// Pauses all animations and marks the wiring for reconnection mode.
  void onDisconnect() {
    if (_disposed) return;
    AnimationService.instance.pauseAll();
    developer.log('Disconnected: pausing animations', name: 'AnimationWiring');
  }

  /// Called when the game reconnects.
  ///
  /// Resumes the animation service and sets reconnection mode so the next
  /// state update skips animations.
  void onReconnect() {
    if (_disposed) return;
    AnimationService.instance.resumeAll();
    _isReconnecting = true;
    developer.log(
      'Reconnected: will skip animations for next state update',
      name: 'AnimationWiring',
    );
  }

  /// Dispose the wiring and release resources.
  void dispose() {
    _disposed = true;
    _previousPhase = null;
  }

  // ─── Private Phase Handlers ──────────────────────────────────────────

  /// Handle the deal phase: trigger card deal animation if enabled.
  Future<void> _handleDealPhase(List<DealTarget>? dealTargets) async {
    if (!featureFlags.isDealAnimationEnabled) return;
    if (dealTargets == null || dealTargets.isEmpty) return;

    await coordinator.playDealSequence(dealTargets);
  }

  /// Handle the showdown phase: trigger showdown reveal if enabled.
  Future<void> _handleShowdownPhase(List<ShowdownHand>? hands) async {
    if (!featureFlags.isCelebrationAnimationEnabled) return;
    if (hands == null || hands.isEmpty) return;

    await coordinator.playShowdown(hands);
  }

  /// Handle the result phase: trigger celebration if enabled.
  Future<void> _handleResultPhase(int? winningSeat, int? potAmount) async {
    if (!featureFlags.isCelebrationAnimationEnabled) return;
    if (winningSeat == null || potAmount == null) return;

    await coordinator.playCelebration(winningSeat, potAmount);
  }
}
