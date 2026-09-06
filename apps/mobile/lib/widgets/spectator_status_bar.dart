import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';

/// Bottom bar replacing BettingPanel during spectator mode.
/// Shows "รอเล่นรอบถัดไป..." and optional "Post Behind" button.
class SpectatorStatusBar extends StatelessWidget {
  final int bigBlindAmount;
  final int playerChips;
  final bool handInProgress;
  final VoidCallback onPostBehind;

  const SpectatorStatusBar({
    super.key,
    required this.bigBlindAmount,
    required this.playerChips,
    required this.handInProgress,
    required this.onPostBehind,
  });

  bool get _canPostBehind => playerChips >= bigBlindAmount && handInProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        border: Border(
          top: BorderSide(
            color: const Color(0xFFDAA520).withOpacity(0.4),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status text
            Text(
              ThaiLabels.waitingForNextRound,
              style: TextStyle(color: SunTheme.goldLight, fontSize: 12),
            ),
            const SizedBox(height: 8),
            // Post Behind button
            if (handInProgress)
              GestureDetector(
                onTap: _canPostBehind
                    ? onPostBehind
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ThaiLabels.insufficientChips),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _canPostBehind
                        ? const Color(0xFF2E7D32)
                        : Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${ThaiLabels.postBehind} C${NumberFormatter.formatWithCommas(bigBlindAmount)}',
                    style: TextStyle(
                      color: _canPostBehind ? Colors.white : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
