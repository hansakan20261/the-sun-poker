import 'package:flutter/material.dart';
import '../utils/free_tips_engine.dart';
import '../utils/thai_labels.dart';

/// Color-coded game guide badge above the betting panel.
/// Green for strong, yellow for medium, red for weak.
class RecommendationBadge extends StatelessWidget {
  final HandStrengthCategory category;
  final String explanationTh;

  const RecommendationBadge({
    super.key,
    required this.category,
    required this.explanationTh,
  });

  @override
  Widget build(BuildContext context) {
    final color = FreeTipsEngine.getRecommendationColor(category);
    final icon = _iconForCategory(category);

    return Container(
      constraints: const BoxConstraints(maxHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            explanationTh,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForCategory(HandStrengthCategory cat) {
    switch (cat) {
      case HandStrengthCategory.strong:
        return Icons.trending_up;
      case HandStrengthCategory.medium:
        return Icons.trending_flat;
      case HandStrengthCategory.weak:
        return Icons.trending_down;
    }
  }
}
