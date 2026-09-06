import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import '../../services/animation/chip_animation_controller.dart';
import '../../services/animation/rive_asset_key.dart';
import 'rive_animation_widget.dart';

/// State machine trigger input names for the chip_movement.riv artboard.
///
/// These correspond to the state machine inputs defined in the Rive file
/// that control chip animation transitions.
class ChipRiveInputs {
  ChipRiveInputs._();

  /// Trigger input to start the bet animation (chips fly to pot).
  static const String bet = 'bet';

  /// Trigger input to start the win animation (chips fly to winner).
  static const String win = 'win';

  /// Trigger input to start the transfer animation (chips between players).
  static const String transfer = 'transfer';

  /// Number input for the chip sprite count (2 for small, 5 for large).
  static const String spriteCount = 'spriteCount';

  /// Number input for animation progress (0.0 to 1.0).
  static const String progress = 'progress';

  /// Boolean input indicating whether the glow effect is active (all-in).
  static const String glowActive = 'glowActive';
}

/// A widget that integrates chip animations with the Rive animation engine.
///
/// Wraps [RiveAnimationWidget] specifically for chip movement animations,
/// loading the `chip_movement.riv` artboard via [RiveAssetKey.chipMovement].
///
/// Connects to a [ChipAnimationController] to observe state changes and
/// fire the appropriate Rive state machine inputs (bet, win, transfer triggers).
///
/// Handles the case where the Rive artboard isn't loaded yet by showing a
/// graceful fallback (empty SizedBox) and queuing trigger requests until ready.
///
/// Requirements: 21.1
class ChipRiveWidget extends StatefulWidget {
  const ChipRiveWidget({
    super.key,
    required this.controller,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.stateMachineName = 'State Machine 1',
    this.fallbackBuilder,
  });

  /// The [ChipAnimationController] whose state changes drive the Rive
  /// state machine inputs.
  final ChipAnimationController controller;

  /// Optional fixed width for the widget.
  final double? width;

  /// Optional fixed height for the widget.
  final double? height;

  /// How the Rive animation should be inscribed into the available space.
  final BoxFit fit;

  /// Alignment of the Rive animation within its bounds.
  final Alignment alignment;

  /// The name of the state machine in the chip_movement.riv file.
  final String stateMachineName;

  /// Builder for the fallback widget shown when the asset fails to load.
  /// If null, a default empty [SizedBox.shrink] is used.
  final WidgetBuilder? fallbackBuilder;

  @override
  State<ChipRiveWidget> createState() => ChipRiveWidgetState();
}

/// State for [ChipRiveWidget].
///
/// Listens to the [ChipAnimationController]'s value notifiers and fires
/// the corresponding Rive state machine inputs when animation phases change.
///
/// Exposes public methods [triggerBet], [triggerWin], and [triggerTransfer]
/// for manual triggering if needed.
class ChipRiveWidgetState extends State<ChipRiveWidget> {
  /// Key for accessing the inner [RiveAnimationWidgetState].
  final GlobalKey<RiveAnimationWidgetState> _riveKey =
      GlobalKey<RiveAnimationWidgetState>();

  /// Whether the Rive artboard has been loaded and the state machine is ready.
  bool _isReady = false;

  /// Queue of pending triggers to fire once the artboard is ready.
  final List<String> _pendingTriggers = [];

  @override
  void initState() {
    super.initState();
    _attachListeners();
  }

  @override
  void didUpdateWidget(ChipRiveWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachListeners(oldWidget.controller);
      _attachListeners();
    }
  }

  @override
  void dispose() {
    _detachListeners(widget.controller);
    super.dispose();
  }

  // ─── Public API ──────────────────────────────────────────────────────

  /// Manually trigger the bet animation on the Rive state machine.
  ///
  /// If the artboard isn't ready yet, the trigger is queued and will fire
  /// once the state machine is available.
  void triggerBet() {
    _fireTriggerOrQueue(ChipRiveInputs.bet);
  }

  /// Manually trigger the win animation on the Rive state machine.
  ///
  /// If the artboard isn't ready yet, the trigger is queued and will fire
  /// once the state machine is available.
  void triggerWin() {
    _fireTriggerOrQueue(ChipRiveInputs.win);
  }

  /// Manually trigger the transfer animation on the Rive state machine.
  ///
  /// If the artboard isn't ready yet, the trigger is queued and will fire
  /// once the state machine is available.
  void triggerTransfer() {
    _fireTriggerOrQueue(ChipRiveInputs.transfer);
  }

  /// Whether the Rive state machine is loaded and ready to receive inputs.
  bool get isReady => _isReady;

  // ─── Private: Listener Management ────────────────────────────────────

  void _attachListeners() {
    widget.controller.chipState.addListener(_onChipStateChanged);
    widget.controller.allInState.addListener(_onAllInStateChanged);
    widget.controller.winChipState.addListener(_onWinChipStateChanged);
  }

  void _detachListeners(ChipAnimationController controller) {
    controller.chipState.removeListener(_onChipStateChanged);
    controller.allInState.removeListener(_onAllInStateChanged);
    controller.winChipState.removeListener(_onWinChipStateChanged);
  }

  // ─── Private: State Change Handlers ──────────────────────────────────

  /// Called when the chip bet animation state changes.
  ///
  /// Fires the 'bet' trigger when the phase transitions to [ChipAnimationPhase.flying],
  /// and updates the sprite count and progress number inputs.
  void _onChipStateChanged() {
    final state = widget.controller.chipState.value;
    if (state == null) return;

    switch (state.phase) {
      case ChipAnimationPhase.flying:
        _fireTriggerOrQueue(ChipRiveInputs.bet);
        _setNumberInput(
          ChipRiveInputs.spriteCount,
          state.spriteCount.toDouble(),
        );
        _setNumberInput(ChipRiveInputs.progress, state.progress);
        break;
      case ChipAnimationPhase.arrived:
        _setNumberInput(ChipRiveInputs.progress, 1.0);
        break;
      case ChipAnimationPhase.waiting:
        // No action needed — waiting for animation to start.
        break;
    }
  }

  /// Called when the all-in push animation state changes.
  ///
  /// Fires the 'bet' trigger on push start (all-in is a dramatic bet),
  /// and activates the glow boolean input during the glow phase.
  void _onAllInStateChanged() {
    final state = widget.controller.allInState.value;
    if (state == null) return;

    switch (state.phase) {
      case AllInAnimationPhase.pushing:
        _fireTriggerOrQueue(ChipRiveInputs.bet);
        _setNumberInput(
          ChipRiveInputs.spriteCount,
          ChipAnimationController.largeBetSpriteCount.toDouble(),
        );
        _setNumberInput(ChipRiveInputs.progress, state.progress);
        break;
      case AllInAnimationPhase.glowing:
        _setBoolInput(ChipRiveInputs.glowActive, true);
        break;
      case AllInAnimationPhase.completed:
        _setBoolInput(ChipRiveInputs.glowActive, false);
        _setNumberInput(ChipRiveInputs.progress, 1.0);
        break;
      case AllInAnimationPhase.idle:
        // No action needed.
        break;
    }
  }

  /// Called when the win chip animation state changes.
  ///
  /// Fires the 'win' trigger when the phase transitions to
  /// [WinChipAnimationPhase.flying], and updates progress.
  void _onWinChipStateChanged() {
    final state = widget.controller.winChipState.value;
    if (state == null) return;

    switch (state.phase) {
      case WinChipAnimationPhase.flying:
        _fireTriggerOrQueue(ChipRiveInputs.win);
        _setNumberInput(
          ChipRiveInputs.spriteCount,
          state.spriteCount.toDouble(),
        );
        _setNumberInput(ChipRiveInputs.progress, state.progress);
        break;
      case WinChipAnimationPhase.arrived:
        _setNumberInput(ChipRiveInputs.progress, 1.0);
        break;
      case WinChipAnimationPhase.idle:
        // No action needed.
        break;
    }
  }

  // ─── Private: Rive Input Helpers ─────────────────────────────────────

  /// Fire a trigger input, or queue it if the artboard isn't ready yet.
  void _fireTriggerOrQueue(String inputName) {
    if (_isReady) {
      _riveKey.currentState?.fireTrigger(inputName);
    } else {
      _pendingTriggers.add(inputName);
      developer.log(
        'Queued trigger "$inputName" — Rive artboard not ready yet',
        name: 'ChipRiveWidget',
      );
    }
  }

  /// Set a boolean input on the Rive state machine.
  /// No-op if the artboard isn't ready.
  void _setBoolInput(String inputName, bool value) {
    if (!_isReady) return;
    _riveKey.currentState?.setBoolInput(inputName, value);
  }

  /// Set a number input on the Rive state machine.
  /// No-op if the artboard isn't ready.
  void _setNumberInput(String inputName, double value) {
    if (!_isReady) return;
    _riveKey.currentState?.setNumberInput(inputName, value);
  }

  /// Called when the [RiveAnimationWidget] controller is ready.
  /// Flushes any pending triggers that were queued before the artboard loaded.
  void _onControllerReady(RiveAnimationController controller) {
    _isReady = true;

    // Flush pending triggers.
    if (_pendingTriggers.isNotEmpty) {
      developer.log(
        'Flushing ${_pendingTriggers.length} pending triggers',
        name: 'ChipRiveWidget',
      );
      for (final trigger in _pendingTriggers) {
        _riveKey.currentState?.fireTrigger(trigger);
      }
      _pendingTriggers.clear();
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RiveAnimationWidget(
      key: _riveKey,
      assetKey: RiveAssetKey.chipMovement,
      stateMachineName: widget.stateMachineName,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      onControllerReady: _onControllerReady,
      fallbackBuilder: widget.fallbackBuilder,
      placeholderBuilder: (_) => const SizedBox.shrink(),
    );
  }
}
