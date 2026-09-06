import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Sound effect categories used throughout the app.
enum SoundEffect {
  chipToss,
  chipStack,
  sliderRatchet,
  cardFlip,
  cardDeal,
  cardCommunity,
  cardShuffle,
  coinCascade,
  allInPush,
  buttonTap,
  winCelebration,
  countdownTick,
  countdownUrgent,
}

/// Singleton service for loading and playing sound effects + background music.
///
/// Respects device mute state and persists user sound preference
/// via SharedPreferences.
class AudioManager {
  static final AudioManager instance = AudioManager._();
  AudioManager._();

  static const _prefKey = 'sound_enabled';
  static const _musicPrefKey = 'music_enabled';
  static const _sfxVolKey = 'sfx_volume';
  static const _bgmVolKey = 'bgm_volume';

  bool _soundEnabled = true;
  bool _musicEnabled = true;
  bool _preloaded = false;
  double _sfxVolume = 0.85; // 0.0 – 1.0
  double _bgmVolume = 0.35; // 0.0 – 1.0

  final Map<SoundEffect, AudioPlayer> _players = {};
  AudioPlayer? _bgmPlayer;
  bool _bgmPlaying = false;

  static const _assetPaths = <SoundEffect, String>{
    SoundEffect.chipToss: 'sounds/chip_toss.mp3',
    SoundEffect.chipStack: 'sounds/chip_stack.mp3',
    SoundEffect.sliderRatchet: 'sounds/slider_ratchet.mp3',
    SoundEffect.cardFlip: 'sounds/card_flip.mp3',
    SoundEffect.cardDeal: 'sounds/card_deal.mp3',
    SoundEffect.cardCommunity: 'sounds/card_community.mp3',
    SoundEffect.cardShuffle: 'sounds/card_shuffle.mp3',
    SoundEffect.coinCascade: 'sounds/coin_cascade.mp3',
    SoundEffect.allInPush: 'sounds/all_in_push.mp3',
    SoundEffect.buttonTap: 'sounds/button_tap.mp3',
    SoundEffect.winCelebration: 'sounds/win_celebration.mp3',
    SoundEffect.countdownTick: 'sounds/countdown_tick.mp3',
    SoundEffect.countdownUrgent: 'sounds/countdown_urgent.mp3',
  };

  static const _bgmAsset = 'sounds/bgm_music.mp3';

  // ── Getters ────────────────────────────────────────────────

  bool get isSoundEnabled => _soundEnabled;
  bool get isMusicEnabled => _musicEnabled;
  double get sfxVolume => _sfxVolume;
  double get bgmVolume => _bgmVolume;

  // ── Initialisation ─────────────────────────────────────────

  /// Pre-load all sound assets. Call during app initialization.
  Future<void> preload() async {
    if (_preloaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _soundEnabled = prefs.getBool(_prefKey) ?? true;
      _musicEnabled = prefs.getBool(_musicPrefKey) ?? true;
      _sfxVolume = prefs.getDouble(_sfxVolKey) ?? 0.85;
      _bgmVolume = prefs.getDouble(_bgmVolKey) ?? 0.35;

      for (final effect in SoundEffect.values) {
        final player = AudioPlayer();
        await player.setSource(AssetSource(_assetPaths[effect]!));
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setVolume(_sfxVolume);
        _players[effect] = player;
      }

      // Prepare BGM player
      _bgmPlayer = AudioPlayer();
      await _bgmPlayer!.setSource(AssetSource(_bgmAsset));
      await _bgmPlayer!.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer!.setVolume(_bgmVolume);

      _preloaded = true;
    } catch (_) {
      // Silently skip — audio is non-critical
    }
  }

  // ── Playback ───────────────────────────────────────────────

  /// Play a sound effect. Respects device mute and user setting.
  Future<void> play(SoundEffect effect) async {
    if (!_soundEnabled) return;
    try {
      final player = _players[effect];
      if (player != null) {
        await player.stop();
        await player.setVolume(_sfxVolume);
        await player.play(AssetSource(_assetPaths[effect]!));
      }
    } catch (_) {
      // Silently catch — continue without audio
    }
  }

  /// Start background music (looping).
  Future<void> startBgm() async {
    if (!_musicEnabled || _bgmPlaying) return;
    try {
      // On web, browsers block autoplay without user gesture.
      // We attempt to play — if it fails silently, the user can tap to trigger later.
      _bgmPlayer?.dispose();
      _bgmPlayer = AudioPlayer();
      _bgmPlaying = true;
      await _bgmPlayer!.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer!.setVolume(_bgmVolume);
      await _bgmPlayer!.play(AssetSource(_bgmAsset));
      debugPrint('🎵 [BGM] Started playing background music');
    } catch (e) {
      _bgmPlaying = false;
      debugPrint('🎵 [BGM] ERROR (autoplay may be blocked on web): $e');
    }
  }

  /// Pause background music (when app goes to background).
  Future<void> pauseBgm() async {
    if (!_bgmPlaying) return;
    try {
      await _bgmPlayer?.pause();
    } catch (_) {}
  }

  /// Resume background music (when app comes back to foreground).
  Future<void> resumeBgm() async {
    if (!_bgmPlaying || !_musicEnabled) return;
    try {
      await _bgmPlayer?.resume();
    } catch (_) {}
  }

  /// Stop background music.
  Future<void> stopBgm() async {
    _bgmPlaying = false;
    try {
      await _bgmPlayer?.stop();
    } catch (_) {}
  }

  /// Try starting BGM after a user gesture (needed for web/Safari autoplay policy).
  /// Call this from any first user tap/click on web.
  Future<void> retryBgmAfterGesture() async {
    if (_musicEnabled && !_bgmPlaying) {
      await startBgm();
    }
  }

  /// True once every [SoundEffect] player has been created by [preload]
  /// AND [unlockAllAudioContexts] has successfully run against all of
  /// them. While false, callers (the first-gesture listener in main.dart)
  /// should keep retrying on subsequent taps — preload() downloads 13
  /// audio files over the network and may still be in progress when the
  /// user's first tap happens, in which case [_players] would be empty
  /// (or partially populated) and nothing would get unlocked.
  bool get sfxContextsUnlocked => _sfxContextsUnlocked;
  bool _sfxContextsUnlocked = false;

  /// Unlock every SFX player's AudioContext during a user gesture.
  ///
  /// On web, each [SoundEffect] has its OWN separate AudioContext (created
  /// eagerly in [preload]). Unlocking BGM's context (via [startBgm]) does
  /// NOT unlock these — they stay permanently "suspended" because game
  /// sound effects are triggered by server/socket events, not by a direct
  /// tap/click, so the browser never sees a qualifying gesture for them.
  ///
  /// The fix is the standard Web Audio "warm-up" trick: briefly resume +
  /// immediately pause each player (muted, so nothing audible happens)
  /// while inside a real user gesture. Once a context transitions to
  /// "running" it stays running for the rest of the page's life.
  ///
  /// Runs all players CONCURRENTLY (not one-by-one with sequential awaits)
  /// so every resume() call is dispatched as close as possible to the
  /// original tap/click — some browsers only honor the "user gesture"
  /// requirement for calls made without a long async gap after the event.
  /// Returns true only if every effect was loaded AND unlocked; if
  /// [preload] hasn't finished yet, returns false so the caller retries
  /// on the next tap instead of giving up permanently.
  Future<bool> unlockAllAudioContexts() async {
    if (!kIsWeb)
      return true; // Only needed on web; native platforms don't gate audio.
    if (_players.isEmpty)
      return false; // preload() still in progress — retry next tap.

    final originalVolume = _sfxVolume;
    await Future.wait(
      _players.values.map((player) async {
        try {
          await player.setVolume(0);
          await player.resume();
          await player.pause();
        } catch (_) {
          // Some effects may fail individually — continue unlocking the rest.
        }
      }),
    );
    for (final player in _players.values) {
      try {
        await player.setVolume(originalVolume);
      } catch (_) {}
    }

    final allLoaded = _players.length == SoundEffect.values.length;
    if (allLoaded) _sfxContextsUnlocked = true;
    return allLoaded;
  }

  /// Fade out BGM over duration.
  Future<void> fadeOutBgm({
    Duration duration = const Duration(seconds: 2),
  }) async {
    if (!_bgmPlaying) return;
    try {
      const steps = 10;
      final stepDuration = duration ~/ steps;
      for (int i = steps; i >= 0; i--) {
        await _bgmPlayer?.setVolume(_bgmVolume * (i / steps));
        await Future.delayed(stepDuration);
      }
      await stopBgm();
    } catch (_) {
      await stopBgm();
    }
  }

  // ── Volume control ─────────────────────────────────────────

  /// Set SFX volume (0.0 – 1.0) and persist.
  Future<void> setSfxVolume(double v) async {
    _sfxVolume = v.clamp(0.0, 1.0);
    for (final p in _players.values) {
      try {
        await p.setVolume(_sfxVolume);
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_sfxVolKey, _sfxVolume);
    } catch (_) {}
  }

  /// Set BGM volume (0.0 – 1.0) and persist.
  Future<void> setBgmVolume(double v) async {
    _bgmVolume = v.clamp(0.0, 1.0);
    try {
      await _bgmPlayer?.setVolume(_bgmVolume);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_bgmVolKey, _bgmVolume);
    } catch (_) {}
  }

  // ── Preferences ────────────────────────────────────────────

  /// Persist user sound preference.
  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);
    } catch (_) {}
  }

  /// Persist user music preference.
  Future<void> setMusicEnabled(bool enabled) async {
    _musicEnabled = enabled;
    if (!enabled) {
      await stopBgm();
    } else if (!_bgmPlaying) {
      await startBgm();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_musicPrefKey, enabled);
    } catch (_) {}
  }

  // ── Cleanup ────────────────────────────────────────────────

  /// Dispose all audio players.
  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    _bgmPlayer?.dispose();
    _bgmPlayer = null;
    _bgmPlaying = false;
    _preloaded = false;
  }
}
