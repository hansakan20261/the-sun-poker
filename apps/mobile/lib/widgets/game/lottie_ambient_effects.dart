import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../services/animation/animation_service.dart';

/// A widget that loads and plays Lottie ambient effects for the game table.
///
/// - Loads ambient_particles.json for background floating particles
/// - Loads card_shimmer.json for subtle card highlights
/// - Loads table_glow.json for table edge ambient glow
/// - Skips ambient effects on low-memory devices or when frame drops detected
///
/// Requirements: 21.2, 21.4, 12.1, 12.5
class LottieAmbientEffects extends StatelessWidget {
  /// Whether to show ambient effects. Set to false to disable.
  final bool enabled;

  const LottieAmbientEffects({super.key, this.enabled = true});

  /// Whether ambient effects should be skipped based on device capabilities.
  static bool shouldSkipEffects() {
    return AnimationService.instance.useSimplifiedMode;
  }

  @override
  Widget build(BuildContext context) {
    // Skip on low-memory devices or when simplified mode is active
    if (!enabled || shouldSkipEffects()) {
      return const SizedBox.shrink();
    }

    return const Stack(
      children: [
        // Background floating particles
        Positioned.fill(
          child: _LottieEffect(asset: 'assets/lottie/ambient_particles.json'),
        ),
        // Table edge ambient glow
        Positioned.fill(
          child: _LottieEffect(asset: 'assets/lottie/table_glow.json'),
        ),
      ],
    );
  }
}

/// A widget that shows card shimmer effect on a specific card.
///
/// Requirements: 21.2
class CardShimmerEffect extends StatelessWidget {
  final double width;
  final double height;
  final bool enabled;

  const CardShimmerEffect({
    super.key,
    this.width = 48,
    this.height = 66,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || LottieAmbientEffects.shouldSkipEffects()) {
      return SizedBox(width: width, height: height);
    }

    return SizedBox(
      width: width,
      height: height,
      child: const _LottieEffect(asset: 'assets/lottie/card_shimmer.json'),
    );
  }
}

/// Internal widget that loads and plays a single Lottie animation.
///
/// Handles loading errors gracefully by showing nothing on failure.
class _LottieEffect extends StatelessWidget {
  final String asset;

  const _LottieEffect({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      asset,
      fit: BoxFit.cover,
      repeat: true,
      animate: !AnimationService.instance.isPaused,
      errorBuilder: (context, error, stackTrace) {
        // Skip decorative animation on failure — no user-visible error
        return const SizedBox.shrink();
      },
    );
  }
}
