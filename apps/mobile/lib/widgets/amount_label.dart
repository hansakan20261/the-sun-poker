import 'package:flutter/material.dart';
import '../utils/number_formatter.dart';
import '../utils/showdown_anim_config.dart';

/// Animated win/loss amount label displayed next to player avatars.
/// Winner: green "+CX" with scale-up (elastic-out). Loser: red "-CX" with fade-in.
class AmountLabelWidget extends StatefulWidget {
  final int amount;
  final bool isWinner;
  final Duration animationDuration;

  const AmountLabelWidget({
    super.key,
    required this.amount,
    required this.isWinner,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<AmountLabelWidget> createState() => _AmountLabelWidgetState();
}

class _AmountLabelWidgetState extends State<AmountLabelWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _scaleAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefix = widget.isWinner ? '+' : '-';
    final color = widget.isWinner ? Colors.greenAccent : Colors.redAccent;
    final text =
        '${prefix}${NumberFormatter.formatWithCommas(widget.amount.abs())}';

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final value = widget.isWinner ? _scaleAnim.value : _fadeAnim.value;
        return widget.isWinner
            ? Transform.scale(
                scale: value.clamp(0.0, 1.5),
                child: _label(text, color),
              )
            : Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: _label(text, color),
              );
      },
    );
  }

  Widget _label(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
    );
  }
}

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
