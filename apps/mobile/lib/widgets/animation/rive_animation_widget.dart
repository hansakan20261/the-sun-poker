import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import '../../services/animation/animation_service.dart';
import '../../services/animation/rive_asset_key.dart';

/// A reusable widget that loads and displays a Rive animation from
/// [AnimationService], exposing state machine inputs for triggering
/// transitions (deal, flip, etc.).
///
/// Shows a fallback placeholder if the asset fails to load.
/// Handles disposed artboard gracefully — firing inputs on a disposed
/// controller is a no-op and will not crash.
///
/// Usage:
/// ```dart
/// RiveAnimationWidget(
///   assetKey: RiveAssetKey.cardDeal,
///   stateMachineName: 'State Machine 1',
///   fit: BoxFit.contain,
///   onControllerReady: (controller) {
///     // Store controller reference to fire inputs later
///   },
/// )
/// ```
class RiveAnimationWidget extends StatefulWidget {
  const RiveAnimationWidget({
    super.key,
    required this.assetKey,
    this.stateMachineName = 'State Machine 1',
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.onControllerReady,
    this.fallbackBuilder,
    this.placeholderBuilder,
  });

  /// The Rive asset to load (maps to a `.riv` file via [RiveAssetKey]).
  final RiveAssetKey assetKey;

  /// The name of the state machine to attach. Defaults to 'State Machine 1'.
  final String stateMachineName;

  /// How the Rive animation should be inscribed into the available space.
  final BoxFit fit;

  /// Alignment of the Rive animation within its bounds.
  final Alignment alignment;

  /// Optional fixed width for the widget.
  final double? width;

  /// Optional fixed height for the widget.
  final double? height;

  /// Called when the [StateMachineController] is ready.
  ///
  /// Use this to obtain a reference to the controller for firing
  /// state machine inputs (triggers, booleans, numbers) externally.
  final ValueChanged<RiveAnimationController>? onControllerReady;

  /// Builder for the fallback widget shown when the asset fails to load.
  /// If null, a default empty [SizedBox.shrink] is used.
  final WidgetBuilder? fallbackBuilder;

  /// Builder for the placeholder widget shown while the asset is loading.
  /// If null, a default empty [SizedBox.shrink] is used.
  final WidgetBuilder? placeholderBuilder;

  @override
  State<RiveAnimationWidget> createState() => RiveAnimationWidgetState();
}

/// State for [RiveAnimationWidget].
///
/// Exposes [fireInput] for triggering state machine inputs externally.
/// All input-firing methods are safe to call even after the widget is
/// disposed — they become no-ops.
class RiveAnimationWidgetState extends State<RiveAnimationWidget> {
  Artboard? _artboard;
  StateMachineController? _stateMachineController;
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _disposed = false;

  /// The active [StateMachineController], or null if not yet loaded or failed.
  StateMachineController? get stateMachineController => _stateMachineController;

  @override
  void initState() {
    super.initState();
    _loadArtboard();
  }

  @override
  void didUpdateWidget(RiveAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetKey != widget.assetKey ||
        oldWidget.stateMachineName != widget.stateMachineName) {
      _disposeController();
      _loadArtboard();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeController();
    super.dispose();
  }

  // ─── Public API ──────────────────────────────────────────────────────

  /// Fire a trigger input on the state machine by [inputName].
  ///
  /// Safe to call after dispose — becomes a no-op.
  void fireTrigger(String inputName) {
    if (_disposed || _stateMachineController == null) return;
    AnimationService.instance.fireStateMachineInput(
      _stateMachineController!,
      inputName,
      null, // triggers don't need a value; fireStateMachineInput handles SMITrigger
    );
  }

  /// Set a boolean input on the state machine.
  ///
  /// Safe to call after dispose — becomes a no-op.
  void setBoolInput(String inputName, bool value) {
    if (_disposed || _stateMachineController == null) return;
    AnimationService.instance.fireStateMachineInput(
      _stateMachineController!,
      inputName,
      value,
    );
  }

  /// Set a number input on the state machine.
  ///
  /// Safe to call after dispose — becomes a no-op.
  void setNumberInput(String inputName, double value) {
    if (_disposed || _stateMachineController == null) return;
    AnimationService.instance.fireStateMachineInput(
      _stateMachineController!,
      inputName,
      value,
    );
  }

  /// Fire a named input with a dynamic value.
  ///
  /// Delegates to [AnimationService.fireStateMachineInput] which handles
  /// type detection (trigger, bool, number). Safe to call after dispose.
  void fireInput(String inputName, [dynamic value]) {
    if (_disposed || _stateMachineController == null) return;
    AnimationService.instance.fireStateMachineInput(
      _stateMachineController!,
      inputName,
      value,
    );
  }

  // ─── Private ─────────────────────────────────────────────────────────

  Future<void> _loadArtboard() async {
    if (_disposed) return;

    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      final artboard = await AnimationService.instance.getRiveArtboard(
        widget.assetKey,
      );

      if (_disposed) return;

      if (artboard == null) {
        developer.log(
          'Failed to load artboard for ${widget.assetKey}',
          name: 'RiveAnimationWidget',
        );
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
        return;
      }

      // Attach state machine controller.
      final controller = StateMachineController.fromArtboard(
        artboard,
        widget.stateMachineName,
      );

      if (controller == null) {
        developer.log(
          'State machine "${widget.stateMachineName}" not found on '
          '${widget.assetKey}. Rendering artboard without state machine.',
          name: 'RiveAnimationWidget',
        );
      } else {
        artboard.addController(controller);
        _stateMachineController = controller;

        // Notify caller that the controller is ready.
        if (widget.onControllerReady != null) {
          widget.onControllerReady!(controller);
        }
      }

      if (_disposed) {
        // Widget was disposed while loading — clean up immediately.
        controller?.dispose();
        return;
      }

      setState(() {
        _artboard = artboard;
        _isLoading = false;
        _loadFailed = false;
      });
    } catch (e) {
      developer.log(
        'Error loading Rive artboard for ${widget.assetKey}: $e',
        name: 'RiveAnimationWidget',
      );
      if (!_disposed && mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  void _disposeController() {
    _stateMachineController?.dispose();
    _stateMachineController = null;
    _artboard = null;
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_isLoading) {
      child =
          widget.placeholderBuilder?.call(context) ?? const SizedBox.shrink();
    } else if (_loadFailed || _artboard == null) {
      child =
          widget.fallbackBuilder?.call(context) ??
          AnimationService.instance.getFallbackWidget(widget.assetKey);
    } else {
      child = Rive(
        artboard: _artboard!,
        fit: widget.fit,
        alignment: widget.alignment,
      );
    }

    if (widget.width != null || widget.height != null) {
      return SizedBox(width: widget.width, height: widget.height, child: child);
    }

    return child;
  }
}
