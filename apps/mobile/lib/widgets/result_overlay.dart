import 'package:flutter/material.dart';
import '../utils/split_pot_calculator.dart';
import '../utils/card_size_config.dart';
import '../utils/thai_labels.dart';
import '../services/runtime_config_service.dart';
import 'playing_card.dart';
import 'split_pot_display.dart';
import 'rake_display.dart';

class ResultOverlay extends StatefulWidget {
  final bool isWinner;
  final int amount;
  final String handName;
  final VoidCallback onDismiss;
  final List<Map<String, dynamic>>? winners;
  final List<Map<String, dynamic>>? losers;
  final List<String>? communityCards;
  // Task 12.1: Rake and split pot support
  final int rakeAmount;
  final double rakePercent;
  final int rakeCap;
  final int? dealerSeat;
  final int maxSeats;

  const ResultOverlay({
    super.key,
    required this.isWinner,
    required this.amount,
    required this.handName,
    required this.onDismiss,
    this.winners,
    this.losers,
    this.communityCards,
    this.rakeAmount = 0,
    this.rakePercent = 5.0,
    this.rakeCap = 0,
    this.dealerSeat,
    this.maxSeats = 9,
  });

  @override
  State<ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends State<ResultOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scale = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _ctrl.forward();
    final displaySeconds = RuntimeConfigService.optionalValue('result_display_sec') as int? ?? 8;
    Future.delayed(Duration(seconds: displaySeconds), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: Colors.black.withOpacity(0.75),
        child: AnimBuilder(
          animation: _ctrl,
          builder: (_, __) => Opacity(
            opacity: _opacity.value,
            child: Center(
              child: Transform.scale(
                scale: _scale.value,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.92,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.75,
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF1A0808),
                        Color(0xFF0E0404),
                        Color(0xFF1A0808),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFDAA520).withOpacity(0.4),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.05),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        Text(
                          widget.isWinner ? '🏆 YOU WIN!' : '😔 YOU LOSE',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Winner hand name
                        if (widget.handName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              widget.handName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: widget.isWinner
                                    ? Colors.greenAccent
                                    : Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        // Pot amount
                        if (widget.amount > 0)
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFDAA520).withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              'POT C${widget.amount}',
                              style: const TextStyle(
                                color: Color(0xFFDAA520),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        // Amount animation
                        _AnimatedAmount(
                          amount: widget.amount,
                          isWinner: widget.isWinner,
                        ),
                        const SizedBox(height: 14),
                        // Task 12.1: Split pot display when multiple winners
                        if (widget.winners != null &&
                            widget.winners!.length > 1) ...[
                          Builder(
                            builder: (_) {
                              final winnerSeats = widget.winners!
                                  .map((w) => w['seat'] as int? ?? 0)
                                  .where((s) => s > 0)
                                  .toList();
                              if (winnerSeats.length > 1) {
                                final splitResult =
                                    SplitPotCalculator.calculate(
                                      pot: widget.amount * winnerSeats.length,
                                      winnerSeats: winnerSeats,
                                      dealerSeat: widget.dealerSeat ?? 1,
                                      maxSeats: widget.maxSeats,
                                    );
                                final playerNames = <int, String>{};
                                for (final w in widget.winners!) {
                                  final seat = w['seat'] as int? ?? 0;
                                  playerNames[seat] =
                                      w['username'] ?? 'Seat $seat';
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: SplitPotDisplay(
                                    splitResult: splitResult,
                                    playerNames: playerNames,
                                    winningHandNameTh:
                                        widget.winners!.first['handName'] ?? '',
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                        // Task 12.1: Rake display below pot total
                        if (widget.rakeAmount > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RakeDisplay(
                              rakeAmount: widget.rakeAmount,
                              rakePercent: widget.rakePercent,
                              rakeCap: widget.rakeCap,
                            ),
                          ),
                        // Community cards
                        if (widget.communityCards != null &&
                            widget.communityCards!.isNotEmpty) ...[
                          Text(
                            ThaiLabels.communityCardsLabel,
                            style: TextStyle(
                              color: const Color(0xFFDAA520).withOpacity(0.5),
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final c in widget.communityCards!)
                                PlayingCard(
                                  card: c,
                                  faceUp: true,
                                  width: CardSizeConfig.enlargedWidth,
                                  height: CardSizeConfig.enlargedHeight,
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                        ],
                        // Divider
                        Container(
                          height: 1,
                          color: const Color(0xFFDAA520).withOpacity(0.15),
                        ),
                        const SizedBox(height: 10),
                        // Winners
                        if (widget.winners != null &&
                            widget.winners!.isNotEmpty) ...[
                          _sectionLabel(
                            ThaiLabels.winner,
                            Icons.emoji_events_rounded,
                            Colors.greenAccent,
                          ),
                          const SizedBox(height: 6),
                          ...widget.winners!.map(
                            (w) => _PlayerResultRow(player: w, isWinner: true),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // Losers
                        if (widget.losers != null &&
                            widget.losers!.isNotEmpty) ...[
                          _sectionLabel(
                            ThaiLabels.loser,
                            Icons.sentiment_dissatisfied_rounded,
                            Colors.red.shade300,
                          ),
                          const SizedBox(height: 6),
                          ...widget.losers!.map(
                            (l) => _PlayerResultRow(player: l, isWinner: false),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          ThaiLabels.tapToClose,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.2),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// Animated amount counter
class _AnimatedAmount extends StatelessWidget {
  final int amount;
  final bool isWinner;
  const _AnimatedAmount({required this.amount, required this.isWinner});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: amount.abs()),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Arrow icon
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            builder: (_, v, child) => Transform.translate(
              offset: Offset(0, isWinner ? -8 * (1 - v) : 8 * (1 - v)),
              child: Opacity(opacity: v, child: child),
            ),
            child: Icon(
              isWinner
                  ? Icons.arrow_drop_up_rounded
                  : Icons.arrow_drop_down_rounded,
              color: isWinner ? Colors.greenAccent : Colors.redAccent,
              size: 36,
            ),
          ),
          Text(
            '${isWinner ? "+" : "-"}C$value',
            style: TextStyle(
              color: isWinner ? Colors.greenAccent : Colors.redAccent,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }
}

// Player result row with cards reveal animation
class _PlayerResultRow extends StatefulWidget {
  final Map<String, dynamic> player;
  final bool isWinner;
  const _PlayerResultRow({required this.player, required this.isWinner});
  @override
  State<_PlayerResultRow> createState() => _PlayerResultRowState();
}

class _PlayerResultRowState extends State<_PlayerResultRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(Duration(milliseconds: widget.isWinner ? 300 : 600), () {
      if (mounted) _anim.forward();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final cards = List<String>.from(p['holeCards'] ?? []);
    final name = p['username'] ?? 'Player';
    final seat = p['seat'] ?? '?';
    final handName = p['handName'] ?? '';
    final folded = p['folded'] == true;
    final isW = widget.isWinner;

    return AnimatedBuilder2(
      animation: _anim,
      builder: (_, __) {
        final slide = Tween<Offset>(
          begin: Offset(isW ? -0.3 : 0.3, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
        final opacity = Tween<double>(
          begin: 0,
          end: 1,
        ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeIn));

        return SlideTransition(
          position: slide,
          child: Opacity(
            opacity: opacity.value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isW
                      ? [
                          const Color(0xFF1B5E20).withOpacity(0.2),
                          const Color(0xFF1B5E20).withOpacity(0.05),
                        ]
                      : [
                          const Color(0xFF8B0000).withOpacity(0.15),
                          const Color(0xFF8B0000).withOpacity(0.05),
                        ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isW
                      ? Colors.greenAccent.withOpacity(0.25)
                      : Colors.red.withOpacity(0.15),
                ),
              ),
              child: Row(
                children: [
                  // Seat badge
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isW
                            ? [const Color(0xFF2E8B57), const Color(0xFF1B5E20)]
                            : [
                                const Color(0xFF8B0000),
                                const Color(0xFF5C0000),
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isW ? Colors.greenAccent : Colors.red)
                              .withOpacity(0.2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '$seat',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Name + hand + status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                color: isW
                                    ? Colors.greenAccent
                                    : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (isW)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'WIN',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (!isW && folded)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  ThaiLabels.fold,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (!isW && !folded)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'LOSE',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (handName.isNotEmpty)
                          Text(
                            handName,
                            style: TextStyle(
                              color: const Color(0xFFDAA520).withOpacity(0.5),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Cards (animated reveal)
                  if (cards.isNotEmpty && !folded)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final c in cards)
                          Container(
                            decoration: isW
                                ? BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFDAA520),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFFFD700,
                                        ).withOpacity(0.5),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  )
                                : null,
                            child: PlayingCard(
                              card: c,
                              faceUp: true,
                              width: CardSizeConfig.enlargedWidth,
                              height: CardSizeConfig.enlargedHeight,
                            ),
                          ),
                      ],
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlayingCard(
                          card: '??',
                          faceUp: false,
                          width: CardSizeConfig.enlargedWidth,
                          height: CardSizeConfig.enlargedHeight,
                        ),
                        PlayingCard(
                          card: '??',
                          faceUp: false,
                          width: CardSizeConfig.enlargedWidth,
                          height: CardSizeConfig.enlargedHeight,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AnimBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);
  @override
  Widget build(BuildContext context) => builder(context, null);
}

class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder2({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);
  @override
  Widget build(BuildContext context) => builder(context, null);
}
