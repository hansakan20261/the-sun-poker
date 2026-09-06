import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

/// Target for a card deal animation — specifies where a card should fly to.
class DealTarget {
  const DealTarget({
    required this.seatIndex,
    required this.position,
    this.cardId,
  });

  /// The seat number (0–8) receiving the card.
  final int seatIndex;

  /// The screen position where the card should land.
  final Offset position;

  /// Optional card identifier (e.g., "Ah" for Ace of hearts).
  final String? cardId;
}

/// Represents a player's hand during showdown reveal.
class ShowdownHand {
  const ShowdownHand({
    required this.seatIndex,
    required this.cards,
    this.isWinner = false,
  });

  /// The seat number (0–8) of the player.
  final int seatIndex;

  /// The cards to reveal (e.g., ["Ah", "Kh"]).
  final List<String> cards;

  /// Whether this hand is the winning hand.
  final bool isWinner;
}

/// A queued animation entry with its completer for resolution.
class _AnimationEntry {
  _AnimationEntry(this.action) : completer = Completer<void>();

  /// The async action to execute.
  final Future<void> Function() action;

  /// Completer that resolves when the animation finishes or is skipped.
  final Completer<void> completer;
}

/// Orchestrates animation sequences triggered by game state changes.
///
/// Coordinates timing between AnimationService, AudioManager, and HapticService.
/// Manages an animation queue with a max depth of 3 — if the queue exceeds 3,
/// intermediate animations are skipped to keep the UI responsive.
///
/// Provides [isAnimating] state tracking and [skipCurrentAnimation] for
/// user tap-to-skip functionality.
class AnimationCoordinator {
  AnimationCoordinator();

  /// Maximum number of animations allowed in the queue.
  /// If exceeded, intermediate states are skipped.
  static const int maxQueueDepth = 3;

  /// The animation queue.
  final Queue<_AnimationEntry> _queue = Queue<_AnimationEntry>();

  /// Whether an animation is currently playing.
  bool _isAnimating = false;

  /// Completer for the currently playing animation (used for skip).
  Completer<void>? _currentCompleter;

  /// Whether the current animation has been requested to skip.
  bool _skipRequested = false;

  /// Whether the coordinator has been disposed.
  bool _disposed = false;

  // ─── Public API ──────────────────────────────────────────────────────

  /// Whether an animation is currently playing.
  /// When true, user betting actions should be blocked.
  bool get isAnimating => _isAnimating;

  /// The current number of queued animations (excluding the active one).
  int get queueLength => _queue.length;

  /// Whether a skip has been requested for the current animation.
  bool get skipRequested => _skipRequested;

  /// Play the card deal sequence for poker.
  ///
  /// Animates cards flying from dealer to each [targets] seat in order.
  /// Override in subclasses to provide actual animation implementation.
  Future<void> playDealSequence(List<DealTarget> targets) {
    return _enqueue(() => onPlayDealSequence(targets));
  }

  /// Play chip movement from [from] to [to] with the given [amount].
  Future<void> playChipAnimation(Offset from, Offset to, int amount) {
    return _enqueue(() => onPlayChipAnimation(from, to, amount));
  }

  /// Play the showdown reveal sequence.
  Future<void> playShowdown(List<ShowdownHand> hands) {
    return _enqueue(() => onPlayShowdown(hands));
  }

  /// Play winner celebration (confetti + chip collection).
  Future<void> playCelebration(int winningSeat, int potAmount) {
    return _enqueue(() => onPlayCelebration(winningSeat, potAmount));
  }

  /// Skip the current animation sequence.
  ///
  /// Immediately resolves the pending animation future so the game can
  /// proceed to the next state. If there are queued animations, they will
  /// also be skipped if the queue exceeds max depth.
  void skipCurrentAnimation() {
    if (!_isAnimating) return;

    _skipRequested = true;

    // Resolve the current animation immediately.
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete();
    }
  }

  /// Dispose the coordinator and cancel all pending animations.
  void dispose() {
    _disposed = true;
    _skipRequested = true;

    // Complete the current animation if running.
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete();
    }

    // Complete all queued animations without executing them.
    while (_queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      if (!entry.completer.isCompleted) {
        entry.completer.complete();
      }
    }

    _isAnimating = false;
  }

  // ─── Protected Methods (override in subclasses) ──────────────────────

  /// Override to implement the actual deal animation.
  /// Check [skipRequested] periodically to allow early termination.
  @protected
  Future<void> onPlayDealSequence(List<DealTarget> targets) async {}

  /// Override to implement the actual chip animation.
  @protected
  Future<void> onPlayChipAnimation(Offset from, Offset to, int amount) async {}

  /// Override to implement the actual showdown animation.
  @protected
  Future<void> onPlayShowdown(List<ShowdownHand> hands) async {}

  /// Override to implement the actual celebration animation.
  @protected
  Future<void> onPlayCelebration(int winningSeat, int potAmount) async {}

  // ─── Private Queue Management ────────────────────────────────────────

  /// Enqueue an animation action. If the queue exceeds [maxQueueDepth],
  /// skip intermediate animations to keep the UI responsive.
  Future<void> _enqueue(Future<void> Function() action) {
    if (_disposed) return Future.value();

    final entry = _AnimationEntry(action);

    // If queue is at max depth, skip intermediate entries to catch up.
    if (_queue.length >= maxQueueDepth) {
      _skipIntermediateAnimations();
    }

    _queue.addLast(entry);

    // If not currently processing, start the queue.
    if (!_isAnimating) {
      _processQueue();
    }

    return entry.completer.future;
  }

  /// Process animations from the queue sequentially.
  Future<void> _processQueue() async {
    if (_isAnimating || _disposed) return;

    _isAnimating = true;

    while (_queue.isNotEmpty && !_disposed) {
      final entry = _queue.removeFirst();
      _skipRequested = false;
      _currentCompleter = Completer<void>();

      try {
        // Race between the animation action and the skip completer.
        await Future.any([_runAnimation(entry), _currentCompleter!.future]);
      } catch (e) {
        developer.log('Animation error: $e', name: 'AnimationCoordinator');
      } finally {
        // Ensure the entry's completer is resolved.
        if (!entry.completer.isCompleted) {
          entry.completer.complete();
        }
      }
    }

    _isAnimating = false;
    _currentCompleter = null;
    _skipRequested = false;
  }

  /// Run a single animation entry.
  Future<void> _runAnimation(_AnimationEntry entry) async {
    try {
      await entry.action();
    } finally {
      if (!entry.completer.isCompleted) {
        entry.completer.complete();
      }
      if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
        _currentCompleter!.complete();
      }
    }
  }

  /// Skip intermediate animations when queue exceeds max depth.
  /// Keeps the first (currently processing) and last (most recent) entries,
  /// completing all intermediate entries immediately.
  void _skipIntermediateAnimations() {
    // Complete all queued entries except the last one (most recent state).
    while (_queue.length >= maxQueueDepth) {
      final entry = _queue.removeFirst();
      if (!entry.completer.isCompleted) {
        entry.completer.complete();
      }
      developer.log(
        'Skipped intermediate animation (queue overflow)',
        name: 'AnimationCoordinator',
      );
    }
  }
}
