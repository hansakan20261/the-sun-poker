import 'dart:async';

import 'package:flutter/widgets.dart';

import '../audio_manager.dart';
import '../haptic_service.dart';
import 'animation_coordinator.dart';
import 'animation_service.dart';
import 'animation_timing_config.dart';
import 'rive_asset_key.dart';

/// The phase of the Chinese Poker animation controller.
enum ChinesePokerAnimPhase {
  /// No animation is active.
  idle,

  /// Cards are being dealt with stagger.
  dealing,

  /// A card is being placed from hand to a row.
  placing,

  /// A card is being removed from a row back to hand.
  removing,

  /// All cards are returning to hand simultaneously.
  resetting,

  /// Cards are auto-arranging to computed positions.
  autoArranging,

  /// Row-by-row showdown reveal is in progress.
  rowReveal,

  /// Scoring count-up animation is playing.
  scoring,

  /// Royalty sparkle effect is playing.
  royalty,

  /// Fantasyland golden aura is playing.
  fantasyland,

  /// Animation sequence has completed.
  completed,
}

/// Represents the current state of the Chinese Poker animation controller.
class ChinesePokerAnimState {
  const ChinesePokerAnimState({
    required this.phase,
    this.progress = 0.0,
    this.currentRow = -1,
    this.revealedRows = const [],
    this.isFouled = false,
    this.scoreValue = 0,
    this.winningRows = const [],
  });

  /// Current animation phase.
  final ChinesePokerAnimPhase phase;

  /// Animation progress from 0.0 (start) to 1.0 (complete).
  final double progress;

  /// The current row being revealed during showdown (-1 if none).
  /// 0 = back, 1 = middle, 2 = front.
  final int currentRow;

  /// List of row indices that have been revealed.
  final List<int> revealedRows;

  /// Whether the current arrangement is fouled.
  final bool isFouled;

  /// Current score value during count-up animation.
  final int scoreValue;

  /// Rows that won comparison (highlighted with green glow).
  final List<int> winningRows;

  /// Create a copy with updated fields.
  ChinesePokerAnimState copyWith({
    ChinesePokerAnimPhase? phase,
    double? progress,
    int? currentRow,
    List<int>? revealedRows,
    bool? isFouled,
    int? scoreValue,
    List<int>? winningRows,
  }) {
    return ChinesePokerAnimState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      currentRow: currentRow ?? this.currentRow,
      revealedRows: revealedRows ?? this.revealedRows,
      isFouled: isFouled ?? this.isFouled,
      scoreValue: scoreValue ?? this.scoreValue,
      winningRows: winningRows ?? this.winningRows,
    );
  }
}

/// Controller responsible for orchestrating all Chinese Poker specific
/// animations.
///
/// Handles:
/// - Card deal with 100ms stagger (Req 5.1)
/// - Card placement from hand to row, 250ms ease-out (Req 5.2)
/// - Card removal from row to hand, 200ms (Req 5.3)
/// - Reset all cards simultaneously, 300ms (Req 5.4)
/// - Auto-arrange with 50ms cascading stagger (Req 5.5)
/// - Row-by-row showdown reveal with 800ms pauses (Req 6.1–6.5)
/// - Scoring count-up, 500ms (Req 7.1)
/// - Chip transfer between players, 400ms (Req 7.3)
/// - Royalty sparkle effect via Rive (Req 7.2)
/// - Fantasyland golden aura via Rive (Req 7.4)
/// - Summary scoreboard overlay (Req 7.5)
/// - Haptic feedback on card placement (Req 16.5)
///
/// Extends [AnimationCoordinator] and uses the sentinel-based queue routing
/// pattern for sequencing animations through the base class queue.
class ChinesePokerAnimationController extends AnimationCoordinator {
  ChinesePokerAnimationController();

  /// Notifier for the current Chinese Poker animation state.
  /// UI widgets observe this to render animations at the correct timing.
  final ValueNotifier<ChinesePokerAnimState> state =
      ValueNotifier<ChinesePokerAnimState>(
        const ChinesePokerAnimState(phase: ChinesePokerAnimPhase.idle),
      );

  // ─── Sentinel values for queue routing ─────────────────────────────

  static const int _dealSentinel = -1001;
  static const int _placeSentinel = -1002;
  static const int _removeSentinel = -1003;
  static const int _resetSentinel = -1004;
  static const int _autoArrangeSentinel = -1005;
  static const int _rowRevealSentinel = -1006;
  static const int _scoringSentinel = -1007;
  static const int _chipTransferSentinel = -1008;
  static const int _royaltySentinel = -1009;
  static const int _fantasylandSentinel = -1010;

  /// Pending action and completer for sentinel-based routing.
  Future<void> Function()? _pendingAction;
  Completer<void>? _pendingCompleter;

  // ─── Public API ──────────────────────────────────────────────────────

  /// Animate dealing [cardCount] cards with 100ms stagger delay.
  ///
  /// Each card appears one by one with [AnimationTimingConfig.chineseCardStagger]
  /// (100ms) delay between them. Total duration: cardCount × 100ms.
  ///
  /// Validates: Requirement 5.1
  Future<void> animateDeal(int cardCount) {
    return _enqueueAction(_dealSentinel, () => _onAnimateDeal(cardCount));
  }

  /// Animate a card placement from hand to a row over 250ms with ease-out.
  ///
  /// Triggers light haptic feedback on placement (Req 16.5).
  ///
  /// Validates: Requirement 5.2, 16.5
  Future<void> animateCardPlace() {
    return _enqueueAction(_placeSentinel, () => _onAnimateCardPlace());
  }

  /// Animate a card removal from row back to hand over 200ms.
  ///
  /// Validates: Requirement 5.3
  Future<void> animateCardRemove() {
    return _enqueueAction(_removeSentinel, () => _onAnimateCardRemove());
  }

  /// Animate all placed cards returning to hand simultaneously over 300ms.
  ///
  /// Validates: Requirement 5.4
  Future<void> animateReset() {
    return _enqueueAction(_resetSentinel, () => _onAnimateReset());
  }

  /// Animate auto-arrange of [cardCount] cards with 50ms cascading stagger.
  ///
  /// Total duration: cardCount × 50ms.
  ///
  /// Validates: Requirement 5.5
  Future<void> animateAutoArrange(int cardCount) {
    return _enqueueAction(
      _autoArrangeSentinel,
      () => _onAnimateAutoArrange(cardCount),
    );
  }

  /// Animate row-by-row showdown reveal.
  ///
  /// Reveals [rows] (typically ['back', 'middle', 'front']) with 800ms pause
  /// between each row. Highlights [winningRows] with green glow. If [isFouled]
  /// is true, displays a red "FOUL" label with shake animation.
  ///
  /// Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5
  Future<void> animateRowReveal({
    required List<String> rows,
    List<int> winningRows = const [],
    bool isFouled = false,
  }) {
    return _enqueueAction(
      _rowRevealSentinel,
      () => _onAnimateRowReveal(rows, winningRows, isFouled),
    );
  }

  /// Animate scoring count-up from 0 to [points] over 500ms.
  ///
  /// Validates: Requirement 7.1
  Future<void> animateScoring(int points) {
    return _enqueueAction(_scoringSentinel, () => _onAnimateScoring(points));
  }

  /// Animate chip transfer between players over 400ms.
  ///
  /// Validates: Requirement 7.3
  Future<void> animateChipTransfer() {
    return _enqueueAction(
      _chipTransferSentinel,
      () => _onAnimateChipTransfer(),
    );
  }

  /// Animate royalty sparkle effect with the royalty [value] displayed.
  ///
  /// Loads `royalty_effect.riv` via AnimationService (fire-and-forget).
  ///
  /// Validates: Requirement 7.2
  Future<void> animateRoyalty(int value) {
    return _enqueueAction(_royaltySentinel, () => _onAnimateRoyalty(value));
  }

  /// Animate Fantasyland golden aura on qualifying player's avatar.
  ///
  /// Loads `fantasyland_aura.riv` via AnimationService (fire-and-forget).
  ///
  /// Validates: Requirement 7.4
  Future<void> animateFantasyland() {
    return _enqueueAction(_fantasylandSentinel, () => _onAnimateFantasyland());
  }

  // ─── AnimationCoordinator Override ───────────────────────────────────

  @override
  Future<void> onPlayChipAnimation(Offset from, Offset to, int amount) async {
    if (_pendingAction != null) {
      final action = _pendingAction!;
      final completer = _pendingCompleter!;
      _pendingAction = null;
      _pendingCompleter = null;
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
      return;
    }
  }

  // ─── Private: Queue Routing ──────────────────────────────────────────

  /// Enqueue an action through the coordinator's queue using sentinel routing.
  Future<void> _enqueueAction(int sentinel, Future<void> Function() action) {
    final completer = Completer<void>();
    _pendingAction = action;
    _pendingCompleter = completer;
    playChipAnimation(Offset.zero, Offset.zero, sentinel);
    return completer.future;
  }

  // ─── Private: Animation Implementations ──────────────────────────────

  /// Deal animation: cards appear one by one with 100ms stagger.
  Future<void> _onAnimateDeal(int cardCount) async {
    if (cardCount <= 0) {
      state.value = const ChinesePokerAnimState(
        phase: ChinesePokerAnimPhase.completed,
        progress: 1.0,
      );
      return;
    }

    state.value = const ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.dealing,
      progress: 0.0,
    );

    for (var i = 0; i < cardCount; i++) {
      if (skipRequested) {
        _resolveToCompleted();
        return;
      }

      final progress = (i + 1) / cardCount;
      state.value = ChinesePokerAnimState(
        phase: ChinesePokerAnimPhase.dealing,
        progress: progress,
      );

      if (i < cardCount - 1) {
        await _waitDuration(AnimationTimingConfig.chineseCardStagger);
        if (skipRequested) {
          _resolveToCompleted();
          return;
        }
      }
    }

    _resolveToCompleted();
  }

  /// Card placement animation: 250ms with ease-out curve.
  /// Triggers light haptic on placement (Req 16.5).
  Future<void> _onAnimateCardPlace() async {
    state.value = const ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.placing,
      progress: 0.0,
    );

    // Trigger light haptic feedback on card placement (Req 16.5).
    _triggerPlacementHaptic();

    if (skipRequested) {
      _resolveToCompleted();
      return;
    }

    await _animateWithEaseOut(AnimationTimingConfig.chineseCardPlace);

    _resolveToCompleted();
  }

  /// Card removal animation: 200ms linear.
  Future<void> _onAnimateCardRemove() async {
    state.value = const ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.removing,
      progress: 0.0,
    );

    if (skipRequested) {
      _resolveToCompleted();
      return;
    }

    await _animateLinear(AnimationTimingConfig.chineseCardReturn);

    _resolveToCompleted();
  }

  /// Reset animation: all cards return simultaneously over 300ms.
  Future<void> _onAnimateReset() async {
    state.value = const ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.resetting,
      progress: 0.0,
    );

    if (skipRequested) {
      _resolveToCompleted();
      return;
    }

    await _animateLinear(AnimationTimingConfig.chineseResetAll);

    _resolveToCompleted();
  }

  /// Auto-arrange animation: cascading 50ms stagger per card.
  Future<void> _onAnimateAutoArrange(int cardCount) async {
    if (cardCount <= 0) {
      state.value = const ChinesePokerAnimState(
        phase: ChinesePokerAnimPhase.completed,
        progress: 1.0,
      );
      return;
    }

    state.value = const ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.autoArranging,
      progress: 0.0,
    );

    for (var i = 0; i < cardCount; i++) {
      if (skipRequested) {
        _resolveToCompleted();
        return;
      }

      final progress = (i + 1) / cardCount;
      state.value = ChinesePokerAnimState(
        phase: ChinesePokerAnimPhase.autoArranging,
        progress: progress,
      );

      if (i < cardCount - 1) {
        await _waitDuration(AnimationTimingConfig.chineseAutoArrangeStagger);
        if (skipRequested) {
          _resolveToCompleted();
          return;
        }
      }
    }

    _resolveToCompleted();
  }

  /// Row-by-row showdown reveal with 800ms pauses between rows.
  Future<void> _onAnimateRowReveal(
    List<String> rows,
    List<int> winningRows,
    bool isFouled,
  ) async {
    if (rows.isEmpty) {
      state.value = const ChinesePokerAnimState(
        phase: ChinesePokerAnimPhase.completed,
        progress: 1.0,
      );
      return;
    }

    state.value = ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.rowReveal,
      progress: 0.0,
      currentRow: -1,
      revealedRows: const [],
      isFouled: isFouled,
      winningRows: winningRows,
    );

    final revealedRows = <int>[];

    for (var i = 0; i < rows.length; i++) {
      if (skipRequested) {
        _resolveRowRevealToFinal(rows, winningRows, isFouled);
        return;
      }

      final progress = (i + 1) / rows.length;

      // Reveal current row.
      state.value = ChinesePokerAnimState(
        phase: ChinesePokerAnimPhase.rowReveal,
        progress: progress,
        currentRow: i,
        revealedRows: List.unmodifiable(revealedRows),
        isFouled: isFouled,
        winningRows: winningRows,
      );

      // Play card flip sound for the row reveal.
      _playCardFlipSound();

      // Wait for the flip animation to complete (use a short duration).
      await _waitDuration(AnimationTimingConfig.showdownFlipDuration);

      if (skipRequested) {
        _resolveRowRevealToFinal(rows, winningRows, isFouled);
        return;
      }

      // Mark row as revealed.
      revealedRows.add(i);
      state.value = ChinesePokerAnimState(
        phase: ChinesePokerAnimPhase.rowReveal,
        progress: progress,
        currentRow: i,
        revealedRows: List.unmodifiable(revealedRows),
        isFouled: isFouled,
        winningRows: winningRows,
      );

      // Pause 800ms between rows (except after the last row).
      if (i < rows.length - 1) {
        await _waitDuration(AnimationTimingConfig.chineseRowPause);
        if (skipRequested) {
          _resolveRowRevealToFinal(rows, winningRows, isFouled);
          return;
        }
      }
    }

    _resolveRowRevealToFinal(rows, winningRows, isFouled);
  }

  /// Scoring count-up animation: counts from 0 to [points] over 500ms.
  Future<void> _onAnimateScoring(int points) async {
    if (points <= 0) {
      state.value = const ChinesePokerAnimState(
        phase: ChinesePokerAnimPhase.completed,
        progress: 1.0,
        scoreValue: 0,
      );
      return;
    }

    state.value = const ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.scoring,
      progress: 0.0,
      scoreValue: 0,
    );

    if (skipRequested) {
      _resolveScoringToFinal(points);
      return;
    }

    const steps = 10;
    final stepDuration = AnimationTimingConfig.scoreCountUp ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) {
        _resolveScoringToFinal(points);
        return;
      }

      final t = step / steps;
      final currentScore = (points * t).round();

      state.value = ChinesePokerAnimState(
        phase: ChinesePokerAnimPhase.scoring,
        progress: t,
        scoreValue: currentScore,
      );

      await Future.delayed(Duration(milliseconds: stepDuration));
    }

    _resolveScoringToFinal(points);
  }

  /// Chip transfer animation: 400ms flight between players.
  Future<void> _onAnimateChipTransfer() async {
    state.value = const ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.placing,
      progress: 0.0,
    );

    if (skipRequested) {
      _resolveToCompleted();
      return;
    }

    await _animateLinear(AnimationTimingConfig.chipTransferFlight);

    // Play chip sound on arrival.
    _playChipSound();

    _resolveToCompleted();
  }

  /// Royalty sparkle effect animation.
  /// Loads royalty_effect.riv via AnimationService (fire-and-forget).
  Future<void> _onAnimateRoyalty(int value) async {
    state.value = ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.royalty,
      progress: 0.0,
      scoreValue: value,
    );

    // Fire-and-forget: load the Rive artboard for royalty effect.
    _loadRiveAsset(RiveAssetKey.royaltyEffect);

    if (skipRequested) {
      _resolveToCompleted();
      return;
    }

    // Animate the sparkle effect duration (use confetti duration as reference).
    await _animateLinear(AnimationTimingConfig.winGlowPulse);

    state.value = ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.completed,
      progress: 1.0,
      scoreValue: value,
    );
  }

  /// Fantasyland golden aura animation.
  /// Loads fantasyland_aura.riv via AnimationService (fire-and-forget).
  Future<void> _onAnimateFantasyland() async {
    state.value = const ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.fantasyland,
      progress: 0.0,
    );

    // Fire-and-forget: load the Rive artboard for fantasyland aura.
    _loadRiveAsset(RiveAssetKey.fantasylandAura);

    if (skipRequested) {
      _resolveToCompleted();
      return;
    }

    // Animate the golden aura duration.
    await _animateLinear(AnimationTimingConfig.winGlowPulse);

    _resolveToCompleted();
  }

  // ─── Private: State Resolution ───────────────────────────────────────

  /// Resolve to the completed phase.
  void _resolveToCompleted() {
    state.value = const ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.completed,
      progress: 1.0,
    );
  }

  /// Resolve row reveal to final state with all rows revealed.
  void _resolveRowRevealToFinal(
    List<String> rows,
    List<int> winningRows,
    bool isFouled,
  ) {
    final allRows = List<int>.generate(rows.length, (i) => i);
    state.value = ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.completed,
      progress: 1.0,
      currentRow: rows.length - 1,
      revealedRows: List.unmodifiable(allRows),
      isFouled: isFouled,
      winningRows: winningRows,
    );
  }

  /// Resolve scoring to final state with full points.
  void _resolveScoringToFinal(int points) {
    state.value = ChinesePokerAnimState(
      phase: ChinesePokerAnimPhase.completed,
      progress: 1.0,
      scoreValue: points,
    );
  }

  // ─── Private: Animation Helpers ──────────────────────────────────────

  /// Wait for a given duration in milliseconds, checking skip between steps.
  Future<void> _waitDuration(int durationMs) async {
    const steps = 5;
    final stepDuration = durationMs ~/ steps;

    for (var step = 0; step < steps; step++) {
      if (skipRequested) return;
      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Animate linearly over [durationMs], updating progress from 0 to 1.
  Future<void> _animateLinear(int durationMs) async {
    const steps = 10;
    final stepDuration = durationMs ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final t = step / steps;
      state.value = state.value.copyWith(progress: t);

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Animate with ease-out curve over [durationMs], updating progress.
  /// Ease-out: 1 - (1-t)² — fast start, smooth deceleration.
  Future<void> _animateWithEaseOut(int durationMs) async {
    const steps = 10;
    final stepDuration = durationMs ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (skipRequested) return;

      final linearT = step / steps;
      // Ease-out curve.
      final t = 1.0 - (1.0 - linearT) * (1.0 - linearT);
      state.value = state.value.copyWith(progress: t);

      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  // ─── Private: Sound & Haptic Integration ─────────────────────────────

  /// Trigger light haptic feedback on card placement (Req 16.5).
  void _triggerPlacementHaptic() {
    try {
      HapticService.instance.lightImpact().catchError((_) {});
    } catch (_) {
      // Non-critical — continue without haptic.
    }
  }

  /// Play card flip sound effect during row reveal.
  void _playCardFlipSound() {
    try {
      AudioManager.instance.play(SoundEffect.cardFlip).catchError((_) {});
    } catch (_) {
      // Non-critical — continue without sound.
    }
  }

  /// Play chip sound effect on chip transfer arrival.
  void _playChipSound() {
    try {
      AudioManager.instance.play(SoundEffect.chipToss).catchError((_) {});
    } catch (_) {
      // Non-critical — continue without sound.
    }
  }

  /// Load a Rive asset via AnimationService (fire-and-forget).
  void _loadRiveAsset(RiveAssetKey key) {
    try {
      AnimationService.instance.getRiveArtboard(key).catchError((_) => null);
    } catch (_) {
      // Non-critical — continue without Rive animation.
    }
  }

  // ─── Dispose ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }
}
