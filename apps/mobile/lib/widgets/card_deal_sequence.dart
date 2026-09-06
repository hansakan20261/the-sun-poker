import 'package:flutter/material.dart';
import 'playing_card.dart';
import '../services/audio_manager.dart';

/// Animated card dealing sequence — deals cards one by one from dealer position
/// to player positions with fly animation.
///
/// Used in both NLH (2 cards) and OFC (13 cards) modes.
class CardDealSequence extends StatefulWidget {
  /// Cards to deal (in order)
  final List<String> cards;

  /// Duration per card animation
  final Duration cardDuration;

  /// Delay between each card
  final Duration cardDelay;

  /// Called when all cards have been dealt
  final VoidCallback onComplete;

  /// Card dimensions
  final double cardWidth;
  final double cardHeight;

  /// Whether to show card face during flight (false = show back)
  final bool showFaceDuringFlight;

  const CardDealSequence({
    super.key,
    required this.cards,
    required this.onComplete,
    this.cardDuration = const Duration(milliseconds: 350),
    this.cardDelay = const Duration(milliseconds: 120),
    this.cardWidth = 50,
    this.cardHeight = 70,
    this.showFaceDuringFlight = false,
  });

  @override
  State<CardDealSequence> createState() => _CardDealSequenceState();
}

class _CardDealSequenceState extends State<CardDealSequence>
    with TickerProviderStateMixin {
  final List<_DealingCard> _dealingCards = [];
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _startDealSequence();
  }

  Future<void> _startDealSequence() async {
    for (int i = 0; i < widget.cards.length; i++) {
      if (!mounted) return;

      final controller = AnimationController(
        vsync: this,
        duration: widget.cardDuration,
      );

      final card = _DealingCard(
        card: widget.cards[i],
        controller: controller,
        index: i,
      );

      setState(() => _dealingCards.add(card));

      // Play deal sound
      AudioManager.instance.play(SoundEffect.cardDeal);

      controller.forward();

      // Wait before dealing next card
      if (i < widget.cards.length - 1) {
        await Future.delayed(widget.cardDelay);
      }
    }

    // Wait for last card animation to finish
    await Future.delayed(widget.cardDuration);

    if (mounted && !_completed) {
      _completed = true;
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    for (final dc in _dealingCards) {
      dc.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Dealer position (center of table)
    final dealerX = size.width / 2 - widget.cardWidth / 2;
    final dealerY = size.height * 0.3;
    // Target position (bottom center — player's hand area)
    final targetX = size.width / 2 - widget.cardWidth / 2;
    final targetY = size.height * 0.75;

    return IgnorePointer(
      child: Stack(
        children: [
          // Semi-transparent overlay during dealing
          AnimatedOpacity(
            opacity: _completed ? 0.0 : 0.3,
            duration: const Duration(milliseconds: 300),
            child: Container(color: Colors.black),
          ),
          // Flying cards
          for (final dc in _dealingCards)
            AnimatedBuilder(
              animation: dc.controller,
              builder: (context, _) {
                final t = CurvedAnimation(
                  parent: dc.controller,
                  curve: Curves.easeOutCubic,
                ).value;

                final x = dealerX + (targetX - dealerX) * t;
                final y = dealerY + (targetY - dealerY) * t;
                final scale = 0.5 + 0.5 * t;
                final opacity = t < 0.1 ? t * 10 : 1.0;
                // Show face only after card arrives
                final showFace = widget.showFaceDuringFlight || t > 0.9;

                return Positioned(
                  left: x + (dc.index % 2 == 0 ? -10 : 10) * (1 - t),
                  top: y,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: Transform.rotate(
                        angle: (1 - t) * 0.3 * (dc.index % 2 == 0 ? 1 : -1),
                        child: PlayingCard(
                          card: dc.card,
                          faceUp: showFace,
                          width: widget.cardWidth,
                          height: widget.cardHeight,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DealingCard {
  final String card;
  final AnimationController controller;
  final int index;

  _DealingCard({
    required this.card,
    required this.controller,
    required this.index,
  });
}

/// Simple AnimatedBuilder replacement (since the custom one in deal_animation_overlay conflicts)
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
