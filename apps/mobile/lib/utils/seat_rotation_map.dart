/// Pure utility for rotating seat positions so the current player
/// appears at the bottom center of the screen.
class SeatRotationMap {
  /// Compute the visual position index for a given server seat number.
  ///
  /// [mySeat] — the current player's server-assigned seat (1-based).
  /// [serverSeat] — the seat to map to a visual position.
  /// [maxSeats] — total seats at the table.
  /// [bottomCenterIndex] — the visual index that represents bottom center.
  static int toVisualIndex({
    required int mySeat,
    required int serverSeat,
    required int maxSeats,
    int bottomCenterIndex = 6,
  }) {
    return (serverSeat - mySeat + bottomCenterIndex) % maxSeats;
  }

  /// Get the server seat number for a given visual position index.
  /// Inverse of [toVisualIndex].
  static int toServerSeat({
    required int mySeat,
    required int visualIndex,
    required int maxSeats,
    int bottomCenterIndex = 6,
  }) {
    final raw = (visualIndex - bottomCenterIndex + mySeat) % maxSeats;
    // Convert to 1-based: if raw == 0, it means seat maxSeats
    return raw == 0 ? maxSeats : raw;
  }
}
