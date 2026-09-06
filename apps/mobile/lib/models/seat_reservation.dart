/// Seat reservation state received from the game state WebSocket.
class SeatReservation {
  final int seatNumber;
  final String? reservedByUserId;
  final int remainingSeconds;

  const SeatReservation({
    required this.seatNumber,
    required this.reservedByUserId,
    required this.remainingSeconds,
  });
}
