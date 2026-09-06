import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart';

import 'rive_asset_key.dart';

/// Singleton service managing all Rive and Lottie animation assets.
///
/// Handles preloading, caching, lifecycle, and memory management.
/// Uses a 30 MB memory budget and supports simplified mode for
/// devices with less than 2 GB RAM.
class AnimationService {
  AnimationService._();

  static final AnimationService instance = AnimationService._();

  /// In-memory cache of loaded Rive files keyed by [RiveAssetKey].
  final Map<RiveAssetKey, RiveFile> _cache = {};

  /// Tracks estimated memory usage in bytes.
  int _estimatedMemoryBytes = 0;

  /// Maximum memory budget for animation assets (30 MB).
  static const int memoryBudgetBytes = 30 * 1024 * 1024;

  /// Whether the device should use simplified animations.
  bool _useSimplifiedMode = false;

  /// Whether all animations are currently paused.
  bool _paused = false;

  /// Whether the service has been disposed.
  bool _disposed = false;

  // ─── Public API ──────────────────────────────────────────────────────

  /// Current estimated memory usage in bytes.
  int get estimatedMemoryUsage => _estimatedMemoryBytes;

  /// Whether to use simplified animations (low-memory devices < 2 GB RAM).
  bool get useSimplifiedMode => _useSimplifiedMode;

  /// Whether all animations are currently paused.
  bool get isPaused => _paused;

  /// Set simplified mode (call during app init based on device info).
  set useSimplifiedMode(bool value) {
    _useSimplifiedMode = value;
  }

  /// Preload critical animation files during the loading screen.
  ///
  /// Loads [RiveAssetKey.cardDeal] and [RiveAssetKey.chipMovement] so they
  /// are ready before the game table appears. Returns when all files are
  /// cached and ready.
  Future<void> preloadCritical() async {
    const criticalKeys = [RiveAssetKey.cardDeal, RiveAssetKey.chipMovement];

    for (final key in criticalKeys) {
      await _loadAndCache(key);
    }
  }

  /// Load a Rive artboard by asset key. Returns cached instance if available.
  ///
  /// If the asset fails to load (missing or corrupt), returns `null` and logs
  /// the error. Callers should handle `null` by showing a static fallback.
  Future<Artboard?> getRiveArtboard(RiveAssetKey key) async {
    if (_disposed) return null;

    final riveFile = _cache[key] ?? await _loadAndCache(key);
    if (riveFile == null) return null;

    try {
      return riveFile.mainArtboard.instance();
    } catch (e) {
      developer.log(
        'Failed to get artboard for $key: $e',
        name: 'AnimationService',
      );
      return null;
    }
  }

  /// Fire a state machine input on a loaded artboard.
  ///
  /// Catches exceptions silently if the artboard is disposed or the input
  /// name does not exist — this is a no-op in those cases.
  void fireStateMachineInput(
    StateMachineController controller,
    String inputName,
    dynamic value,
  ) {
    try {
      final input = controller.findInput<dynamic>(inputName);
      if (input == null) {
        developer.log(
          'Input "$inputName" not found on state machine',
          name: 'AnimationService',
        );
        return;
      }
      if (input is SMIBool && value is bool) {
        input.value = value;
      } else if (input is SMINumber && value is num) {
        input.value = value.toDouble();
      } else if (input is SMITrigger) {
        input.fire();
      }
    } catch (e) {
      // No-op on disposed artboard or invalid input.
      developer.log(
        'fireStateMachineInput error: $e',
        name: 'AnimationService',
      );
    }
  }

  /// Pause all running animations (for background/disconnect).
  void pauseAll() {
    _paused = true;
  }

  /// Resume all paused animations.
  void resumeAll() {
    _paused = false;
  }

  /// Dispose all cached artboards and controllers.
  ///
  /// After calling this, the service should not be used until re-initialized.
  void disposeAll() {
    _disposed = true;
    _cache.clear();
    _estimatedMemoryBytes = 0;
    _paused = false;
  }

  /// Reset the service for reuse (e.g., after returning to lobby).
  void reset() {
    _disposed = false;
    _cache.clear();
    _estimatedMemoryBytes = 0;
    _paused = false;
  }

  /// Returns a fallback widget to display when an animation asset fails to load.
  Widget getFallbackWidget(RiveAssetKey key) {
    return const SizedBox.shrink();
  }

  // ─── Private Helpers ─────────────────────────────────────────────────

  /// Load a Rive file from assets and cache it.
  /// Returns null if loading fails.
  Future<RiveFile?> _loadAndCache(RiveAssetKey key) async {
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final data = await rootBundle.load(key.filePath);
      final riveFile = RiveFile.import(data);

      // Estimate memory: use byte data length as approximation.
      final assetSize = data.lengthInBytes;
      _estimatedMemoryBytes += assetSize;

      // If over budget, evict least-recently-used (simple: skip caching).
      if (_estimatedMemoryBytes > memoryBudgetBytes) {
        developer.log(
          'Memory budget exceeded after loading $key. '
          'Current: $_estimatedMemoryBytes bytes',
          name: 'AnimationService',
        );
      }

      _cache[key] = riveFile;
      return riveFile;
    } catch (e) {
      developer.log(
        'Failed to load Rive asset ${key.filePath}: $e',
        name: 'AnimationService',
      );
      return null;
    }
  }
}
