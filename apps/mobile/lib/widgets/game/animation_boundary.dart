import 'package:flutter/material.dart';

/// A utility widget that wraps children with [RepaintBoundary] to isolate
/// animated regions from static UI, preventing unnecessary repaints.
///
/// Use this to wrap:
/// - Card animations
/// - Chip animations
/// - Ambient Lottie effects
/// - Any frequently-updating animated region
///
/// Requirements: 12.6
class AnimationBoundary extends StatelessWidget {
  /// The child widget to isolate with a RepaintBoundary.
  final Widget child;

  const AnimationBoundary({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: child);
  }
}

/// Wraps multiple animated regions each with their own RepaintBoundary.
///
/// Useful for isolating card animations, chip animations, and ambient effects
/// from the static table UI in a single layout.
class AnimationBoundaryStack extends StatelessWidget {
  /// List of animated widgets, each wrapped in its own RepaintBoundary.
  final List<Widget> children;

  const AnimationBoundaryStack({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: children.map((child) => RepaintBoundary(child: child)).toList(),
    );
  }
}
