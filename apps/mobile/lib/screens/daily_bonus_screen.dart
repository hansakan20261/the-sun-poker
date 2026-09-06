import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';
import '../models/bonus_breakdown.dart';
import 'home_screen.dart';

/// Daily Bonus screen with briefcase animation, 3-category bonus breakdown,
/// claim button, and error handling.
///
/// Can be used as a full-screen page (from splash/home) or as a popup dialog
/// (from lobby treasure chest). Set [isPopup] to true when used inside a Dialog.
///
/// Requirements: 10.1–10.9, 11.5
class DailyBonusScreen extends StatefulWidget {
  final bool isPopup;
  const DailyBonusScreen({super.key, this.isPopup = false});
  @override
  State<DailyBonusScreen> createState() => _DailyBonusScreenState();
}

class _DailyBonusScreenState extends State<DailyBonusScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  bool _loadError = false;
  bool _claiming = false;
  bool _claimError = false;
  bool _claimed = false;
  int? _claimedAmount;
  bool _canClaim = true;
  int _dayNumber = 1;
  int _streakCount = 0;

  BonusBreakdown _bonus = const BonusBreakdown(
    gameEntryBonus: 20000,
    lobbyGameBonus: 20000,
    invitationBonus: 10000,
  );

  // Briefcase opening animation (800ms, Req 10.2)
  late AnimationController _briefcaseController;
  late Animation<double> _briefcaseLidAngle;
  late Animation<double> _briefcaseScale;

  // Coin spill particles
  late AnimationController _coinSpillController;
  List<_SpillCoin> _spillCoins = [];

  // Coin collection animation on claim
  late AnimationController _collectController;

  @override
  void initState() {
    super.initState();

    // Briefcase opening: 800ms
    _briefcaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _briefcaseLidAngle = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _briefcaseController, curve: Curves.easeOutBack),
    );
    _briefcaseScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _briefcaseController, curve: Curves.elasticOut),
    );

    // Coin spill particles
    _coinSpillController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1200),
        )..addListener(() {
          if (mounted) setState(() {});
        });

    // Coin collection on claim
    _collectController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1500),
        )..addListener(() {
          if (mounted) setState(() {});
        });
    _collectController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _dismissPopup();
      }
    });

    _loadStatus();
  }

  @override
  void dispose() {
    _briefcaseController.dispose();
    _coinSpillController.dispose();
    _collectController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final data = await ApiService.getDailyBonusStatus();
      if (!mounted) return;

      // Backend returns: { dayNumber, canClaim, streakCount, rewardSchedule }
      final dayNum = data['dayNumber'] ?? 1;
      final schedule = data['rewardSchedule'] as List<dynamic>?;
      int todayReward = 100;
      if (schedule != null && schedule.isNotEmpty) {
        final dayEntry = schedule.firstWhere(
          (e) => e['day'] == dayNum,
          orElse: () => schedule.first,
        );
        todayReward = toInt(dayEntry['coins']);
      }

      // Split reward into 3 visual categories for display
      final gameEntry = (todayReward * 0.4).round();
      final lobbyGame = (todayReward * 0.4).round();
      final invitation = todayReward - gameEntry - lobbyGame;

      setState(() {
        _dayNumber = dayNum;
        _streakCount = data['streakCount'] ?? 0;
        _canClaim = data['canClaim'] ?? true;
        _claimed = !_canClaim;
        _bonus = BonusBreakdown(
          gameEntryBonus: gameEntry,
          lobbyGameBonus: lobbyGame,
          invitationBonus: invitation,
        );
        _loading = false;
        _loadError = false;
      });

      // If already claimed today, show briefly then auto-navigate to home
      if (!_canClaim) {
        _briefcaseController.forward();
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _dismissPopup();
        });
        return;
      }

      // Start briefcase animation within 800ms of appearing (Req 10.2)
      _briefcaseController.forward();
      _startCoinSpill();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
        // Auto-skip to home after 3 seconds if load fails
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _loadError) _dismissPopup();
        });
      }
    }
  }

  void _startCoinSpill() {
    final rng = Random();
    _spillCoins = List.generate(
      20,
      (_) => _SpillCoin(
        startX: 0.4 + rng.nextDouble() * 0.2,
        startY: 0.3,
        endX: rng.nextDouble(),
        endY: 0.1 + rng.nextDouble() * 0.3,
        delay: rng.nextDouble() * 0.3,
        size: 14.0 + rng.nextDouble() * 10,
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _coinSpillController.forward();
    });
  }

  Future<void> _claimBonus() async {
    if (_claiming || _claimed) return;
    setState(() {
      _claiming = true;
      _claimError = false;
    });
    try {
      final result = await ApiService.claimDailyBonus();
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          _claimed = true;
          _canClaim = false;
          _claimedAmount = toInt(
            result['coinsAwarded'] ?? result['coins_awarded'] ?? _bonus.total,
          );
        });
        // Play coin collection animation then dismiss (Req 10.7)
        _collectController.forward();
      } else {
        setState(() {
          _claimError = true;
          _claiming = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 400 && e.message.contains('Already claimed')) {
        // Already claimed today — just mark as claimed
        setState(() {
          _claimed = true;
          _canClaim = false;
          _claiming = false;
        });
      } else {
        setState(() {
          _claimError = true;
          _claiming = false;
        });
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _claimError = true;
          _claiming = false;
        });
    }
  }

  void _dismissPopup() {
    if (!mounted) return;
    if (widget.isPopup) {
      Navigator.of(context).pop();
    } else {
      // Full-screen mode: navigate to HomeScreen
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.of(context).size.height *
              (widget.isPopup ? 0.75 : 1.0),
        ),
        decoration: SunTheme.cardDecoration(
          radius: 24,
          bgColor: const Color(0xFF1A0606),
        ),
        child: _loading
            ? const SizedBox(
                height: 300,
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                ),
              )
            : _loadError
            ? _buildLoadError()
            : _buildContent(),
      ),
    );

    if (widget.isPopup) return content;

    // Full-screen mode with Scaffold
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/lobby_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF3A0A0A),
                    Color(0xFF1A0505),
                    Color(0xFF0E0303),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(padding: const EdgeInsets.all(16), child: content),
            ),
          ),
        ],
      ),
    );
  }

  /// Error view with retry and skip (Req 10.9).
  Widget _buildLoadError() {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text(
              'ไม่สามารถโหลดโบนัสได้',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // "ลองอีกครั้ง" (Retry)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SunTheme.green,
                  ),
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _loadError = false;
                    });
                    _loadStatus();
                  },
                  child: Text(ThaiLabels.retry),
                ),
                const SizedBox(width: 16),
                // "ข้าม" (Skip)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                  ),
                  onPressed: _dismissPopup,
                  child: Text(ThaiLabels.skip),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        // Coin spill particles
        if (_coinSpillController.isAnimating ||
            _coinSpillController.isCompleted)
          ..._buildCoinSpill(),
        // Coin collection overlay
        if (_collectController.isAnimating) _buildCollectOverlay(),
        // Main content
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: _dismissPopup,
                  child: const Icon(
                    Icons.close,
                    color: Colors.white54,
                    size: 24,
                  ),
                ),
              ),
              // Title "DAILY BONUS" with dramatic lighting (Req 10.1)
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [
                    Color(0xFFFFE082),
                    Color(0xFFFFD700),
                    Color(0xFFB8860B),
                  ],
                ).createShader(b),
                child: Text(
                  ThaiLabels.dailyBonus,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 3,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 10,
                        offset: Offset(2, 3),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Briefcase animation (Req 10.2)
              _buildBriefcaseAnimation(),
              const SizedBox(height: 16),
              // Total bonus in Thai format (Req 10.3)
              Text(
                '${NumberFormatter.formatWithCommas(_bonus.total)} ${ThaiLabels.gold}',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                ),
              ),
              const SizedBox(height: 20),
              // 3-category Bonus Breakdown with "+" separators (Req 10.4, 10.5)
              _buildBonusBreakdown(),
              const SizedBox(height: 24),
              // Claim error with retry (Req 10.9)
              if (_claimError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'เกิดข้อผิดพลาด',
                        style: TextStyle(color: Colors.red, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _claimBonus,
                        child: Text(
                          ThaiLabels.retry,
                          style: const TextStyle(
                            color: SunTheme.goldLight,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Green "รับ" (Claim) button (Req 10.6)
              _buildClaimButton(),
              const SizedBox(height: 12),
              // Invitation text (Req 10.8)
              Text(
                ThaiLabels.bonusInviteText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFDAA520).withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Briefcase opening animation with gold coins spilling out (Req 10.2).
  Widget _buildBriefcaseAnimation() {
    return AnimatedBuilder(
      animation: _briefcaseController,
      builder: (_, __) {
        return Transform.scale(
          scale: _briefcaseScale.value,
          child: SizedBox(
            height: 100,
            width: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Briefcase body
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 100,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF8B6914),
                          Color(0xFF6B4F0A),
                          Color(0xFF4A3507),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFDAA520),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.3),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.lock_open,
                        color: Color(0xFFFFD700),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // Lid (rotates open)
                Positioned(
                  top: 0,
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(-_briefcaseLidAngle.value * 1.2),
                    child: Container(
                      width: 100,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFDAA520), Color(0xFF8B6914)],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        border: Border.all(
                          color: const Color(0xFFFFD700),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 30,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Gold glow when open
                if (_briefcaseLidAngle.value > 0.5)
                  Positioned(
                    top: 20,
                    child: Container(
                      width: 80,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            const Color(
                              0xFFFFD700,
                            ).withOpacity(0.4 * _briefcaseLidAngle.value),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 3-category Bonus Breakdown with "+" separators (Req 10.4, 10.5).
  Widget _buildBonusBreakdown() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildBonusCategory(ThaiLabels.gameEntryBonus, _bonus.gameEntryBonus),
        _buildPlusSeparator(),
        _buildBonusCategory(ThaiLabels.lobbyGameBonus, _bonus.lobbyGameBonus),
        _buildPlusSeparator(),
        _buildBonusCategory(ThaiLabels.invitationBonus, _bonus.invitationBonus),
      ],
    );
  }

  Widget _buildBonusCategory(String label, int amount) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFDAA520).withOpacity(0.2),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ชิป', style: TextStyle(fontSize: 22)),
                const SizedBox(height: 4),
                Text(
                  NumberFormatter.formatWithCommas(amount),
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFFDAA520).withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlusSeparator() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 20),
      child: Text(
        '+',
        style: TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Green "รับ" (Claim) button (Req 10.6).
  Widget _buildClaimButton() {
    // Already claimed: show "received today" message
    if (_claimed && !_claiming) {
      return Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey.shade700, Colors.grey.shade800],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            '✓ รับแล้ววันนี้',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: (!_claiming && !_claimed) ? _claimBonus : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3CB371), Color(0xFF2E8B57), Color(0xFF155C30)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2E8B57).withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: _claiming
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  ThaiLabels.claim,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
        ),
      ),
    );
  }

  /// Coin spill particles from briefcase.
  List<Widget> _buildCoinSpill() {
    return _spillCoins.map((coin) {
      final progress =
          ((_coinSpillController.value - coin.delay) / (1.0 - coin.delay))
              .clamp(0.0, 1.0);
      final x = coin.startX + (coin.endX - coin.startX) * progress;
      final y =
          coin.startY -
          (coin.startY - coin.endY) * Curves.easeOutCubic.transform(progress);
      final opacity = progress < 0.1
          ? progress * 10
          : (progress > 0.7 ? (1 - progress) / 0.3 : 1.0);
      return Positioned(
        left: x * 280,
        top: y * 400,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Text('ชิป', style: TextStyle(fontSize: coin.size)),
        ),
      );
    }).toList();
  }

  /// Coin collection animation overlay on claim (Req 10.7).
  Widget _buildCollectOverlay() {
    final progress = _collectController.value;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            builder: (_, v, child) => Opacity(
              opacity: v * (1 - progress),
              child: Transform.scale(scale: 0.5 + v * 0.5, child: child),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFDAA520)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.5),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Text(
                '+${NumberFormatter.formatWithCommas(_claimedAmount ?? _bonus.total)} ชิป',
                style: const TextStyle(
                  color: Color(0xFF3A0A0A),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpillCoin {
  final double startX, startY, endX, endY, delay, size;
  const _SpillCoin({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.delay,
    required this.size,
  });
}
