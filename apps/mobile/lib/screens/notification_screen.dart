import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/runtime_config_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<dynamic> _notifications = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  Future<void> _startPolling() async {
    try {
      await RuntimeConfigService.load();
      if (!mounted || RuntimeConfigService.value('in_app_enabled') != true)
        return;
      await _load();
      _pollTimer = Timer.periodic(
        Duration(
          seconds: RuntimeConfigService.integer(
            'notification_poll_interval_sec',
          ),
        ),
        (_) => _load(),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/notifications');
      if (mounted) setState(() => _notifications = data['notifications'] ?? []);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NOTIFICATION'),
        backgroundColor: SunTheme.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)],
          ),
        ),
        child: _notifications.isEmpty
            ? Center(
                child: Text(
                  'THERE IS NO ONLINE NOTIFICATION RIGHT NOW!',
                  style: TextStyle(
                    color: SunTheme.gold.withOpacity(0.3),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.builder(
                itemCount: _notifications.length,
                itemBuilder: (_, i) {
                  final n = _notifications[i];
                  return ListTile(
                    leading: Icon(
                      Icons.notifications,
                      color: n['is_read']
                          ? SunTheme.gold.withOpacity(0.3)
                          : SunTheme.goldLight,
                    ),
                    title: Text(
                      n['title'],
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    subtitle: Text(
                      n['message'] ?? '',
                      style: TextStyle(
                        color: SunTheme.gold.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
