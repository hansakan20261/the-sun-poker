import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/thai_labels.dart';

/// Horizontal progress bar showing current step / total steps for hand replay.
///
/// Requirements: 1.7
class ReplayTimeline extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const ReplayTimeline({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalSteps > 0 ? (currentStep + 1) / totalSteps : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Step counter label
        Text(
          '${ThaiLabels.step} ${currentStep + 1} / $totalSteps',
          style: TextStyle(
            color: SunTheme.gold,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(SunTheme.goldLight),
          ),
        ),
      ],
    );
  }
}
