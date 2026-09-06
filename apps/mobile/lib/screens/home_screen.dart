import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/audio_manager.dart';
import '../services/profile_provider.dart';
import '../services/runtime_config_service.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';
import '../services/feature_flags_service.dart';
import 'lobby_screen.dart';
import 'profile_screen.dart';
import 'shop_screen.dart';
import 'club_screen.dart';
import 'tournament_screen.dart';
import 'daily_bonus_screen.dart';
import 'practice_room_screen.dart';
import 'settings_screen.dart';
import 'friends_screen.dart';
import '../widgets/hand_history_sheet.dart';
import '../widgets/transaction_history_popup.dart';
import '../widgets/app_background.dart';
import '../widgets/falling_items_overlay.dart';
import '../widgets/poker_chip_icon.dart';

class HomeScreen extends StatefulWidget {
  final bool showDailyBonus;
  const HomeScreen({super.key, this.showDailyBonus = false});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // 0=ร้านค้า 1=ทัวร์ 2=Home 3=คลับ 4=โปรไฟล์
  int _tab = 2;
  Map<String, dynamic>? _profile;
  bool _bonusClaimable = false;
  Timer? _refreshTimer;
  Timer? _bannerTimer;
  final PageController _bannerCtrl = PageController();
  int _bannerPage = 0;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    ProfileProvider.instance.addListener(_onProfileChanged);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween(
      begin: 0.88,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadProfile();
    _checkBonus();
    // Start background music
    AudioManager.instance.startBgm();
    _startConfiguredTimers();

    // Show daily bonus popup if requested from splash
    if (widget.showDailyBonus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openBonus();
      });
    }
  }

  Future<void> _startConfiguredTimers() async {
    try {
      await RuntimeConfigService.load();
      if (!mounted) return;
      _refreshTimer = Timer.periodic(
        Duration(
          seconds: RuntimeConfigService.integer('balance_poll_interval_sec'),
        ),
        (_) => _refreshBal(),
      );
      _bannerTimer = Timer.periodic(
        Duration(
          seconds: RuntimeConfigService.integer(
            'promotion_banner_interval_sec',
          ),
        ),
        (_) {
          if (!mounted || !_bannerCtrl.hasClients) return;
          _bannerPage = (_bannerPage + 1) % _promoBanners.length;
          _bannerCtrl.animateToPage(
            _bannerPage,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        },
      );
    } catch (error) {
      debugPrint('Runtime config timers unavailable: $error');
    }
  }

  @override
  void dispose() {
    ProfileProvider.instance.removeListener(_onProfileChanged);
    _pulseCtrl.dispose();
    _refreshTimer?.cancel();
    _bannerTimer?.cancel();
    _bannerCtrl.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted)
      setState(() {
        _profile = ProfileProvider.instance.profile;
      });
  }

  Future<void> _refreshBal() async {
    await ProfileProvider.instance.refreshBalance();
    if (mounted)
      setState(() {
        _profile = ProfileProvider.instance.profile;
      });
  }

  Future<void> _loadProfile() async {
    await ProfileProvider.instance.load();
    if (!mounted) return;
    setState(() {
      _profile = ProfileProvider.instance.profile;
      if (_profile != null)
        _profile!['balance'] = ProfileProvider.instance.balance;
    });
  }

  Future<void> _checkBonus() async {
    try {
      final d = await ApiService.getDailyBonusStatus();
      if (mounted) setState(() => _bonusClaimable = d['canClaim'] ?? false);
    } catch (_) {}
  }

  void _openBonus() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(16),
        child: DailyBonusScreen(isPopup: true),
      ),
    ).then((_) {
      _checkBonus();
      _loadProfile();
    });
  }

  void _push(Widget s) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => s));
  void _slideRight(Widget s) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => s,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, a, __, c) => SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
          child: c,
        ),
      ),
    );
  }

  static const _cardFaces = [
    'A♠',
    'K♥',
    'Q♦',
    'J♣',
    '10♥',
    '9♠',
    'A♥',
    'K♠',
    'Q♣',
    'J♦',
  ];

  Widget _buildFallingWidget(_FallingItem item) {
    switch (item.type) {
      case 0: // Playing card
        final face = _cardFaces[(item.x * 100).toInt() % _cardFaces.length];
        final isRed = face.contains('♥') || face.contains('♦');
        return Container(
          width: item.size * 0.7,
          height: item.size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4),
            ],
          ),
          child: Center(
            child: Text(
              face.substring(face.length - 1),
              style: TextStyle(
                color: isRed ? Colors.red.shade700 : Colors.black87,
                fontSize: item.size * 0.35,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case 1: // Coin
        return Container(
          width: item.size,
          height: item.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFFFFE082), Color(0xFFFFD700), Color(0xFFB8860B)],
              stops: [0.0, 0.6, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.4),
                blurRadius: 6,
              ),
            ],
          ),
          child: Center(
            child: Text(
              'C',
              style: TextStyle(
                color: const Color(0xFF8B6000),
                fontSize: item.size * 0.45,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      default: // Banknote
        return Container(
          width: item.size * 1.6,
          height: item.size * 0.85,
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF4CAF50).withOpacity(0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4),
            ],
          ),
          child: Center(
            child: Text('💵', style: TextStyle(fontSize: item.size * 0.45)),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: AppBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Glow
            Positioned(
              top: -100,
              left: 0,
              right: 0,
              child: Container(
                height: 320,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF8B0000).withOpacity(0.12),
                      Colors.transparent,
                    ],
                    radius: 0.9,
                  ),
                ),
              ),
            ),
            // Falling items overlay — behind all content
            if (_tab == 2) const FallingItemsOverlay(),
            // Content
            IndexedStack(
              index: _tab,
              children: [
                const ShopScreen(),
                const TournamentScreen(isEmbedded: true),
                _homeContent(),
                const ClubScreen(isEmbedded: true),
                const ProfileScreen(),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  // ═══════════════════════════════════════
  //  HOME CONTENT
  // ═══════════════════════════════════════
  Widget _homeContent() {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _topBar()),
          SliverToBoxAdapter(
            child: SizedBox(
              height:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  140,
              child: Center(child: _gameHub()),
            ),
          ),
        ],
      ),
    );
  }

  // ── TOP BAR ──
  Widget _topBar() {
    final name = _profile?['display_name'] ?? _profile?['username'] ?? 'Player';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          // Avatar → Profile
          GestureDetector(
            onTap: () => setState(() => _tab = 4),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ProfileProvider.instance.avatarImage == null
                    ? const LinearGradient(
                        colors: [Color(0xFFDAA520), Color(0xFF8B6914)],
                      )
                    : null,
                border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.7),
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFCC2222).withOpacity(0.45),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.2),
                    blurRadius: 16,
                  ),
                ],
                image: ProfileProvider.instance.avatarImage != null
                    ? DecorationImage(
                        image: ProfileProvider.instance.avatarImage!,
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: ProfileProvider.instance.avatarImage == null
                  ? Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'P',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'สวัสดี 👋',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 12,
                  ),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Balance + top-up + bonus gift
          GestureDetector(
            onTap: () => setState(() => _tab = 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.55),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFCC2222).withOpacity(0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.10),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PokerChipIcon(amount: toInt(_profile?['balance']), size: 22),
                  const SizedBox(width: 6),
                  Text(
                    NumberFormatter.formatAbbreviated(
                      toInt(_profile?['balance']),
                    ),
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Daily bonus — FREE button
          GestureDetector(
            onTap: _openBonus,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: _bonusClaimable
                    ? const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                      )
                    : null,
                color: _bonusClaimable ? null : Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _bonusClaimable
                      ? const Color(0xFFFFD700).withOpacity(0.8)
                      : const Color(0xFFFFD700).withOpacity(0.55),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFCC2222).withOpacity(0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                  if (_bonusClaimable)
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.3),
                      blurRadius: 14,
                    ),
                ],
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Text('🎁', style: TextStyle(fontSize: 18)),
                  ),
                  if (_bonusClaimable)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFFD700),
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topIcon(IconData ic, VoidCallback onTap, {bool badge = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFFD700).withOpacity(0.55),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFCC2222).withOpacity(0.35),
              blurRadius: 10,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.10),
              blurRadius: 14,
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(child: Icon(ic, color: Colors.white70, size: 21)),
            if (badge)
              Positioned(
                right: 7,
                top: 7,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFD700).withOpacity(0.6),
                      width: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── WALLET CARD ──
  Widget _walletCard() {
    final bal = toInt(_profile?['balance']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A0E0E), Color(0xFF1C0808), Color(0xFF250D0D)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFDAA520).withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // VIP + Bonus
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDAA520), Color(0xFFB8860B)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield,
                        color: Color(0xFF3A0A0A),
                        size: 13,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'VIP ${_profile?['vip_level'] ?? 0}',
                        style: const TextStyle(
                          color: Color(0xFF3A0A0A),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _openBonus,
                  child: _BonusPill(pulse: _pulse, active: _bonusClaimable),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Balance
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PokerChipIcon(amount: bal, size: 34),
                const SizedBox(width: 8),
                Text(
                  NumberFormatter.formatWithCommas(bal),
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black, blurRadius: 12)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'ยอดเหรียญของคุณ',
              style: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 18),
            // Quick actions
            Row(
              children: [
                _quickAction(
                  'เติมเหรียญ',
                  Icons.add_circle_outline,
                  const Color(0xFF2E8B57),
                  () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 10),
                _quickAction(
                  'โบนัสรายวัน',
                  Icons.card_giftcard_outlined,
                  const Color(0xFFDAA520),
                  _openBonus,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(String label, IconData ic, Color c, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: c.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withOpacity(0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ic, color: c, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: c,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── PROMO BANNER SLIDER ──
  static const _promoBanners = [
    _PromoBanner('🎰 SPINUP เปิดแล้ว!', 'หมุนวงล้อลุ้นรางวัลใหญ่', [
      Color(0xFF4A148C),
      Color(0xFF7B1FA2),
    ], Icons.casino),
    _PromoBanner('🀄 ไพ่สามกอง OFC', 'เล่นกับเพื่อน 2-4 คน', [
      Color(0xFF1A3A5C),
      Color(0xFF0D47A1),
    ], Icons.style),
    _PromoBanner('🃏 Texas Hold\'em', 'โต๊ะใหม่เปิดทุกวัน', [
      Color(0xFF8B0000),
      Color(0xFFB71C1C),
    ], Icons.casino_outlined),
    _PromoBanner('🎁 โบนัสรายวัน', 'เข้าเกมทุกวัน รับเหรียญฟรี', [
      Color(0xFF1B5E20),
      Color(0xFF2E7D32),
    ], Icons.card_giftcard),
    _PromoBanner('👥 สร้างคลับ', 'เล่นกับเพื่อนในคลับส่วนตัว', [
      Color(0xFF4E342E),
      Color(0xFF6D4C41),
    ], Icons.groups),
  ];

  Widget _promoBannerSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 100,
            child: PageView.builder(
              controller: _bannerCtrl,
              itemCount: _promoBanners.length,
              onPageChanged: (i) => setState(() => _bannerPage = i),
              itemBuilder: (_, i) {
                final b = _promoBanners[i];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: b.colors,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: b.colors[0].withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Background icon
                      Positioned(
                        right: 16,
                        bottom: -8,
                        child: Icon(
                          b.icon,
                          size: 80,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      // Content
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              b.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(color: Colors.black38, blurRadius: 4),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              b.subtitle,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Dots indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < _promoBanners.length; i++)
                Container(
                  width: _bannerPage == i ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _bannerPage == i
                        ? const Color(0xFFFFD700)
                        : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── DAILY BONUS BANNER ──
  Widget _dailyBonusBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _openBonus,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _bonusClaimable
                  ? [const Color(0xFF2E6B30), const Color(0xFF1A4520)]
                  : [const Color(0xFF2A0E0E), const Color(0xFF1C0808)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _bonusClaimable
                  ? Colors.greenAccent.withOpacity(0.4)
                  : const Color(0xFFDAA520).withOpacity(0.15),
            ),
          ),
          child: Row(
            children: [
              const Text('🎁', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bonusClaimable ? 'โบนัสรายวันพร้อมรับ!' : 'โบนัสรายวัน',
                      style: TextStyle(
                        color: _bonusClaimable
                            ? Colors.greenAccent
                            : const Color(0xFFFFD700),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _bonusClaimable
                          ? 'แตะเพื่อรับเหรียญฟรี'
                          : 'กลับมารับทุกวัน',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _bonusClaimable ? Icons.redeem : Icons.chevron_right,
                color: _bonusClaimable ? Colors.greenAccent : Colors.white24,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── GAME HUB — layout ใหม่: 2 featured cards บน + 4 grid ล่าง ──
  Widget _gameHub() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final halfW = (w - 10) / 2;

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Row 1: NLH (ใหญ่) + OFC (ใหญ่) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _hubCard(
                    'NLH',
                    'โป๊กเกอร์',
                    '2-9 ผู้เล่น',
                    'assets/hub_poker.png',
                    () => _slideRight(
                      const LobbyScreen(filterGameSlug: 'texas_holdem'),
                    ),
                    width: halfW,
                    height: 180,
                  ),
                  const SizedBox(width: 10),
                  _hubCard(
                    'OFC',
                    'ไพ่สามกอง',
                    '2-4 ผู้เล่น',
                    'assets/hub_ofc.png',
                    () => _slideRight(
                      const LobbyScreen(filterGameSlug: 'chinese_poker'),
                    ),
                    width: halfW,
                    height: 180,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Row 2: TOURNAMENT (wide) ──
              _hubCard(
                'TOURNAMENT',
                'ทัวร์นาเมนต์',
                'แข่งชิงรางวัล',
                'assets/hub_tournament.png',
                () => setState(() => _tab = 1),
                width: w,
                height: 160,
              ),

              const SizedBox(height: 10),

              // ── Row 3: SPINUP + LOBBY (เล็ก) ──
              Row(
                children: [
                  _hubCard(
                    'SPINUP',
                    'หมุนแล้วเล่น',
                    'เร็วๆ นี้',
                    'assets/hub_spinup.png',
                    () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('SPINUP — เร็วๆ นี้!'),
                        backgroundColor: Color(0xFF4A148C),
                      ),
                    ),
                    width: halfW,
                    height: 140,
                  ),
                  const SizedBox(width: 10),
                  _hubCard(
                    'LOBBY',
                    'เข้าล็อบบี้',
                    'เล่นเลย >',
                    'assets/hub_vip_club.png',
                    () => _slideRight(const LobbyScreen()),
                    width: halfW,
                    height: 140,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Row 4: PRACTICE (wide) ──
              _hubCard(
                'FREE',
                'ทดลองเล่น',
                'ชิปฟรี — ไม่ใช้เหรียญจริง',
                'assets/hub_practice.jpg',
                () =>
                    _slideRight(const LobbyScreen(filterGameSlug: 'practice')),
                width: w,
                height: 110,
                showLabel: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _hubCard(
    String badge,
    String title,
    String sub,
    String imagePath,
    VoidCallback onTap, {
    required double width,
    required double height,
    bool showLabel = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: height,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFFD700).withOpacity(0.55),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFCC2222).withOpacity(0.45),
                blurRadius: 14,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.18),
                blurRadius: 20,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // รูปเต็ม cover เท่ากันทุกการ์ด
                Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1A0303)),
                ),
                // Gradient ด้านล่างให้ข้อความอ่านได้
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 65,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.80),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Badge บนซ้าย
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                // ชื่อ + subtitle ล่างซ้าย
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        sub,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── PLAY BUTTONS ──
  Widget _playButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // เล่นเลย
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => _slideRight(const LobbyScreen()),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFCC2222),
                      Color(0xFF8B0000),
                      Color(0xFF5C0000),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withOpacity(0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B0000).withOpacity(0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.casino,
                      color: Color(0xFFFFD700),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'เล่นเลย',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: const Color(0xFFFFD700).withOpacity(0.5),
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ทดลอง
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _push(const PracticeRoomScreen()),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFF8C00).withOpacity(0.12),
                      const Color(0xFFFF6600).withOpacity(0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFF8C00).withOpacity(0.28),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.science_outlined,
                      color: Color(0xFFFF8C00),
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'ทดลอง',
                      style: TextStyle(
                        color: Color(0xFFFF8C00),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── GAME CARDS (horizontal) ──
  Widget _gamesRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'เกม',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            children: [
              _gameCard(
                'NLH',
                'Texas Hold\'em',
                '🃏',
                const [Color(0xFF8B0000), Color(0xFF5C0000)],
                () => _slideRight(
                  const LobbyScreen(filterGameSlug: 'texas_holdem'),
                ),
              ),
              const SizedBox(width: 12),
              _gameCard(
                'OFC',
                'ไพ่สามกอง',
                '🀄',
                const [Color(0xFF1A3A5C), Color(0xFF0E2240)],
                () => _slideRight(
                  const LobbyScreen(filterGameSlug: 'chinese_poker'),
                ),
              ),
              const SizedBox(width: 12),
              _gameCard(
                'SPINUP',
                'หมุนแล้วเล่น',
                '🎰',
                const [Color(0xFF4A148C), Color(0xFF311B92)],
                () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('SPINUP — เร็วๆ นี้!'),
                    backgroundColor: Color(0xFF4A148C),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _gameCard('TOURNAMENT', 'ทัวร์นาเมนต์', '🏆', const [
                Color(0xFF8B6914),
                Color(0xFF5C4A0E),
              ], () => setState(() => _tab = 1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gameCard(
    String title,
    String sub,
    String emoji,
    List<Color> colors,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
          boxShadow: [
            BoxShadow(
              color: colors[0].withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── CLUB ROW ──
  Widget _clubRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'คลับ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _clubBtn(
                  'เข้าร่วมคลับ',
                  Icons.group_add_outlined,
                  const Color(0xFF2E8B57),
                  () => setState(() => _tab = 3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _clubBtn(
                  'สร้างคลับ',
                  Icons.add_business_outlined,
                  const Color(0xFF8B6914),
                  () => setState(() => _tab = 3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _clubBtn(String label, IconData ic, Color c, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withOpacity(0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.withOpacity(0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(ic, color: c, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: c.withOpacity(0.4), size: 18),
          ],
        ),
      ),
    );
  }

  // ── INVITE BANNER ──
  Widget _inviteBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A0808), Color(0xFF2A0E0E)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDAA520).withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🎉 เชิญเพื่อนรับโบนัส',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ชวนเพื่อนมาเล่น รับเหรียญฟรีทั้งคู่!',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _push(const FriendsScreen()),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDAA520), Color(0xFF8B6914)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'เชิญ',
                  style: TextStyle(
                    color: Color(0xFF1A0505),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  BOTTOM NAV BAR (ตามรูป reference)
  // ═══════════════════════════════════════
  Widget _bottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E0303).withOpacity(0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.04))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (FeatureFlagsService.isEnabled('menu_shop'))
                _navTab(
                  0,
                  Icons.storefront_outlined,
                  Icons.storefront,
                  'ร้านค้า',
                ),
              if (FeatureFlagsService.isEnabled('menu_tournaments'))
                _navTab(
                  1,
                  Icons.emoji_events_outlined,
                  Icons.emoji_events,
                  'ทัวร์',
                ),
              _navHome(),
              if (FeatureFlagsService.isEnabled('menu_clubs'))
                _navTab(3, Icons.groups_outlined, Icons.groups, 'คลับ'),
              _navTab(4, Icons.person_outline, Icons.person, 'โปรไฟล์'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navTab(int i, IconData off, IconData on, String label) {
    final active = _tab == i;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? on : off,
              color: active ? const Color(0xFFFFD700) : Colors.white30,
              size: 25,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFFFFD700) : Colors.white30,
                fontSize: 9,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navHome() {
    final active = _tab == 2;
    return GestureDetector(
      onTap: () => setState(() => _tab = 2),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE02020),
                    Color(0xFFCC2222),
                    Color(0xFF8B0000),
                  ],
                )
              : LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.06),
                    Colors.white.withOpacity(0.03),
                  ],
                ),
          border: Border.all(
            color: active
                ? const Color(0xFFFFD700).withOpacity(0.6)
                : Colors.white10,
            width: 2.5,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFFCC2222).withOpacity(0.5),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.15),
                    blurRadius: 20,
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.home_rounded,
          color: active ? const Color(0xFFFFD700) : Colors.white30,
          size: 28,
        ),
      ),
    );
  }
}

// ── Bonus Pill (animated glow when claimable) ──
class _BonusPill extends AnimatedWidget {
  final bool active;
  const _BonusPill({required Animation<double> pulse, required this.active})
    : super(listenable: pulse);
  @override
  Widget build(BuildContext context) {
    final v = (listenable as Animation<double>).value;
    return Transform.scale(
      scale: active ? v : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                )
              : LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.08),
                    Colors.white.withOpacity(0.04),
                  ],
                ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(active ? '🎁' : '📦', style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              active ? 'รับโบนัส!' : 'โบนัสวันนี้',
              style: TextStyle(
                color: active
                    ? const Color(0xFF3A0A0A)
                    : Colors.white.withOpacity(0.45),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoBanner {
  final String title;
  final String subtitle;
  final List<Color> colors;
  final IconData icon;
  const _PromoBanner(this.title, this.subtitle, this.colors, this.icon);
}

class _FallingItem {
  final double x, delay, speed, size, rotSpeed;
  final int type; // 0=card, 1=coin, 2=banknote
  const _FallingItem({
    required this.x,
    required this.delay,
    required this.speed,
    required this.size,
    required this.type,
    required this.rotSpeed,
  });
}
