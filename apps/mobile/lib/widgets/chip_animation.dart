import 'dart:math';
import 'package:flutter/material.dart';

/// A single animated chip that flies from [start] to [end] position.
class FlyingChip extends StatefulWidget {
  final Offset start;
  final Offset end;
  final Duration duration;
  final Duration delay;
  final VoidCallback? onComplete;
  final int amount;

  const FlyingChip({
    super.key,
    required this.start,
    required this.end,
    this.duration = const Duration(milliseconds: 500),
    this.delay = Duration.zero,
    this.onComplete,
    this.amount = 0,
  });

  @override
  State<FlyingChip> createState() => _FlyingChipState();
}

class _FlyingChipState extends State<FlyingChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _positionAnimation = Tween<Offset>(begin: widget.start, end: widget.end)
        .animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
        );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.2), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 70),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.7, 1.0)),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });

    Future.delayed(widget.delay, () {
      if (mounted) {
        setState(() => _started = true);
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pos = _positionAnimation.value;
        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 14,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          ),
        );
      },
      child: _ChipIcon(amount: widget.amount),
    );
  }
}

/// Realistic casino chip widget with edge markings and 3D depth
class _ChipIcon extends StatelessWidget {
  final int amount;
  const _ChipIcon({this.amount = 0});

  // Chip color based on amount (casino standard)
  Color get _chipColor {
    if (amount >= 1000) return const Color(0xFF1A1A1A); // Black
    if (amount >= 500) return const Color(0xFF6A0DAD); // Purple
    if (amount >= 100) return const Color(0xFF1B1B1B); // Dark (black)
    if (amount >= 25) return const Color(0xFF2E7D32); // Green
    if (amount >= 5) return const Color(0xFFCC2222); // Red
    return const Color(0xFF1565C0); // Blue (default)
  }

  Color get _chipAccent {
    if (amount >= 1000) return const Color(0xFFFFD700);
    if (amount >= 500) return const Color(0xFFE0E0E0);
    if (amount >= 100) return const Color(0xFFFFD700);
    if (amount >= 25) return const Color(0xFFFFFFFF);
    if (amount >= 5) return const Color(0xFFFFFFFF);
    return const Color(0xFFFFFFFF);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(
        painter: _CasinoChipPainter(
          chipColor: _chipColor,
          accentColor: _chipAccent,
        ),
      ),
    );
  }
}

/// Custom painter for realistic casino chip
class _CasinoChipPainter extends CustomPainter {
  final Color chipColor;
  final Color accentColor;

  _CasinoChipPainter({required this.chipColor, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 1;

    // Shadow
    canvas.drawCircle(
      Offset(cx, cy + 2),
      r,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Main chip body
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [
            chipColor.withOpacity(0.9),
            chipColor,
            chipColor.withOpacity(0.7),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );

    // Edge ring (outer)
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = accentColor.withOpacity(0.8),
    );

    // Inner ring
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accentColor.withOpacity(0.5),
    );

    // Edge markings (8 dashes around the chip)
    final dashPaint = Paint()
      ..color = accentColor.withOpacity(0.9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 8; i++) {
      final angle = i * 3.14159 * 2 / 8;
      final innerR = r * 0.82;
      final outerR = r * 0.98;
      canvas.drawLine(
        Offset(cx + innerR * cos(angle), cy + innerR * sin(angle)),
        Offset(cx + outerR * cos(angle), cy + outerR * sin(angle)),
        dashPaint,
      );
    }

    // Center highlight (3D shine)
    canvas.drawCircle(
      Offset(cx - r * 0.2, cy - r * 0.2),
      r * 0.25,
      Paint()
        ..shader =
            RadialGradient(
              colors: [Colors.white.withOpacity(0.3), Colors.transparent],
            ).createShader(
              Rect.fromCircle(
                center: Offset(cx - r * 0.2, cy - r * 0.2),
                radius: r * 0.25,
              ),
            ),
    );

    // Center text "C"
    final tp = TextPainter(
      text: TextSpan(
        text: 'C',
        style: TextStyle(
          color: accentColor,
          fontSize: r * 0.8,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CasinoChipPainter old) =>
      old.chipColor != chipColor || old.accentColor != accentColor;
}

/// Controller that manages multiple chip animations on the poker table.
class ChipAnimationController extends ChangeNotifier {
  final List<ChipAnimationData> _animations = [];
  int _nextId = 0;

  List<ChipAnimationData> get animations => List.unmodifiable(_animations);

  /// Animate chips flying from a player seat to the pot (center).
  void betToPot({
    required Offset from,
    required Offset to,
    required int amount,
    int chipCount = 3,
  }) {
    final rng = Random();
    for (int i = 0; i < chipCount; i++) {
      // Slight random offset for each chip
      final offsetX = (rng.nextDouble() - 0.5) * 16;
      final offsetY = (rng.nextDouble() - 0.5) * 16;
      _animations.add(
        ChipAnimationData(
          id: _nextId++,
          start: Offset(from.dx + offsetX, from.dy + offsetY),
          end: Offset(to.dx + offsetX * 0.3, to.dy + offsetY * 0.3),
          delay: Duration(milliseconds: i * 80),
          amount: amount,
        ),
      );
    }
    notifyListeners();
  }

  /// Animate chips flying from pot (center) to the winner.
  void potToWinner({
    required Offset from,
    required Offset to,
    required int amount,
    int chipCount = 5,
  }) {
    final rng = Random();
    for (int i = 0; i < chipCount; i++) {
      final offsetX = (rng.nextDouble() - 0.5) * 20;
      final offsetY = (rng.nextDouble() - 0.5) * 20;
      _animations.add(
        ChipAnimationData(
          id: _nextId++,
          start: Offset(from.dx + offsetX, from.dy + offsetY),
          end: Offset(to.dx + offsetX * 0.2, to.dy + offsetY * 0.2),
          delay: Duration(milliseconds: i * 100),
          duration: const Duration(milliseconds: 600),
          amount: amount,
        ),
      );
    }
    notifyListeners();
  }

  /// Animate pot splitting into side pots visually.
  /// Chips spread from center pot to side pot positions (left/right of center).
  void splitPot({
    required Offset potCenter,
    required int mainPotAmount,
    required List<int> sidePotAmounts,
  }) {
    final rng = Random();
    final totalPots = sidePotAmounts.length + 1;

    // Side pot positions: spread horizontally from center
    for (int i = 0; i < sidePotAmounts.length; i++) {
      final offsetX =
          (i + 1) * 50.0 * (i.isEven ? 1 : -1); // alternate left/right
      final targetPos = Offset(potCenter.dx + offsetX, potCenter.dy + 25);
      final chipCount = sidePotAmounts[i] > 100 ? 4 : 3;

      for (int j = 0; j < chipCount; j++) {
        final rx = (rng.nextDouble() - 0.5) * 10;
        final ry = (rng.nextDouble() - 0.5) * 10;
        _animations.add(
          ChipAnimationData(
            id: _nextId++,
            start: Offset(potCenter.dx + rx, potCenter.dy + ry),
            end: Offset(targetPos.dx + rx * 0.5, targetPos.dy + ry * 0.5),
            delay: Duration(milliseconds: 200 + j * 80),
            duration: const Duration(milliseconds: 400),
            amount: sidePotAmounts[i],
          ),
        );
      }
    }
    notifyListeners();
  }

  /// Animate side pots distributing to their respective winners.
  /// Each side pot flies to its eligible winner with staggered timing.
  void sidePotToWinners({
    required Offset potCenter,
    required List<Map<String, dynamic>> sidePots,
    required Map<int, Offset> winnerPositions,
    required List<int> winnerSeats,
  }) {
    final rng = Random();
    int delayMs = 0;

    for (int i = 0; i < sidePots.length; i++) {
      final pot = sidePots[i];
      final amount = pot['amount'] as int? ?? 0;
      final eligibleSeats = List<int>.from(pot['eligibleSeats'] ?? []);

      // Find which winner gets this side pot
      final potWinners = winnerSeats
          .where((s) => eligibleSeats.contains(s))
          .toList();
      if (potWinners.isEmpty) continue;

      // Source position: offset from center based on pot index
      final offsetX = i == 0 ? 0.0 : i * 50.0 * (i.isEven ? 1 : -1);
      final fromPos = Offset(
        potCenter.dx + offsetX,
        potCenter.dy + (i > 0 ? 25 : 0),
      );

      // Distribute to each eligible winner
      final prizeEach = amount ~/ potWinners.length;
      for (final winnerSeat in potWinners) {
        final toPos = winnerPositions[winnerSeat];
        if (toPos == null) continue;

        final chipCount = prizeEach > 100 ? 5 : (prizeEach > 50 ? 4 : 3);
        for (int j = 0; j < chipCount; j++) {
          final rx = (rng.nextDouble() - 0.5) * 16;
          final ry = (rng.nextDouble() - 0.5) * 16;
          _animations.add(
            ChipAnimationData(
              id: _nextId++,
              start: Offset(fromPos.dx + rx, fromPos.dy + ry),
              end: Offset(toPos.dx + rx * 0.2, toPos.dy + ry * 0.2),
              delay: Duration(milliseconds: delayMs + j * 80),
              duration: const Duration(milliseconds: 600),
              amount: prizeEach,
            ),
          );
        }
      }
      delayMs += 500; // Stagger each side pot distribution
    }
    notifyListeners();
  }

  void removeAnimation(int id) {
    _animations.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void clear() {
    _animations.clear();
    notifyListeners();
  }
}

class ChipAnimationData {
  final int id;
  final Offset start;
  final Offset end;
  final Duration delay;
  final Duration duration;
  final int amount;

  const ChipAnimationData({
    required this.id,
    required this.start,
    required this.end,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 500),
    this.amount = 0,
  });
}

/// Overlay widget that renders all active chip animations.
class ChipAnimationOverlay extends StatelessWidget {
  final ChipAnimationController controller;

  const ChipAnimationOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.animations.isEmpty) return const SizedBox.shrink();
        return Stack(
          children: controller.animations.map((anim) {
            return FlyingChip(
              key: ValueKey(anim.id),
              start: anim.start,
              end: anim.end,
              delay: anim.delay,
              duration: anim.duration,
              amount: anim.amount,
              onComplete: () => controller.removeAnimation(anim.id),
            );
          }).toList(),
        );
      },
    );
  }
}

/// Animated chip count display that shows +/- with animation
class AnimatedChipCount extends StatelessWidget {
  final int amount;
  final bool isWin;

  const AnimatedChipCount({
    super.key,
    required this.amount,
    required this.isWin,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * -20),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isWin ? Colors.green.shade800 : Colors.red.shade900,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: (isWin ? Colors.greenAccent : Colors.red).withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChipIcon(amount: amount),
            const SizedBox(width: 4),
            Text(
              '${isWin ? "+" : "-"}$amount',
              style: TextStyle(
                color: isWin ? Colors.greenAccent : Colors.red.shade200,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
