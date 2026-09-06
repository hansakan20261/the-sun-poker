import 'package:flutter/material.dart';

/// A widget that renders a playing card with the four-color suit design.
///
/// Suit colors:
/// - Spade: #1A1A1A (black)
/// - Heart: #D32F2F (red)
/// - Club: #1B5E20 (dark green)
/// - Diamond: #0D47A1 (dark blue)
///
/// Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7
class PlayingCardWidget extends StatelessWidget {
  /// Card code (e.g., "Ah" for Ace of hearts, "Ts" for 10 of spades).
  /// First char is rank, second is suit.
  /// Null or "??" renders the card back.
  final String? card;

  /// Whether to show the card face (true) or back (false).
  final bool faceUp;

  final double width;
  final double height;

  const PlayingCardWidget({
    super.key,
    this.card,
    this.faceUp = true,
    this.width = 48,
    this.height = 66,
  });

  /// Returns the color for a given suit character.
  ///
  /// - 's' (spade) → #1A1A1A (black)
  /// - 'h' (heart) → #D32F2F (red)
  /// - 'c' (club) → #1B5E20 (dark green)
  /// - 'd' (diamond) → #0D47A1 (dark blue)
  static Color getSuitColor(String suit) {
    switch (suit) {
      case 's':
        return const Color(0xFF1A1A1A);
      case 'h':
        return const Color(0xFFD32F2F);
      case 'c':
        return const Color(0xFF1B5E20);
      case 'd':
        return const Color(0xFF0D47A1);
      default:
        return const Color(0xFF1A1A1A);
    }
  }

  /// Maps rank character to display string.
  static String getRankDisplay(String rank) {
    switch (rank) {
      case 'T':
        return '10';
      case 'J':
        return 'J';
      case 'Q':
        return 'Q';
      case 'K':
        return 'K';
      case 'A':
        return 'A';
      default:
        return rank;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showFace =
        faceUp && card != null && card != '??' && (card?.length ?? 0) >= 2;

    if (!showFace) {
      return _buildBack();
    }

    return _buildFront();
  }

  Widget _buildFront() {
    final rank = card![0];
    final suit = card![1];
    final displayRank = getRankDisplay(rank);
    final color = getSuitColor(suit);

    return Container(
      width: width,
      height: height,
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
          // Top-left: bold rank text with suit-matched color
          Padding(
            padding: EdgeInsets.only(left: width * 0.08, top: height * 0.03),
            child: Align(
              alignment: Alignment.topLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    displayRank,
                    style: TextStyle(
                      fontSize: width * 0.32,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1.0,
                    ),
                  ),
                  // Small suit icon below rank
                  CustomPaint(
                    size: Size(width * 0.18, width * 0.18),
                    painter: SuitPainter(suit: suit),
                  ),
                ],
              ),
            ),
          ),
          // Center: large suit symbol via CustomPaint
          Expanded(
            child: Center(
              child: CustomPaint(
                size: Size(width * 0.5, width * 0.5),
                painter: SuitPainter(suit: suit),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Card back: gradient red with gold border and sun logo.
  Widget _buildBack() {
    return Container(
      width: width,
      height: height,
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
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFDAA520), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            // Inner gold frame
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: const Color(0xFFDAA520).withOpacity(0.4),
                    width: 0.5,
                  ),
                ),
              ),
            ),
            // Center sun logo
            Center(
              child: Text(
                '☀',
                style: TextStyle(
                  fontSize: width * 0.3,
                  color: const Color(0xFFDAA520).withOpacity(0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter that draws suit symbols using vector paths.
///
/// Renders suit symbols via CustomPaint rather than Unicode text characters.
/// Requirements: 10.5
class SuitPainter extends CustomPainter {
  final String suit;

  SuitPainter({required this.suit});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = PlayingCardWidget.getSuitColor(suit);

    switch (suit) {
      case 'h':
        _drawHeart(canvas, size, paint);
        break;
      case 'd':
        _drawDiamond(canvas, size, paint);
        break;
      case 'c':
        _drawClub(canvas, size, paint);
        break;
      case 's':
        _drawSpade(canvas, size, paint);
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
  bool shouldRepaint(covariant SuitPainter oldDelegate) {
    return oldDelegate.suit != suit;
  }
}
