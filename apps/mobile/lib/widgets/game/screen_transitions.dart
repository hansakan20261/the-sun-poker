import 'package:flutter/material.dart';

import '../../services/animation/animation_timing_config.dart';

/// Utility class providing screen transition animations for game room navigation.
///
/// - Slide-in from right (300ms) when entering game room
/// - Slide-out to right (300ms) when leaving to lobby
/// - Fade-in table and seats (400ms) after loading completes
///
/// Requirements: 20.1, 20.2, 20.4
class ScreenTransitions {
  ScreenTransitions._();

  /// Duration for slide transitions (entering/leaving game room).
  static const Duration slideDuration = Duration(
    milliseconds: AnimationTimingConfig.screenTransition,
  );

  /// Duration for fade-in after loading completes.
  static const Duration fadeInDuration = Duration(
    milliseconds: AnimationTimingConfig.tableFadeIn,
  );

  /// Creates a slide-in from right route transition for entering the game room.
  static Route<T> slideInFromRight<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: slideDuration,
      reverseTransitionDuration: slideDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final offsetAnimation =
            Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );

        return SlideTransition(position: offsetAnimation, child: child);
      },
    );
  }

  /// Creates a slide-out to right route transition for leaving to lobby.
  static Route<T> slideOutToRight<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: slideDuration,
      reverseTransitionDuration: slideDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final offsetAnimation =
            Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(1.0, 0.0),
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeInCubic),
            );

        return SlideTransition(position: offsetAnimation, child: child);
      },
    );
  }

  /// A widget that fades in its child over 400ms after loading completes.
  ///
  /// Use this to wrap the table and seats after the loading screen dismisses.
  static Widget fadeIn({required Widget child, required bool show}) {
    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: fadeInDuration,
      curve: Curves.easeIn,
      child: child,
    );
  }
}

/// A widget that wraps content with a fade-in animation triggered by [show].
///
/// Useful for fading in the table and player seats after loading completes.
class FadeInWidget extends StatelessWidget {
  final bool show;
  final Widget child;

  const FadeInWidget({super.key, required this.show, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: ScreenTransitions.fadeInDuration,
      curve: Curves.easeIn,
      child: child,
    );
  }
}
