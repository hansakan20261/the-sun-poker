import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen overlay: cinematic card deal
/// 1. Cards fly from dealer (top) → zoom to large center
/// 2. Cards flip 3D + unfold/peel open to reveal face
/// 3. Cards shrink down to player hand
class DealAnimationOverlay extends StatefulWidget {
  final List<String> cards;
  final VoidCallback onComplete;

  const DealAnimationOverlay({
    super.key,
    required this.cards,
    required this.onComplete,
  });

  @override
  State<DealAnimationOverlay> createState() => _DealAnimationOverlayState();
}

class _DealAnimationOverlayState extends State<DealAnimationOverlay>
    with TickerProviderStateMixin {
  late AnimationController _flyCtrl;
  late AnimationController _flipCtrl;
  late AnimationController _settleCtrl;

  // Fly in
  late Animation<double> _flySlideY;
  late Animation<double> _flyScale;
  late Animation<double> _flyOpacity;

  // Flip + unfold
  late Animation<double> _flipValue;
  late Animation<double> _unfoldValue;
  late Animation<double> _spreadValue;

  // Settle out
  late Animation<double> _settleScale;
  late Animation<double> _settleSlideY;
  late Animation<double> _settleOpacity;

  bool _showFront = false;
  bool _settling = false;

  static const _suits = {
    'h': '\u2665',
    'd': '\u2666',
    'c': '\u2663',
    's': '\u2660',
  };
  static const _ranks = {'T': '10', 'J': 'J', 'Q': 'Q', 'K': 'K', 'A': 'A'};

  @override
  void initState() {
    super.initState();

    // Phase 1: Fly in from dealer
    _flyCtrl = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _flySlideY = Tween<double>(
      begin: -0.8,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _flyCtrl, curve: Curves.easeOutCubic));
    _flyScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.1,
          end: 1.1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 75,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.1,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_flyCtrl);
    _flyOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _flyCtrl,
        curve: const Interval(0.0, 0.2, curve: Curves.easeIn),
      ),
    );

    // Phase 2: Flip + unfold
    _flipCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _flipValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _flipCtrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeInOutCubic),
      ),
    );
    _flipValue.addListener(() {
      if (_flipValue.value >= 0.5 && !_showFront) {
        setState(() => _showFront = true);
      }
    });
    _unfoldValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _flipCtrl,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOutBack),
      ),
    );
    _spreadValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _flipCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    // Phase 3: Settle to hand
    _settleCtrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _settleScale = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _settleCtrl, curve: Curves.easeInCubic));
    _settleSlideY = Tween<double>(
      begin: 0.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _settleCtrl, curve: Curves.easeInCubic));
    _settleOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _settleCtrl,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    if (!mounted) return;
    await _flyCtrl.forward();
    if (!mounted) return;
    // Task 9.2: Haptic feedback when card reaches destination (Req 5.3)
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    await _flipCtrl.forward();
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _settling = true);
    await _settleCtrl.forward();
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  void dispose() {
    _flyCtrl.dispose();
    _flipCtrl.dispose();
    _settleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_flyCtrl, _flipCtrl, _settleCtrl]),
      builder: (context, _) {
        final slideY = _settling ? _settleSlideY.value : _flySlideY.value;
        final scale = _settling ? _settleScale.value : _flyScale.value;
        final opacity = _settling ? _settleOpacity.value : _flyOpacity.value;
        final flip = _flipValue.value;
        final unfold = _unfoldValue.value;
        final spread = _spreadValue.value;

        return IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  color: Colors.black.withOpacity(
                    0.5 * (1 - (_settling ? _settleCtrl.value : 0)),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, slideY * 200),
                  child: Transform.scale(
                    scale: scale,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < widget.cards.length; i++)
                          _buildCard(widget.cards[i], i, flip, unfold, spread),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(
    String card,
    int index,
    double flip,
    double unfold,
    double spread,
  ) {
    final cardCount = widget.cards.length;
    final centerIndex = (cardCount - 1) / 2;
    final offsetX = (index - centerIndex) * 65 * spread;
    final rotation = (index - centerIndex) * 0.08 * spread;
    final unfoldTilt = (1 - unfold) * 0.35;

    return Transform.translate(
      offset: Offset(offsetX, 0),
      child: Transform.rotate(
        angle: rotation,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY((1 - flip) * math.pi)
            ..rotateX(_showFront ? unfoldTilt : 0),
          child: _showFront ? _buildCardFront(card) : _buildCardBack(),
        ),
      ),
    );
  }

  Widget _buildCardFront(String card) {
    if (card == '??' || card.length < 2) return _buildCardBack();
    final rank = card[0], suit = card.length > 1 ? card[1] : 'h';
    final dr = _ranks[rank] ?? rank, ds = _suits[suit] ?? suit;

    // Match PlayingCard widget colors exactly:
    // s (spade) = black, h (heart) = red, c (club) = green, d (diamond) = blue
    Color color;
    switch (suit) {
      case 's':
        color = const Color(0xFF1A1A1A); // ดำ
      case 'h':
        color = const Color(0xFFD32F2F); // แดง
      case 'c':
        color = const Color(0xFF1B5E20); // เขียวเข้ม
      case 'd':
        color = const Color(0xFF0D47A1); // น้ำเงินเข้ม
      default:
        color = Colors.black;
    }

    return Container(
      width: 120,
      height: 170,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(4, 8),
          ),
          BoxShadow(color: color.withOpacity(0.15), blurRadius: 30),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 6,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dr,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
                CustomPaint(
                  size: const Size(20, 20),
                  painter: _DealSuitPainter(suit: suit, size: 20),
                ),
              ],
            ),
          ),
          Center(
            child: CustomPaint(
              size: const Size(64, 64),
              painter: _DealSuitPainter(suit: suit, size: 64),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 6,
            child: Transform.rotate(
              angle: math.pi,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dr,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1,
                    ),
                  ),
                  CustomPaint(
                    size: const Size(20, 20),
                    painter: _DealSuitPainter(suit: suit, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBack() {
    return Container(
      width: 120,
      height: 170,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFD42020),
            Color(0xFFAA1515),
            Color(0xFF8B0000),
            Color(0xFF5C0000),
          ],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDAA520), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(4, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Outer frame
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFDAA520).withOpacity(0.5),
                  width: 1.5,
                ),
              ),
            ),
          ),
          // Inner frame
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFDAA520).withOpacity(0.3),
                  width: 1,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.transparent,
                    Colors.black.withOpacity(0.15),
                  ],
                ),
              ),
            ),
          ),
          // Center logo
          Center(
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFDAA520).withOpacity(0.6),
                  width: 1.5,
                ),
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFDAA520).withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
              child: const Center(
                child: Text(
                  '☀',
                  style: TextStyle(fontSize: 28, color: Color(0xFFDAA520)),
                ),
              ),
            ),
          ),
          // Corner diamonds
          const Positioned(
            left: 8,
            top: 8,
            child: Text(
              '♦',
              style: TextStyle(fontSize: 14, color: Color(0xAADAA520)),
            ),
          ),
          const Positioned(
            right: 8,
            top: 8,
            child: Text(
              '♦',
              style: TextStyle(fontSize: 14, color: Color(0xAADAA520)),
            ),
          ),
          const Positioned(
            left: 8,
            bottom: 8,
            child: Text(
              '♦',
              style: TextStyle(fontSize: 14, color: Color(0xAADAA520)),
            ),
          ),
          const Positioned(
            right: 8,
            bottom: 8,
            child: Text(
              '♦',
              style: TextStyle(fontSize: 14, color: Color(0xAADAA520)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DealSuitPainter extends CustomPainter {
  final String suit;
  final double size;

  _DealSuitPainter({required this.suit, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()..style = PaintingStyle.fill;

    switch (suit) {
      case 'h':
        paint.color = const Color(0xFFD32F2F);
        _drawHeart(canvas, canvasSize, paint);
        break;
      case 'd':
        paint.color = const Color(0xFF0D47A1);
        _drawDiamond(canvas, canvasSize, paint);
        break;
      case 'c':
        paint.color = const Color(0xFF1B5E20);
        _drawClub(canvas, canvasSize, paint);
        break;
      case 's':
        paint.color = const Color(0xFF1A1A1A);
        _drawSpade(canvas, canvasSize, paint);
        break;
    }
  }

  void _drawHeart(Canvas canvas, Size s, Paint paint) {
    final path = Path();
    final w = s.width, h = s.height;
    path.moveTo(w * 0.5, h * 0.85);
    path.cubicTo(w * 0.1, h * 0.55, w * 0.0, h * 0.25, w * 0.25, h * 0.15);
    path.cubicTo(w * 0.4, h * 0.08, w * 0.5, h * 0.2, w * 0.5, h * 0.3);
    path.cubicTo(w * 0.5, h * 0.2, w * 0.6, h * 0.08, w * 0.75, h * 0.15);
    path.cubicTo(w * 1.0, h * 0.25, w * 0.9, h * 0.55, w * 0.5, h * 0.85);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawDiamond(Canvas canvas, Size s, Paint paint) {
    final path = Path();
    final w = s.width, h = s.height;
    path.moveTo(w * 0.5, h * 0.05);
    path.lineTo(w * 0.9, h * 0.5);
    path.lineTo(w * 0.5, h * 0.95);
    path.lineTo(w * 0.1, h * 0.5);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawClub(Canvas canvas, Size s, Paint paint) {
    final w = s.width, h = s.height;
    final r = w * 0.22;
    canvas.drawCircle(Offset(w * 0.5, h * 0.28), r, paint);
    canvas.drawCircle(Offset(w * 0.3, h * 0.52), r, paint);
    canvas.drawCircle(Offset(w * 0.7, h * 0.52), r, paint);
    final stem = Path();
    stem.moveTo(w * 0.42, h * 0.6);
    stem.lineTo(w * 0.35, h * 0.9);
    stem.lineTo(w * 0.65, h * 0.9);
    stem.lineTo(w * 0.58, h * 0.6);
    stem.close();
    canvas.drawPath(stem, paint);
  }

  void _drawSpade(Canvas canvas, Size s, Paint paint) {
    final path = Path();
    final w = s.width, h = s.height;
    path.moveTo(w * 0.5, h * 0.05);
    path.cubicTo(w * 0.1, h * 0.35, w * 0.0, h * 0.6, w * 0.25, h * 0.7);
    path.cubicTo(w * 0.38, h * 0.75, w * 0.45, h * 0.68, w * 0.5, h * 0.6);
    path.cubicTo(w * 0.55, h * 0.68, w * 0.62, h * 0.75, w * 0.75, h * 0.7);
    path.cubicTo(w * 1.0, h * 0.6, w * 0.9, h * 0.35, w * 0.5, h * 0.05);
    path.close();
    canvas.drawPath(path, paint);
    final stem = Path();
    stem.moveTo(w * 0.42, h * 0.65);
    stem.lineTo(w * 0.35, h * 0.92);
    stem.lineTo(w * 0.65, h * 0.92);
    stem.lineTo(w * 0.58, h * 0.65);
    stem.close();
    canvas.drawPath(stem, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({
    super.key,
    required Listenable animation,
    required this.builder,
  }) : super(listenable: animation);
  @override
  Widget build(BuildContext context) => builder(context, null);
}
