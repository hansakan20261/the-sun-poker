import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'daily_bonus_screen.dart';

class WelcomeScreen extends StatefulWidget {
  final String username;
  final int coinBalance;
  final bool showDailyBonus;
  final Widget? nextScreen;
  const WelcomeScreen({
    super.key,
    required this.username,
    required this.coinBalance,
    this.showDailyBonus = false,
    this.nextScreen,
  });
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeIn;
  late Animation<double> _fadeOut;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    // Fade in during first 20%, stay visible, fade out last 15%
    _fadeIn = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeCtrl,
        curve: const Interval(0.0, 0.2, curve: Curves.easeIn),
      ),
    );
    _fadeOut = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _fadeCtrl,
        curve: const Interval(0.85, 1.0, curve: Curves.easeOut),
      ),
    );

    _fadeCtrl.forward();
    _fadeCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _goNext();
      }
    });
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;

    Widget destination;
    if (widget.nextScreen != null) {
      // Not logged in → go to login
      destination = widget.nextScreen!;
    } else if (widget.showDailyBonus) {
      // Logged in → always show daily bonus first
      destination = const DailyBonusScreen(isPopup: false);
    } else {
      destination = const HomeScreen();
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, a, __, c) =>
            FadeTransition(opacity: a, child: c),
      ),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _goNext,
        child: AnimatedBuilder(
          animation: _fadeCtrl,
          builder: (context, child) {
            final opacity = (_fadeIn.value * _fadeOut.value).clamp(0.0, 1.0);
            return Opacity(opacity: opacity, child: child);
          },
          child: SizedBox.expand(
            child: Image.asset(
              'assets/welcome_bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF1A0505),
                child: const Center(
                  child: Icon(Icons.casino, color: Color(0xFFFFD700), size: 80),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
