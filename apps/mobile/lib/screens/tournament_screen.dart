import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../widgets/app_background.dart';
import 'tournament_result_screen.dart';
import 'tournament_detail_screen.dart';

class TournamentScreen extends StatefulWidget {
  final bool isEmbedded;
  const TournamentScreen({super.key, this.isEmbedded = false});
  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  List<dynamic> _tournaments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/poker/tournaments');
      if (mounted)
        setState(() {
          _tournaments = data['tournaments'] ?? [];
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register(String id) async {
    try {
      final result = await ApiService.post(
        '/poker/tournaments/$id/register',
        {},
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'สมัครสำเร็จ! ได้รับ ${result['starting_chips']} ชิป',
            ),
            backgroundColor: Colors.green,
          ),
        );
      _load();
    } catch (e) {
      String msg = '$e';
      if (msg.contains('Already registered'))
        msg = 'คุณสมัครรายการนี้แล้ว';
      else if (msg.contains('Insufficient balance'))
        msg = 'เหรียญไม่เพียงพอ';
      else if (msg.contains('Tournament full'))
        msg = 'รายการเต็มแล้ว';
      else if (msg.contains('Registration closed'))
        msg = 'ปิดรับสมัครแล้ว';
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Stack(
          children: [
            // Red glow at top
            Positioned(
              top: -80,
              left: 0,
              right: 0,
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF8B0000).withOpacity(0.2),
                      Colors.transparent,
                    ],
                    radius: 0.9,
                  ),
                ),
              ),
            ),
            // Content
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Back button
                  if (!widget.isEmbedded)
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
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                ),
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
                  // Scrollable content
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      color: const Color(0xFFFFD700),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
                        child: Column(
                          children: [
                            // Cup image
                            Image.asset(
                              'assets/cup_tournament.png',
                              height: 170,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.emoji_events,
                                color: Color(0xFFFFD700),
                                size: 100,
                              ),
                            ),
                            // Title
                            ShaderMask(
                              shaderCallback: (b) => const LinearGradient(
                                colors: [
                                  Color(0xFFFFE082),
                                  Color(0xFFFFD700),
                                  Color(0xFFDAA520),
                                  Color(0xFFB8860B),
                                ],
                              ).createShader(b),
                              child: const Text(
                                'TOURNAMENT',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 10,
                                      offset: Offset(2, 3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Tournament list inside dark board
                            _buildTournamentBoard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTournamentBoard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
      decoration: SunTheme.cardDecoration(
        radius: 16,
        bgColor: const Color(0xFF0D0D0D),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFFFD700),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'รายการแข่งขัน (${_tournaments.length})',
                  style: TextStyle(
                    color: const Color(0xFFFFD700).withOpacity(0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Content
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFFD700)),
              ),
            )
          else if (_tournaments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 48,
                      color: SunTheme.gold.withOpacity(0.15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ยังไม่มีรายการแข่ง',
                      style: TextStyle(color: SunTheme.gold.withOpacity(0.25)),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._tournaments.map((t) => _buildTournamentCard(t)),
        ],
      ),
    );
  }

  Widget _buildTournamentCard(dynamic t) {
    final status = t['status'] ?? '';
    final isOpen = status == 'registration';
    final isFinished = status == 'finished';
    final isLive = status == 'running' || status == 'final_table';
    final name = t['name'] ?? '';
    final buyIn = toInt(t['buy_in']);
    final entryFee = toInt(t['entry_fee']);
    final prizePool = toInt(t['prize_pool']);
    final playerCount = toInt(t['registered_count']);
    final maxPlayers = toInt(t['max_players']);
    final type = t['type'] ?? 'sit_and_go';
    final startingChips = toInt(t['starting_chips']);

    String typeLabel = type == 'sit_and_go'
        ? 'ซิท แอนด์ โก'
        : type == 'scheduled'
        ? 'ตามเวลา'
        : 'หลายโต๊ะ';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TournamentDetailScreen(tournamentId: t['id']),
        ),
      ).then((_) => _load()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: SunTheme.cardDecoration(
          radius: 14,
          bgColor: const Color(0xFF120404),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            children: [
              // Top highlight
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Row(
                  children: [
                    // Trophy icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFF3A1212), Color(0xFF1A0606)],
                        ),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withOpacity(0.2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withOpacity(0.08),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFFFD700),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            typeLabel,
                            style: TextStyle(
                              color: const Color(0xFFDAA520).withOpacity(0.5),
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'ค่าสมัคร: $buyIn + $entryFee | รางวัล: $prizePool',
                            style: TextStyle(
                              color: const Color(0xFFDAA520).withOpacity(0.45),
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'ผู้เล่น: $playerCount / $maxPlayers | ชิป: $startingChips',
                            style: TextStyle(
                              color: const Color(0xFFDAA520).withOpacity(0.45),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Action button
                    _buildActionButton(t, isOpen, isFinished, isLive),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    dynamic t,
    bool isOpen,
    bool isFinished,
    bool isLive,
  ) {
    if (isOpen) {
      return GestureDetector(
        onTap: () => _register(t['id']),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFCC2222), Color(0xFF8B0000), Color(0xFF5C0000)],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.12),
                width: 0.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B0000).withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 4,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Text(
            'สมัคร',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.5,
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
        ),
      );
    }
    if (isFinished) {
      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TournamentResultScreen(
              tournamentId: t['id'],
              tournamentName: t['name'],
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2E8B57), Color(0xFF1E6B3E)],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E8B57).withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Text(
            'ผลแข่ง',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    if (isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8C00), Color(0xFFCC7000)],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8C00).withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'กำลังแข่ง',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    // Default: waiting
    final statusText = t['status']?.toString() ?? 'waiting';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Text(
        statusText.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
