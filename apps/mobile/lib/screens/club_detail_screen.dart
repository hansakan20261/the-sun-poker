import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import 'poker_table_screen.dart';
import 'chinese_poker_screen.dart';

class ClubDetailScreen extends StatefulWidget {
  final Map<String, dynamic> club;
  const ClubDetailScreen({super.key, required this.club});
  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen> {
  List<dynamic> _members = [];
  List<dynamic> _tables = [];
  List<dynamic> _gameTypes = [];
  int _tab = 0; // 0=rooms, 1=members
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await ApiService.getClubMembers(widget.club['id']);
      final tables = await ApiService.getClubTables(widget.club['id']);
      final types = await ApiService.getGameTypes();
      if (mounted)
        setState(() {
          _members = members['members'] ?? [];
          _tables = tables['tables'] ?? [];
          _gameTypes = types['game_types'] ?? types['gameTypes'] ?? [];
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCreateRoom() {
    String selectedTypeId = _gameTypes.isNotEmpty ? _gameTypes[0]['id'] : '';
    String roomName = '';
    int smallBlind = 10;
    int bigBlind = 20;
    int minBuyIn = 800;
    int maxBuyIn = 2000;

    bool isOFC() => _gameTypes.any(
      (g) => g['id'] == selectedTypeId && g['slug'] == 'chinese_poker',
    );

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final ofc = isOFC();
          return Center(
            child: SingleChildScrollView(
              child: Container(
                width: MediaQuery.of(ctx).size.width * 0.88,
                margin: const EdgeInsets.symmetric(vertical: 40),
                padding: const EdgeInsets.all(24),
                decoration: SunTheme.cardDecoration(
                  radius: 24,
                  bgColor: const Color(0xFF1A0606),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'สร้างห้องในคลับ',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Game type selector
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFDAA520).withOpacity(0.2),
                          ),
                        ),
                        child: DropdownButton<String>(
                          value: selectedTypeId.isNotEmpty
                              ? selectedTypeId
                              : null,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF2E0C0C),
                          style: const TextStyle(color: Colors.white),
                          underline: const SizedBox(),
                          items: _gameTypes
                              .map<DropdownMenuItem<String>>(
                                (g) => DropdownMenuItem(
                                  value: g['id'] as String,
                                  child: Text(
                                    g['name_th'] ?? g['name'] ?? '',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setS(() {
                            selectedTypeId = v ?? selectedTypeId;
                            if (isOFC()) {
                              smallBlind = 0;
                              bigBlind = 0;
                            }
                          }),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ofc
                            ? 'ไพ่สามกอง: 2-4 ผู้เล่น'
                            : 'โป๊กเกอร์: 2-9 ผู้เล่น',
                        style: TextStyle(
                          color: const Color(0xFFDAA520).withOpacity(0.4),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Room name
                      TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'ชื่อห้อง',
                          labelStyle: TextStyle(
                            color: const Color(0xFFDAA520).withOpacity(0.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: const Color(0xFFDAA520).withOpacity(0.2),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFFFFD700),
                            ),
                          ),
                        ),
                        onChanged: (v) => roomName = v,
                      ),
                      const SizedBox(height: 12),
                      // Blinds (NLH only)
                      if (!ofc) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _numField(
                                'SB',
                                smallBlind,
                                (v) => setS(() {
                                  smallBlind = v;
                                  bigBlind = v * 2;
                                  minBuyIn = bigBlind * 40;
                                  maxBuyIn = bigBlind * 100;
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _numField(
                                'BB',
                                bigBlind,
                                (v) => setS(() {
                                  bigBlind = v;
                                  minBuyIn = bigBlind * 40;
                                  maxBuyIn = bigBlind * 100;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Buy-in
                      Row(
                        children: [
                          Expanded(
                            child: _numField(
                              'ซื้อเข้าขั้นต่ำ',
                              minBuyIn,
                              (v) => setS(() => minBuyIn = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numField(
                              'ซื้อเข้าสูงสุด',
                              maxBuyIn,
                              (v) => setS(() => maxBuyIn = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Create button
                      GestureDetector(
                        onTap: () async {
                          if (roomName.isEmpty)
                            roomName = ofc ? 'ห้องไพ่สามกอง' : 'ห้องโป๊กเกอร์';
                          try {
                            await ApiService.createClubTable(
                              widget.club['id'],
                              {
                                'game_type_id': selectedTypeId,
                                'name': roomName,
                              },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _load();
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('สร้างห้องสำเร็จ!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                          } catch (e) {
                            debugPrint('Create room error: $e');
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('สร้างห้องไม่สำเร็จ: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3CB371), Color(0xFF2E8B57)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Text(
                              'สร้างห้อง',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _numField(String label, int value, Function(int) onChanged) {
    final ctrl = TextEditingController(text: value.toString());
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: const Color(0xFFDAA520).withOpacity(0.5),
          fontSize: 10,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: const Color(0xFFDAA520).withOpacity(0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFFD700)),
        ),
        isDense: true,
      ),
      onChanged: (v) => onChanged(int.tryParse(v) ?? value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0303),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A0505), Color(0xFF0E0303)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.arrow_back_ios,
                          color: Color(0xFFFFD700),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.club['name'] ?? 'คลับ',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Tabs
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF5C2020)),
                  ),
                  child: Row(
                    children: [
                      _tabBtn('ห้องเล่น', 0),
                      const SizedBox(width: 4),
                      _tabBtn('สมาชิก (${_members.length})', 1),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFFD700),
                          ),
                        )
                      : _tab == 0
                      ? _buildRooms()
                      : _buildMembers(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int index) {
    final active = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFFCC2222), Color(0xFF8B0000)],
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFFFFD700) : Colors.white38,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRooms() {
    if (_tables.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.casino, color: Colors.white.withOpacity(0.1), size: 64),
            const SizedBox(height: 12),
            const Text(
              'ยังไม่มีห้องเล่น',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'กด "สร้างห้อง" เพื่อเริ่ม',
              style: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _tables.length,
      itemBuilder: (_, i) => _buildTableCard(_tables[i]),
    );
  }

  Future<void> _openTable(dynamic table) async {
    var authorizedTable = Map<String, dynamic>.from(table);
    if (table['has_password'] == true) {
      final controller = TextEditingController();
      final password = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A0606),
          title: const Text(
            'ใส่รหัสห้อง',
            style: TextStyle(color: Color(0xFFFFD700)),
          ),
          content: TextField(
            controller: controller,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'รหัสผ่าน'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('เข้าห้อง'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (password == null || password.isEmpty) return;
      try {
        final result = await ApiService.post('/tables/join-by-code', {
          'room_code': table['room_code'],
          'password': password,
        });
        authorizedTable = Map<String, dynamic>.from(result['table']);
        authorizedTable['_roomAccessToken'] = result['room_access_token'];
      } on ApiException catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    } else if (table['is_private'] == true) {
      try {
        final result = await ApiService.post('/tables/join-by-code', {
          'room_code': table['room_code'],
        });
        authorizedTable = Map<String, dynamic>.from(result['table']);
        authorizedTable['_roomAccessToken'] = result['room_access_token'];
      } on ApiException catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    }
    if (!mounted) return;
    final slug = authorizedTable['game_type_slug'] ?? '';
    authorizedTable['_buyIn'] = toInt(authorizedTable['min_buy_in']);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => slug == 'chinese_poker'
            ? ChinesePokerScreen(table: authorizedTable)
            : PokerTableScreen(table: authorizedTable),
      ),
    );
  }

  Widget _buildTableCard(dynamic table) {
    final name = table['name'] ?? '';
    final slug = table['game_type_slug'] ?? '';
    final isOFC = slug == 'chinese_poker';
    final sb = toInt(table['small_blind']);
    final bb = toInt(table['big_blind']);
    final minBuy = toInt(table['min_buy_in']);
    final playerCount = toInt(table['player_count']);
    final maxPlayers = toInt(table['max_players'] ?? 9);

    return GestureDetector(
      onTap: () => _openTable(table),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: SunTheme.cardDecoration(
          radius: 14,
          bgColor: const Color(0xFF1A0606),
        ),
        child: Row(
          children: [
            // Game type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isOFC
                      ? [const Color(0xFF1A3A5C), const Color(0xFF0E2240)]
                      : [const Color(0xFF8B0000), const Color(0xFF5C0000)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isOFC ? 'OFC' : 'NLH',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    isOFC
                        ? 'Buy-in: ${NumberFormatter.formatWithCommas(minBuy)}'
                        : 'Blinds: $sb/$bb | Buy-in: ${NumberFormatter.formatWithCommas(minBuy)}',
                    style: TextStyle(
                      color: const Color(0xFFDAA520).withOpacity(0.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Text(
                  '$playerCount/$maxPlayers',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
                const Icon(Icons.people, color: Colors.white24, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembers() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _members.length,
      itemBuilder: (_, i) {
        final m = _members[i];
        final role = m['role'] ?? 'member';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFDAA520).withOpacity(0.15),
                child: Text(
                  (m['display_name'] ?? m['username'] ?? '?')[0].toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['display_name'] ?? m['username'] ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (role != 'member')
                      Text(
                        role == 'owner' ? 'เจ้าของ' : 'แอดมิน',
                        style: TextStyle(
                          color: const Color(0xFFFFD700).withOpacity(0.6),
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
