import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/seat_rotation_map.dart';
import '../models/seat_reservation.dart';
import 'reservation_label.dart';

/// Data class for a seated player.
class PlayerInfo {
  final String id;
  final String username;
  final String? countryFlag;
  final int chipCount;
  final String? avatarUrl;

  const PlayerInfo({
    required this.id,
    required this.username,
    this.countryFlag,
    required this.chipCount,
    this.avatarUrl,
  });
}

/// Oval table overlay showing all seat positions.
/// Occupied seats show player info; empty seats are tappable.
/// Task 7.1: Pulsing opacity on empty seats (Req 4.3, 10.2)
/// Task 7.2: Scale-up feedback on seat tap (Req 4.5, 10.3)
class SeatSelectionOverlay extends StatefulWidget {
  final Map<int, PlayerInfo?> seats;
  final int maxSeats;
  final Function(int seatNumber) onSeatSelected;
  // Task 13.1: Reservation and rotation support
  final int? mySeat; // For rotation; null if not yet seated
  final Map<int, SeatReservation> reservations;
  final String? currentUserId;
  final Function(int seatNumber)? onSeatReserve;
  final Function(int seatNumber)? onReservationCancel;

  const SeatSelectionOverlay({
    super.key,
    required this.seats,
    required this.maxSeats,
    required this.onSeatSelected,
    this.mySeat,
    this.reservations = const {},
    this.currentUserId,
    this.onSeatReserve,
    this.onReservationCancel,
  });

  @override
  State<SeatSelectionOverlay> createState() => _SeatSelectionOverlayState();
}

class _SeatSelectionOverlayState extends State<SeatSelectionOverlay>
    with TickerProviderStateMixin {
  // Task 7.1: Pulsing animation controller
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Task 7.2: Scale-up feedback
  int? _tappedSeat;
  late AnimationController _tapScaleController;
  late Animation<double> _tapScaleAnimation;

  @override
  void initState() {
    super.initState();
    // Pulsing opacity: 0.4 → 1.0 over 1000ms, repeating (Req 10.2)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Scale-up: 1.0 → 1.2 → 1.0 over 300ms (Req 10.3)
    _tapScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _tapScaleAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 50),
          TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 50),
        ]).animate(
          CurvedAnimation(parent: _tapScaleController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tapScaleController.dispose();
    super.dispose();
  }

  void _onSeatTap(int seatNum) async {
    // Check if seat is already reserved by another player
    final reservation = widget.reservations[seatNum];
    if (reservation != null &&
        reservation.reservedByUserId != widget.currentUserId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ที่นั่งนี้ถูกจองแล้ว'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    // Check if seat is occupied
    if (widget.seats[seatNum] != null) return;

    setState(() => _tappedSeat = seatNum);
    _tapScaleController.forward(from: 0);
    await _tapScaleController.forward();
    // Task 13.1: Emit seat:reserve event instead of immediate join
    if (widget.onSeatReserve != null) {
      widget.onSeatReserve!(seatNum);
    } else {
      if (mounted) widget.onSeatSelected(seatNum);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text(
              'เลือกที่นั่ง',
              style: TextStyle(
                color: SunTheme.goldLight,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'แตะที่นั่งว่างเพื่อนั่ง',
              style: TextStyle(
                color: SunTheme.gold.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildTable(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final cx = w / 2;
        final cy = h / 2;
        final rx = w * 0.38;
        final ry = h * 0.34;

        return Stack(
          children: [
            // Oval table background
            Center(
              child: Container(
                width: rx * 2 + 20,
                height: ry * 2 + 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ry + 10),
                  gradient: const RadialGradient(
                    colors: [
                      Color(0xFF8B0000),
                      Color(0xFF5C0000),
                      Color(0xFF3A0000),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFFDAA520).withOpacity(0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'THE SUN POKER',
                    style: TextStyle(
                      color: const Color(0xFFDAA520).withOpacity(0.15),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
            ),
            // Seat positions arranged in oval
            for (int i = 1; i <= widget.maxSeats; i++)
              _buildSeatAt(i, cx, cy, rx, ry),
          ],
        );
      },
    );
  }

  Widget _buildSeatAt(int seatNum, double cx, double cy, double rx, double ry) {
    // Task 13.1: Apply SeatRotationMap for visual positioning
    final visualIndex = widget.mySeat != null && widget.mySeat! > 0
        ? SeatRotationMap.toVisualIndex(
            mySeat: widget.mySeat!,
            serverSeat: seatNum,
            maxSeats: widget.maxSeats,
            bottomCenterIndex: widget.maxSeats > 6 ? 6 : widget.maxSeats - 2,
          )
        : seatNum - 1;
    final angle = -math.pi / 2 + (2 * math.pi * visualIndex / widget.maxSeats);
    final x = cx + rx * math.cos(angle) - 34;
    final y = cy + ry * math.sin(angle) - 40;
    final player = widget.seats[seatNum];
    final reservation = widget.reservations[seatNum];

    return Positioned(
      left: x,
      top: y,
      child: player != null
          ? _occupiedSeat(player, seatNum)
          : reservation != null
          ? _reservedSeat(reservation, seatNum)
          : _emptySeat(seatNum),
    );
  }

  // Task 13.1: Reserved seat display with ReservationLabel
  Widget _reservedSeat(SeatReservation reservation, int seatNum) {
    final isMyReservation =
        widget.currentUserId != null &&
        reservation.reservedByUserId == widget.currentUserId;
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black26,
              border: Border.all(color: Colors.amber, width: 2),
            ),
            child: const Icon(
              Icons.person_outline,
              color: Colors.amber,
              size: 20,
            ),
          ),
          const SizedBox(height: 2),
          ReservationLabel(
            remainingSeconds: reservation.remainingSeconds,
            isMyReservation: isMyReservation,
            onCancel: isMyReservation && widget.onReservationCancel != null
                ? () => widget.onReservationCancel!(seatNum)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _occupiedSeat(PlayerInfo player, int seatNum) {
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SunTheme.goldLight, width: 2),
              color: const Color(0xFF2A0A0A),
              image: player.avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(player.avatarUrl!),
                      fit: BoxFit.cover,
                    )
                  : const DecorationImage(
                      image: AssetImage('assets/logo.png'),
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(height: 2),
          if (player.countryFlag != null)
            Text(player.countryFlag!, style: const TextStyle(fontSize: 12)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                Text(
                  player.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'C${player.chipCount}',
                  style: TextStyle(color: SunTheme.goldLight, fontSize: 7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySeat(int seatNum) {
    final isTapped = _tappedSeat == seatNum;
    return GestureDetector(
      onTap: () => _onSeatTap(seatNum),
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnimation, _tapScaleAnimation]),
        builder: (_, __) {
          final scale = isTapped ? _tapScaleAnimation.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 68,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green.withOpacity(0.15),
                      border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.7),
                        width: 2,
                      ),
                    ),
                    // Task 7.1: Pulsing opacity on "+" icon (Req 4.3, 10.2)
                    child: Opacity(
                      opacity: _pulseAnimation.value,
                      child: const Icon(
                        Icons.add,
                        color: Colors.greenAccent,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Seat $seatNum',
                      style: TextStyle(
                        color: Colors.greenAccent.withOpacity(0.7),
                        fontSize: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({
    super.key,
    required Listenable animation,
    required this.builder,
  }) : super(listenable: animation);
  @override
  Widget build(BuildContext context) => builder(context, null);
}
