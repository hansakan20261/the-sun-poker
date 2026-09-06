import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/thai_labels.dart';

/// Three-row card placement area for OFC (Open Face Chinese Poker).
///
/// Displays three rows: กองหน้า (max 3), กองกลาง (max 5), กองหลัง (max 5)
/// with Thai labels. Empty slots shown as dashed-border rectangles.
/// Supports tap-to-place with gold border highlight on valid targets.
/// Rejects placement on full rows with "กองนี้เต็มแล้ว" toast.
/// Pulsing highlight on rows with available slots when card awaiting placement.
///
/// Requirements: 23.7, 23.8, 24.2-24.9, 25.1, 25.7
class CardPlacementArea extends StatefulWidget {
  final List<String> frontCards;
  final List<String> middleCards;
  final List<String> backCards;
  final bool isCurrentPlayer;
  final Function(String card, String row)? onCardPlaced;

  const CardPlacementArea({
    super.key,
    required this.frontCards,
    required this.middleCards,
    required this.backCards,
    required this.isCurrentPlayer,
    this.onCardPlaced,
  });

  @override
  State<CardPlacementArea> createState() => _CardPlacementAreaState();
}

class _CardPlacementAreaState extends State<CardPlacementArea>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  String? _selectedCard;

  static const int _maxFront = 3;
  static const int _maxMiddle = 5;
  static const int _maxBack = 5;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  bool _isRowFull(String row) {
    switch (row) {
      case 'front':
        return widget.frontCards.length >= _maxFront;
      case 'middle':
        return widget.middleCards.length >= _maxMiddle;
      case 'back':
        return widget.backCards.length >= _maxBack;
      default:
        return true;
    }
  }

  void _onRowTapped(String row) {
    if (!widget.isCurrentPlayer || widget.onCardPlaced == null) return;
    if (_selectedCard == null) return;

    if (_isRowFull(row)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(ThaiLabels.rowFull),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    widget.onCardPlaced!(_selectedCard!, row);
    if (mounted) {
      setState(() => _selectedCard = null);
    }
  }

  /// Set the card awaiting placement (called externally).
  void selectCard(String card) {
    setState(() => _selectedCard = card);
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedCard != null && widget.isCurrentPlayer;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(
          label: ThaiLabels.frontHand,
          cards: widget.frontCards,
          maxCards: _maxFront,
          row: 'front',
          highlight: hasSelection && !_isRowFull('front'),
        ),
        const SizedBox(height: 8),
        _buildRow(
          label: ThaiLabels.middleHand,
          cards: widget.middleCards,
          maxCards: _maxMiddle,
          row: 'middle',
          highlight: hasSelection && !_isRowFull('middle'),
        ),
        const SizedBox(height: 8),
        _buildRow(
          label: ThaiLabels.backHand,
          cards: widget.backCards,
          maxCards: _maxBack,
          row: 'back',
          highlight: hasSelection && !_isRowFull('back'),
        ),
      ],
    );
  }

  Widget _buildRow({
    required String label,
    required List<String> cards,
    required int maxCards,
    required String row,
    required bool highlight,
  }) {
    return GestureDetector(
      onTap: () => _onRowTapped(row),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, _) {
          final borderColor = highlight
              ? SunTheme.goldLight.withOpacity(_pulseAnimation.value)
              : SunTheme.gold.withOpacity(0.2);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: SunTheme.redDark.withOpacity(0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: highlight ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: SunTheme.goldLight.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(maxCards, (i) {
                    if (i < cards.length) {
                      return _buildFilledSlot(cards[i]);
                    }
                    return _buildEmptySlot();
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilledSlot(String card) {
    final rank = card.isNotEmpty ? card[0] : '?';
    final suit = card.length > 1 ? card[1] : '?';
    final isRed = suit == 'h' || suit == 'd';
    const suits = {'h': '♥', 'd': '♦', 'c': '♣', 's': '♠'};
    const ranks = {'T': '10', 'J': 'J', 'Q': 'Q', 'K': 'K', 'A': 'A'};
    final displayRank = ranks[rank] ?? rank;
    final displaySuit = suits[suit] ?? suit;

    return Container(
      width: 40,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$displayRank$displaySuit',
          style: TextStyle(
            color: isRed ? Colors.red.shade700 : Colors.grey.shade900,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySlot() {
    return Container(
      width: 40,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: SunTheme.gold.withOpacity(0.3),
          width: 1,
          // Dashed border simulated via a dotted pattern
        ),
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: SunTheme.gold.withOpacity(0.4),
          strokeWidth: 1,
          dashWidth: 4,
          dashSpace: 3,
        ),
      ),
    );
  }
}

/// Paints a dashed rectangle border.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(5),
        ),
      );

    _drawDashedPath(canvas, path, paint);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, end.clamp(0, metric.length)),
          paint,
        );
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      color != old.color || strokeWidth != old.strokeWidth;
}

/// Minimal AnimatedBuilder for use with Listenable animations.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) => builder(context, null);
}
