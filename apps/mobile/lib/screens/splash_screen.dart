import 'dart:async';
import 'package:flutter/material.dart';
import '../services/animation/animation_service.dart';
import '../services/api_service.dart';
import '../services/audio_manager.dart';
import '../services/app_control_service.dart';
import '../services/feature_flags_service.dart';
import '../models/practice_session.dart';
import 'daily_bonus_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Light sweep animation across logo text (1500ms)
  late final AnimationController _sweepController;
  late final Animation<double> _sweepAnimation;

  // Progress bar animation
  late final AnimationController _progressController;

  // Auth result tracking
  bool _authComplete = false;
  bool _configComplete = false;
  String? _blockMessage;
  bool _minTimeElapsed = false;
  bool? _loggedIn;
  bool _hasUnclaimedBonus = false;
  bool _navigated = false;
  String _username = '';
  int _coinBalance = 0;

  @override
  void initState() {
    super.initState();

    // Light sweep: repeats across logo text, 1500ms per cycle
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _sweepAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _sweepController, curve: Curves.easeInOut),
    );

    // Progress bar: fills over ~2000ms
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    _startMinTimer();
    _checkAuth();
    _loadConfiguration();
    _preloadAnimations();
  }

  /// Preload critical animation assets in the background.
  Future<void> _preloadAnimations() async {
    try {
      await AnimationService.instance.preloadCritical();
    } catch (_) {
      // Non-critical: game can still function without preloaded animations.
    }
  }

  void _startMinTimer() {
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      setState(() => _minTimeElapsed = true);
      _tryNavigate();
    });
  }

  Future<void> _loadConfiguration() async {
    final results = await Future.wait([
      AppControlService.load(),
      FeatureFlagsService.load(),
    ]);
    if (!mounted) return;
    final control = results[0] as AppControlResult;
    setState(() {
      _blockMessage = control.blocked ? control.message : null;
      _configComplete = true;
    });
    _tryNavigate();
  }

  Future<void> _checkAuth() async {
    try {
      final loggedIn = await ApiService.loadSavedToken();
      if (!mounted) return;

      bool hasBonus = false;
      if (loggedIn) {
        try {
          final bonusData = await ApiService.getDailyBonusStatus();
          hasBonus = bonusData['canClaim'] ?? bonusData['can_claim'] ?? false;
        } catch (_) {
          hasBonus = false;
        }
        // Fetch user info for welcome popup
        try {
          final balData = await ApiService.getBalance();
          _coinBalance = (balData['balance'] as num?)?.toInt() ?? 0;
          _username = balData['username'] as String? ?? '';
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _loggedIn = loggedIn;
        _hasUnclaimedBonus = hasBonus;
        _authComplete = true;
      });
      _tryNavigate();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loggedIn = false;
        _authComplete = true;
      });
      _tryNavigate();
    }
  }

  void _tryNavigate() {
    if (_navigated ||
        !_authComplete ||
        !_configComplete ||
        _blockMessage != null ||
        !_minTimeElapsed ||
        !mounted)
      return;
    _navigated = true;

    // Ensure progress bar is full before navigating
    if (!_progressController.isCompleted) {
      _progressController.forward().then((_) => _performNavigation());
    } else {
      _performNavigation();
    }
  }

  void _performNavigation() {
    if (!mounted) return;

    if (_loggedIn == true) {
      // Always show welcome animation → then daily bonus → then home
      _navigateTo(
        WelcomeScreen(
          username: _username,
          coinBalance: _coinBalance,
          showDailyBonus: true, // always show daily bonus
          nextScreen: null, // go to home after daily bonus
        ),
      );
    } else {
      // Not logged in: show welcome animation → then login
      _navigateTo(
        WelcomeScreen(
          username: '',
          coinBalance: 0,
          showDailyBonus: false,
          nextScreen: const LoginScreen(),
        ),
      );
    }
  }

  void _navigateTo(Widget destination) {
    if (!mounted) return;
    // Start BGM when leaving splash (ensures audio context is ready)
    AudioManager.instance.startBgm();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5C0000),
      body: Column(
        children: [
          // Centered logo area
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo image
                  Image.asset(
                    'assets/logo.png',
                    width: 220,
                    height: 220,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.casino,
                      color: Color(0xFFFFD700),
                      size: 80,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Logo text with light sweep animation
                  AnimatedBuilder(
                    animation: _sweepAnimation,
                    builder: (context, child) {
                      return ShaderMask(
                        shaderCallback: (bounds) {
                          final sweepPos = _sweepAnimation.value;
                          return LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: const [
                              Color(0xFFFFD700),
                              Colors.white,
                              Color(0xFFFFD700),
                            ],
                            stops: [
                              (sweepPos - 0.3).clamp(0.0, 1.0),
                              sweepPos.clamp(0.0, 1.0),
                              (sweepPos + 0.3).clamp(0.0, 1.0),
                            ],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.srcIn,
                        child: child,
                      );
                    },
                    child: const Text(
                      'THE SUN POKER',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Progress bar + status label at bottom
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress bar
                AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, _) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progressController.value,
                        backgroundColor: Colors.white.withOpacity(0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFFD700),
                        ),
                        minHeight: 4,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Status label
                Text(
                  _blockMessage ?? 'Checking for updates...',
                  style: TextStyle(
                    color: const Color(0xFFDAA520).withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
