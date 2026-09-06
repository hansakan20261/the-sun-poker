import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';

/// Dedicated confirmation button for slider bets.
///
/// Displays "ยืนยันเดิมพัน X" with formatted amount.
/// Requirements: 17.2, 17.3, 17.4
class BetConfirmButton extends StatelessWidget {
  final int amount;
  final VoidCallback onConfirm;

  const BetConfirmButton({
    super.key,
    required this.amount,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final label =
        '${ThaiLabels.confirmBet} ${NumberFormatter.formatWithCommas(amount)}';

    return GestureDetector(
      onTap: onConfirm,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1565C0), Color(0xFF082E6A)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1565C0).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
