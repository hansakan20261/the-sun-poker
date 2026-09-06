import 'package:flutter/material.dart';

/// The type of poker action to display.
enum PokerActionType { call, raise, allIn, check, fold, blind }

/// A widget that displays a poker action label (CALL, RAISE, ALL IN, etc.)
/// with a pop-scale animation on appearance and a fade-out after a brief
/// display period.
///
/// The pop animation scales from 0 → 1.2 → 1.0 using a two-phase tween
/// sequence, then holds for [displayDuration] before fading out over
/// [fadeOutDuration].
///
/// This widget is positioned near the player's seat and is reusable across
/// all action types.
///
/// Requirements: 3.4
class ActionLabelPopWidget extends StatefulWidget {
  const ActionLabelPopWidget({
    super.key,
    required this.actionType,
    this.displayDuration = const Duration(milliseconds: 1500),
    this.fadeOutDuration = const Duration(milliseconds: 400),
    this.popDuration = const Duration(milliseconds: 350),
    this.onComplete,
  });

  /// The poker action type to display.
  final PokerActionType actionType;

  /// How long the label stays visible at full opacity after the pop animation.
  final Duration displayDuration;

  /// Duration of the fade-out animation after the display period.
  final Duration fadeOutDuration;

  /// Duration of the pop-scale animation (0 → 1.2 → 1.0).
  final Duration popDuration;

  /// Callback invoked when the full animation sequence completes
  /// (pop + display + fade-out).
  final VoidCallback? onComplete;

  /// Convert a string action name to [PokerActionType].
  /// Returns null if the action string is not recognized.
  static PokerActionType? actionTypeFromString(String? action) {
    switch (action) {
      case 'call':
        return PokerActionType.call;
      case 'raise':
        return PokerActionType.raise;
      case 'all_in':
        return PokerActionType.allIn;
      case 'check':
        return PokerActionType.check;
      case 'fold':
        return PokerActionType.fold;
      case 'blind':
        return PokerActionType.blind;
      default:
        return null;
    }
  }

  /// Get the display label for the given action type.
  static String getActionLabel(PokerActionType actionType) {
    switch (actionType) {
      case PokerActionType.call:
        return 'CALL';
      case PokerActionType.raise:
        return 'RAISE';
      case PokerActionType.allIn:
        return 'ALL IN';
      case PokerActionType.check:
        return 'CHECK';
      case PokerActionType.fold:
        return 'FOLD';
      case PokerActionType.blind:
        return 'BLIND';
    }
  }

  /// Get the background color for the given action type.
  static Color getActionColor(PokerActionType actionType) {
    switch (actionType) {
      case PokerActionType.call:
        return Colors.blue.shade700;
      case PokerActionType.raise:
        return Colors.orange.shade800;
      case PokerActionType.allIn:
        return Colors.purple.shade700;
      case PokerActionType.check:
        return Colors.green.shade700;
      case PokerActionType.fold:
        return Colors.red.shade800;
      case PokerActionType.blind:
        return Colors.grey.shade700;
    }
  }

  @override
  State<ActionLabelPopWidget> createState() => _ActionLabelPopWidgetState();
}

class _ActionLabelPopWidgetState extends State<ActionLabelPopWidget>
    with TickerProviderStateMixin {
  late AnimationController _popController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Pop-scale animation: 0 → 1.2 → 1.0 with overshoot.
    _popController = AnimationController(
      vsync: this,
      duration: widget.popDuration,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.2,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.2,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_popController);

    // Fade-out animation: 1.0 → 0.0.
    _fadeController = AnimationController(
      vsync: this,
      duration: widget.fadeOutDuration,
    );

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));

    _startAnimationSequence();
  }

  Future<void> _startAnimationSequence() async {
    // 1. Play pop-scale animation.
    await _popController.forward();

    // 2. Hold at full scale for the display duration.
    await Future.delayed(widget.displayDuration);

    // 3. Fade out.
    if (!mounted) return;
    await _fadeController.forward();

    // 4. Notify completion.
    if (mounted) {
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _popController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_popController, _fadeController]),
      builder: (context, child) {
        return Opacity(
          key: const ValueKey('action_label_opacity'),
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            key: const ValueKey('action_label_scale'),
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: _buildLabel(),
    );
  }

  Widget _buildLabel() {
    final label = ActionLabelPopWidget.getActionLabel(widget.actionType);
    final color = ActionLabelPopWidget.getActionColor(widget.actionType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.6),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
