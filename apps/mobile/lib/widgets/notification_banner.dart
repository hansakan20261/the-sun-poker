import 'package:flutter/material.dart';

import '../theme.dart';

/// Dismissible notification banner for the lobby screen.
///
/// Displays a message with an optional tap action and dismiss button.
/// Fade-out dismiss animation over 300ms.
///
/// Requirements: 8.1-8.5
class NotificationBanner extends StatefulWidget {
  final String message;
  final String severity;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const NotificationBanner({
    super.key,
    required this.message,
    required this.severity,
    this.onTap,
    this.onDismiss,
  });

  @override
  State<NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<NotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _controller.forward().then((_) {
      if (mounted) {
        widget.onDismiss?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWarning =
        widget.severity == 'warning' || widget.severity == 'maintenance';
    final accent = isWarning ? Colors.orangeAccent : SunTheme.gold;
    final icon = widget.severity == 'maintenance'
        ? Icons.build_circle_outlined
        : isWarning
        ? Icons.warning_amber_outlined
        : Icons.info_outline;
    return FadeTransition(
      opacity: _opacity,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              GestureDetector(
                onTap: _dismiss,
                child: const Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
