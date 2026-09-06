import 'package:flutter/material.dart';
import '../models/split_result.dart';
import '../theme.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';

/// Overlay annotation for split pot results.
///
/// Shows "แบ่งกองกลาง" label, each winner's name and share,
/// "+1 เศษ" annotation on odd chip recipient, winning hand name in Thai.
/// Requirements: 6.1, 6.2, 6.3, 6.4
class SplitPotDisplay extends StatelessWidget {
  final SplitResult splitResult;
  final Map<int, String> playerNames;
  final String winningHandNameTh;

  const SplitPotDisplay({
    super.key,
    required this.splitResult,
    required this.playerNames,
    required this.winningHandNameTh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SunTheme.gold.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "แบ่งกองกลาง" header
          Text(
            ThaiLabels.splitPot,
            style: const TextStyle(
              color: SunTheme.goldLight,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          // Winning hand name
          if (winningHandNameTh.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                winningHandNameTh,
                style: TextStyle(
                  color: SunTheme.gold.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
            ),
          // Per-winner shares
          ...splitResult.shares.entries.map((entry) {
            final seat = entry.key;
            final share = entry.value;
            final name = playerNames[seat] ?? 'Seat $seat';
            final isOddRecipient = seat == splitResult.oddChipRecipient;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    NumberFormatter.formatWithCommas(share),
                    style: const TextStyle(
                      color: SunTheme.goldLight,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isOddRecipient) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+1 ${ThaiLabels.oddChip}',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
