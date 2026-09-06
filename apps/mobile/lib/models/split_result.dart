/// Result of a split pot calculation.
class SplitResult {
  /// Seat number → chip amount awarded.
  final Map<int, int> shares;

  /// Seat that receives the extra odd chip, or null if evenly divisible.
  final int? oddChipRecipient;

  /// Sum of all shares (must equal the original pot).
  final int totalDistributed;

  const SplitResult({
    required this.shares,
    required this.oddChipRecipient,
    required this.totalDistributed,
  });
}
