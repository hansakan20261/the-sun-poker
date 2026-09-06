import 'dart:math';
import 'package:flutter/material.dart';

/// Animated overlay showing cards sliding FROM the dealer position
/// ACROSS the table surface to each player's avatar.
/// Cards stay flat on the table plane (no vertical fly-in).
class DealToPlayersAnimation extends StatefulWidget {
  final int playerCount;
  final int cardsPerPlayer;
  final VoidCallback? onComplete;

  const DealToPlayersAnimation({
    super.key,
    required this.playerCount,
    this.cardsPerPlayer = 2,
    this.onComplete,
  });

  @override
  State<DealToPlayersAnimation> createState() => _DealToPlayersAnimationState();
}

class _DealToPlayersAnimationState extends State<DealToPlayersAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_FlyingCard> _cards = [];
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final totalCards = widget.playerCount * widget.cardsPerPlayer;
    final effectiveCards = totalCards.clamp(1, 16); // cap for performance
    final duration = Duration(milliseconds: 100 * effectiveCards + 500);

    _controller = AnimationController(duration: duration, vsync: this);

    for (int idx = 0; idx < effectiveCards; idx++) {
      final p = idx % widget.playerCount;
      final startMs = idx * 100;
      final endMs = startMs + 400;
      _cards.add(
        _FlyingCard(
          playerIndex: p,
          startFraction: (startMs / duration.inMilliseconds).clamp(0.0, 0.99),
          endFraction: (endMs / duration.inMilliseconds).clamp(0.01, 1.0),
        ),
      );
    }

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_completed) {
        _completed = true;
        widget.onComplete?.call();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Detect landscape mode (width > height)
        final isLandscape = w > h;

        // Dealer/center position: center of table
        final dealerPos = isLandscape
            ? Offset(w / 2, h / 2) // Landscape: exact center of table
            : Offset(
                w / 2,
                MediaQuery.of(context).padding.top +
                    36.0 +
                    (h - MediaQuery.of(context).padding.top - 36.0) * 0.08,
              ); // Portrait: top-center

        final n = widget.playerCount.clamp(1, 8);
        List<Offset> targets = [];

        if (isLandscape) {
          // Landscape seat positions (Chinese Poker: 4 seats)
          // Me at bottom center
          targets.add(Offset(w / 2, h * 0.82));
          // Opponents: left, top, right
          const landscapeX = [0.05, 0.40, 0.75];
          const landscapeY = [0.35, 0.18, 0.35];
          for (int i = 0; i < n - 1 && i < landscapeX.length; i++) {
            targets.add(Offset(landscapeX[i] * w + 45, landscapeY[i] * h + 30));
          }
        } else {
          // Portrait seat positions (NLH Poker: up to 7 opponents)
          final safeTop = MediaQuery.of(context).padding.top;
          final tableAreaTop = safeTop + 36.0;
          final tableAreaHeight = h - tableAreaTop;
          // Me at bottom center
          targets.add(Offset(w / 2, tableAreaTop + tableAreaHeight * 0.85));
          // Opponents
          const seatXPercents = [0.02, 0.02, 0.12, 0.70, 0.78, 0.78, 0.68];
          const seatYPercents = [0.62, 0.42, 0.20, 0.20, 0.42, 0.62, 0.78];
          for (int i = 0; i < n - 1 && i < seatXPercents.length; i++) {
            targets.add(
              Offset(
                seatXPercents[i] * w + 45,
                tableAreaTop + seatYPercents[i] * tableAreaHeight + 30,
              ),
            );
          }
        }

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final card in _cards)
                  if (_controller.value >= card.startFraction)
                    _buildCard(
                      dealerPos,
                      targets[card.playerIndex % targets.length],
                      card,
                      _controller.value,
                    ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCard(Offset from, Offset to, _FlyingCard card, double progress) {
    final t =
        ((progress - card.startFraction) /
                (card.endFraction - card.startFraction))
            .clamp(0.0, 1.0);
    // Smooth ease-out curve for sliding across table
    final curve = Curves.easeOutCubic.transform(t);

    final x = from.dx + (to.dx - from.dx) * curve;
    final y = from.dy + (to.dy - from.dy) * curve;

    // Card stays flat — slight perspective scale (farther = smaller)
    final distFromCenter = (Offset(x, y) - from).distance;
    final maxDist = (to - from).distance;
    final perspectiveScale =
        0.7 + 0.3 * (1 - distFromCenter / maxDist.clamp(1, 9999));

    // Rotation: card points toward target
    final angle = atan2(to.dy - from.dy, to.dx - from.dx);

    // Fade out at the end
    final opacity = t < 0.8 ? 1.0 : (1.0 - (t - 0.8) / 0.2).clamp(0.0, 1.0);

    // Shadow grows as card moves away from dealer
    final shadowBlur = 2.0 + curve * 4.0;

    return Positioned(
      left: x - 18,
      top: y - 25,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.002) // perspective depth
            ..rotateX(0.6) // tilt card to lay flat on table surface
            ..scale(perspectiveScale)
            ..rotateZ(angle * 0.15), // subtle rotation toward target
          child: Container(
            width: 36,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFCC2222), Color(0xFF8B0000)],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFDAA520), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: shadowBlur,
                  offset: Offset(0, shadowBlur * 0.5),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 24,
                height: 34,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFDAA520).withOpacity(0.4),
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Center(
                  child: Text(
                    '☀',
                    style: TextStyle(fontSize: 12, color: Color(0xFFDAA520)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlyingCard {
  final int playerIndex;
  final double startFraction;
  final double endFraction;

  _FlyingCard({
    required this.playerIndex,
    required this.startFraction,
    required this.endFraction,
  });
}
