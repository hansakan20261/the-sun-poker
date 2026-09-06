import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/showdown_anim_config.dart';

class PlayingCard extends StatefulWidget {
  final String? card;
  final bool faceUp;
  final double width;
  final double height;
  final bool animate;
  final Duration delay;
  final VoidCallback? onTap;
  final double? perspectiveValue;

  const PlayingCard({
    super.key,
    this.card,
    this.faceUp = true,
    this.width = 50,
    this.height = 70,
    this.animate = false,
    this.delay = Duration.zero,
    this.onTap,
    this.perspectiveValue,
  });

  @override
  State<PlayingCard> createState() => _PlayingCardState();
}

class _PlayingCardState extends State<PlayingCard>
    with TickerProviderStateMixin {
  AnimationController? _flyCtrl;
  AnimationController? _flipCtrl;
  AnimationController? _emphasisCtrl; // Task 12.1: post-flip scale emphasis

  Animation<double>? _flyScale;
  Animation<Offset>? _flySlide;
  Animation<double>? _flyOpacity;
  Animation<double>? _flipValue;
  Animation<double>? _unfoldValue;
  Animation<double>? _emphasisScale; // Task 12.1

  bool _showFront = false;
  bool _started = false;

  static const _suits = {
    'h': '\u2665',
    'd': '\u2666',
    'c': '\u2663',
    's': '\u2660',
  };
  static const _ranks = {'T': '10', 'J': 'J', 'Q': 'Q', 'K': 'K', 'A': 'A'};

  bool get _isFace =>
      widget.faceUp &&
      widget.card != null &&
      widget.card != '??' &&
      (widget.card?.length ?? 0) >= 2;

  @override
  void initState() {
    super.initState();

    if (!widget.animate) {
      _showFront = _isFace;
      _started = true;
      return;
    }

    // Phase 1: Fly from dealer to player
    _flyCtrl = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _flyScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.1,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.15,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_flyCtrl!);

    _flySlide = Tween<Offset>(
      begin: const Offset(0, -5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _flyCtrl!, curve: Curves.easeOutCubic));

    _flyOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _flyCtrl!,
        curve: const Interval(0.0, 0.2, curve: Curves.easeIn),
      ),
    );

    // Phase 2: Flip + unfold
    _flipCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _flipValue = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _flipCtrl!,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOutCubic),
      ),
    );
    _flipValue!.addListener(() {
      if (_flipValue!.value >= 0.5 && !_showFront && _isFace) {
        if (mounted) setState(() => _showFront = true);
      }
    });

    _unfoldValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _flipCtrl!,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOutBack),
      ),
    );

    // Task 12.1: Post-flip scale emphasis (Req 7.4, 7.5)
    _emphasisCtrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _emphasisScale = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1), weight: 50),
        TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 50),
      ],
    ).animate(CurvedAnimation(parent: _emphasisCtrl!, curve: Curves.easeInOut));

    _startAnimation();
  }

  Future<void> _startAnimation() async {
    await Future.delayed(widget.delay);
    if (!mounted) return;
    setState(() => _started = true);
    await _flyCtrl?.forward();
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    await _flipCtrl?.forward();
    // Task 12.1: Post-flip scale emphasis (Req 7.5)
    if (!mounted) return;
    _emphasisCtrl?.forward();
  }

  @override
  void didUpdateWidget(PlayingCard old) {
    super.didUpdateWidget(old);
    if (widget.card != old.card && _isFace && !_showFront) {
      if (_flyCtrl != null) {
        _showFront = false;
        _flyCtrl!.reset();
        _flipCtrl!.reset();
        _startAnimation();
      } else {
        _showFront = _isFace;
      }
    }
  }

  @override
  void dispose() {
    _flyCtrl?.dispose();
    _flipCtrl?.dispose();
    _emphasisCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.card == null && !widget.faceUp) {
      // Explicitly face-down with no card data → show solid card back
      return _buildBack();
    }
    if (widget.card == null || widget.card!.isEmpty) {
      // Empty placeholder slot
      return Container(
        width: widget.width,
        height: widget.height,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: const Color(0xFF8B0000).withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFDAA520).withOpacity(0.15)),
        ),
      );
    }

    // No animation — static card
    if (_flyCtrl == null) {
      return GestureDetector(
        onTap: widget.onTap,
        child: _showFront ? _buildFront() : _buildBack(),
      );
    }

    // Animated card
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _flyCtrl!,
          _flipCtrl!,
          if (_emphasisCtrl != null) _emphasisCtrl!,
        ]),
        builder: (_, __) {
          final scale = _flyScale?.value ?? 1.0;
          final slide = _flySlide?.value ?? Offset.zero;
          final opacity = _flyOpacity?.value ?? 1.0;
          final flip = _flipValue?.value ?? (_showFront ? 1.0 : 0.0);
          final unfold = _unfoldValue?.value ?? 1.0;
          final unfoldTilt = (1 - unfold) * 0.3;
          // Task 12.1: Apply post-flip emphasis scale
          final emphasisS = _emphasisScale?.value ?? 1.0;

          return AnimatedOpacity(
            opacity: _started ? opacity.clamp(0.0, 1.0) : 0.0,
            duration: const Duration(milliseconds: 80),
            child: SlideTransition(
              position: AlwaysStoppedAnimation(slide),
              child: Transform.scale(
                scale: scale * emphasisS,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..setEntry(
                      3,
                      2,
                      widget.perspectiveValue ??
                          ShowdownAnimConfig.perspectiveValue,
                    )
                    ..rotateY((1 - flip) * math.pi)
                    ..rotateX(_showFront ? unfoldTilt : 0),
                  child: _showFront ? _buildFront() : _buildBack(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFront() {
    final c = widget.card!;
    if (c == '??' || c.length < 2) return _buildBack();
    final rank = c[0], suit = c.length > 1 ? c[1] : 'h';
    final dr = _ranks[rank] ?? rank;

    // Custom suit colors:
    // s (spade/โพดำ) = black
    // h (heart/โพแดง) = red
    // c (club/ดอกจิก) = green
    // d (diamond/ข้าวหลามตัด) = blue
    Color suitColor;
    switch (suit) {
      case 's':
        suitColor = const Color(0xFF1A1A1A); // ดำ
      case 'h':
        suitColor = const Color(0xFFD32F2F); // แดง
      case 'c':
        suitColor = const Color(0xFF1B5E20); // เขียวเข้ม
      case 'd':
        suitColor = const Color(0xFF0D47A1); // น้ำเงินเข้ม
      default:
        suitColor = Colors.black;
    }

    return Container(
      width: widget.width,
      height: widget.height,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top section: rank + small suit icon — ขยายใหญ่ 10 ระดับ
          Padding(
            padding: EdgeInsets.only(
              left: widget.width * 0.04,
              top: widget.height * 0.01,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    dr,
                    style: TextStyle(
                      fontSize: widget.width * 0.58,
                      fontWeight: FontWeight.w900,
                      color: suitColor,
                      height: 1.0,
                    ),
                  ),
                  _buildSuitIcon(suit, widget.width * 0.28),
                ],
              ),
            ),
          ),
          // Center: large suit icon
          Expanded(
            child: Center(child: _buildSuitIcon(suit, widget.width * 0.65)),
          ),
        ],
      ),
    );
  }

  /// Build a colored suit icon using CustomPaint instead of Unicode text
  Widget _buildSuitIcon(String suit, double size) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SuitPainter(suit: suit, size: size),
    );
  }

  int _rankToNum(String rank) {
    switch (rank) {
      case 'A':
        return 1;
      case '2':
        return 2;
      case '3':
        return 3;
      case '4':
        return 4;
      case '5':
        return 5;
      case '6':
        return 6;
      case '7':
        return 7;
      case '8':
        return 8;
      case '9':
        return 9;
      case 'T':
        return 10;
      default:
        return 0;
    }
  }

  Widget _pip(String ds, double size, Color color, {bool flip = false}) {
    return Transform.rotate(
      angle: flip ? math.pi : 0,
      child: Text(
        ds,
        style: TextStyle(fontSize: size, color: color, height: 1),
      ),
    );
  }

  Widget _buildPipLayout(int num, String ds, double size, Color color) {
    final s = size * 0.85;
    switch (num) {
      case 2:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [_pip(ds, s, color), _pip(ds, s, color, flip: true)],
        );
      case 3:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _pip(ds, s, color),
            _pip(ds, s, color),
            _pip(ds, s, color, flip: true),
          ],
        );
      case 4:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pip(ds, s, color, flip: true),
                _pip(ds, s, color, flip: true),
              ],
            ),
          ],
        );
      case 5:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Center(child: _pip(ds, s, color)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pip(ds, s, color, flip: true),
                _pip(ds, s, color, flip: true),
              ],
            ),
          ],
        );
      case 6:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pip(ds, s, color, flip: true),
                _pip(ds, s, color, flip: true),
              ],
            ),
          ],
        );
      case 7:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Center(child: _pip(ds, s, color)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pip(ds, s, color, flip: true),
                _pip(ds, s, color, flip: true),
              ],
            ),
          ],
        );
      case 8:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Center(child: _pip(ds, s, color)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Center(child: _pip(ds, s, color, flip: true)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pip(ds, s, color, flip: true),
                _pip(ds, s, color, flip: true),
              ],
            ),
          ],
        );
      case 9:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Center(child: _pip(ds, s, color)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pip(ds, s, color, flip: true),
                _pip(ds, s, color, flip: true),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pip(ds, s, color, flip: true),
                _pip(ds, s, color, flip: true),
              ],
            ),
          ],
        );
      case 10:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Center(child: _pip(ds, s, color)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_pip(ds, s, color), _pip(ds, s, color)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pip(ds, s, color, flip: true),
                _pip(ds, s, color, flip: true),
              ],
            ),
            Center(child: _pip(ds, s, color, flip: true)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pip(ds, s, color, flip: true),
                _pip(ds, s, color, flip: true),
              ],
            ),
          ],
        );
      default:
        return Center(child: _pip(ds, size, color));
    }
  }

  Widget _buildBack() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE02020),
            Color(0xFFCC1818),
            Color(0xFFA00000),
            Color(0xFF700000),
          ],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFDAA520), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(1, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            // Solid inner gold frame
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFFDAA520), width: 1),
                ),
              ),
            ),
            // Center logo — fully opaque
            Center(
              child: Container(
                width: widget.width * 0.4,
                height: widget.width * 0.4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFDAA520),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '☀',
                    style: TextStyle(
                      fontSize: widget.width * 0.22,
                      color: const Color(0xFFFFD700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get fanValue => 0;
}

/// Custom painter that draws suit symbols with exact colors
class _SuitPainter extends CustomPainter {
  final String suit;
  final double size;

  _SuitPainter({required this.suit, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()..style = PaintingStyle.fill;

    switch (suit) {
      case 'h': // Heart — RED
        paint.color = const Color(0xFFD32F2F);
        _drawHeart(canvas, canvasSize, paint);
        break;
      case 'd': // Diamond — BLUE
        paint.color = const Color(0xFF0D47A1);
        _drawDiamond(canvas, canvasSize, paint);
        break;
      case 'c': // Club — GREEN
        paint.color = const Color(0xFF1B5E20);
        _drawClub(canvas, canvasSize, paint);
        break;
      case 's': // Spade — BLACK
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
    // Three circles
    canvas.drawCircle(Offset(w * 0.5, h * 0.28), r, paint); // top
    canvas.drawCircle(Offset(w * 0.3, h * 0.52), r, paint); // left
    canvas.drawCircle(Offset(w * 0.7, h * 0.52), r, paint); // right
    // Stem
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
    // Spade shape (inverted heart + stem)
    path.moveTo(w * 0.5, h * 0.05);
    path.cubicTo(w * 0.1, h * 0.35, w * 0.0, h * 0.6, w * 0.25, h * 0.7);
    path.cubicTo(w * 0.38, h * 0.75, w * 0.45, h * 0.68, w * 0.5, h * 0.6);
    path.cubicTo(w * 0.55, h * 0.68, w * 0.62, h * 0.75, w * 0.75, h * 0.7);
    path.cubicTo(w * 1.0, h * 0.6, w * 0.9, h * 0.35, w * 0.5, h * 0.05);
    path.close();
    canvas.drawPath(path, paint);
    // Stem
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
