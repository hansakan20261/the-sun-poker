import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';
import 'poker_chip_icon.dart';

class WelcomePopup extends StatefulWidget {
  final String username;
  final int coinBalance;
  final String dailyTip;
  final VoidCallback onEnterGame;

  const WelcomePopup({
    super.key,
    required this.username,
    required this.coinBalance,
    required this.dailyTip,
    required this.onEnterGame,
  });

  @override
  State<WelcomePopup> createState() => _WelcomePopupState();
}

class _WelcomePopupState extends State<WelcomePopup>
    with TickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late AnimationController _shimmerCtrl;
  late AnimationController _coinCtrl;
  late AnimationController _particleCtrl;
  late AnimationController _charCtrl;
  late AnimationController _autoTimerCtrl;

  late Animation<double> _cardScale, _cardFade;
  late Animation<double> _coinCount;
  late Animation<double> _charSlide, _charFade;
  late Animation<double> _logoScale;

  final _rng = Random();
  late List<_Spark> _sparks;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();

    // Card entry: scale + fade
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _cardScale = Tween(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.elasticOut));
    _cardFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.0, 0.3)),
    );
    _logoScale = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.2, 0.7, curve: Curves.elasticOut),
      ),
    );

    // Gold shimmer
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    // Coin count-up
    _coinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _coinCount = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _coinCtrl, curve: Curves.easeOutCubic));

    // Character slide-in from right
    _charCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _charSlide = Tween(
      begin: 1.5,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _charCtrl, curve: Curves.easeOutBack));
    _charFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _charCtrl, curve: const Interval(0.0, 0.5)),
    );

    // Sparks
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
    _sparks = List.generate(
      25,
      (_) => _Spark(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        speed: 0.2 + _rng.nextDouble() * 0.6,
        size: 3 + _rng.nextDouble() * 7,
        delay: _rng.nextDouble(),
      ),
    );

    // Auto-dismiss timer (4 seconds)
    _autoTimerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    // Sequence
    _entryCtrl.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _coinCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _charCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _autoTimerCtrl.forward();
    });

    _autoTimerCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && !_dismissed) _dismiss();
    });
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onEnterGame();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _shimmerCtrl.dispose();
    _coinCtrl.dispose();
    _particleCtrl.dispose();
    _charCtrl.dispose();
    _autoTimerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.username.isNotEmpty ? widget.username : '';
    return Material(
      color: Colors.transparent,
      child: _Anim(
        animation: Listenable.merge([
          _entryCtrl,
          _particleCtrl,
          _charCtrl,
          _coinCtrl,
          _autoTimerCtrl,
        ]),
        builder: (_, __) => GestureDetector(
          onTap: _dismiss, // tap anywhere to skip
          child: Stack(
            children: [
              // Overlay
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.75 * _cardFade.value),
                ),
              ),
              // Sparks
              ..._buildSparks(),
              // Character WIN (bottom-right)
              Positioned(
                right: -20,
                bottom: MediaQuery.of(context).size.height * 0.18,
                child: Transform.translate(
                  offset: Offset(100 * _charSlide.value, 0),
                  child: Opacity(
                    opacity: _charFade.value.clamp(0.0, 1.0),
                    child: Image.asset(
                      'assets/character_win.png',
                      height: 200,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                ),
              ),
              // Main card
              Center(
                child: Transform.scale(
                  scale: _cardScale.value,
                  child: Opacity(
                    opacity: _cardFade.value.clamp(0.0, 1.0),
                    child: _card(name),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(String name) {
    final bal = widget.coinBalance;
    final displayBal = (bal * _coinCount.value).round();
    final w = MediaQuery.of(context).size.width;

    return Container(
      width: w * 0.88,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: SunTheme.cardDecoration(
        radius: 24,
        bgColor: const Color(0xFF1A0606),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo
          Transform.scale(
            scale: _logoScale.value,
            child: Image.asset(
              'assets/welcome_logo.png',
              height: 80,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.casino, color: Color(0xFFFFD700), size: 60),
            ),
          ),
          const SizedBox(height: 12),
          // Shimmer welcome text
          _Anim(
            animation: _shimmerCtrl,
            builder: (_, __) => ShaderMask(
              shaderCallback: (bounds) {
                final dx = _shimmerCtrl.value * bounds.width * 3 - bounds.width;
                return LinearGradient(
                  colors: const [
                    Color(0xFFB8860B),
                    Color(0xFFFFD700),
                    Color(0xFFFFE082),
                    Color(0xFFFFD700),
                    Color(0xFFB8860B),
                  ],
                  stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                ).createShader(
                  Rect.fromLTWH(dx, 0, bounds.width, bounds.height),
                );
              },
              child: Text(
                'ยินดีต้อนรับ${name.isNotEmpty ? ', $name!' : '!'}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 10)],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Coin balance with count-up
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFDAA520).withOpacity(0.25),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFFFFD700,
                  ).withOpacity(0.05 + 0.1 * _coinCount.value),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PokerChipIcon(amount: 10000, size: 28),
                const SizedBox(width: 10),
                Text(
                  'C${NumberFormatter.formatWithCommas(displayBal)}',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (widget.dailyTip.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.dailyTip,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SunTheme.goldLight.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Progress bar (auto-timer)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 4,
              width: double.infinity,
              child: LinearProgressIndicator(
                value: _autoTimerCtrl.value,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF3CB371)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Enter button
          GestureDetector(
            onTap: _dismiss,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF3CB371),
                    Color(0xFF2E8B57),
                    Color(0xFF155C30),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E8B57).withOpacity(0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'เข้าสู่เกม',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSparks() {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    return _sparks.map((s) {
      final t = ((_particleCtrl.value + s.delay) % 1.0);
      final op = t < 0.1 ? t * 10 : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
      final y = h * (1.0 - t * s.speed);
      return Positioned(
        left: w * s.x + sin(t * 6.28) * 15,
        top: y,
        child: Opacity(
          opacity: (op * _cardFade.value).clamp(0.0, 1.0),
          child: Container(
            width: s.size,
            height: s.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFFD700).withOpacity(0.9),
                  const Color(0xFFDAA520).withOpacity(0.0),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _Spark {
  final double x, y, speed, size, delay;
  const _Spark({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.delay,
  });
}

class _Anim extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const _Anim({required Listenable animation, required this.builder})
    : super(listenable: animation);
  @override
  Widget build(BuildContext context) => builder(context, null);
}
