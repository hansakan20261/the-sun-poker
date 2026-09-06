import 'package:flutter/foundation.dart';

import 'animation_coordinator.dart';

/// A mixin that provides action-blocking behavior based on animation state.
///
/// Game screens can mix this in to check whether betting actions should be
/// blocked while an animation is playing. When [isAnimating] is true,
/// fold/call/raise/all-in actions are rejected and not forwarded to the server.
///
/// Usage:
/// ```dart
/// class _PokerTableScreenState extends State<PokerTableScreen>
///     with AnimationActionBlocker {
///   @override
///   AnimationCoordinator? get animationCoordinator => _coordinator;
/// }
/// ```
///
/// Requirements: 2.4 — WHILE the Deal_Animation is playing, THE Poker_Room
/// SHALL prevent user betting actions.
mixin AnimationActionBlocker {
  /// The animation coordinator to observe for blocking state.
  /// Return null if no coordinator is available (actions will not be blocked).
  AnimationCoordinator? get animationCoordinator;

  /// Whether betting actions are currently blocked due to an animation playing.
  ///
  /// Returns true when the [animationCoordinator] reports [isAnimating] is true.
  /// Returns false if no coordinator is set or animation has completed/been skipped.
  bool get areActionsBlocked {
    return animationCoordinator?.isAnimating ?? false;
  }

  /// Attempts to execute a betting action. Returns true if the action was
  /// allowed (not blocked), false if it was rejected due to animation.
  ///
  /// [action] is the action identifier (e.g., 'fold', 'call', 'raise', 'all_in').
  /// [execute] is the callback to run if the action is allowed.
  ///
  /// Blocked actions: fold, call, raise, all_in, check
  bool tryExecuteAction(String action, VoidCallback execute) {
    if (_isBettingAction(action) && areActionsBlocked) {
      return false;
    }
    execute();
    return true;
  }

  /// Whether the given action string represents a betting action that should
  /// be blocked during animations.
  bool _isBettingAction(String action) {
    return const {'fold', 'call', 'raise', 'all_in', 'check'}.contains(action);
  }
}
