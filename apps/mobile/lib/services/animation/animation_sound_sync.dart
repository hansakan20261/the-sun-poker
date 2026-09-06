import '../audio_manager.dart';
import '../haptic_service.dart';

/// Centralizes sound effect synchronization callbacks for animation events.
///
/// Each animation controller triggers sounds at specific moments:
/// - **Card deal**: card-slide sound at the start of each card flight (Req 15.1)
/// - **Chip bet**: chip-clink sound when chips reach the pot center (Req 15.2)
/// - **Win**: coin-cascade sound when chips reach the winner (Req 15.3)
/// - **All-in**: dramatic push sound at the start of the all-in animation (Req 15.4)
/// - **Countdown**: urgent tick sound on each second when ≤ 5 seconds remain (Req 15.5)
///
/// The mute toggle for sound effects is independent from background music
/// (Req 15.6). This is handled by [AudioManager.setSoundEnabled] which
/// controls sound effects without affecting [AudioManager.setMusicEnabled].
///
/// This class provides factory methods for creating the callback functions
/// that animation controllers use to trigger synchronized audio playback.
/// It does NOT modify [AudioManager] or [GameSocket] — it simply provides
/// the callback wiring between animation events and the existing audio system.
class AnimationSoundSync {
  AnimationSoundSync._();

  static final AnimationSoundSync instance = AnimationSoundSync._();

  // ─── Sound Trigger Callbacks ─────────────────────────────────────────

  /// Trigger the card-slide sound effect.
  /// Called at the start of each card flight during the deal sequence.
  /// Requirement: 15.1
  void playCardSlide() {
    _playSound(SoundEffect.cardDeal);
  }

  /// Trigger the chip-clink sound effect.
  /// Called when chips arrive at the pot center during a bet animation.
  /// Requirement: 15.2
  void playChipClink() {
    _playSound(SoundEffect.chipToss);
  }

  /// Trigger the coin-cascade sound effect.
  /// Called when chips reach the winner during the win animation.
  /// Requirement: 15.3
  void playCoinCascade() {
    _playSound(SoundEffect.coinCascade);
  }

  /// Trigger the dramatic all-in push sound effect.
  /// Called at the start of the all-in animation.
  /// Requirement: 15.4
  void playAllInPush() {
    _playSound(SoundEffect.allInPush);
  }

  /// Trigger the countdown tick sound effect.
  /// Called on each second when the countdown timer has ≤ 5 seconds remaining.
  /// Requirement: 15.5
  void playCountdownTick(int secondsRemaining) {
    if (secondsRemaining <= 5) {
      _playSound(SoundEffect.countdownTick);
    }
    if (secondsRemaining <= 3) {
      _playSound(SoundEffect.countdownUrgent);
    }
  }

  /// Trigger the community card flip sound effect.
  /// Called when flop/turn/river cards are revealed.
  /// Requirement: 14.4
  void playCommunityCardFlip() {
    _playSound(SoundEffect.cardCommunity);
  }

  /// Trigger the win celebration sound effect.
  /// Called during the confetti celebration.
  void playWinCelebration() {
    _playSound(SoundEffect.winCelebration);
  }

  // ─── Haptic Trigger Callbacks ────────────────────────────────────────

  /// Trigger light haptic on card arrival at player seat.
  /// Requirement: 16.2
  void hapticCardArrival() {
    _triggerHaptic(() => HapticService.instance.lightImpact());
  }

  /// Trigger medium haptic on betting action button press.
  /// Requirement: 16.1
  void hapticBettingAction() {
    _triggerHaptic(() => HapticService.instance.mediumImpact());
  }

  /// Trigger success haptic pattern on win.
  /// Requirement: 16.3
  void hapticWinCelebration() {
    _triggerHaptic(() => HapticService.instance.successPattern());
  }

  /// Trigger tick haptic on countdown (≤ 3 seconds).
  /// Requirement: 16.4
  void hapticCountdownTick(int secondsRemaining) {
    if (secondsRemaining <= 3) {
      _triggerHaptic(() => HapticService.instance.tick());
    }
  }

  /// Trigger light haptic on card placement in Chinese Poker.
  /// Requirement: 16.5
  void hapticCardPlacement() {
    _triggerHaptic(() => HapticService.instance.lightImpact());
  }

  // ─── Mute Control ────────────────────────────────────────────────────

  /// Whether sound effects are currently enabled.
  /// Independent from background music (Req 15.6).
  bool get isSoundEnabled => AudioManager.instance.isSoundEnabled;

  /// Whether background music is currently enabled.
  /// Independent from sound effects (Req 15.6).
  bool get isMusicEnabled => AudioManager.instance.isMusicEnabled;

  /// Toggle sound effects on/off independently from background music.
  /// Requirement: 15.6
  Future<void> setSoundEnabled(bool enabled) async {
    await AudioManager.instance.setSoundEnabled(enabled);
  }

  /// Toggle background music on/off independently from sound effects.
  /// Requirement: 15.6
  Future<void> setMusicEnabled(bool enabled) async {
    await AudioManager.instance.setMusicEnabled(enabled);
  }

  // ─── Private Helpers ─────────────────────────────────────────────────

  /// Play a sound effect. Fire-and-forget — never blocks the animation loop.
  /// Respects the sound enabled setting via AudioManager.
  void _playSound(SoundEffect effect) {
    try {
      AudioManager.instance.play(effect).catchError((_) {});
    } catch (_) {
      // Non-critical — continue without sound.
    }
  }

  /// Trigger a haptic feedback action. Fire-and-forget.
  void _triggerHaptic(Future<void> Function() action) {
    try {
      action().catchError((_) {});
    } catch (_) {
      // Non-critical — continue without haptic.
    }
  }
}
