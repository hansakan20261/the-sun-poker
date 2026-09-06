import '../models/split_result.dart';

/// Pure utility for dividing pots among tied winners and determining
/// the odd chip recipient.
class SplitPotCalculator {
  /// Divide [pot] equally among [winnerSeats]. The odd chip (if any)
  /// goes to the first winner clockwise from [dealerSeat].
  ///
  /// [maxSeats] is the table size used for clockwise calculation.
  static SplitResult calculate({
    required int pot,
    required List<int> winnerSeats,
    required int dealerSeat,
    required int maxSeats,
  }) {
    if (winnerSeats.isEmpty) {
      return const SplitResult(
        shares: {},
        oddChipRecipient: null,
        totalDistributed: 0,
      );
    }

    if (winnerSeats.length == 1) {
      return SplitResult(
        shares: {winnerSeats.first: pot},
        oddChipRecipient: null,
        totalDistributed: pot,
      );
    }

    final baseShare = pot ~/ winnerSeats.length;
    final remainder = pot % winnerSeats.length;

    final shares = <int, int>{};
    int? oddRecipient;

    if (remainder > 0) {
      oddRecipient = findOddChipRecipient(
        winnerSeats: winnerSeats,
        dealerSeat: dealerSeat,
        maxSeats: maxSeats,
      );
    }

    for (final seat in winnerSeats) {
      shares[seat] = baseShare + (seat == oddRecipient ? remainder : 0);
    }

    return SplitResult(
      shares: shares,
      oddChipRecipient: oddRecipient,
      totalDistributed: pot,
    );
  }

  /// Find the first winner seat clockwise from the dealer.
  ///
  /// Iterates seats starting from (dealerSeat + 1) wrapping around,
  /// and returns the first seat found in [winnerSeats].
  static int findOddChipRecipient({
    required List<int> winnerSeats,
    required int dealerSeat,
    required int maxSeats,
  }) {
    final winnerSet = winnerSeats.toSet();
    for (var i = 1; i <= maxSeats; i++) {
      final seat = (dealerSeat % maxSeats) + i;
      // Seats are 1-based: convert modular result to 1-based
      final normalised = ((seat - 1) % maxSeats) + 1;
      if (winnerSet.contains(normalised)) {
        return normalised;
      }
    }
    // Fallback — should never happen if winnerSeats is non-empty
    return winnerSeats.first;
  }
}
