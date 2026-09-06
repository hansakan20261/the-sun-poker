/// Feature flags controlling the animation backend for each phase.
///
/// Allows incremental migration from old Flutter AnimationController-based
/// animations to the new Rive animation engine. Each phase can be toggled
/// independently, enabling per-phase rollout and rollback.
///
/// The [useRiveAnimations] master toggle overrides all per-phase flags —
/// when false, all phases fall back to the old animation backend regardless
/// of individual flag values.
class AnimationFeatureFlags {
  AnimationFeatureFlags({
    this.useRiveAnimations = true,
    this.useDealAnimation = true,
    this.useChipAnimation = true,
    this.useCelebrationAnimation = true,
    this.useCountdownAnimation = true,
    this.useResponsiveLayout = true,
  });

  /// Master toggle: when false, all Rive animations are disabled and the
  /// old AnimationController-based animations are used for every phase.
  bool useRiveAnimations;

  /// Whether to use the new Rive-based card deal animation.
  /// Falls back to old deal animation when false or when [useRiveAnimations]
  /// is false.
  bool useDealAnimation;

  /// Whether to use the new Rive-based chip movement animations.
  /// Falls back to old chip animation when false or when [useRiveAnimations]
  /// is false.
  bool useChipAnimation;

  /// Whether to use the new Rive-based celebration effects (confetti,
  /// showdown, win highlight).
  /// Falls back to old celebration effects when false or when
  /// [useRiveAnimations] is false.
  bool useCelebrationAnimation;

  /// Whether to use the new Rive-based countdown ring animation.
  /// Falls back to old countdown indicator when false or when
  /// [useRiveAnimations] is false.
  bool useCountdownAnimation;

  /// Whether to use the new responsive layout engine with percentage-based
  /// positioning.
  /// Falls back to old fixed-pixel CardSizeConfig when false or when
  /// [useRiveAnimations] is false.
  bool useResponsiveLayout;

  // ─── Resolved Getters ────────────────────────────────────────────────

  /// Whether the deal phase should use the new Rive animation.
  /// Respects the master toggle.
  bool get isDealAnimationEnabled => useRiveAnimations && useDealAnimation;

  /// Whether the chip phase should use the new Rive animation.
  /// Respects the master toggle.
  bool get isChipAnimationEnabled => useRiveAnimations && useChipAnimation;

  /// Whether the celebration phase should use the new Rive animation.
  /// Respects the master toggle.
  bool get isCelebrationAnimationEnabled =>
      useRiveAnimations && useCelebrationAnimation;

  /// Whether the countdown phase should use the new Rive animation.
  /// Respects the master toggle.
  bool get isCountdownAnimationEnabled =>
      useRiveAnimations && useCountdownAnimation;

  /// Whether the responsive layout engine should be used.
  /// Respects the master toggle.
  bool get isResponsiveLayoutEnabled =>
      useRiveAnimations && useResponsiveLayout;

  // ─── Convenience ─────────────────────────────────────────────────────

  /// Disable all Rive animations (revert to old backend for all phases).
  void disableAll() {
    useRiveAnimations = false;
  }

  /// Enable all Rive animations (use new backend for all phases).
  void enableAll() {
    useRiveAnimations = true;
    useDealAnimation = true;
    useChipAnimation = true;
    useCelebrationAnimation = true;
    useCountdownAnimation = true;
    useResponsiveLayout = true;
  }

  /// Create a copy with specific overrides.
  AnimationFeatureFlags copyWith({
    bool? useRiveAnimations,
    bool? useDealAnimation,
    bool? useChipAnimation,
    bool? useCelebrationAnimation,
    bool? useCountdownAnimation,
    bool? useResponsiveLayout,
  }) {
    return AnimationFeatureFlags(
      useRiveAnimations: useRiveAnimations ?? this.useRiveAnimations,
      useDealAnimation: useDealAnimation ?? this.useDealAnimation,
      useChipAnimation: useChipAnimation ?? this.useChipAnimation,
      useCelebrationAnimation:
          useCelebrationAnimation ?? this.useCelebrationAnimation,
      useCountdownAnimation:
          useCountdownAnimation ?? this.useCountdownAnimation,
      useResponsiveLayout: useResponsiveLayout ?? this.useResponsiveLayout,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AnimationFeatureFlags &&
        other.useRiveAnimations == useRiveAnimations &&
        other.useDealAnimation == useDealAnimation &&
        other.useChipAnimation == useChipAnimation &&
        other.useCelebrationAnimation == useCelebrationAnimation &&
        other.useCountdownAnimation == useCountdownAnimation &&
        other.useResponsiveLayout == useResponsiveLayout;
  }

  @override
  int get hashCode => Object.hash(
    useRiveAnimations,
    useDealAnimation,
    useChipAnimation,
    useCelebrationAnimation,
    useCountdownAnimation,
    useResponsiveLayout,
  );

  @override
  String toString() {
    return 'AnimationFeatureFlags('
        'master: $useRiveAnimations, '
        'deal: $useDealAnimation, '
        'chip: $useChipAnimation, '
        'celebration: $useCelebrationAnimation, '
        'countdown: $useCountdownAnimation, '
        'layout: $useResponsiveLayout)';
  }
}
