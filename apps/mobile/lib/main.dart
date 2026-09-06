import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'services/audio_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to portrait by default — game screens will override to landscape
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Use bundled Prompt font — disable runtime fetching for consistent layout
  GoogleFonts.config.allowRuntimeFetching = false;
  // Show overflow errors in debug mode for layout debugging
  // FlutterError.onError = FlutterError.presentError; (default behavior)
  runApp(const TheSunPokerApp());
}

class TheSunPokerApp extends StatefulWidget {
  const TheSunPokerApp({super.key});

  @override
  State<TheSunPokerApp> createState() => _TheSunPokerAppState();
}

class _TheSunPokerAppState extends State<TheSunPokerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Task 16.1: Preload audio assets during app initialization
    _initAudio();
  }

  Future<void> _initAudio() async {
    await AudioManager.instance.preload();
    // Start BGM after preload completes
    AudioManager.instance.startBgm();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause BGM when app goes to background, resume when foreground
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      AudioManager.instance.pauseBgm();
    } else if (state == AppLifecycleState.resumed) {
      AudioManager.instance.resumeBgm();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THE SUN POKER',
      theme: SunTheme.theme,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
      // Web browsers (Chrome/Safari) block audio autoplay until the user
      // interacts with the page. The splash screen auto-navigates with no
      // tap required, so BGM started from main()/splash never actually
      // played on web. This wraps the ENTIRE app in a listener that
      // catches the very first tap/click anywhere and retries starting
      // the BGM — after that first unlock, the browser allows audio
      // normally so this has no effect on native iOS/Android (audio
      // already plays there without a gesture).
      builder: (context, child) => _FirstGestureAudioUnlocker(child: child),
    );
  }
}

/// Listens for the first pointer-down anywhere in the app and uses it as
/// the "user gesture" required by browser autoplay policies to unlock
/// audio playback. Removes itself after the first successful trigger.
class _FirstGestureAudioUnlocker extends StatefulWidget {
  final Widget? child;
  const _FirstGestureAudioUnlocker({required this.child});

  @override
  State<_FirstGestureAudioUnlocker> createState() =>
      _FirstGestureAudioUnlockerState();
}

class _FirstGestureAudioUnlockerState
    extends State<_FirstGestureAudioUnlocker> {
  bool _fullyUnlocked = false;

  Future<void> _onGesture() async {
    if (_fullyUnlocked) return;
    AudioManager.instance.retryBgmAfterGesture();
    // Also unlock every SFX player's AudioContext (chip toss, card deal,
    // win celebration, etc.) — these are triggered later by game/socket
    // events, not by a tap, so without this warm-up they'd stay silent
    // for the whole session even after BGM starts playing.
    //
    // preload() downloads 13 sound files over the network and may still
    // be running when the FIRST tap happens (very likely — the splash
    // screen navigates away almost immediately), in which case there'd
    // be nothing to unlock yet. So we keep listening on EVERY tap/click
    // until unlockAllAudioContexts() confirms all effects were loaded
    // AND unlocked, instead of giving up after a single attempt.
    final done = await AudioManager.instance.unlockAllAudioContexts();
    if (done && mounted) setState(() => _fullyUnlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_fullyUnlocked) return widget.child ?? const SizedBox();
    return Listener(
      onPointerDown: (_) => _onGesture(),
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
