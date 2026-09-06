import 'package:flutter/material.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';

/// Persistent banner displaying "ทดลองเล่น" in distinct color.
class PracticeLabel extends StatelessWidget {
  final int demoChips;

  const PracticeLabel({super.key, required this.demoChips});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8C00), Color(0xFFFF6600)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.science, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            '${ThaiLabels.practicePrefix}: C${NumberFormatter.formatWithCommas(demoChips)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
