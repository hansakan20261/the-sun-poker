import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<dynamic> _friends = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/profile/friends');
      setState(() => _friends = data['friends'] ?? []);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('👫 เพื่อน')),
      body: _friends.isEmpty
          ? Center(
              child: Text(
                'ยังไม่มีเพื่อน',
                style: TextStyle(color: SunTheme.gold.withOpacity(0.4)),
              ),
            )
          : ListView.builder(
              itemCount: _friends.length,
              itemBuilder: (_, i) {
                final f = _friends[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: SunTheme.gold,
                    child: Text(
                      (f['display_name'] ?? f['username'] ?? '?')[0]
                          .toUpperCase(),
                      style: TextStyle(
                        color: SunTheme.redDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    f['display_name'] ?? f['username'],
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '@${f['username']}',
                    style: TextStyle(color: SunTheme.gold.withOpacity(0.5)),
                  ),
                  trailing: const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white54,
                  ),
                );
              },
            ),
    );
  }
}
