import 'package:flutter/services.dart';

/// Thin wrapper around Flutter's [HapticFeedback] for game-specific patterns.
///
/// Provides named methods for common game interactions so that haptic
/// feedback is consistent across the app and easy to disable globally.
class HapticService {
  HapticService._();

  static final HapticService instance = HapticService._();

  /// Whether haptic feedback is enabled. Can be toggled from settings.
  bool enabled = true;

  /// Light tap feedback (card arrival, card placement in Chinese Poker).
  Future<void> lightImpact() async {
    if (!enabled) return;
    await HapticFeedback.lightImpact();
  }

  /// Medium impact (betting action buttons: fold, call, raise, all-in).
  Future<void> mediumImpact() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
  }

  /// Success pattern: three short pulses (win celebration).
  Future<void> successPattern() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }

  /// Tick feedback (countdown timer seconds).
  Future<void> tick() async {
    if (!enabled) return;
    await HapticFeedback.selectionClick();
  }
}
