import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/thai_labels.dart';

/// Seat reservation status with countdown timer.
///
/// Displays "จองแล้ว" with countdown, amber border styling,
/// "ยกเลิก" button for player's own reservation, timeout handling.
/// Requirements: 12.1, 12.2, 12.3, 12.4, 13.1, 13.2, 14.1, 14.2
class ReservationLabel extends StatefulWidget {
  final int remainingSeconds;
  final bool isMyReservation;
  final VoidCallback? onCancel;
  final VoidCallback? onTimeout;

  const ReservationLabel({
    super.key,
    required this.remainingSeconds,
    required this.isMyReservation,
    this.onCancel,
    this.onTimeout,
  });

  @override
  State<ReservationLabel> createState() => _ReservationLabelState();
}

class _ReservationLabelState extends State<ReservationLabel> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.remainingSeconds;
    _startTimer();
  }

  @override
  void didUpdateWidget(ReservationLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remainingSeconds != widget.remainingSeconds) {
      _secondsLeft = widget.remainingSeconds;
      _timer?.cancel();
      _startTimer();
    }
  }

  void _startTimer() {
    if (_secondsLeft <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
      });
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        widget.onTimeout?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "จองแล้ว" label
          const Text(
            ThaiLabels.reserved,
            style: TextStyle(
              color: Colors.amber,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          // Countdown
          Text(
            '${_secondsLeft}s',
            style: TextStyle(
              color: _secondsLeft <= 5 ? Colors.redAccent : Colors.amber,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          // Cancel button (only for own reservation)
          if (widget.isMyReservation && widget.onCancel != null) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: const Text(
                  ThaiLabels.cancel,
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
