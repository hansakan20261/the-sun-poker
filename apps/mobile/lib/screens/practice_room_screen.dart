import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';
import '../models/practice_session.dart';
import '../widgets/practice_label.dart';
import '../widgets/app_background.dart';
import '../widgets/sun_button.dart';
import 'lobby_screen.dart';
import 'poker_table_screen.dart';
import 'chinese_poker_screen.dart';
import 'ofc_game_screen.dart';

class PracticeRoomScreen extends StatefulWidget {
  const PracticeRoomScreen({super.key});
  @override
  State<PracticeRoomScreen> createState() => _PracticeRoomScreenState();
}

class _PracticeRoomScreenState extends State<PracticeRoomScreen> {
  int _selectedTab = 0; // 0=NLH, 1=OFC

  static const _nlhRooms = [
    {
      'name': 'Micro 1/2',
      'sb': 1,
      'bb': 2,
      'minBuy': 80,
      'maxBuy': 200,
      'emoji': '🟢',
    },
    {
      'name': 'Small 5/10',
      'sb': 5,
      'bb': 10,
      'minBuy': 400,
      'maxBuy': 1000,
      'emoji': '🔵',
    },
    {
      'name': 'Medium 25/50',
      'sb': 25,
      'bb': 50,
      'minBuy': 2000,
      'maxBuy': 5000,
      'emoji': '🟡',
    },
    {
      'name': 'High 100/200',
      'sb': 100,
      'bb': 200,
      'minBuy': 8000,
      'maxBuy': 20000,
      'emoji': '🔴',
    },
  ];

  static const _ofcRooms = [
    {'name': 'ห้อง 5', 'bb': 5, 'minBuy': 250, 'maxBuy': 1250, 'emoji': '🟢'},
    {'name': 'ห้อง 10', 'bb': 10, 'minBuy': 500, 'maxBuy': 2500, 'emoji': '🟢'},
    {
      'name': 'ห้อง 20',
      'bb': 20,
      'minBuy': 1000,
      'maxBuy': 5000,
      'emoji': '🔵',
    },
    {
      'name': 'ห้อง 30',
      'bb': 30,
      'minBuy': 1500,
      'maxBuy': 7500,
      'emoji': '🔵',
    },
    {
      'name': 'ห้อง 40',
      'bb': 40,
      'minBuy': 2000,
      'maxBuy': 10000,
      'emoji': '🟡',
    },
    {
      'name': 'ห้อง 50',
      'bb': 50,
      'minBuy': 2500,
      'maxBuy': 12500,
      'emoji': '🟡',
    },
    {
      'name': 'ห้อง 100',
      'bb': 100,
      'minBuy': 5000,
      'maxBuy': 25000,
      'emoji': '🔴',
    },
    {
      'name': 'ห้อง 200',
      'bb': 200,
      'minBuy': 10000,
      'maxBuy': 50000,
      'emoji': '🔴',
    },
  ];

  @override
  Widget build(BuildContext context) {
    // When embedded in lobby, show only content without scaffold/header
    final content = Column(
      children: [
        _tabBar(),
        const SizedBox(height: 12),
        Expanded(child: _selectedTab == 0 ? _nlhList() : _ofcList()),
      ],
    );

    if (Navigator.of(context).canPop()) {
      // Standalone mode — full screen with header
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackground(
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
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
                              color: SunTheme.goldLight,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'ทดลองเล่น',
                            style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: const Text(
                              '🎰 ชิปฟรี',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: content),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Embedded mode — just content
    return content;
  }

  Widget _tabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A0A0A), Color(0xFF1A0505), Color(0xFF2A0A0A)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5C2020), width: 1),
      ),
      child: Row(
        children: [
          _tab('โป๊กเกอร์', 0),
          const SizedBox(width: 4),
          _tab('ไพ่สามกอง', 1),
        ],
      ),
    );
  }

  Widget _tab(String label, int index) {
    final active = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [
                      Color(0xFFCC2222),
                      Color(0xFF8B0000),
                      Color(0xFF5C0000),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? const Color(0xFFFFD700)
                    : const Color(0xFF8B6914).withOpacity(0.5),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nlhList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      itemCount: _nlhRooms.length,
      itemBuilder: (_, i) => _roomCard(_nlhRooms[i], 'NLH'),
    );
  }

  Widget _ofcList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      itemCount: _ofcRooms.length,
      itemBuilder: (_, i) => _roomCard(_ofcRooms[i], 'OFC'),
    );
  }

  Widget _roomCard(Map<String, dynamic> room, String type) {
    final name = room['name'] as String;
    final minBuy = room['minBuy'] as int;
    final maxBuy = room['maxBuy'] as int;
    final sb = room['sb'] as int? ?? 0;
    final bb = room['bb'] as int? ?? 0;

    return GestureDetector(
      onTap: () =>
          _startPractice(type, sb: sb, bb: bb, minBuy: minBuy, maxBuy: maxBuy),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: SunTheme.cardDecoration(
          radius: 16,
          bgColor: const Color(0xFF1A0606),
        ),
        child: Row(
          children: [
            // Logo icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFDAA520).withOpacity(0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFDAA520).withOpacity(0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset('assets/room_logo.jpg', fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (type == 'NLH')
                    Text(
                      'Blinds: $sb/$bb  |  Buy-in: ${NumberFormatter.formatWithCommas(minBuy)} - ${NumberFormatter.formatWithCommas(maxBuy)}',
                      style: TextStyle(
                        color: const Color(0xFFDAA520).withOpacity(0.5),
                        fontSize: 11,
                      ),
                    )
                  else
                    Text(
                      'เรท: ${NumberFormatter.formatWithCommas(bb)}  |  ซื้อเข้า: ${NumberFormatter.formatWithCommas(minBuy)} - ${NumberFormatter.formatWithCommas(maxBuy)}',
                      style: TextStyle(
                        color: const Color(0xFFDAA520).withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            SunButton.orange(
              label: 'เล่น',
              onTap: () => _startPractice(
                type,
                sb: sb,
                bb: bb,
                minBuy: minBuy,
                maxBuy: maxBuy,
              ),
              width: 72,
              height: 36,
            ),
          ],
        ),
      ),
    );
  }

  void _startPractice(
    String gameType, {
    int sb = 10,
    int bb = 20,
    int minBuy = 800,
    int maxBuy = 2000,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      ),
    );

    try {
      final slug = gameType == 'OFC' ? 'chinese_poker' : 'texas_holdem';
      Map<String, dynamic>? table;

      // Always create a fresh practice table with correct blinds
      final result = await ApiService.createPracticeTable(
        slug,
        smallBlind: sb,
        bigBlind: bb,
        minBuyIn: minBuy,
        maxBuyIn: maxBuy,
      );
      table = result['table'] != null
          ? Map<String, dynamic>.from(result['table'])
          : null;

      if (!mounted) return;
      Navigator.pop(context);
      if (table == null) throw Exception('No table');

      // Override blinds/buy-in from selected room
      table['small_blind'] = sb;
      table['big_blind'] = bb;
      table['min_buy_in'] = minBuy;
      table['max_buy_in'] = maxBuy;

      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => gameType == 'OFC'
              ? ChinesePokerScreen(
                  table: {...table!, '_isPractice': true, '_buyIn': maxBuy},
                )
              : PokerTableScreen(
                  table: {...table!, '_buyIn': maxBuy, '_isPractice': true},
                ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่สามารถสร้างห้องทดลองได้: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
