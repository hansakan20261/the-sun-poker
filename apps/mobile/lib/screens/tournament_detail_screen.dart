import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../widgets/app_background.dart';
import 'poker_table_screen.dart';

class TournamentDetailScreen extends StatefulWidget {
  final String tournamentId;
  const TournamentDetailScreen({super.key, required this.tournamentId});
  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  Map<String, dynamic>? _tournament;
  List<dynamic> _players = [];
  List<dynamic> _blindLevels = [];
  List<dynamic> _payout = [];
  bool _loading = true;
  bool _registering = false;
  bool _isRegistered = false;

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
      if (mounted)
        setState(() {
          _tournament = data['tournament'];
          _players = data['players'] ?? [];
          _blindLevels = data['blind_levels'] ?? [];
          _payout = data['payout'] ?? [];
          _isRegistered = _players.any(
            (p) => p['user_id'] == ApiService.currentUserId,
          );
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (_registering) return;
    setState(() => _registering = true);
    try {
      final result = await ApiService.post(
        '/poker/tournaments/${widget.tournamentId}/register',
        {},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'สมัครสำเร็จ! ได้รับ ${result['starting_chips']} ชิป',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
    }
    if (mounted) setState(() => _registering = false);
  }

  void _enterTournamentGame() {
    // Find player's table assignment
    final myPlayer = _players.firstWhere(
      (p) => p['user_id'] == ApiService.currentUserId,
      orElse: () => null,
    );

    if (myPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบข้อมูลผู้เล่น'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final tableId = myPlayer['table_id'];
    final playerStatus = myPlayer['status'] ?? '';

    if (tableId == null || playerStatus == 'registered') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('รอ Admin เริ่มแข่ง — ยังไม่ได้จัดโต๊ะ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (playerStatus == 'eliminated') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('คุณตกรอบแล้ว'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Navigate to poker table with tournament flag
    final tableData = {
      'id': tableId,
      'name': _tournament!['name'] ?? 'Tournament',
      'small_blind': _blindLevels.isNotEmpty
          ? _blindLevels[0]['small_blind']
          : 25,
      'big_blind': _blindLevels.isNotEmpty ? _blindLevels[0]['big_blind'] : 50,
      'min_buy_in': _tournament!['starting_chips'],
      'max_buy_in': _tournament!['starting_chips'],
      '_buyIn': myPlayer['chips'] ?? _tournament!['starting_chips'],
      '_isTournament': true,
      '_tournamentId': widget.tournamentId,
      '_seatNo': myPlayer['seat_no'],
    };

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PokerTableScreen(table: tableData)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                )
              : _tournament == null
              ? const Center(
                  child: Text(
                    'ไม่พบรายการ',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final t = _tournament!;
    final status = t['status'] ?? '';
    final isOpen = status == 'registration';
    final name = t['name'] ?? '';
    final type = t['type'] ?? 'sit_and_go';
    final buyIn = toInt(t['buy_in']);
    final entryFee = toInt(t['entry_fee']);
    final prizePool = toInt(t['prize_pool']);
    final maxPlayers = toInt(t['max_players']);
    final startingChips = toInt(t['starting_chips']);
    final blindMinutes = toInt(t['blind_level_minutes']);
    final desc = t['description'] ?? '';
    final typeLabel = type == 'sit_and_go'
        ? 'ซิท แอนด์ โก'
        : type == 'scheduled'
        ? 'ตามเวลา'
        : 'หลายโต๊ะ';

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isOpen
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isOpen
                        ? Colors.green.withOpacity(0.5)
                        : Colors.orange.withOpacity(0.5),
                  ),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: isOpen ? Colors.greenAccent : Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: SunTheme.cardDecoration(
                    radius: 16,
                    bgColor: const Color(0xFF0D0D0D),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            color: Color(0xFFFFD700),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            typeLabel,
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'เท็กซัสโฮลเอ็ม',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          desc,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Stats grid
                      Row(
                        children: [
                          _infoTile(
                            'ค่าสมัคร',
                            '${NumberFormatter.formatWithCommas(buyIn)}',
                          ),
                          _infoTile(
                            'ค่าธรรมเนียม',
                            '${NumberFormatter.formatWithCommas(entryFee)}',
                          ),
                          _infoTile(
                            'เงินรางวัล',
                            '${NumberFormatter.formatWithCommas(prizePool)}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _infoTile(
                            'ผู้เล่น',
                            '${_players.length}/$maxPlayers',
                          ),
                          _infoTile(
                            'ชิปเริ่มต้น',
                            '${NumberFormatter.formatWithCommas(startingChips)}',
                          ),
                          _infoTile('ระดับบลายด์', '$blindMinutes นาที'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Register button
                if (isOpen && !_isRegistered)
                  GestureDetector(
                    onTap: _register,
                    child: Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFCC2222), Color(0xFF8B0000)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B0000).withOpacity(0.4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: _registering
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'สมัครแข่ง (${NumberFormatter.formatWithCommas(buyIn + entryFee)} ชิป)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                if (_isRegistered && !isOpen)
                  GestureDetector(
                    onTap: () => _enterTournamentGame(),
                    child: Container(
                      width: double.infinity,
                      height: 54,
                      margin: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF8C00), Color(0xFFCC7000)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF8C00).withOpacity(0.4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'เข้าเล่น',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_isRegistered && isOpen)
                  Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.withOpacity(0.4)),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'สมัครแล้ว — รอเริ่มแข่ง',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 18),

                // Blind levels
                _sectionTitle('ระดับบลายด์'),
                Container(
                  decoration: SunTheme.cardDecoration(
                    radius: 12,
                    bgColor: const Color(0xFF0D0D0D),
                  ),
                  child: Column(
                    children: [
                      // Header row
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.05),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            _colHeader('Lv', flex: 1),
                            _colHeader('SB', flex: 2),
                            _colHeader('BB', flex: 2),
                            _colHeader('Ante', flex: 2),
                          ],
                        ),
                      ),
                      ..._blindLevels.map(
                        (bl) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: Colors.white.withOpacity(0.03),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${bl['level_no']}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${bl['small_blind']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${bl['big_blind']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${bl['ante']}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Payout
                _sectionTitle('การแจกรางวัล'),
                Container(
                  decoration: SunTheme.cardDecoration(
                    radius: 12,
                    bgColor: const Color(0xFF0D0D0D),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: _payout.map((p) {
                      final rank = p['rank'] ?? 0;
                      final percent = p['percent'] ?? 0;
                      final prize = prizePool > 0
                          ? (prizePool * percent / 100).round()
                          : 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 30,
                              child: Text(
                                '#$rank',
                                style: TextStyle(
                                  color: rank <= 3
                                      ? const Color(0xFFFFD700)
                                      : Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(
                                        0xFFFFD700,
                                      ).withOpacity(rank <= 3 ? 0.6 : 0.2),
                                      Colors.transparent,
                                    ],
                                    stops: [percent / 50, 1.0],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$percent%',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 60,
                              child: Text(
                                prize > 0
                                    ? NumberFormatter.formatWithCommas(prize)
                                    : '-',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: rank <= 3
                                      ? const Color(0xFFFFD700)
                                      : Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 18),

                // Players list
                _sectionTitle('ผู้เล่นที่สมัคร (${_players.length})'),
                if (_players.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'ยังไม่มีผู้สมัคร',
                        style: TextStyle(color: Colors.white.withOpacity(0.3)),
                      ),
                    ),
                  )
                else
                  ...List.generate(_players.length, (i) {
                    final p = _players[i];
                    final displayName =
                        p['display_name'] ?? p['username'] ?? '';
                    final pStatus = p['status'] ?? '';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: SunTheme.cardDecoration(
                        radius: 10,
                        bgColor: const Color(0xFF0D0D0D),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFDAA520).withOpacity(0.15),
                              image: p['avatar_url'] != null
                                  ? DecorationImage(
                                      image: NetworkImage(p['avatar_url']),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: p['avatar_url'] == null
                                ? Center(
                                    child: Text(
                                      displayName.isNotEmpty
                                          ? displayName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Color(0xFFFFD700),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            pStatus,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoTile(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: const Color(0xFFFFD700).withOpacity(0.6),
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _colHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xFFFFD700).withOpacity(0.5),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
