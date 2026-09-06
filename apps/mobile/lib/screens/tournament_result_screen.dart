import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';

class TournamentResultScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;
  const TournamentResultScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
  });
  @override
  State<TournamentResultScreen> createState() => _TournamentResultScreenState();
}

class _TournamentResultScreenState extends State<TournamentResultScreen> {
  Map<String, dynamic>? _tournament;
  List<dynamic> _players = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get(
        '/poker/tournaments/${widget.tournamentId}',
      );
      setState(() {
        _tournament = data['tournament'];
        _players = data['players'] ?? [];
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset('assets/tournament_bg.png', fit: BoxFit.cover),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Back button
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.black38,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Cup
                Image.asset(
                  'assets/cup_tournament.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 4),
                // Title
                Text(
                  widget.tournamentName,
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 8,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Content
                Expanded(
                  child: _tournament == null
                      ? const Center(child: CircularProgressIndicator())
                      : _buildContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final bottomPad = MediaQuery.of(context).padding.bottom + 20;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
      children: [
        // Tournament info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0E0E0E).withOpacity(0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SunTheme.gold.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Text(
                '${_tournament!['game'] ?? 'texas_holdem'} | ${_tournament!['type'] ?? 'sit_and_go'}',
                style: TextStyle(
                  color: SunTheme.gold.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _infoChip('Buy-in', '${_tournament!['buy_in']}'),
                  _infoChip('เงินรางวัล', '${_tournament!['prize_pool']}'),
                  _infoChip('ผู้เล่น', '${_players.length}'),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _tournament!['status'] == 'finished'
                      ? SunTheme.green
                      : Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _tournament!['status'] == 'finished'
                      ? '🏁 จบแล้ว'
                      : _tournament!['status'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Leaderboard header
        Row(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Text(
              'อันดับผู้เล่น',
              style: TextStyle(
                color: SunTheme.goldLight,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Player list
        ..._players.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final pos =
              int.tryParse(p['finish_rank']?.toString() ?? '') ?? (i + 1);
          final prize = int.tryParse(p['prize']?.toString() ?? '') ?? 0;
          final isTop3 = pos <= 3;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isTop3
                  ? const Color(0xFF2A2A2A).withOpacity(0.95)
                  : const Color(0xFF1E1E1E).withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isTop3
                    ? SunTheme.goldLight.withOpacity(0.5)
                    : Colors.grey.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                // Position badge
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pos == 1
                        ? Colors.amber
                        : pos == 2
                        ? Colors.grey.shade400
                        : pos == 3
                        ? Colors.brown.shade400
                        : const Color(0xFF1A1A1A),
                    boxShadow: isTop3
                        ? [
                            BoxShadow(
                              color: (pos == 1 ? Colors.amber : Colors.grey)
                                  .withOpacity(0.3),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$pos',
                      style: TextStyle(
                        color: pos <= 3 ? Colors.black : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Avatar
                CircleAvatar(
                  radius: 18,
                  backgroundColor: SunTheme.gold.withOpacity(0.2),
                  child: Text(
                    (p['display_name'] ?? p['username'] ?? '?')[0]
                        .toUpperCase(),
                    style: TextStyle(
                      color: SunTheme.goldLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Name + status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['display_name'] ?? p['username'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        p['status'] == 'eliminated'
                            ? 'ตกรอบ'
                            : p['status'] ?? '',
                        style: TextStyle(
                          color: p['status'] == 'eliminated'
                              ? Colors.redAccent.withOpacity(0.7)
                              : SunTheme.gold.withOpacity(0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Prize
                if (prize > 0)
                  Text(
                    '+$prize ชิป',
                    style: const TextStyle(
                      color: Color(0xFF4ADE80),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  )
                else
                  Text(
                    '${int.tryParse(p['chip_count']?.toString() ?? '') ?? 0}',
                    style: TextStyle(
                      color: SunTheme.gold.withOpacity(0.4),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _infoChip(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: SunTheme.goldLight,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: SunTheme.gold.withOpacity(0.4), fontSize: 11),
        ),
      ],
    );
  }
}
