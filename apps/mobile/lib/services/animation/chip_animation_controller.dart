import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../audio_manager.dart';
import '../haptic_service.dart';
import 'animation_coordinator.dart';
import 'animation_timing_config.dart';

/// The phase of a chip animation.
enum ChipAnimationPhase {
  /// Chips have not started animating yet.
  waiting,

  /// Chips are flying from source to destination.
  flying,

  /// Chips have arrived at the destination.
  arrived,
}

/// The phase of a chip-to-winner animation.
enum WinChipAnimationPhase {
  /// Not started.
  idle,

  /// Chips are flying from pot center to winner seat.
  flying,

  /// Chips have arrived at the winner's seat.
  arrived,
}

/// The phase of an all-in push animation.
enum AllInAnimationPhase {
  /// Not started.
  idle,

  /// Chip stack is sliding dramatically toward the pot.
  pushing,

  /// Glow effect is active after chips arrive.
  glowing,

  /// Animation complete.
  completed,
}

/// Represents the current state of an all-in push animation.
class AllInAnimationState {
  const AllInAnimationState({
    required this.phase,
    required this.position,
    this.progress = 0.0,
    this.glowIntensity = 0.0,
  });

  /// Current animation phase.
  final AllInAnimationPhase phase;

  /// Current screen position of the chip stack.
  final Offset position;

  /// Animation progress from 0.0 (start) to 1.0 (complete).
  final double progress;

  /// Glow effect intensity from 0.0 (off) to 1.0 (full brightness).
  /// UI can observe this to render a glow overlay via Rive state machine.
  final double glowIntensity;

  /// Create a copy with updated fields.
  AllInAnimationState copyWith({
    AllInAnimationPhase? phase,
    Offset? position,
    double? progress,
    double? glowIntensity,
  }) {
    return AllInAnimationState(
      phase: phase ?? this.phase,
      position: position ?? this.position,
      progress: progress ?? this.progress,
      glowIntensity: glowIntensity ?? this.glowIntensity,
    );
  }
}

/// Represents the current state of a chip-to-winner animation.
class WinChipAnimationState {
  const WinChipAnimationState({
    required this.phase,
    required this.position,
    required this.spriteCount,
    this.progress = 0.0,
  });

  /// Current animation phase.
  final WinChipAnimationPhase phase;

  /// Current screen position of the chip group.
  final Offset position;

  /// Number of chip sprites to render (always 5 for win — dramatic moment).
  final int spriteCount;

  /// Animation progress from 0.0 (start) to 1.0 (complete).
  final double progress;

  /// Create a copy with updated fields.
  WinChipAnimationState copyWith({
    WinChipAnimationPhase? phase,
    Offset? position,
    int? spriteCount,
    double? progress,
  }) {
    return WinChipAnimationState(
      phase: phase ?? this.phase,
      position: position ?? this.position,
      spriteCount: spriteCount ?? this.spriteCount,
      progress: progress ?? this.progress,
    );
  }
}

/// Represents the current animation state of a chip bet animation.
class ChipAnimationState {
  const ChipAnimationState({
    required this.phase,
    required this.position,
    required this.spriteCount,
    this.progress = 0.0,
  });

  /// Current animation phase.
  final ChipAnimationPhase phase;

  /// Current screen position of the chip group.
  final Offset position;

  /// Number of chip sprites to render (2 for small, 5 for large bets).
  final int spriteCount;

  /// Animation progress from 0.0 (start) to 1.0 (complete).
  final double progress;

  /// Create a copy with updated fields.
  ChipAnimationState copyWith({
    ChipAnimationPhase? phase,
    Offset? position,
    int? spriteCount,
    double? progress,
  }) {
    return ChipAnimationState(
      phase: phase ?? this.phase,
      position: position ?? this.position,
      spriteCount: spriteCount ?? this.spriteCount,
      progress: progress ?? this.progress,
    );
  }
}

/// Controller responsible for orchestrating chip bet animations.
///
/// Animates chips flying from a player seat (source) to the pot center
/// (destination) over 350ms. Varies chip sprite count based on bet amount:
/// 2 chips for small bets (below threshold), 5 chips for large bets
/// (at or above threshold).
///
/// The threshold for small vs large bets is configurable and defaults to
/// 10x the big blind. If no big blind is set, a default threshold of 100
/// is used.
///
/// Integrates with [AudioManager] for chip-clink sound on arrival and
/// [HapticService] for tactile feedback.
class ChipAnimationController extends AnimationCoordinator {
  ChipAnimationController({this.bigBlind = 10, this.largeBetMultiplier = 10})
    : largeBetThreshold = bigBlind * largeBetMultiplier;

  /// The big blind value for the current table.
  final int bigBlind;

  /// Multiplier applied to big blind to determine large bet threshold.
  final int largeBetMultiplier;

  /// The threshold amount at or above which a bet is considered "large".
  /// Bets below this use 2 chip sprites; bets at or above use 5.
  final int largeBetThreshold;

  /// Number of chip sprites for a small bet.
  static const int smallBetSpriteCount = 2;

  /// Number of chip sprites for a large bet.
  static const int largeBetSpriteCount = 5;

  /// Notifier for the current chip animation state.
  /// UI widgets observe this to render chip sprites at the correct position.
  final ValueNotifier<ChipAnimationState?> chipState =
      ValueNotifier<ChipAnimationState?>(null);

  /// Notifier for the current all-in push animation state.
  /// UI widgets observe this to render the dramatic push effect and glow.
  final ValueNotifier<AllInAnimationState?> allInState =
      ValueNotifier<AllInAnimationState?>(null);

  /// Notifier for the current chip-to-winner animation state.
  /// UI widgets observe this to render chips flying from pot to winner seat.
  final ValueNotifier<WinChipAnimationState?> winChipState =
      ValueNotifier<WinChipAnimationState?>(null);

  // ─── Public API ──────────────────────────────────────────────────────

  /// Compute the number of chip sprites to display based on [betAmount].
  ///
  /// Returns [smallBetSpriteCount] (2) for bets below [largeBetThreshold],
  /// and [largeBetSpriteCount] (5) for bets at or above the threshold.
  int computeSpriteCount(int betAmount) {
    if (betAmount <= 0) return smallBetSpriteCount;
    return betAmount >= largeBetThreshold
        ? largeBetSpriteCount
        : smallBetSpriteCount;
  }

  /// Animate a chip bet from [source] to [destination] with the given
  /// [amount].
  ///
  /// The animation runs over [AnimationTimingConfig.chipBetFlight] (350ms).
  /// On arrival, triggers a chip-clink sound and light haptic feedback.
  ///
  /// Returns a Future that completes when the animation finishes or is
  /// skipped.
  Future<void> animateBet({
    required Offset source,
    required Offset destination,
    required int amount,
  }) {
    return playChipAnimation(source, destination, amount);
  }

  /// Animate a dramatic all-in push from [source] to [destination].
  ///
  /// This is more dramatic than a normal bet animation:
  /// - Uses a longer flight duration (600ms) with an ease-in-out curve
  /// - Triggers [SoundEffect.allInPush] at the start (Req 15.4)
  /// - Activates a glow effect after chips arrive (Req 3.2)
  /// - Uses all chip sprites (large bet count) regardless of amount
  /// - Triggers medium haptic on push start
  ///
  /// Returns a Future that completes when the full animation (push + glow)
  /// finishes or is skipped.
  Future<void> animateAllIn({
    required Offset source,
    required Offset destination,
    required int amount,
  }) {
    return _enqueueAllIn(
      () => _onPlayAllInAnimation(source, destination, amount),
    );
  }

  /// Animate chips flying from pot center to the winner's seat.
  ///
  /// This is the chip-to-winner celebration animation:
  /// - Flies chips from [potCenter] to [winnerSeat] over 500ms (Req 4.3)
  /// - Always uses large sprite count (5) for dramatic effect
  /// - Triggers [SoundEffect.coinCascade] when chips reach the winner (Req 15.3)
  /// - Triggers success haptic pattern (three short pulses) on arrival (Req 16.3)
  /// - Supports skip via [skipRequested]
  ///
  /// Returns a Future that completes when the animation finishes or is
  /// skipped.
  Future<void> animateWin({
    required Offset potCenter,
    required Offset winnerSeat,
  }) {
    return _enqueueWin(() => _onPlayWinAnimation(potCenter, winnerSeat));
  }

  // ─── AnimationCoordinator Override ───────────────────────────────────

  @override
  Future<void> onPlayChipAnimation(Offset from, Offset to, int amount) async {
    // Check if this is an all-in animation routed through the queue.
    if (amount == _allInSentinel && _pendingAllInAction != null) {
      final action = _pendingAllInAction!;
      final completer = _pendingAllInCompleter!;
      _pendingAllInAction = null;
      _pendingAllInCompleter = null;
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
      return;
    }

    // Check if this is a win animation routed through the queue.
    if (amount == _winSentinel && _pendingWinAction != null) {
      final action = _pendingWinAction!;
      final completer = _pendingWinCompleter!;
      _pendingWinAction = null;
      _pendingWinCompleter = null;
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
      return;
    }

    final spriteCount = computeSpriteCount(amount);

    // Initialize chip state.
    chipState.value = ChipAnimationState(
      phase: ChipAnimationPhase.waiting,
      position: from,
      spriteCount: spriteCount,
    );

    if (skipRequested) {
      _resolveToFinalState(to, spriteCount);
      return;
    }

    // Transition to flying phase.
    chipState.value = chipState.value!.copyWith(
      phase: ChipAnimationPhase.flying,
    );

    // Animate flight from source to destination over chipBetFlight (350ms).
    await _animateChipFlight(from: from, to: to, spriteCount: spriteCount);

    // Always resolve to final state (whether skipped or completed naturally).
    _resolveToFinalState(to, spriteCount);

    // Trigger chip-clink sound on arrival at pot (Req 15.2).
    _playChipClinkSound();

    // Trigger light haptic on chip arrival.
    _triggerArrivalHaptic();
  }

  // ─── Private Helpers ─────────────────────────────────────────────────

  /// Animate the chip flight from [from] to [to] over chipBetFlight duration.
  /// Interpolates position linearly over discrete steps.
  Future<void> _animateChipFlight({
    required Offset from,
    required Offset to,
    required int spriteCount,
  }) async {
    const steps = 10;
    final stepDuration = AnimationTimingConfig.chipBetFlight ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final t = step / steps;
      final currentPosition = Offset.lerp(from, to, t)!;

      chipState.value = ChipAnimationState(
        phase: ChipAnimationPhase.flying,
        position: currentPosition,
        spriteCount: spriteCount,
        progress: t,
      );

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Set the chip state to its final arrived position.
  void _resolveToFinalState(Offset destination, int spriteCount) {
    chipState.value = ChipAnimationState(
      phase: ChipAnimationPhase.arrived,
      position: destination,
      spriteCount: spriteCount,
      progress: 1.0,
    );
  }

  /// Play the chip-clink sound effect when chips reach the pot center.
  /// Silently no-ops if audio is unavailable or disabled.
  void _playChipClinkSound() {
    try {
      // Fire-and-forget — don't await to avoid blocking the animation loop.
      AudioManager.instance.play(SoundEffect.chipToss).catchError((_) {});
    } catch (_) {
      // Non-critical — continue without sound.
    }
  }

  /// Trigger light haptic feedback when chips arrive at the pot.
  /// Silently no-ops if haptic is unavailable or disabled.
  void _triggerArrivalHaptic() {
    try {
      // Fire-and-forget — don't await to avoid blocking the animation loop.
      HapticService.instance.lightImpact().catchError((_) {});
    } catch (_) {
      // Non-critical — continue without haptic.
    }
  }

  // ─── All-In Push Animation ───────────────────────────────────────────

  /// Enqueue the all-in animation through the coordinator's queue.
  Future<void> _enqueueAllIn(Future<void> Function() action) {
    return _enqueueViaCoordinator(action);
  }

  /// Enqueue an action through the base coordinator queue mechanism.
  /// This delegates to [playChipAnimation] with a sentinel amount of -1
  /// to reuse the queue, but overrides the actual behavior.
  Future<void> _enqueueViaCoordinator(Future<void> Function() action) {
    // We use the base class queue by wrapping in playChipAnimation's
    // queue mechanism. Instead, we directly call the protected _enqueue
    // pattern by overriding onPlayChipAnimation conditionally.
    // Simpler approach: use a completer and the base queue.
    final completer = Completer<void>();
    _pendingAllInAction = action;
    _pendingAllInCompleter = completer;
    // Trigger through the base class queue with a sentinel.
    playChipAnimation(Offset.zero, Offset.zero, _allInSentinel);
    return completer.future;
  }

  /// Sentinel value to identify all-in animations in the queue.
  static const int _allInSentinel = -999;

  /// Pending all-in action to execute.
  Future<void> Function()? _pendingAllInAction;

  /// Completer for the pending all-in animation.
  Completer<void>? _pendingAllInCompleter;

  /// Execute the all-in push animation sequence.
  Future<void> _onPlayAllInAnimation(Offset from, Offset to, int amount) async {
    // 1. Trigger dramatic push sound at the start (Req 15.4).
    _playAllInPushSound();

    // 2. Trigger medium haptic for dramatic effect.
    _triggerAllInHaptic();

    // 3. Initialize all-in state.
    allInState.value = AllInAnimationState(
      phase: AllInAnimationPhase.idle,
      position: from,
    );

    if (skipRequested) {
      _resolveAllInToFinalState(to);
      return;
    }

    // 4. Transition to pushing phase.
    allInState.value = allInState.value!.copyWith(
      phase: AllInAnimationPhase.pushing,
    );

    // 5. Animate the dramatic push flight (600ms with ease-in-out curve).
    await _animateAllInPush(from: from, to: to);

    if (skipRequested) {
      _resolveAllInToFinalState(to);
      return;
    }

    // 6. Transition to glow phase.
    allInState.value = allInState.value!.copyWith(
      phase: AllInAnimationPhase.glowing,
      position: to,
      progress: 1.0,
    );

    // 7. Animate glow effect (800ms pulse).
    await _animateGlowEffect();

    // 8. Complete.
    _resolveAllInToFinalState(to);

    // 9. Trigger chip-clink sound on arrival.
    _playChipClinkSound();
  }

  /// Animate the all-in chip stack push from [from] to [to].
  /// Uses ease-in-out curve for dramatic acceleration/deceleration.
  /// Duration: [AnimationTimingConfig.allInPushFlight] (600ms).
  Future<void> _animateAllInPush({
    required Offset from,
    required Offset to,
  }) async {
    const steps = 15; // More steps for smoother dramatic animation.
    final stepDuration = AnimationTimingConfig.allInPushFlight ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final linearT = step / steps;
      // Ease-in-out curve: 3t² - 2t³ (smoothstep).
      final t = linearT * linearT * (3.0 - 2.0 * linearT);
      final currentPosition = Offset.lerp(from, to, t)!;

      allInState.value = AllInAnimationState(
        phase: AllInAnimationPhase.pushing,
        position: currentPosition,
        progress: linearT,
        glowIntensity: 0.0,
      );

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Animate the glow effect pulsing after chips arrive.
  /// Duration: [AnimationTimingConfig.allInGlowDuration] (800ms).
  /// Glow intensity ramps up to 1.0 then fades back to 0.0.
  Future<void> _animateGlowEffect() async {
    const steps = 10;
    final stepDuration = AnimationTimingConfig.allInGlowDuration ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final t = step / steps;
      // Sine curve for smooth pulse: peaks at 0.5, returns to 0 at 1.0.
      final glowIntensity = math.sin(t * math.pi);

      allInState.value = allInState.value!.copyWith(
        glowIntensity: glowIntensity,
      );

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Set the all-in state to its final completed position.
  void _resolveAllInToFinalState(Offset destination) {
    allInState.value = AllInAnimationState(
      phase: AllInAnimationPhase.completed,
      position: destination,
      progress: 1.0,
      glowIntensity: 0.0,
    );
  }

  /// Play the dramatic all-in push sound effect (Req 15.4).
  /// Silently no-ops if audio is unavailable or disabled.
  void _playAllInPushSound() {
    try {
      AudioManager.instance.play(SoundEffect.allInPush).catchError((_) {});
    } catch (_) {
      // Non-critical — continue without sound.
    }
  }

  /// Trigger medium haptic feedback for the dramatic all-in push.
  void _triggerAllInHaptic() {
    try {
      HapticService.instance.mediumImpact().catchError((_) {});
    } catch (_) {
      // Non-critical — continue without haptic.
    }
  }

  // ─── Win Chip Animation ──────────────────────────────────────────────

  /// Sentinel value to identify win animations in the queue.
  static const int _winSentinel = -998;

  /// Pending win action to execute.
  Future<void> Function()? _pendingWinAction;

  /// Completer for the pending win animation.
  Completer<void>? _pendingWinCompleter;

  /// Enqueue the win animation through the coordinator's queue.
  Future<void> _enqueueWin(Future<void> Function() action) {
    final completer = Completer<void>();
    _pendingWinAction = action;
    _pendingWinCompleter = completer;
    // Trigger through the base class queue with a sentinel.
    playChipAnimation(Offset.zero, Offset.zero, _winSentinel);
    return completer.future;
  }

  /// Execute the chip-to-winner animation sequence.
  ///
  /// Animates chips from pot center to winner seat over 500ms (chipWinFlight).
  /// Always uses large sprite count (5) for dramatic effect.
  /// Triggers coin-cascade sound and success haptic on arrival.
  Future<void> _onPlayWinAnimation(Offset potCenter, Offset winnerSeat) async {
    const spriteCount = largeBetSpriteCount; // Always 5 for win animations.

    // 1. Initialize win chip state.
    winChipState.value = WinChipAnimationState(
      phase: WinChipAnimationPhase.idle,
      position: potCenter,
      spriteCount: spriteCount,
    );

    if (skipRequested) {
      _resolveWinToFinalState(winnerSeat, spriteCount);
      _playCoinCascadeSound();
      _triggerWinHaptic();
      return;
    }

    // 2. Transition to flying phase.
    winChipState.value = winChipState.value!.copyWith(
      phase: WinChipAnimationPhase.flying,
    );

    // 3. Animate flight from pot center to winner seat over chipWinFlight (500ms).
    await _animateWinChipFlight(
      from: potCenter,
      to: winnerSeat,
      spriteCount: spriteCount,
    );

    // 4. Resolve to final state.
    _resolveWinToFinalState(winnerSeat, spriteCount);

    // 5. Trigger coin-cascade sound when chips reach winner (Req 15.3).
    _playCoinCascadeSound();

    // 6. Trigger success haptic pattern on arrival (Req 16.3).
    _triggerWinHaptic();
  }

  /// Animate the win chip flight from [from] to [to] over chipWinFlight duration.
  /// Uses ease-out curve for a satisfying deceleration as chips arrive.
  /// Duration: [AnimationTimingConfig.chipWinFlight] (500ms).
  Future<void> _animateWinChipFlight({
    required Offset from,
    required Offset to,
    required int spriteCount,
  }) async {
    const steps = 12; // Smooth steps for 500ms animation.
    final stepDuration = AnimationTimingConfig.chipWinFlight ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final linearT = step / steps;
      // Ease-out curve: 1 - (1-t)² — fast start, smooth deceleration.
      final t = 1.0 - (1.0 - linearT) * (1.0 - linearT);
      final currentPosition = Offset.lerp(from, to, t)!;

      winChipState.value = WinChipAnimationState(
        phase: WinChipAnimationPhase.flying,
        position: currentPosition,
        spriteCount: spriteCount,
        progress: linearT,
      );

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Set the win chip state to its final arrived position.
  void _resolveWinToFinalState(Offset destination, int spriteCount) {
    winChipState.value = WinChipAnimationState(
      phase: WinChipAnimationPhase.arrived,
      position: destination,
      spriteCount: spriteCount,
      progress: 1.0,
    );
  }

  /// Play the coin-cascade sound effect when chips reach the winner (Req 15.3).
  /// Silently no-ops if audio is unavailable or disabled.
  void _playCoinCascadeSound() {
    try {
      AudioManager.instance.play(SoundEffect.coinCascade).catchError((_) {});
    } catch (_) {
      // Non-critical — continue without sound.
    }
  }

  /// Trigger success haptic pattern (three short pulses) on win (Req 16.3).
  /// Silently no-ops if haptic is unavailable or disabled.
  void _triggerWinHaptic() {
    try {
      HapticService.instance.successPattern().catchError((_) {});
    } catch (_) {
      // Non-critical — continue without haptic.
    }
  }

  /// Dispose the controller and clean up resources.
  @override
  void dispose() {
    chipState.dispose();
    allInState.dispose();
    winChipState.dispose();
    super.dispose();
  }
}
