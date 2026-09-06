import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/runtime_config_service.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';
import '../widgets/notification_banner.dart';
import '../widgets/room_card.dart';
import '../widgets/app_background.dart';
import '../widgets/sun_button.dart';
import '../services/audio_manager.dart';
import 'poker_table_screen.dart';
import 'chinese_poker_screen.dart';
import 'practice_room_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'daily_bonus_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String? filterGameSlug;
  final String? title;
  const LobbyScreen({super.key, this.filterGameSlug, this.title});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

/// Maps common city/room names to country flag emojis for city-themed room cards.
String _getCityFlag(String roomName) {
  final lower = roomName.toLowerCase();
  const cityFlags = <String, String>{
    'new york': '🇺🇸',
    'los angeles': '🇺🇸',
    'las vegas': '🇺🇸',
    'chicago': '🇺🇸',
    'manila': '🇵🇭',
    'cebu': '🇵🇭',
    'bangkok': '🇹🇭',
    'phuket': '🇹🇭',
    'chiang mai': '🇹🇭',
    'tokyo': '🇯🇵',
    'osaka': '🇯🇵',
    'london': '🇬🇧',
    'macau': '🇲🇴',
    'hong kong': '🇭🇰',
    'seoul': '🇰🇷',
    'singapore': '🇸🇬',
    'sydney': '🇦🇺',
    'melbourne': '🇦🇺',
    'paris': '🇫🇷',
    'berlin': '🇩🇪',
    'moscow': '🇷🇺',
    'dubai': '🇦🇪',
    'mumbai': '🇮🇳',
    'beijing': '🇨🇳',
    'shanghai': '🇨🇳',
    'taipei': '🇹🇼',
    'hanoi': '🇻🇳',
    'ho chi minh': '🇻🇳',
    'jakarta': '🇮🇩',
    'kuala lumpur': '🇲🇾',
    'rio': '🇧🇷',
    'mexico city': '🇲🇽',
    'toronto': '🇨🇦',
    'amsterdam': '🇳🇱',
    'rome': '🇮🇹',
    'madrid': '🇪🇸',
    'lisbon': '🇵🇹',
    'cairo': '🇪🇬',
    'istanbul': '🇹🇷',
  };
  for (final entry in cityFlags.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return '🏙️';
}

/// Game type tab definition for the lobby tab bar.
class _GameTypeTab {
  final String label;
  final String slug;
  const _GameTypeTab(this.label, this.slug);
}

const _kGameTypeTabs = [
  _GameTypeTab('โป๊กเกอร์', 'texas_holdem'),
  _GameTypeTab('ไพ่สามกอง', 'chinese_poker'),
  _GameTypeTab('ทดลองเล่น', 'practice'),
];

class _LobbyScreenState extends State<LobbyScreen> {
  List<dynamic> _gameTypes = [];
  List<dynamic> _tables = [];
  int _selectedTabIndex = 0; // Default NLH (Req 7.4)
  int _coinBalance = 0;
  bool _showNotification = false;
  String _notificationMessage = '';
  String _announcementSeverity = 'info';
  Timer? _lobbyTimer;
  bool _loadError = false; // Task 19.2: Room list API failure state

  @override
  void initState() {
    super.initState();
    // Ensure portrait when entering lobby (coming back from landscape game)
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // Start background music
    AudioManager.instance.startBgm();
    // Set initial tab based on filterGameSlug from Home screen
    if (widget.filterGameSlug != null) {
      final idx = _kGameTypeTabs.indexWhere(
        (t) => t.slug == widget.filterGameSlug,
      );
      if (idx >= 0) _selectedTabIndex = idx;
      // 'practice' from home goes to practice tab
      if (widget.filterGameSlug == 'practice') {
        _selectedTabIndex = _kGameTypeTabs.indexWhere(
          (t) => t.slug == 'practice',
        );
      }
    }
    _load();
    _loadBalance();
    _startLobbyPolling();
  }

  Future<void> _startLobbyPolling() async {
    try {
      await RuntimeConfigService.load();
      if (!mounted) return;
      setState(() {
        _showNotification =
            RuntimeConfigService.value('announcement_enabled') == true;
        _notificationMessage =
            RuntimeConfigService.optionalValue('announcement')?.toString() ??
            '';
        _announcementSeverity = RuntimeConfigService.string(
          'announcement_severity',
        );
      });
      _lobbyTimer = Timer.periodic(
        Duration(
          seconds: RuntimeConfigService.integer('lobby_poll_interval_sec'),
        ),
        (_) => _load(),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _lobbyTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      final bal = await ApiService.getBalance();
      if (!mounted) return;
      setState(() => _coinBalance = toInt(bal['balance']));
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final types = await ApiService.getGameTypes();
      final tables = await ApiService.getTables();
      if (!mounted) return;
      setState(() {
        _gameTypes = types['game_types'] ?? [];
        _tables = tables['tables'] ?? [];
        _loadError = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  String _getSlug(String? id) {
    if (id == null) return 'texas_holdem';
    final m = _gameTypes.where((g) => g['id'] == id);
    return m.isNotEmpty ? m.first['slug'] : 'texas_holdem';
  }

  /// Returns the game type id matching the selected tab slug, or null.
  String? _getSelectedTypeId() {
    final slug = _kGameTypeTabs[_selectedTabIndex].slug;
    final match = _gameTypes.where((g) => g['slug'] == slug);
    return match.isNotEmpty ? match.first['id'] : null;
  }

  /// Filter tables by selected game type tab and order by minBuyIn ascending (Req 7.2, 9.8).
  List<dynamic> get _filtered {
    final typeId = _getSelectedTypeId();
    List<dynamic> result;
    if (typeId == null) {
      result = List<dynamic>.from(_tables);
    } else {
      result = _tables.where((t) => t['game_type_id'] == typeId).toList();
    }
    // Hide closed tables
    result = result.where((t) => t['status'] != 'closed').toList();
    // Sort by minBuyIn ascending
    result.sort(
      (a, b) => toInt(a['min_buy_in']).compareTo(toInt(b['min_buy_in'])),
    );
    return result;
  }

  void _openDailyBonus() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(16),
        child: DailyBonusScreen(isPopup: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: Stack(
          children: [
            // Red glow
            Positioned(
              top: -80,
              left: 0,
              right: 0,
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF8B0000).withOpacity(0.15),
                      Colors.transparent,
                    ],
                    radius: 0.9,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // Header (Req 6.1-6.6)
                  _buildHeader(),
                  const SizedBox(height: 8),
                  // Game Type Tab Bar (Req 7.1-7.5)
                  _buildGameTypeTabBar(),
                  const SizedBox(height: 6),
                  // Room list
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Header with back arrow, title, settings, friends, coin balance, treasure chest (Req 6.1-6.6).
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Back arrow
          GestureDetector(
            onTap: () {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 300),
                  pageBuilder: (_, __, ___) => const HomeScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    return SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(-1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOut,
                            ),
                          ),
                      child: child,
                    );
                  },
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.arrow_back_ios,
                color: SunTheme.goldLight,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Title
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFFFFE082), Color(0xFFFFD700), Color(0xFFB8860B)],
            ).createShader(b),
            child: Text(
              ThaiLabels.lobby,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Game Type Tab Bar: NLH, PLO, OFC, CRASH — default NLH (Req 7.1-7.5).
  Widget _buildGameTypeTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A0A0A), Color(0xFF1A0505), Color(0xFF2A0A0A)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5C2020), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: List.generate(_kGameTypeTabs.length, (i) {
          final tab = _kGameTypeTabs[i];
          final isActive = _selectedTabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTabIndex = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFCC2222),
                            Color(0xFF8B0000),
                            Color(0xFF5C0000),
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(0xFFB22222).withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    tab.label,
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF8B6914).withOpacity(0.5),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Room list body with NotificationBanner and RoomCard widgets (Req 8.1-8.5, 9.1-9.9).
  Widget _buildBody() {
    // Practice tab → show PracticeRoomScreen content
    if (_kGameTypeTabs[_selectedTabIndex].slug == 'practice') {
      return const PracticeRoomScreen();
    }
    final tables = _filtered;
    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await _loadBalance();
      },
      color: const Color(0xFFFFD700),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notification Banner (Req 8.1-8.5)
            if (_showNotification)
              NotificationBanner(
                message: _notificationMessage,
                severity: _announcementSeverity,
                onTap: () {
                  // Navigate to relevant game/event
                },
                onDismiss: () {
                  if (mounted) setState(() => _showNotification = false);
                },
              ),
            // Task 19.2: Room list API failure → "ไม่สามารถโหลดห้องได้" with pull-to-refresh (Req 10.9)
            if (_loadError)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_off,
                        size: 48,
                        color: SunTheme.gold.withOpacity(0.25),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ThaiLabels.cannotLoadRooms,
                        style: TextStyle(
                          color: SunTheme.gold.withOpacity(0.5),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ดึงลงเพื่อลองใหม่',
                        style: TextStyle(
                          color: SunTheme.gold.withOpacity(0.3),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_loadError) ...[
              // Section header + Create button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Row(
                  children: [
                    Text(
                      'ห้องเล่น (${tables.length})',
                      style: TextStyle(
                        color: const Color(0xFFFFD700).withOpacity(0.55),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    SunButton.red(
                      label: 'สร้างห้อง',
                      onTap: _showCreateRoomDialog,
                      width: 110,
                      height: 34,
                      icon: Icons.add,
                    ),
                  ],
                ),
              ),
              // Room cards using RoomCard widget (Req 9.1-9.9)
              if (tables.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.casino_outlined,
                          size: 48,
                          color: SunTheme.gold.withOpacity(0.15),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ยังไม่มีห้องเล่น',
                          style: TextStyle(
                            color: SunTheme.gold.withOpacity(0.25),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ...tables.map((t) => _buildRoomCardFromTable(t)),
            ],
          ],
        ),
      ),
    );
  }

  /// Build a RoomCard widget from API table data.
  Widget _buildRoomCardFromTable(dynamic t) {
    final slug = _getSlug(t['game_type_id']);
    final minBuyIn = toInt(t['min_buy_in']);
    final maxBuyIn = toInt(t['max_buy_in']);
    final name = t['name'] ?? 'Room #${t['room_code']}';
    final smallBlind = toInt(t['small_blind']);
    final bigBlind = toInt(t['big_blind']);
    final ante = toInt(t['ante']);
    final playerCount = toInt(t['player_count']);
    final maxPlayers = toInt(t['max_players']);

    return RoomCard(
      cityName: name,
      cityIconUrl: '', // Use flag fallback
      smallBlind: smallBlind,
      bigBlind: bigBlind,
      ante: ante,
      playerCount: playerCount,
      maxPlayers: maxPlayers,
      minBuyIn: minBuyIn,
      onTap: () => _handleJoin(t, slug, minBuyIn, maxBuyIn),
    );
  }

  Future<void> _showCreateRoomDialog() async {
    String roomName = '';
    // Auto-select game type based on current tab
    final currentSlug = _kGameTypeTabs[_selectedTabIndex].slug;
    String selectedType = '';
    for (final g in _gameTypes) {
      if (g['slug'] == currentSlug) {
        selectedType = g['id'] as String;
        break;
      }
    }
    if (selectedType.isEmpty && _gameTypes.isNotEmpty) {
      selectedType = _gameTypes[0]['id'] as String;
    }
    if (selectedType.isEmpty) return;

    Map<String, dynamic> roomDefaults;
    try {
      final effective = await ApiService.get(
        '/tables/config-effective?game_type_id=$selectedType',
      );
      roomDefaults = Map<String, dynamic>.from(
        effective['effective_config']?['value'] ?? const {},
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่สามารถโหลดค่าเริ่มต้นของห้องจากเซิร์ฟเวอร์'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!mounted || roomDefaults.isEmpty) return;

    int smallBlind = toInt(roomDefaults['small_blind']);
    int bigBlind = toInt(roomDefaults['big_blind']);
    int ante = toInt(roomDefaults['ante']);
    int minBuyIn = toInt(roomDefaults['min_buy_in']);
    int maxBuyIn = toInt(roomDefaults['max_buy_in']);
    final int maxPlayers = toInt(roomDefaults['max_players']);
    final int turnTimeSec = toInt(roomDefaults['turn_time_sec']);
    final int autoStartAt = toInt(roomDefaults['auto_start_at']);
    final int autoStartDelaySec = toInt(roomDefaults['auto_start_delay_sec']);
    final int minimumPlayMinutes = toInt(roomDefaults['minimum_play_minutes']);
    bool isCreating = false;
    String? createdRoomCode;
    String roomPassword = ''; // รหัสเข้าห้อง ที่เจ้าของห้องตั้งเอง

    bool _isOFC() => _gameTypes.any(
      (g) => g['id'] == selectedType && g['slug'] == 'chinese_poker',
    );

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final isOFC = _isOFC();
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
                        'สร้างห้องเล่น',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
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
                      // Game type — fixed based on current tab
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFDAA520).withOpacity(0.2),
                          ),
                          color: Colors.black.withOpacity(0.2),
                        ),
                        child: Text(
                          isOFC
                              ? '🀄 ไพ่สามกอง (OFC)'
                              : '🃏 เท็กซัสโฮลเอ็ม (NLH)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Game type info
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isOFC
                              ? 'ไพ่สามกอง: 2-4 ผู้เล่น, ไม่มีเดิมพัน, คะแนนเป็นแต้ม'
                              : 'โป๊กเกอร์: 2-9 ผู้เล่น, เดิมพันแบบ No Limit',
                          style: TextStyle(
                            color: const Color(0xFFDAA520).withOpacity(0.5),
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Blinds (only for NLH, not OFC)
                      if (!isOFC) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _numField(
                                'สมอลบลายด์ (SB)',
                                smallBlind,
                                (v) => setS(() => smallBlind = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _numField(
                                'บิ๊กบลายด์ (BB)',
                                bigBlind,
                                (v) => setS(() => bigBlind = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Buy-in: ขั้นต่ำ $minBuyIn / สูงสุด $maxBuyIn',
                          style: TextStyle(
                            color: const Color(0xFFDAA520).withOpacity(0.4),
                            fontSize: 9,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (isOFC) ...[
                        _numField(
                          'เรทต่อแต้ม (Ante)',
                          ante,
                          (v) => setS(() => ante = v),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // Buy-in fields
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
                      const SizedBox(height: 12),
                      // ตั้งรหัสเข้าห้อง
                      TextField(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: '🔒 ตั้งรหัสเข้าห้อง (บังคับ)',
                          labelStyle: TextStyle(
                            color: const Color(0xFFDAA520).withOpacity(0.6),
                          ),
                          hintText: 'เช่น 1234 หรือ ABC',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: const Color(0xFFE65100).withOpacity(0.4),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFFFF6D00),
                              width: 2,
                            ),
                          ),
                          prefixIcon: const Icon(
                            Icons.lock,
                            color: Color(0xFFFF6D00),
                            size: 20,
                          ),
                        ),
                        onChanged: (v) => roomPassword = v,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ผู้เล่นต้องกรอกรหัสนี้เพื่อเข้าห้อง',
                        style: TextStyle(
                          color: const Color(0xFFDAA520).withOpacity(0.4),
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(height: 20),
                      isCreating
                          ? Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade700,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'กำลังสร้างห้อง...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : SunButton.green(
                              label: 'สร้างห้อง',
                              onTap: () async {
                                if (roomName.isEmpty)
                                  roomName = isOFC
                                      ? 'ห้องไพ่สามกอง'
                                      : 'ห้องโป๊กเกอร์';
                                if (roomPassword.isEmpty) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('กรุณาตั้งรหัสเข้าห้อง'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  return;
                                }
                                setS(() => isCreating = true);
                                try {
                                  final result =
                                      await ApiService.post('/tables', {
                                        'game_type_id': selectedType,
                                        'name': roomName,
                                        'small_blind': smallBlind,
                                        'big_blind': bigBlind,
                                        'ante': ante,
                                        'min_buy_in': minBuyIn,
                                        'max_buy_in': maxBuyIn,
                                        'max_players': maxPlayers,
                                        'turn_time_sec': turnTimeSec,
                                        'auto_start_at': autoStartAt,
                                        'auto_start_delay_sec': autoStartDelaySec,
                                        'minimum_play_minutes': minimumPlayMinutes,
                                        'password': roomPassword,
                                      });
                                  final roomCode =
                                      result['table']?['room_code'] ?? '';
                                  setS(() {
                                    isCreating = false;
                                    createdRoomCode = roomCode;
                                  });
                                  _load();
                                  if (roomCode.isNotEmpty) {
                                    // Show room code dialog
                                    if (ctx.mounted) {
                                      showDialog(
                                        context: ctx,
                                        builder: (_) => AlertDialog(
                                          backgroundColor: const Color(
                                            0xFF1A0606,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          title: const Text(
                                            '✅ สร้างห้องสำเร็จ!',
                                            style: TextStyle(
                                              color: Color(0xFFFFD700),
                                              fontSize: 18,
                                            ),
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text(
                                                'รหัสห้อง:',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 12,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withOpacity(0.5),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFFFD700,
                                                    ).withOpacity(0.5),
                                                  ),
                                                ),
                                                child: Text(
                                                  roomCode,
                                                  style: const TextStyle(
                                                    color: Color(0xFFFFD700),
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 4,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              const Text(
                                                'ส่งรหัสนี้ให้เพื่อนเพื่อเข้าร่วมห้อง',
                                                style: TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(ctx);
                                                Navigator.pop(ctx);
                                              },
                                              child: const Text(
                                                'ตกลง',
                                                style: TextStyle(
                                                  color: Color(0xFFFFD700),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } else {
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted)
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('✅ สร้างห้องสำเร็จ!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                  }
                                } on ApiException catch (e) {
                                  setS(() => isCreating = false);
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'สร้างห้องไม่สำเร็จ: ${e.message}',
                                        ),
                                        backgroundColor: Colors.red,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                } on NetworkException catch (e) {
                                  setS(() => isCreating = false);
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'เชื่อมต่อไม่ได้: ${e.message}',
                                        ),
                                        backgroundColor: Colors.orange.shade800,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                } catch (e) {
                                  setS(() => isCreating = false);
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('ข้อผิดพลาด: $e'),
                                        backgroundColor: Colors.red,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                }
                              },
                              height: 50,
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

  void _showJoinByCodeDialog() {
    String roomCode = '';
    bool isLoading = false;
    String? errorMsg;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          return Center(
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.82,
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
                      '🔑 ใส่รหัสห้อง',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'กรอกรหัส 6 ตัวอักษรที่ได้รับจากเจ้าของห้อง',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        letterSpacing: 6,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      decoration: InputDecoration(
                        hintText: 'ABC123',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.2),
                          letterSpacing: 6,
                        ),
                        counterText: '',
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: const Color(0xFFDAA520).withOpacity(0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFFFD700),
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.3),
                      ),
                      onChanged: (v) {
                        roomCode = v.toUpperCase();
                        if (errorMsg != null) setS(() => errorMsg = null);
                      },
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorMsg!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 20),
                    isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFFFD700),
                            ),
                          )
                        : SunButton.green(
                            label: 'เข้าห้อง',
                            onTap: () async {
                              if (roomCode.length < 6) {
                                setS(
                                  () => errorMsg = 'กรุณากรอกรหัสให้ครบ 6 ตัว',
                                );
                                return;
                              }
                              setS(() {
                                isLoading = true;
                                errorMsg = null;
                              });
                              try {
                                final result = await ApiService.post(
                                  '/tables/join-by-code',
                                  {'room_code': roomCode},
                                );
                                final table = Map<String, dynamic>.from(
                                  result['table'],
                                );
                                table['_roomAccessToken'] =
                                    result['room_access_token'];
                                if (ctx.mounted) Navigator.pop(ctx);
                                final slug = table['game_type_slug'] ?? '';
                                _proceedToJoin(
                                  table,
                                  slug,
                                  toInt(table['min_buy_in']),
                                  toInt(table['max_buy_in']),
                                );
                              } on ApiException catch (e) {
                                setS(() {
                                  isLoading = false;
                                  errorMsg = e.message;
                                });
                              } on NetworkException catch (e) {
                                setS(() {
                                  isLoading = false;
                                  errorMsg = 'เชื่อมต่อไม่ได้: ${e.message}';
                                });
                              } catch (e) {
                                setS(() {
                                  isLoading = false;
                                  errorMsg = 'ข้อผิดพลาด: $e';
                                });
                              }
                            },
                            height: 48,
                          ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'ยกเลิก',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _numField(String label, int value, Function(int) onChanged) {
    return TextField(
      style: const TextStyle(color: Colors.white, fontSize: 14),
      keyboardType: TextInputType.number,
      controller: TextEditingController(text: value.toString()),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: const Color(0xFFDAA520).withOpacity(0.4),
          fontSize: 11,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      onChanged: (v) => onChanged(int.tryParse(v) ?? value),
    );
  }

  void _handleJoin(dynamic t, String slug, int minBuyIn, int maxBuyIn) async {
    // ถ้าห้องมีรหัส (is_private) → ให้ใส่รหัสก่อน
    if (t['has_password'] == true) {
      _showPasswordPrompt(t, slug, minBuyIn, maxBuyIn);
      return;
    }
    if (t['is_private'] == true) {
      try {
        final result = await ApiService.post('/tables/join-by-code', {
          'room_code': t['room_code'],
        });
        final authorizedTable = Map<String, dynamic>.from(result['table']);
        authorizedTable['_roomAccessToken'] = result['room_access_token'];
        _proceedToJoin(authorizedTable, slug, minBuyIn, maxBuyIn);
      } on ApiException catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    _proceedToJoin(t, slug, minBuyIn, maxBuyIn);
  }

  void _showPasswordPrompt(dynamic t, String slug, int minBuyIn, int maxBuyIn) {
    String password = '';
    String? errorMsg;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Center(
          child: Container(
            width: MediaQuery.of(ctx).size.width * 0.82,
            padding: const EdgeInsets.all(24),
            decoration: SunTheme.cardDecoration(
              radius: 20,
              bgColor: const Color(0xFF1A0606),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🔒 ใส่รหัสเข้าห้อง',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t['name'] ?? 'ห้องส่วนตัว',
                    style: TextStyle(
                      color: const Color(0xFFDAA520).withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'รหัสห้อง',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: const Color(0xFFFF6D00).withOpacity(0.4),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFFF6D00),
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.3),
                      prefixIcon: const Icon(
                        Icons.lock_open,
                        color: Color(0xFFFF6D00),
                      ),
                    ),
                    onChanged: (v) {
                      password = v;
                      if (errorMsg != null) setS(() => errorMsg = null);
                    },
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMsg!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'ยกเลิก',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SunButton.green(
                          label: 'เข้าห้อง',
                          onTap: () async {
                            if (password.isEmpty) {
                              setS(() => errorMsg = 'กรุณากรอกรหัส');
                              return;
                            }
                            try {
                              final result = await ApiService.post(
                                '/tables/join-by-code',
                                {
                                  'room_code': t['room_code'],
                                  'password': password,
                                },
                              );
                              final authorizedTable = Map<String, dynamic>.from(
                                result['table'],
                              );
                              authorizedTable['_roomAccessToken'] =
                                  result['room_access_token'];
                              if (ctx.mounted) Navigator.pop(ctx);
                              _proceedToJoin(
                                authorizedTable,
                                slug,
                                minBuyIn,
                                maxBuyIn,
                              );
                            } on ApiException catch (e) {
                              setS(() => errorMsg = e.message);
                            } catch (_) {
                              setS(
                                () => errorMsg = 'ไม่สามารถตรวจสอบรหัสห้องได้',
                              );
                            }
                          },
                          height: 42,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _proceedToJoin(
    dynamic t,
    String slug,
    int minBuyIn,
    int maxBuyIn,
  ) async {
    try {
      final bal = await ApiService.getBalance();
      final balance = toInt(bal['balance']);
      if (balance < minBuyIn) {
        if (mounted) {
          showDialog(
            context: context,
            barrierColor: Colors.black.withOpacity(0.75),
            builder: (_) => Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.82,
                padding: const EdgeInsets.all(24),
                decoration: SunTheme.cardDecoration(
                  radius: 20,
                  bgColor: const Color(0xFF1A0606),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('⚠️', style: TextStyle(fontSize: 36)),
                      const SizedBox(height: 8),
                      Text(
                        ThaiLabels.insufficientFunds,
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'ต้องมีอย่างน้อย $minBuyIn ชิป เพื่อเข้าห้องนี้',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFFDAA520).withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ยอดเงินปัจจุบัน: $balance ชิป',
                        style: TextStyle(
                          color: Colors.orangeAccent.withOpacity(0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: SunButton.red(
                          label: 'ตกลง',
                          onTap: null,
                          height: 44,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return;
      }
      if (mounted) _showBuyInDialog(t, slug, balance, minBuyIn, maxBuyIn);
    } catch (_) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => slug == 'chinese_poker'
                ? ChinesePokerScreen(table: t)
                : PokerTableScreen(table: t),
          ),
        );
      }
    }
  }

  void _showBuyInDialog(
    dynamic t,
    String slug,
    int balance,
    int minBuyIn,
    int maxBuyIn,
  ) {
    int buyIn = minBuyIn;
    final actualMax = balance < maxBuyIn ? balance : maxBuyIn;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Center(
          child: Container(
            width: MediaQuery.of(ctx).size.width * 0.85,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
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
                    'BUY-IN',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${t['name']} | ${t['small_blind']}/${t['big_blind']}',
                    style: TextStyle(
                      color: const Color(0xFFDAA520).withOpacity(0.4),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'กระเป๋า: $balance ชิป',
                        style: TextStyle(
                          color: const Color(0xFFDAA520).withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '$minBuyIn - $maxBuyIn',
                        style: TextStyle(
                          color: const Color(0xFFDAA520).withOpacity(0.3),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$buyIn ชิป',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFFFFD700),
                      inactiveTrackColor: const Color(
                        0xFFDAA520,
                      ).withOpacity(0.15),
                      thumbColor: const Color(0xFFFFD700),
                      overlayColor: const Color(0xFFFFD700).withOpacity(0.1),
                    ),
                    child: Slider(
                      value: buyIn.toDouble(),
                      min: minBuyIn.toDouble(),
                      max: actualMax.toDouble(),
                      divisions: ((actualMax - minBuyIn) / 100).ceil().clamp(
                        1,
                        100,
                      ),
                      onChanged: (v) => setS(() => buyIn = v.round()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _quickChip('MIN', () => setS(() => buyIn = minBuyIn)),
                      _quickChip(
                        '50%',
                        () => setS(
                          () => buyIn = ((minBuyIn + actualMax) / 2).round(),
                        ),
                      ),
                      _quickChip('MAX', () => setS(() => buyIn = actualMax)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E8B57),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 6,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        final tableWithBuyIn = Map<String, dynamic>.from(t);
                        tableWithBuyIn['_buyIn'] = buyIn;
                        // Zoom transition to poker table (Req 11.3)
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            transitionDuration: const Duration(
                              milliseconds: 500,
                            ),
                            reverseTransitionDuration: const Duration(
                              milliseconds: 300,
                            ),
                            pageBuilder: (_, __, ___) => slug == 'chinese_poker'
                                ? ChinesePokerScreen(table: tableWithBuyIn)
                                : PokerTableScreen(table: tableWithBuyIn),
                            transitionsBuilder: (_, animation, __, child) {
                              return ScaleTransition(
                                scale: Tween<double>(begin: 0.0, end: 1.0)
                                    .animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                          ),
                        );
                      },
                      child: Text(
                        'JOIN WITH $buyIn ชิป',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0606),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDAA520).withOpacity(0.25)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
