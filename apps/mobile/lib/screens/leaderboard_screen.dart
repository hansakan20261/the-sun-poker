import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<dynamic> _leaderboard = [];
  String _tab = 'global';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/leaderboard/$_tab');
      setState(() => _leaderboard = data['leaderboard'] ?? []);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🏆 Leaderboard')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _tabBtn('global', '💰 เหรียญ'),
                const SizedBox(width: 8),
                _tabBtn('wins', '🏆 ชนะ'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _leaderboard.length,
              itemBuilder: (_, i) {
                final p = _leaderboard[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: i < 3 ? SunTheme.gold : SunTheme.redDark,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    p['display_name'] ?? p['username'],
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: Text(
                    _tab == 'global'
                        ? '${p['balance']} ชิป'
                        : '${p['total_wins']} wins',
                    style: TextStyle(
                      color: SunTheme.goldLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String key, String label) => Expanded(
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _tab == key ? SunTheme.red : SunTheme.black,
      ),
      onPressed: () {
        setState(() => _tab = key);
        _load();
      },
      child: Text(label, style: const TextStyle(fontSize: 13)),
    ),
  );
}
