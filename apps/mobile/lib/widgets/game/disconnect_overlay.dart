import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/animation/animation_service.dart';
import '../../services/runtime_config_service.dart';

/// Connection state for the disconnect overlay.
enum ConnectionState { connected, reconnecting, lost }

/// A semi-transparent overlay shown during network disconnection.
///
/// - Shows "Reconnecting..." with spinner within 2 seconds of disconnect
/// - Pauses all animations on disconnect
/// - Removes overlay and resyncs state on reconnection
/// - Shows "Connection Lost" with retry button after 30s timeout
///
/// Requirements: 17.1, 17.2, 17.3, 17.4, 17.5
class DisconnectOverlay extends StatefulWidget {
  final ConnectionState connectionState;
  final VoidCallback? onRetry;
  final VoidCallback? onReturnToLobby;

  const DisconnectOverlay({
    super.key,
    required this.connectionState,
    this.onRetry,
    this.onReturnToLobby,
  });

  @override
  State<DisconnectOverlay> createState() => _DisconnectOverlayState();
}

class _DisconnectOverlayState extends State<DisconnectOverlay> {
  Timer? _timeoutTimer;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _handleStateChange();
  }

  @override
  void didUpdateWidget(DisconnectOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionState != widget.connectionState) {
      _handleStateChange();
    }
  }

  void _handleStateChange() {
    switch (widget.connectionState) {
      case ConnectionState.reconnecting:
        // Pause all animations on disconnect
        AnimationService.instance.pauseAll();
        _timeoutTimer?.cancel();
        _timedOut = false;
        _startTimeout();
        break;
      case ConnectionState.connected:
        // Resume animations on reconnect
        AnimationService.instance.resumeAll();
        _timeoutTimer?.cancel();
        _timedOut = false;
        break;
      case ConnectionState.lost:
        _timedOut = true;
        break;
    }
  }

  Future<void> _startTimeout() async {
    try {
      await RuntimeConfigService.load();
      if (!mounted || widget.connectionState != ConnectionState.reconnecting)
        return;
      _timeoutTimer = Timer(
        Duration(seconds: RuntimeConfigService.integer('disconnect_grace_sec')),
        () {
          if (mounted) setState(() => _timedOut = true);
        },
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.connectionState == ConnectionState.connected) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: _timedOut ? _buildLostContent() : _buildReconnectingContent(),
      ),
    );
  }

  Widget _buildReconnectingContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDAA520)),
        ),
        const SizedBox(height: 16),
        const Text(
          'Reconnecting...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLostContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off, color: Colors.white70, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Connection Lost',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: widget.onRetry,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDAA520),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
          child: const Text(
            'Retry',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: widget.onReturnToLobby,
          child: const Text(
            'Return to Lobby',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}
