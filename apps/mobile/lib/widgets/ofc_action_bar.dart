import 'package:flutter/material.dart';

import '../utils/thai_labels.dart';
import 'sun_button.dart';

/// OFC-specific action bar with Confirm and Reset buttons.
///
/// Requirements: 28.1, 28.2, 28.8
class OFCActionBar extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onReset;
  final bool canConfirm;

  const OFCActionBar({
    super.key,
    required this.onConfirm,
    required this.onReset,
    required this.canConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Reset button (red)
          Expanded(
            child: SunButton.red(
              label: ThaiLabels.reset,
              onTap: onReset,
              height: 50,
            ),
          ),
          const SizedBox(width: 12),
          // Confirm button (green)
          Expanded(
            child: SunButton.green(
              label: ThaiLabels.confirmAction,
              onTap: canConfirm ? onConfirm : null,
              height: 50,
            ),
          ),
        ],
      ),
    );
  }
}
