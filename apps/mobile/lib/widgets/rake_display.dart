import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';

/// Rake amount label shown near pot display during result phase.
///
/// Shows "เรค: X" with comma-formatted amount. Hidden when rake is 0.
/// On tap, shows tooltip "เรค: X% (สูงสุด Y)".
/// Requirements: 7.1, 7.2, 7.3, 7.4, 8.1, 8.2, 8.3
class RakeDisplay extends StatefulWidget {
  final int rakeAmount;
  final double rakePercent;
  final int rakeCap;

  const RakeDisplay({
    super.key,
    required this.rakeAmount,
    required this.rakePercent,
    required this.rakeCap,
  });

  @override
  State<RakeDisplay> createState() => _RakeDisplayState();
}

class _RakeDisplayState extends State<RakeDisplay> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();

  void _showTooltip() {
    _overlayController.show();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _overlayController.isShowing) {
        _overlayController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rakeAmount <= 0) return const SizedBox.shrink();

    final label =
        '${ThaiLabels.rake}: ${NumberFormatter.formatWithCommas(widget.rakeAmount)}';

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (_) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -4),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A).withOpacity(0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SunTheme.gold.withOpacity(0.4)),
              ),
              child: Text(
                ThaiLabels.rakeTooltip(widget.rakePercent, widget.rakeCap),
                style: const TextStyle(color: SunTheme.goldLight, fontSize: 11),
              ),
            ),
          ),
        ),
        child: GestureDetector(
          onTap: _showTooltip,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: SunTheme.gold.withOpacity(0.2)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: SunTheme.gold.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
