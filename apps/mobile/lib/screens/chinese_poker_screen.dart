import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme.dart';
import '../services/api_service.dart';
import '../services/game_socket.dart';
import '../services/runtime_config_service.dart';
import '../utils/number_formatter.dart';
import '../utils/hand_evaluator.dart';
import '../utils/ofc_scorer.dart';
import '../utils/ofc_auto_arrange.dart';
import '../utils/thai_labels.dart';
import '../utils/timer_logic.dart';
import '../layout/responsive_layout_engine.dart';
import '../models/ofc_game_state.dart';
import '../widgets/playing_card.dart';
import '../widgets/result_overlay.dart';
import '../widgets/hand_history_sheet.dart';
import '../widgets/card_placement_area.dart';
import '../widgets/ofc_action_bar.dart';
import '../widgets/turn_indicator.dart';
import '../widgets/recommendation_badge.dart';
import '../widgets/sun_button.dart';
import '../widgets/chip_animation.dart';
import '../widgets/card_deal_sequence.dart';
import '../widgets/deal_to_players_animation.dart';
import '../widgets/game_effects.dart';
import '../widgets/table_seat_layout.dart';
import '../widgets/perspective_table_layout.dart';
import '../widgets/player_avatar_3d.dart';
import '../widgets/game_stage.dart';
import '../services/fullscreen_helper.dart';
import '../utils/free_tips_engine.dart';
import '../services/audio_manager.dart';
import '../services/profile_provider.dart';
import 'lobby_screen.dart';

/// OFC (Open Face Chinese Poker / ไพ่สามกอง) game screen.
///
/// Tasks 17.1, 17.2, 17.3: Major overhaul sharing NLH table visual style,
/// with round-based dealing, three-hand arrangement, scoring, royalties,
/// foul detection, and Fantasyland mode.
///
/// Requirements: 23.1–23.9, 24.1–24.9, 25.1–25.7, 26.1–26.7,
///               27.1–27.7, 28.1–28.8, 29.1–29.10
/// Reference design size for the FUNCTIONAL game content only (seats,
/// cards, chips — everything inside [GameStage] via
/// _buildChineseTableLayout). Matches the mobile-landscape breakpoint
/// PerspectiveTableLayout's own internal clamp()/scale formulas already
/// saturate around, and equals one of the required test breakpoints.
///
/// IMPORTANT: the decorative room photo (assets/bg_ofc_room.jpg) is
/// deliberately rendered OUTSIDE GameStage as a separate full-bleed
/// BoxFit.cover layer (see build()) — it has no alignment-critical
/// content (seats are positioned by percentage of their own container,
/// not by exact pixel coordinates in this photo), so locking it to this
/// design box only produced empty letterbox bars on viewports with a
/// different aspect ratio, with no benefit. Keeping it outside GameStage
/// is what makes the background actually fill the whole screen.
const double kGameStageDesignWidth = 844.0;
const double kGameStageDesignHeight = 390.0;

class ChinesePokerScreen extends StatefulWidget {
  final Map<String, dynamic> table;
  const ChinesePokerScreen({super.key, required this.table});
  @override
  State<ChinesePokerScreen> createState() => _ChinesePokerScreenState();
}

class _ChinesePokerScreenState extends State<ChinesePokerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Game state ──
  String _phase =
      'waiting'; // waiting, dealing, placing/arranging, showdown, result
  int _currentRound = 1; // 1–8
  List<String> _hand = []; // Unplaced cards in current round
  List<String> _front = [];
  List<String> _middle = [];
  List<String> _back = [];
  bool _showResult = false;
  bool _isWinner = false;
  int _resultAmount = 0;
  int _myChips = 0;
  late int _mySeat;
  Map<int, Map<String, dynamic>> _serverPlayers = {};
  List<dynamic> _resultData = [];
  int? _currentPlayerSeat;
  bool _showMenu = false;
  bool _isFantasyland = false;

  // ── Showdown reveal state ──
  int _showdownRevealStep = 0; // 0=none, 1=back, 2=middle, 3=front, 4=done
  bool _showdownActive = false;
  bool _showDragonPopup = false; // Dragon (13 different ranks) detected
  int _dragonSeat = -1;
  bool _showFantasylandPopup = false; // Fantasyland qualification popup
  int _fantasylandSeat = -1;

  // ── Recommendation state ──
  bool _showRecommendation = false;
  Map<String, List<String>>? _recommendedArrangement;
  // ── Deal animation state ──
  bool _showDealSequence = false;
  List<String> _dealSequenceCards = [];
  bool _cardsRevealed =
      false; // true after deal animation completes and cards flip
  // Active row for guided placement: 'back' → 'middle' → 'front'
  String _activeRow = 'back';
  bool _guidedMode = true; // true = guided step-by-step, false = free placement
  bool _hasConfirmedArrangement = false;
  bool _pendingNewRound = false; // flag to prevent multiple delayed transitions
  List<String> _pendingHand = []; // cards for next round saved during hold

  // ── Timer state (Task 17.1: TurnIndicator integration) ──
  int _turnTotalSeconds = 0;
  int _turnRemainingSeconds = 0;
  int _minimumPlayMinutes = 0;
  Timer? _countdownTimer;

  // ── Scoring state (Task 17.3) ──
  Map<int, int> _playerPoints = {}; // seat → running point total
  Map<int, int> _playerRoyalties = {}; // seat → last royalty earned
  Map<int, bool> _playerFouls = {}; // seat → foul status
  Map<int, bool> _playerFantasyland = {}; // seat → fantasyland status
  Map<int, int> _playerCoinChange =
      {}; // seat → last round coin change (win/lose)

  // ── Animation controllers (Task 17.3: royalty sparkle) ──
  late AnimationController _royaltyAnimController;
  late Animation<double> _royaltyCountAnimation;
  int _royaltyDisplayValue = 0;
  int _royaltyTargetValue = 0;

  // ── Chip animation ──
  final ChipAnimationController _chipAnimController = ChipAnimationController();
  bool _showConfetti = false;

  // ── Reset animation (Task 17.2: 300ms reset) ──
  late AnimationController _resetAnimController;
  bool _isResetting = false;

  // ── Task 11.7: Responsive layout engine (Req 8.1, 8.7, 9.4, 9.5) ──
  ResponsiveLayoutEngine? _layoutEngine;

  /// Responsive layout engine accessor — always returns the current engine.
  /// Initialized at the start of each build cycle from screen width.
  ResponsiveLayoutEngine get engine => _layoutEngine!;

  /// Animation scale factor based on screen size (Req 9.4).
  /// Use to scale animation distances/durations proportionally.
  double get animationScale => _layoutEngine?.animationScale ?? 1.0;

  // ── Fade-out for navigation ──
  double _fadeOutOpacity = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Force landscape for Chinese Poker (4-seat table layout)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _royaltyAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _royaltyCountAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _royaltyAnimController, curve: Curves.easeOut),
    );
    _resetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Restore portrait when leaving
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _countdownTimer?.cancel();
    _royaltyAnimController.dispose();
    _resetAnimController.dispose();
    _chipAnimController.dispose();
    GameSocket.disconnect();
    super.dispose();
  }

  /// เมื่อ app กลับจาก background → reconnect socket + resync timer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [CP] App resumed — reconnecting and resyncing timer');
      // Force reconnect if socket disconnected during background
      if (!GameSocket.isConnected) {
        _connectSocket();
      } else {
        // Socket still connected — request fresh state to resync timer
        final tid = widget.table['id'];
        if (tid != null) {
          GameSocket.joinChinese(
            tid,
            _mySeat,
            0,
            accessToken: widget.table['_roomAccessToken'],
          ); // rejoin with 0 buyIn = resync only
        }
      }
      // Restart countdown timer if in placing phase
      if ((_phase == 'arranging' || _phase == 'placing') &&
          !_showResult &&
          !_hasConfirmedArrangement) {
        _stopCountdownTimer();
        _startCountdownTimer();
      }
    } else if (state == AppLifecycleState.paused) {
      debugPrint('⏸️ [CP] App paused — stopping local timer');
      _stopCountdownTimer();
    }
  }

  /// Start local countdown timer (1 second interval)
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_turnRemainingSeconds > 0) {
          _turnRemainingSeconds--;
          if (_turnRemainingSeconds <= 5 && _turnRemainingSeconds > 0) {
            AudioManager.instance.play(SoundEffect.countdownUrgent);
          } else if (_turnRemainingSeconds > 5) {
            AudioManager.instance.play(SoundEffect.countdownTick);
          }
        } else {
          timer.cancel();
          _countdownTimer = null;
          // Auto-place and confirm when time runs out
          _autoPlaceAndConfirm();
        }
      });
    });
  }

  /// Stop local countdown timer
  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  // Time lock: player must stay minimum 30 minutes (starts from first hand played)
  late DateTime _joinedAt;
  DateTime? _firstHandPlayedAt; // null = hasn't played yet → can leave freely

  Future<void> _init() async {
    _joinedAt = DateTime.now();
    _mySeat = 1; // Auto-join seat 1 (no seat selection)
    _hasJoinedChinese = true;

    final isPractice = widget.table['_isPractice'] == true;
    if (isPractice) {
      _myChips = toInt(widget.table['_buyIn'] ?? 10000);
    } else {
      _myChips = toInt(
        widget.table['_buyIn'] ?? widget.table['min_buy_in'] ?? 0,
      );
    }
    _connectSocket();
  }

  // ═══════════════════════════════════════════════════════════
  // Socket connection (reuses existing GameSocket.connectChinese)
  // ═══════════════════════════════════════════════════════════

  void _connectSocket() {
    debugPrint(
      '🎮 [CP] _connectSocket() called, tableId=${widget.table['id']}',
    );
    GameSocket.connectChinese(
      onState: (state) {
        if (!mounted) return;
        final serverPhase = state['phase'] ?? 'waiting';
        final round = state['currentRound'];
        final rawPlayers = state['players'] as Map<String, dynamic>? ?? {};
        debugPrint(
          '📡 [CP] onState: phase=$serverPhase, round=$round, players=${rawPlayers.keys.toList()}, turnSec=${state['turnRemainingSeconds']}',
        );

        setState(() {
          // If result is showing and server sends new arranging phase,
          // keep showing result for 5 seconds then clear
          if ((_showResult || _showdownActive) && serverPhase == 'arranging') {
            if (!_pendingNewRound) {
              _pendingNewRound = true;
              debugPrint('🔄 [CP] Server sent ARRANGING — holding result 5s');
              // Wait fixed 5 seconds from NOW regardless of showdown state
              Future.delayed(
                Duration(
                  seconds: RuntimeConfigService.integer(
                    'showdown_ready_delay_sec',
                  ),
                ),
                () {
                  if (!mounted) return;
                  _pendingNewRound = false;
                  setState(() {
                    debugPrint(
                      '🔄 [CP] 5s hold done — clearing result, using pending cards',
                    );
                    _showResult = false;
                    _showdownActive = false;
                    _showdownRevealStep = 0;
                    _resultData = [];
                    _playerCoinChange = {};
                    _hasConfirmedArrangement = false;
                    _highlightWinnerSeat = -1;

                    // Use pending hand from server (saved during hold) or clear
                    _front = [];
                    _middle = [];
                    _back = [];
                    _cardsRevealed = false;
                    _activeRow = 'back';

                    if (_pendingHand.length == 13) {
                      _hand = List<String>.from(_pendingHand);
                      _pendingHand = [];
                      _showDealSequence = true;
                      _dealSequenceCards = List<String>.from(_hand);
                      _recommendedArrangement = OFCAutoArrange.arrange(_hand);
                      _showRecommendation = false;
                      debugPrint(
                        '🎴 [CP] Post-result: deal animation with ${_hand.length} pending cards',
                      );
                    } else {
                      // No pending cards — clear all and wait for server
                      _hand = [];
                      _showDealSequence = false;
                      _dealSequenceCards = [];
                      _recommendedArrangement = null;
                      _showRecommendation = false;
                      debugPrint(
                        '⚠️ [CP] Post-result: no pending cards, waiting for server',
                      );
                    }

                    // Use server's current remaining time
                    _stopCountdownTimer();
                    if (_turnRemainingSeconds > 0) {
                      _startCountdownTimer();
                    } else {
                      _autoPlaceAndConfirm();
                    }
                  });
                },
              );
            }
            // Continue processing state below — but keep result overlay showing
          }

          _phase = serverPhase;

          _currentRound = state['currentRound'] ?? _currentRound;
          _currentPlayerSeat = state['currentPlayerSeat'];
          _isFantasyland = state['isFantasyland'] == true;
          _turnTotalSeconds = toInt(state['turnTotalSeconds']);
          _turnRemainingSeconds = toInt(
            state['turnRemainingSeconds'],
            _turnTotalSeconds,
          );
          _minimumPlayMinutes = toInt(state['minimumPlayMinutes']);

          // ── Restore result data from lastResult if reconnecting mid-showdown ──
          if (serverPhase == 'result' && _resultData.isEmpty) {
            final lastResult = state['lastResult'];
            if (lastResult != null) {
              final results = List<Map<String, dynamic>>.from(
                (lastResult['results'] as List?)?.map(
                      (r) => Map<String, dynamic>.from(r),
                    ) ??
                    [],
              );
              if (results.isNotEmpty) {
                _resultData = results;
                _showdownActive = true;
                _showdownRevealStep =
                    4; // All revealed (reconnect = show full result)
                for (final r in results) {
                  final seat = r['seat'] as int? ?? 0;
                  _playerPoints[seat] = r['points'] ?? _playerPoints[seat] ?? 0;
                  _playerRoyalties[seat] = r['royalties'] ?? 0;
                  _playerFouls[seat] = r['isFoul'] == true;
                  _playerCoinChange[seat] = r['coinChange'] ?? 0;
                }
              }
            }
          }

          // Start local countdown timer when entering placing phase (NOT during result delay)
          if ((_phase == 'arranging' || _phase == 'placing') &&
              _countdownTimer == null &&
              !_showResult) {
            _startCountdownTimer();
          } else if (_phase != 'arranging' && _phase != 'placing') {
            _stopCountdownTimer();
          }

          _serverPlayers = {};
          rawPlayers.forEach((s, d) {
            final seat = int.tryParse(s) ?? 0;
            final p = Map<String, dynamic>.from(d);
            _serverPlayers[seat] = p;

            // Track per-player state
            _playerPoints[seat] = p['points'] ?? _playerPoints[seat] ?? 0;
            _playerFouls[seat] = p['isFoul'] == true;
            _playerFantasyland[seat] = p['isFantasyland'] == true;

            if (seat == _mySeat) {
              _myChips = p['chips'] ?? _myChips;
              debugPrint(
                '👤 [CP] My seat=$_mySeat, chips=$_myChips, phase=$_phase, hand=${(p['hand'] as List?)?.length ?? 0}, front=${(p['front'] as List?)?.length ?? 0}',
              );
              // Only update cards from server if we haven't locally arranged yet
              final localTotal =
                  _hand.length + _front.length + _middle.length + _back.length;
              final serverHand = List<String>.from(p['hand'] ?? []);

              // During pending new round, save server's new cards for later
              if (_pendingNewRound && serverHand.length == 13) {
                _pendingHand = serverHand;
              }

              if ((_phase == 'arranging' || _phase == 'placing') &&
                  localTotal == 0 &&
                  !_pendingNewRound) {
                _hand = serverHand;
                _front = List<String>.from(p['front'] ?? []);
                _middle = List<String>.from(p['middle'] ?? []);
                _back = List<String>.from(p['back'] ?? []);
                _showResult = false;
                debugPrint(
                  '🃏 [CP] Cards received: hand=${_hand.length}, front=${_front.length}, middle=${_middle.length}, back=${_back.length}',
                );
                // Mark first hand played time for time lock
                _firstHandPlayedAt ??= DateTime.now();
                // Trigger deal sequence animation when 13 cards arrive for first time
                if (_hand.length == 13 &&
                    _front.isEmpty &&
                    _middle.isEmpty &&
                    _back.isEmpty) {
                  if (!_showDealSequence &&
                      _dealSequenceCards.isEmpty &&
                      !_cardsRevealed &&
                      !_showResult) {
                    debugPrint(
                      '🎴 [CP] Starting deal sequence animation with 13 cards',
                    );
                    _showDealSequence = true;
                    _dealSequenceCards = List<String>.from(_hand);
                    AudioManager.instance.play(SoundEffect.cardDeal);
                  }
                  // Don't auto-arrange yet — wait for deal animation to finish
                  _recommendedArrangement = OFCAutoArrange.arrange(_hand);
                  _showRecommendation = false;
                } else if (_hand.isNotEmpty) {
                  debugPrint(
                    '📋 [CP] Cards already placed or reconnecting — reveal immediately',
                  );
                  _cardsRevealed = true;
                }
              }
            }
          });
        });
      },
      onResult: (result) {
        if (!mounted) return;
        debugPrint('🏆 [CP] onResult received');
        final results = List<Map<String, dynamic>>.from(
          (result['results'] as List?)?.map(
                (r) => Map<String, dynamic>.from(r),
              ) ??
              [],
        );
        debugPrint('🏆 [CP] Results count: ${results.length}');
        for (final r in results) {
          debugPrint(
            '   seat=${r['seat']}, coinChange=${r['coinChange']}, isFoul=${r['isFoul']}, royalties=${r['royalties']}',
          );
        }
        final myResult = results.where((r) => r['seat'] == _mySeat);
        final coinChange = myResult.isNotEmpty
            ? (myResult.first['coinChange'] ?? 0)
            : 0;

        // Task 17.3: Process scoring, royalties, fouls
        for (final r in results) {
          final seat = r['seat'] as int? ?? 0;
          _playerPoints[seat] = r['points'] ?? _playerPoints[seat] ?? 0;
          _playerRoyalties[seat] = r['royalties'] ?? 0;
          _playerFouls[seat] = r['isFoul'] == true;
          _playerFantasyland[seat] = r['qualifiesFantasyland'] == true;
          _playerCoinChange[seat] = r['coinChange'] ?? 0;
        }

        // Animate royalty display for current player
        final myRoyalty = myResult.isNotEmpty
            ? (myResult.first['royalties'] ?? 0)
            : 0;
        if (myRoyalty > 0) {
          _royaltyDisplayValue = 0;
          _royaltyTargetValue = myRoyalty;
          _royaltyAnimController.forward(from: 0);
        }

        // Start showdown reveal sequence before showing result
        setState(() {
          _resultData = results;
          _isWinner = coinChange > 0;
          _resultAmount = coinChange.abs();
          _phase = 'showdown';
          _showdownActive = true;
          _showdownRevealStep = 0;
        });

        // Reveal cards row by row: back → middle → front
        _runShowdownReveal().then((_) {
          if (!mounted) return;

          // Check for Dragon (coinChange very high = +13 per opponent × unit)
          for (final r in _resultData) {
            final int cc = r['coinChange'] ?? 0;
            final int nonFoulCount = _resultData
                .where((p) => p['seat'] != r['seat'] && p['isFoul'] != true)
                .length;
            // Dragon gives +13 per opponent × unit — detect if coinChange matches
            if (cc > 0 && r['isFoul'] != true) {
              final allCards = [
                ...(List<String>.from(r['front'] ?? [])),
                ...(List<String>.from(r['middle'] ?? [])),
                ...(List<String>.from(r['back'] ?? [])),
              ];
              final ranks = allCards
                  .map((c) => c.isNotEmpty ? c[0] : '')
                  .toSet();
              if (ranks.length == 13 && allCards.length == 13) {
                setState(() {
                  _showDragonPopup = true;
                  _dragonSeat = r['seat'] ?? -1;
                });
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) setState(() => _showDragonPopup = false);
                });
                break;
              }
            }
          }

          // Check for Fantasyland qualification
          for (final r in _resultData) {
            if (r['qualifiesFantasyland'] == true) {
              setState(() {
                _showFantasylandPopup = true;
                _fantasylandSeat = r['seat'] ?? -1;
              });
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) setState(() => _showFantasylandPopup = false);
              });
              break;
            }
          }

          setState(() {
            _showResult = true;
            _phase = 'result';
            _showdownActive = false;
          });
          // Stop countdown timer during result display
          _stopCountdownTimer();

          // Show confetti if player won overall
          final myCoinChange = _playerCoinChange[_mySeat] ?? 0;
          if (myCoinChange > 0) setState(() => _showConfetti = true);

          // Chips updated from server state — don't fetch wallet balance

          Future.delayed(
            Duration(
              seconds: RuntimeConfigService.integer('result_display_sec'),
            ),
            () {
              if (mounted && _showResult) {
                setState(() {
                  _showResult = false;
                  _hand = [];
                  _front = [];
                  _middle = [];
                  _back = [];
                  _playerCoinChange = {};
                  _showDealSequence = false;
                  _dealSequenceCards = [];
                  _cardsRevealed = false;
                });
              }
            },
          );
        });
      },
      onError: (msg) {
        debugPrint('❌ [CP] onError: $msg');
        // Suppress internal timing errors during round transition
        if (msg.contains('do not match') || msg.contains('not your turn'))
          return;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg, style: const TextStyle(fontSize: 12)),
              backgroundColor: Colors.red.shade800,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
    );
    final tid = widget.table['id'];
    if (tid != null) {
      // Auto-join seat 1 immediately (no seat selection)
      final buyIn = toInt(
        widget.table['_buyIn'] ?? widget.table['min_buy_in'] ?? 1000,
      );
      debugPrint('🎮 [CP] Joining table $tid, seat=$_mySeat, buyIn=$buyIn');
      GameSocket.joinChinese(
        tid,
        _mySeat,
        buyIn,
        accessToken: widget.table['_roomAccessToken'],
      );
    } else {
      debugPrint('⚠️ [CP] No table ID found! table=${widget.table}');
    }
  }

  bool _hasJoinedChinese = true;

  void _showChineseSeatSelection() {
    final maxSeats = toInt(widget.table['max_players'] ?? 4);
    final occupiedSeats = _serverPlayers.keys.toSet();
    final emptySeats = <int>[];
    for (int i = 1; i <= maxSeats; i++) {
      if (!occupiedSeats.contains(i)) emptySeats.add(i);
    }
    if (emptySeats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่มีที่นั่งว่าง'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0606),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'เลือกที่นั่ง',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: emptySeats.map((seat) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _joinChineseTable(seat);
                  },
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E8B57).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF2E8B57).withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.event_seat,
                          color: Color(0xFF3CB371),
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Seat $seat',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _joinChineseTable(int seatNumber) {
    final tid = widget.table['id'];
    if (tid == null) return;
    final buyIn = toInt(
      widget.table['_buyIn'] ?? widget.table['min_buy_in'] ?? 1000,
    );
    setState(() {
      _mySeat = seatNumber;
      _hasJoinedChinese = true;
    });
    GameSocket.joinChinese(
      tid,
      seatNumber,
      buyIn,
      accessToken: widget.table['_roomAccessToken'],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Card placement logic (Task 17.2)
  // ═══════════════════════════════════════════════════════════

  void _placeCard(String card, String row) {
    AudioManager.instance.play(SoundEffect.cardFlip);
    setState(() {
      // Find which row the card is currently in
      String? sourceRow;
      if (_front.contains(card))
        sourceRow = 'front';
      else if (_middle.contains(card))
        sourceRow = 'middle';
      else if (_back.contains(card))
        sourceRow = 'back';
      // else it's in _hand

      // Remove card from source
      _hand.remove(card);
      _front.remove(card);
      _middle.remove(card);
      _back.remove(card);

      // Get target row list and max
      List<String> targetList;
      int maxCards;
      switch (row) {
        case 'front':
          targetList = _front;
          maxCards = 3;
        case 'middle':
          targetList = _middle;
          maxCards = 5;
        case 'back':
          targetList = _back;
          maxCards = 5;
        default:
          targetList = _hand;
          maxCards = 99;
      }

      // If target is full, move last card from target back to source row (swap)
      if (targetList.length >= maxCards && sourceRow != null) {
        final displaced = targetList.removeLast();
        switch (sourceRow) {
          case 'front':
            _front.add(displaced);
          case 'middle':
            _middle.add(displaced);
          case 'back':
            _back.add(displaced);
          default:
            _hand.add(displaced);
        }
      } else if (targetList.length >= maxCards) {
        // No source row (from hand) and target full — put back in hand
        _hand.add(card);
        return;
      }

      // Place card in target
      targetList.add(card);

      // Auto-advance guided mode to next row when current is full
      if (_guidedMode) _advanceActiveRow();
    });
  }

  /// Place card into the currently active guided row (tap-to-place shortcut).
  void _guidedPlaceCard(String card) {
    _placeCard(card, _activeRow);
  }

  /// Advance active row when current row is full.
  void _advanceActiveRow() {
    if (_activeRow == 'back' && _back.length >= 5) {
      _activeRow = 'middle';
    } else if (_activeRow == 'middle' && _middle.length >= 5) {
      _activeRow = 'front';
    }
    // 'front' stays as final row
  }

  /// Get max cards for a row.
  int _maxForRow(String row) {
    switch (row) {
      case 'front':
        return 3;
      case 'middle':
        return 5;
      case 'back':
        return 5;
      default:
        return 0;
    }
  }

  /// Get current card count for a row.
  int _countForRow(String row) {
    switch (row) {
      case 'front':
        return _front.length;
      case 'middle':
        return _middle.length;
      case 'back':
        return _back.length;
      default:
        return 0;
    }
  }

  /// Get Thai label for a row.
  String _labelForRow(String row) {
    switch (row) {
      case 'front':
        return ThaiLabels.frontHand;
      case 'middle':
        return ThaiLabels.middleHand;
      case 'back':
        return ThaiLabels.backHand;
      default:
        return '';
    }
  }

  /// Step number for guided mode (1=back, 2=middle, 3=front).
  int get _guidedStep {
    if (_back.length < 5) return 1;
    if (_middle.length < 5) return 2;
    return 3;
  }

  /// Whether all 13 cards are placed.
  bool get _allPlaced =>
      _front.length == 3 && _middle.length == 5 && _back.length == 5;

  void _showRowFullMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(ThaiLabels.rowFull),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  void _removeCardFromRow(String row, int index) {
    setState(() {
      switch (row) {
        case 'front':
          _hand.add(_front.removeAt(index));
        case 'middle':
          _hand.add(_middle.removeAt(index));
        case 'back':
          _hand.add(_back.removeAt(index));
      }
      // Recalculate active row — go back to earliest incomplete row
      if (_guidedMode) {
        if (_back.length < 5) {
          _activeRow = 'back';
        } else if (_middle.length < 5) {
          _activeRow = 'middle';
        } else {
          _activeRow = 'front';
        }
      }
    });
  }

  /// Confirm placement → send to server immediately
  void _confirmArrangement() {
    if (_front.length != 3 || _middle.length != 5 || _back.length != 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กองหน้า 3 ใบ, กองกลาง 5 ใบ, กองหลัง 5 ใบ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!GameSocket.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ขาดการเชื่อมต่อ — กรุณาออกแล้วเข้าห้องใหม่'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    debugPrint('✅ [CP] Confirming arrangement:');
    debugPrint('   Front: $_front');
    debugPrint('   Middle: $_middle');
    debugPrint('   Back: $_back');
    AudioManager.instance.play(SoundEffect.buttonTap);
    setState(() => _hasConfirmedArrangement = true);
    _stopCountdownTimer();
    GameSocket.arrangeChinese(_front, _middle, _back);
  }

  /// Task 17.2: Reset → animate cards back to hand over 300ms
  void _resetPlacement() {
    setState(() => _isResetting = true);
    _resetAnimController.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() {
        _hand.addAll(_front);
        _hand.addAll(_middle);
        _hand.addAll(_back);
        _front = [];
        _middle = [];
        _back = [];
        _isResetting = false;
        // Reset guided mode back to first step
        _activeRow = 'back';
        // Re-compute recommendation if we have 13 cards
        if (_hand.length == 13) {
          _recommendedArrangement = OFCAutoArrange.arrange(_hand);
          _showRecommendation = _recommendedArrangement != null;
        }
      });
    });
  }

  /// สลับไพ่แถวกลาง (Middle) กับแถวล่าง (Back) ทั้งชุด
  void _swapMiddleAndBack() {
    setState(() {
      final temp = List<String>.from(_middle);
      _middle = List<String>.from(_back);
      _back = temp;
    });
  }

  /// When timer expires — force foul immediately by placing cards in invalid order
  /// (strongest cards in front, weakest in back = guaranteed foul) and auto-confirm
  void _autoPlaceAndConfirm() {
    // Don't auto-confirm during result display (10s delay period)
    if (_showResult || _showdownActive) return;

    // Collect all unplaced cards
    final allCards = [..._hand, ..._front, ..._middle, ..._back];
    if (allCards.length != 13) return;

    // Sort cards by strength ASCENDING — weakest first
    // This puts weak cards in back, strong in front = FOUL
    final sorted = List<String>.from(allCards);
    sorted.sort((a, b) {
      const rv = {
        '2': 2,
        '3': 3,
        '4': 4,
        '5': 5,
        '6': 6,
        '7': 7,
        '8': 8,
        '9': 9,
        'T': 10,
        'J': 11,
        'Q': 12,
        'K': 13,
        'A': 14,
      };
      return (rv[a[0]] ?? 0).compareTo(rv[b[0]] ?? 0);
    });

    // Place weakest 5 in back, next 5 in middle, strongest 3 in front = FOUL
    setState(() {
      _back = sorted.sublist(0, 5);
      _middle = sorted.sublist(5, 10);
      _front = sorted.sublist(10, 13);
      _hand = [];
      _activeRow = 'front';
      _hasConfirmedArrangement = true;
    });

    // Show timeout notification
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '⏰ หมดเวลา — ฟาวล์',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );

    // Send foul arrangement to server immediately (no delay)
    _stopCountdownTimer();
    GameSocket.arrangeChinese(_front, _middle, _back);
  }

  bool get _isMyTurn => _currentPlayerSeat == _mySeat;
  bool get _isPlacingPhase => _phase == 'arranging' || _phase == 'placing';

  /// In OFC arranging phase, all players place simultaneously — no turn check needed.
  /// Only check turn for 'placing' phase (round-by-round single card placement).
  bool get _canPlace =>
      _isPlacingPhase &&
      _hasJoinedChinese &&
      (_phase == 'arranging' || _isMyTurn);
  bool get _canConfirm {
    final totalPlaced = _front.length + _middle.length + _back.length;
    return _hand.isEmpty &&
        totalPlaced == 13 &&
        _front.length == 3 &&
        _middle.length == 5 &&
        _back.length == 5;
  }

  /// Whether the arrange popup should be showing (placing phase, cards revealed, not yet confirmed)
  bool get _showingArrangePopup =>
      _isPlacingPhase &&
      _hasJoinedChinese &&
      _cardsRevealed &&
      _allPlaced &&
      !_hasConfirmedArrangement;

  // ═══════════════════════════════════════════════════════════
  // Showdown reveal — flip cards row by row with delay
  // Show winner per row with hand name and chip distribution
  // ═══════════════════════════════════════════════════════════

  // Per-row winner info for display during showdown
  String _rowWinnerText = '';
  int _highlightWinnerSeat =
      -1; // seat to highlight yellow during chip animation

  Future<void> _runShowdownReveal() async {
    // Step 1: reveal back hands
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _showdownRevealStep = 1);
    AudioManager.instance.play(SoundEffect.cardFlip);

    // Animate chips for back row winners
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    _animateRowChips('back');

    // Step 2: reveal middle hands
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    setState(() {
      _showdownRevealStep = 2;
      _highlightWinnerSeat = -1;
    });
    AudioManager.instance.play(SoundEffect.cardFlip);

    // Animate chips for middle row winners
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    _animateRowChips('middle');

    // Step 3: reveal front hands
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    setState(() {
      _showdownRevealStep = 3;
      _highlightWinnerSeat = -1;
    });
    AudioManager.instance.play(SoundEffect.cardFlip);

    // Animate chips for front row winners
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    _animateRowChips('front');

    // Wait for chip animations to finish, then mark done
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    setState(() {
      _showdownRevealStep = 4;
      _highlightWinnerSeat = -1;
      _rowWinnerText = '';
    });
    // Final result sound — win celebration if I won any coins this hand, else a quieter chip sound
    final myGain = _playerCoinChange[_mySeat] ?? 0;
    if (myGain > 0) {
      AudioManager.instance.play(SoundEffect.winCelebration);
    } else if (myGain < 0) {
      AudioManager.instance.play(SoundEffect.chipToss);
    }
  }

  /// Animate chips flying from losers to winners for a specific row
  /// ตามกฏไพ่สามกอง:
  /// - ใช้ backScore/middleScore/frontScore จาก server (ผลรวม head-to-head ทุกคู่)
  /// - คนที่ score ติดลบ = แพ้กองนี้ → ส่งชิปไปคนที่ score บวก
  /// - ฟาวล์ = แพ้ทุกกอง (-2 ต่อคน × จำนวนคนไม่ฟาวล์) + scoop
  /// - Scoop (ชนะ 3 กอง) = ได้โบนัส +3 extra
  void _animateRowChips(String row) {
    if (_resultData.isEmpty) return;
    // Use the GameStage's fixed design size (not the raw device viewport).
    // ChipAnimationOverlay now lives INSIDE GameStage, so it scales together
    // with the table/seats — its coordinates must be expressed in the same
    // fixed design space the seats are laid out in, otherwise the flying
    // chips land at the wrong spot once the stage is scaled down/up.
    const screenSize = Size(kGameStageDesignWidth, kGameStageDesignHeight);

    // Get per-row scores from server result data
    final scores = <int, int>{}; // seat → score for this row (in coins)
    final nonFoulCount = _resultData.where((p) => p['isFoul'] != true).length;

    for (final r in _resultData) {
      final seat = r['seat'] as int? ?? 0;
      final isFoul = r['isFoul'] == true;

      if (isFoul) {
        // Foul: loses 2 points per non-foul opponent per row (1 row + 1 scoop share)
        // Total per row = -2 × nonFoulCount (approximation for animation)
        scores[seat] = -(nonFoulCount * 2);
      } else {
        // Use server-calculated per-row score (already in coins from server)
        final int score;
        switch (row) {
          case 'back':
            score = r['backScore'] ?? 0;
          case 'middle':
            score = r['middleScore'] ?? 0;
          case 'front':
            score = r['frontScore'] ?? 0;
          default:
            score = 0;
        }
        scores[seat] = score;
      }
    }

    // Find winners (positive score) and losers (negative score)
    final winners = scores.entries.where((e) => e.value > 0).toList();
    final losers = scores.entries.where((e) => e.value < 0).toList();

    if (winners.isEmpty || losers.isEmpty) return;

    // Highlight all winners
    final winnerSeats = winners.map((e) => e.key).toSet();
    setState(() => _highlightWinnerSeat = winners.first.key);

    // Animate chips: each loser sends chips to winners proportionally
    for (final loser in losers) {
      final totalLoss = loser.value.abs();
      final perWinner = (totalLoss / winners.length).ceil().clamp(1, totalLoss);

      for (final winner in winners) {
        final fromPos = _getSeatPosition(loser.key, screenSize);
        final toPos = _getSeatPosition(winner.key, screenSize);

        _chipAnimController.potToWinner(
          from: fromPos,
          to: toPos,
          amount: perWinner,
          chipCount: perWinner > 50 ? 3 : 2,
        );
      }
    }

    AudioManager.instance.play(SoundEffect.coinCascade);
  }

  /// Get screen position for a seat (for chip animation targets)
  Offset _getSeatPosition(int seat, Size screenSize) {
    if (seat == _mySeat) {
      return Offset(screenSize.width * 0.4, screenSize.height * 0.82);
    }
    final others = _serverPlayers.entries
        .where((e) => e.key != _mySeat)
        .toList();
    final seatIndex = others.indexWhere((e) => e.key == seat);

    if (seatIndex == 0) {
      // Left opponent
      return Offset(screenSize.width * 0.12, screenSize.height * 0.40);
    } else if (seatIndex == 1) {
      // Top opponent
      return Offset(screenSize.width * 0.42, screenSize.height * 0.18);
    } else {
      // Right opponent
      return Offset(screenSize.width * 0.75, screenSize.height * 0.40);
    }
  }

  // Task 19.1: Slide-left 300ms back to Lobby (Req 11.1–11.5)
  Future<void> _fadeOutAndPop() async {
    if (!mounted) return;

    // Time lock: must stay 30 minutes from first hand played (not from join)
    // If player hasn't played yet (sitting out / waiting), allow leave immediately
    final isPractice = widget.table['_isPractice'] == true;
    final minDuration = Duration(minutes: _minimumPlayMinutes);

    if (!isPractice && _myChips > 0 && _firstHandPlayedAt != null) {
      final elapsed = DateTime.now().difference(_firstHandPlayedAt!);
      if (elapsed < minDuration) {
        final remaining = minDuration - elapsed;
        final mins = remaining.inMinutes;
        final secs = remaining.inSeconds % 60;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'ต้องอยู่ในห้องอย่างน้อย $_minimumPlayMinutes นาที (เหลือ ${mins} นาที ${secs} วินาที)',
              ),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return; // Block exit
      }
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const LobbyScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(-1.0, 0.0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                ),
            child: child,
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    // Task 11.7: Initialize responsive layout engine from screen width (Req 8.1, 8.7, 9.4, 9.5)
    _layoutEngine = ResponsiveLayoutEngine(MediaQuery.of(context).size.width);
    return AnimatedOpacity(
      opacity: _fadeOutOpacity,
      duration: const Duration(milliseconds: 300),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _fadeOutAndPop();
        },
        child: Scaffold(
          body: Stack(
            children: [
              // Decorative room background — fills the ENTIRE device viewport
              // (BoxFit.cover, cropped as needed) regardless of GameStage's
              // scale. It has no alignment-critical content (just a photo of
              // a room for atmosphere), so unlike the table/seats/cards it
              // does NOT need to stay locked to the fixed design box — doing
              // so was the cause of the empty bars on either side of the
              // table on wide/short viewports.
              Positioned.fill(
                child: Image.asset('assets/bg_ofc_room.jpg', fit: BoxFit.cover),
              ),
              // Main content — SafeArea ensures content avoids notch/cutout/status bar
              Positioned.fill(
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildTopBar(),
                      // Game Stage: fixed-design-size canvas (844x390) scaled as
                      // ONE rigid unit to fit the remaining space, so
                      // seats/cards/chips/score-boxes all shrink/grow together
                      // and never overlap independently. The decorative room
                      // background above is intentionally OUTSIDE this stage so
                      // it always fills the full viewport.
                      // LandscapeOnlyGate shows a rotate-device fallback instead of
                      // squeezing the table when width < height (mainly relevant on
                      // web, where the native landscape lock via SystemChrome has no
                      // effect on desktop/mobile browser window shape).
                      Expanded(
                        child: LandscapeOnlyGate(
                          child: GameStage(
                            designWidth: kGameStageDesignWidth,
                            designHeight: kGameStageDesignHeight,
                            child: _buildChineseTableLayout(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Card arrangement popup (fullscreen with blur background, after deal animation)
              if (_showingArrangePopup)
                Positioned.fill(child: _buildCardPopup()),
              // Showdown: cards reveal step-by-step at each player's avatar position (no overlay)
              // Menu overlay
              if (_showMenu) _buildMenuOverlay(),
              // Chip animation overlay moved INSIDE GameStage (see
              // _buildChineseTableLayout) so it scales together with the
              // seats instead of using raw viewport coordinates that no
              // longer match the scaled-down table.
              // Confetti on win
              if (_showConfetti)
                Positioned.fill(
                  child: ConfettiEffect(
                    onComplete: () {
                      if (mounted) setState(() => _showConfetti = false);
                    },
                  ),
                ),
              // Dragon popup
              if (_showDragonPopup)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF6B00),
                              Color(0xFFFF0000),
                              Color(0xFFFF6B00),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.6),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: Colors.red.withOpacity(0.4),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🐉', style: TextStyle(fontSize: 24)),
                            const SizedBox(height: 2),
                            const Text(
                              'DRAGON!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _dragonSeat == _mySeat
                                  ? 'คุณได้มังกร! +13 จากทุกคน'
                                  : 'ผู้เล่น seat $_dragonSeat ได้มังกร!',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Fantasyland qualification popup
              if (_showFantasylandPopup)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 170,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF1A0533),
                              Color(0xFF2D1066),
                              Color(0xFF4A1A8A),
                              Color(0xFF2D1066),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFFFD700),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                            BoxShadow(
                              color: const Color(0xFF7C3AED).withOpacity(0.5),
                              blurRadius: 24,
                              spreadRadius: 5,
                            ),
                            const BoxShadow(
                              color: Colors.black54,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Star icon with glow
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const RadialGradient(
                                  colors: [
                                    Color(0xFFFFD700),
                                    Color(0xFFFF8C00),
                                    Color(0xFFCC6600),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFFD700,
                                    ).withOpacity(0.7),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  '✦',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Title
                            const Text(
                              'FANTASYLAND',
                              style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 6),
                                  Shadow(
                                    color: Color(0xFFFFD700),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Subtitle
                            Text(
                              _fantasylandSeat == _mySeat
                                  ? 'You qualified for Fantasyland!'
                                  : 'A player entered Fantasyland!',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '14 cards next round',
                              style: TextStyle(
                                color: Colors.amber.withOpacity(0.7),
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Deal sequence animation (cards fly from center to ALL players)
              if (_showDealSequence && _dealSequenceCards.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DealToPlayersAnimation(
                      key: ValueKey('ofc_deal_${_dealSequenceCards.length}'),
                      playerCount: _serverPlayers.length.clamp(2, 4),
                      cardsPerPlayer:
                          2, // 2 rounds of dealing per player (visual only)
                      onComplete: () {
                        if (mounted) {
                          setState(() {
                            _showDealSequence = false;
                            _dealSequenceCards = [];
                            _cardsRevealed = true;
                            // Auto-arrange after deal animation completes
                            if (_hand.length == 13 &&
                                _front.isEmpty &&
                                _middle.isEmpty &&
                                _back.isEmpty) {
                              final rec =
                                  _recommendedArrangement ??
                                  OFCAutoArrange.arrange(_hand);
                              if (rec != null) {
                                _front = List<String>.from(rec['front']!);
                                _middle = List<String>.from(rec['middle']!);
                                _back = List<String>.from(rec['back']!);
                                _hand = [];
                                _activeRow = 'front';
                                debugPrint(
                                  '🤖 [CP] Auto-arranged after deal: front=${_front.length}, middle=${_middle.length}, back=${_back.length}',
                                );
                                // หน่วง 1 วินาทีก่อนเปิด popup เพื่อให้เห็น animation แจกไพ่เสร็จ
                                _cardsRevealed = false; // ซ่อน popup ชั่วคราว
                              }
                              // Delay 1s แล้วเปิด popup
                              Future.delayed(const Duration(seconds: 1), () {
                                if (mounted && !_hasConfirmedArrangement) {
                                  setState(() => _cardsRevealed = true);
                                }
                              });
                            }
                          });
                        }
                      },
                    ),
                  ),
                ),
              // Result overlay — fallback when no detailed result data
              if (_showResult && _resultData.isEmpty)
                ResultOverlay(
                  isWinner: _isWinner,
                  amount: _resultAmount,
                  handName: _isWinner
                      ? 'You Win! +C$_resultAmount'
                      : 'You Lose -C$_resultAmount',
                  onDismiss: () => setState(() {
                    _showResult = false;
                    _hand = [];
                    _front = [];
                    _middle = [];
                    _back = [];
                  }),
                ),
              // Seat selection removed — auto-join seat 1
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Shared table layout using TableSeatLayout
  // ═══════════════════════════════════════════════════════════

  Widget _buildChineseTableLayout() {
    final others = _serverPlayers.entries
        .where((e) => _mySeat > 0 ? e.key != _mySeat : true)
        .toList();

    // Build opponent widgets — index 0 = left side (mirror layout)
    final opponentWidgets = <Widget>[];
    for (int i = 0; i < others.length; i++) {
      final isLeftSide = i == 0; // First opponent is on the left
      opponentWidgets.add(
        _buildCompactOpponent(
          others[i].value,
          others[i].key,
          isLeftSide: isLeftSide,
        ),
      );
    }

    // Center content: showdown step label only (scores shown per-player)
    Widget? centerContent;
    if (_showdownActive &&
        _showdownRevealStep > 0 &&
        _showdownRevealStep <= 3) {
      // ไม่แสดงกล่อง label ตอน showdown — ลบออกเพื่อไม่ให้ทับ layout
      centerContent = null;
    } else if (_showdownActive && _showdownRevealStep == 4) {
      centerContent = Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 12),
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Text(
            'Comparing...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // My section at bottom
    final myWidget = _buildMyChineseSection();

    // Overlay widgets (timer at bottom-right) — hide during result delay
    final overlays = <Widget>[];
    if (_isPlacingPhase && _turnRemainingSeconds > 0 && !_showResult) {
      overlays.add(
        Positioned(
          right: 12,
          bottom: 12,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _turnRemainingSeconds <= 5
                  ? Colors.red.shade700
                  : Colors.amber.shade700,
              border: Border.all(
                color: _turnRemainingSeconds <= 5
                    ? Colors.red.shade300
                    : Colors.amber.shade300,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '$_turnRemainingSeconds',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ปุ่ม "จัดใหม่" — แสดงเมื่อกดยืนยันแล้ว + ยังไม่หมดเวลา (รอคนอื่นจัดอยู่)
    if (_isPlacingPhase &&
        _hasConfirmedArrangement &&
        _turnRemainingSeconds > 0 &&
        !_showResult) {
      overlays.add(
        Positioned(
          left: 12,
          bottom: 12,
          child: GestureDetector(
            onTap: () {
              // ยกเลิกยืนยัน → เปิด popup จัดไพ่ใหม่ + ใช้เวลาที่เหลือ
              setState(() {
                _hasConfirmedArrangement = false;
                _cardsRevealed = true; // ให้ popup แสดง
              });
              // เริ่ม countdown ต่อจากเวลาที่เหลือ
              _startCountdownTimer();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade800,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.greenAccent.withOpacity(0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Text(
                'จัดใหม่',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PerspectiveTableLayout(
          opponentWidgets: opponentWidgets,
          myWidget: myWidget,
          centerWidget: centerContent,
          overlayWidgets: overlays,
          landscapeMode: true, // Chinese Poker uses landscape 4-seat layout
          showTableBackground: false, // Using custom bg_ofc_room.jpg instead
        ),
        // Chip fly animation — lives INSIDE GameStage (not the outer
        // Scaffold Stack) so its start/end coordinates — expressed in the
        // fixed design space via _getSeatPosition() — scale together with
        // the seats instead of drifting away from them when the stage is
        // scaled to fit the real viewport.
        Positioned.fill(
          child: ChipAnimationOverlay(controller: _chipAnimController),
        ),
      ],
    );
  }

  /// My section at the bottom of the table
  Widget _buildMyChineseSection() {
    final myData = _serverPlayers[_mySeat] ?? {};
    final username = ProfileProvider.instance.displayName.isNotEmpty
        ? ProfileProvider.instance.displayName
        : (myData['username'] ?? 'คุณ');
    final chips = toInt(myData['chips'] ?? _myChips);
    final isResultPhase = _phase == 'result' || _phase == 'showdown';
    final coinChange = _playerCoinChange[_mySeat] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availW = constraints.maxWidth > 0
              ? constraints.maxWidth
              : 280.0;
          // ไพ่ใช้ขนาดคงที่ตาม ratio — ล็อกตำแหน่ง ไม่ขยับ
          final cardAreaW = (availW * 0.50).clamp(100.0, 170.0);
          // spacing: cards(28) + avatar(38) + gap(2) = 68
          final scoreAreaW = (availW - cardAreaW - 38 - 30).clamp(80.0, 190.0);

          return SizedBox(
            width: availW,
            height: 190,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // LEFT: Fanned cards — ล็อกขนาดคงที่ไม่ขยับ
                SizedBox(
                  width: cardAreaW,
                  child:
                      ((_allPlaced &&
                              _hasConfirmedArrangement &&
                              !_showingArrangePopup) ||
                          _showdownActive ||
                          _showResult)
                      ? _buildMyFannedCardsResponsive(cardAreaW)
                      : const SizedBox(),
                ),
                const SizedBox(width: 28),
                // CENTER: Avatar + name
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _highlightWinnerSeat == _mySeat
                              ? const Color(0xFFFFD700)
                              : _isFantasyland
                              ? const Color(0xFFFF8C00)
                              : const Color(0xFFDAA520),
                          width: 2,
                        ),
                        image: ProfileProvider.instance.avatarImage != null
                            ? DecorationImage(
                                image: ProfileProvider.instance.avatarImage!,
                                fit: BoxFit.cover,
                              )
                            : const DecorationImage(
                                image: AssetImage('assets/logo.png'),
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'C${NumberFormatter.formatAbbreviated(chips)}',
                            style: const TextStyle(
                              color: Color(0xFFDAA520),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isFantasyland)
                      const Text(
                        '🌟 FL',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 2),
                // RIGHT: Score box — ขนาดคงที่เท่ากับ opponent
                if ((_showdownActive || isResultPhase || _showResult) &&
                    _resultData.isNotEmpty)
                  SizedBox(width: scoreAreaW, child: _buildRowScoreBox(_mySeat))
                else if ((isResultPhase || _showResult) &&
                    coinChange != 0 &&
                    !_showdownActive)
                  Container(
                    width: scoreAreaW,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: coinChange > 0
                          ? Colors.green.shade800
                          : Colors.red.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${coinChange >= 0 ? "+" : ""}${NumberFormatter.formatWithCommas(coinChange)}',
                      style: TextStyle(
                        color: coinChange > 0
                            ? Colors.greenAccent
                            : Colors.red.shade200,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Fanned face-up cards — 3 fan groups stacked (bottom→top like reference)
  /// กองหลัง(5) ล่างสุด → กองกลาง(5) ซ้อนทับ → กองหน้า(3) บนสุด
  /// ล็อกตำแหน่งไว้คงที่ — ไม่ขยับเมื่อเปิดไพ่ (ลบ AnimatedSwitcher ออก)
  /// ใช้ขนาดคงที่ตาม container width (130px) เพื่อรองรับทุก device
  Widget _buildMyFannedCards() {
    return _buildMyFannedCardsResponsive(130.0);
  }

  /// Responsive version — รับ containerW จาก LayoutBuilder
  Widget _buildMyFannedCardsResponsive(double containerW) {
    if (_front.isEmpty && _middle.isEmpty && _back.isEmpty)
      return const SizedBox();
    // คำนวณ cardW ให้กองหลัง (5 ใบ) พอดีกับ container
    final cardW = (containerW / 3.2);
    final cardH = cardW * 1.42;
    final peekHeight = (cardW * 1.1).clamp(35.0, 55.0);
    final fanWidth = containerW;
    final fanHeight = cardH * 1.5;
    final totalH = fanHeight + peekHeight * 2;

    final bool revealBack = !_showdownActive || _showdownRevealStep >= 1;
    final bool revealMiddle = !_showdownActive || _showdownRevealStep >= 2;
    final bool revealFront = !_showdownActive || _showdownRevealStep >= 3;

    return SizedBox(
      width: fanWidth,
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // กองหน้า (3 ใบ) — วางก่อน = อยู่ด้านหลังสุด (ถูกบัง)
          Positioned(
            bottom: peekHeight * 2,
            left: 0,
            right: 0,
            child: _buildFannedGroupCompact(_front, revealFront, cardW, cardH),
          ),
          // กองกลาง (5 ใบ) — กลาง
          Positioned(
            bottom: peekHeight,
            left: 0,
            right: 0,
            child: _buildFannedGroupCompact(
              _middle,
              revealMiddle,
              cardW,
              cardH,
            ),
          ),
          // กองหลัง (5 ใบ) — วางสุดท้าย = อยู่ด้านหน้าสุด (เห็นเต็ม)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildFannedGroupCompact(_back, revealBack, cardW, cardH),
          ),
        ],
      ),
    );
  }

  /// Fan group — cards spread in arc from bottom-center pivot
  /// ไพ่กางเป็นพัดจากจุดกลางล่าง เห็น rank ทุกใบ
  /// Reference: angle spread wide enough so all cards are fully readable
  Widget _buildFannedGroupCompact(
    List<String> cards,
    bool faceUp,
    double cardW,
    double cardH,
  ) {
    if (cards.isEmpty) return const SizedBox();
    final count = cards.length;
    // ซ้อนไพ่แบบตรง — คลี่ออกเต็มที่ให้เห็นเลข 10 ชัดเจน
    // แต่ละใบเลื่อนออก 75% ของ width (ซ้อนแค่ 25%)
    final overlap = cardW * 0.75;
    final totalWidth = cardW + (count - 1) * overlap;

    return SizedBox(
      width: totalWidth,
      height: cardH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              left: i * overlap,
              top: 0,
              child: PlayingCard(
                card: faceUp ? cards[i] : null,
                faceUp: faceUp,
                width: cardW,
                height: cardH,
              ),
            ),
        ],
      ),
    );
  }

  /// Fanned cards on table center — my cards face up
  Widget _buildFannedCardsOnTable() {
    if (_front.isEmpty && _middle.isEmpty && _back.isEmpty)
      return const SizedBox();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFannedGroup(_front, true),
            const SizedBox(width: 8),
            _buildFannedGroup(_middle, true),
            const SizedBox(width: 8),
            _buildFannedGroup(_back, true),
          ],
        ),
        const SizedBox(height: 4),
        // Labels
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGroupLabel(ThaiLabels.frontHand, _front, 'front'),
            const SizedBox(width: 8),
            _buildGroupLabel(ThaiLabels.middleHand, _middle, 'middle'),
            const SizedBox(width: 8),
            _buildGroupLabel(ThaiLabels.backHand, _back, 'back'),
          ],
        ),
      ],
    );
  }

  Widget _buildGroupLabel(String label, List<String> cards, String row) {
    final handName = _getHandName(row, cards);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: SunTheme.goldLight.withOpacity(0.7),
            fontSize: 11,
          ),
        ),
        if (handName.isNotEmpty)
          Text(
            handName,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  /// A group of cards fanned (overlapping with rotation)
  Widget _buildFannedGroup(List<String> cards, bool faceUp) {
    if (cards.isEmpty) return const SizedBox(width: 30);
    const cardW = 22.0;
    const cardH = 31.0;
    final count = cards.length;
    // Fan angle: spread cards in an arc
    final totalAngle = (count - 1) * 8.0; // degrees between cards
    final startAngle = -totalAngle / 2;

    return SizedBox(
      width: cardW + (count - 1) * 10,
      height: cardH + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              left: i * 10.0,
              child: Transform.rotate(
                angle: (startAngle + i * 8.0) * 3.14159 / 180,
                child: PlayingCard(
                  card: faceUp ? cards[i] : null,
                  faceUp: faceUp,
                  width: cardW,
                  height: cardH,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Landscape layout: Left opponents panel
  // ═══════════════════════════════════════════════════════════

  Widget _buildLeftOpponents() {
    final others = _serverPlayers.entries
        .where((e) => _mySeat > 0 ? e.key != _mySeat : true)
        .toList();

    if (others.isEmpty) return const SizedBox();

    // Show first half of opponents on left
    final leftCount = (others.length / 2).ceil();
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (int i = 0; i < leftCount && i < others.length; i++)
          _buildCompactOpponent(others[i].value, others[i].key),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Landscape layout: Right panel (timer + opponents)
  // ═══════════════════════════════════════════════════════════

  Widget _buildRightPanel() {
    final others = _serverPlayers.entries
        .where((e) => _mySeat > 0 ? e.key != _mySeat : true)
        .toList();

    final leftCount = (others.length / 2).ceil();

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Timer
        if (_isPlacingPhase)
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.amber.shade700,
              border: Border.all(color: Colors.amber.shade300, width: 2),
              boxShadow: [
                BoxShadow(color: Colors.amber.withOpacity(0.4), blurRadius: 8),
              ],
            ),
            child: Center(
              child: Text(
                '$_turnRemainingSeconds',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        // Right opponents (second half)
        for (int i = leftCount; i < others.length; i++)
          _buildCompactOpponent(others[i].value, others[i].key),
      ],
    );
  }

  /// Compact opponent widget for landscape side panels
  /// ปรับ responsive ตามขนาด container — รองรับทุก device
  Widget _buildCompactOpponent(
    Map<String, dynamic> p,
    int seatNum, {
    bool isLeftSide = false,
  }) {
    final arranged = p['arranged'];
    final isReady = arranged != null || p['isReady'] == true;
    final username = p['username'] ?? 'Player';
    final isResultPhase = _phase == 'result' || _phase == 'showdown';
    final coinChange = _playerCoinChange[seatNum] ?? 0;
    final isWinner = coinChange > 0;
    final isLoser = coinChange < 0;
    final isPlacing = _isPlacingPhase && !_showResult;

    return LayoutBuilder(
      builder: (context, constraints) {
        // คำนวณขนาดตาม container width จริง — รองรับทุก device
        final availW = constraints.maxWidth > 0 ? constraints.maxWidth : 280.0;
        // ใช้ขนาดไพ่คงที่ — ล็อกตำแหน่ง ไม่ขยับเมื่อเปิดไพ่
        // ขนาดปรับตาม container แต่ล็อก ratio เดียวกับของฉัน
        // ใช้ layout ไพ่เท่ากับตอนคว่ำไพ่ — ไม่ขยับ ไม่ scale
        const fixedCardAreaW = 160.0; // ขยายขึ้นให้ไพ่ใหญ่ขึ้น
        final cardAreaW = (availW * 0.50).clamp(100.0, 170.0);
        final avatarW = 38.0;
        // spacing: left=4+2=6, right=2+4=6
        final spacingW = 6.0;
        final scoreAreaW = (availW - cardAreaW - avatarW - spacingW).clamp(
          80.0,
          190.0,
        );

        // Card dimensions — คำนวณให้กอง 5 ใบพอดีกับ container
        final cardW = (fixedCardAreaW / 3.9);
        final cardH = cardW * 1.42;
        final peekHeight = (cardW * 1.1).clamp(35.0, 55.0);
        final fanHeight = cardH * 1.5;
        final totalH = fanHeight + peekHeight * 2;

        // Build reusable sub-widgets — ใช้ขนาดเดียวกับตอนคว่ำไพ่ ไม่ FittedBox
        final cardsWidget = SizedBox(
          width: cardAreaW,
          height: totalH,
          child: (isPlacing || (!isPlacing && _phase != 'waiting'))
              ? _buildOpponentShowdownCardsResponsive(
                  p,
                  seatNum,
                  fixedCardAreaW,
                )
              : const SizedBox(),
        );

        final avatarWidget = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isPlacing && !isReady)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value:
                            _turnRemainingSeconds /
                            _turnTotalSeconds.clamp(1, 60),
                        strokeWidth: 2,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _turnRemainingSeconds > 10
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                    ),
                  PlayerAvatar3D(
                    size: 34,
                    borderColor: _highlightWinnerSeat == seatNum
                        ? const Color(0xFFFFD700)
                        : _playerFantasyland[seatNum] == true
                        ? const Color(0xFFFF8C00)
                        : isWinner
                        ? Colors.greenAccent
                        : isLoser
                        ? Colors.red
                        : isReady
                        ? Colors.greenAccent
                        : const Color(0xFFDAA520),
                    overlay: isPlacing && !isReady
                        ? Container(
                            color: Colors.black.withOpacity(0.5),
                            child: Center(
                              child: Text(
                                '$_turnRemainingSeconds',
                                style: TextStyle(
                                  color: _turnRemainingSeconds > 10
                                      ? Colors.white
                                      : Colors.redAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          )
                        : isPlacing && isReady
                        ? Container(
                            color: Colors.green.withOpacity(0.7),
                            child: const Icon(
                              Icons.check,
                              size: 12,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'C${NumberFormatter.formatAbbreviated(toInt(p['chips'] ?? 0))}',
                    style: const TextStyle(
                      color: Color(0xFFDAA520),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (_playerFantasyland[seatNum] == true)
              const Text(
                '🌟 FL',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (isPlacing) ...[
              if (isReady)
                const Text(
                  'พร้อม',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                )
              else
                const Text(
                  'จัดไพ่',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ],
        );

        Widget? scoreWidget;
        if ((_showdownActive || isResultPhase || _showResult) &&
            _resultData.isNotEmpty) {
          scoreWidget = SizedBox(
            width: scoreAreaW,
            child: _buildRowScoreBox(seatNum),
          );
        } else if ((isResultPhase || _showResult) &&
            coinChange != 0 &&
            !_showdownActive) {
          scoreWidget = Container(
            width: scoreAreaW,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: isWinner ? Colors.green.shade800 : Colors.red.shade900,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${coinChange >= 0 ? "+" : ""}$coinChange',
              style: TextStyle(
                color: isWinner ? Colors.greenAccent : Colors.red.shade200,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }

        // Left side: Cards | Avatar | Score
        // Right side: Score | Avatar | Cards
        // ล็อกขนาดไพ่คงที่ — ไม่ขยับเมื่อกล่องสรุปแสดง
        final children = isLeftSide
            ? <Widget>[
                cardsWidget,
                const SizedBox(width: 36),
                avatarWidget,
                const SizedBox(width: 2),
                if (scoreWidget != null) Flexible(child: scoreWidget),
              ]
            : <Widget>[
                if (scoreWidget != null) Flexible(child: scoreWidget),
                if (scoreWidget != null) const SizedBox(width: 2),
                avatarWidget,
                const SizedBox(width: 4),
                cardsWidget,
              ];

        return SizedBox(
          width: availW,
          height: 190, // Fixed height — prevents position shift
          child: OverflowBox(
            maxWidth: availW + 60, // อนุญาตให้ล้นได้ (ไพ่กาง)
            alignment: isLeftSide ? Alignment.centerLeft : Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: children,
            ),
          ),
        );
      },
    ); // end LayoutBuilder
  }

  /// Per-row score box — shows hand name and win/lose per row during showdown
  Widget _buildRowScoreBox(int seatNum) {
    final playerResult = _resultData.firstWhere(
      (r) => r['seat'] == seatNum,
      orElse: () => <String, dynamic>{},
    );
    if (playerResult.isEmpty) return const SizedBox();

    final isFoul = playerResult['isFoul'] == true;
    String backName = (playerResult['backName'] ?? '') as String;
    String middleName = (playerResult['middleName'] ?? '') as String;
    String frontName = (playerResult['frontName'] ?? '') as String;
    final int backScore = playerResult['backScore'] ?? 0;
    final int middleScore = playerResult['middleScore'] ?? 0;
    final int frontScore = playerResult['frontScore'] ?? 0;
    final int royalties = playerResult['royalties'] ?? 0;

    // Fallback: คำนวณชื่อมือไพ่จากไพ่จริง ถ้า server ไม่ส่งมา
    if (frontName.isEmpty) {
      final front = playerResult['front'];
      if (front is List && front.length == 3) {
        try {
          frontName = HandEvaluator.evaluate3(List<String>.from(front)).nameTh;
        } catch (_) {}
      }
    }
    if (middleName.isEmpty) {
      final middle = playerResult['middle'];
      if (middle is List && middle.length == 5) {
        try {
          middleName = HandEvaluator.evaluate5(
            List<String>.from(middle),
          ).nameTh;
        } catch (_) {}
      }
    }
    if (backName.isEmpty) {
      final back = playerResult['back'];
      if (back is List && back.length == 5) {
        try {
          backName = HandEvaluator.evaluate5(List<String>.from(back)).nameTh;
        } catch (_) {}
      }
    }

    if (isFoul) {
      final int coinChange = playerResult['coinChange'] ?? 0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.shade900.withOpacity(0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade400, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'FOUL!',
              style: TextStyle(
                color: Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_showResult || _showdownRevealStep >= 3)
              Text(
                '$coinChange',
                style: TextStyle(
                  color: Colors.red.shade300,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFDAA520).withOpacity(0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Builder(
        builder: (_) {
          // When result is showing (including 10s delay), show all rows
          final step = _showResult ? 4 : _showdownRevealStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // แสดงทุกบรรทัดตลอด (ขนาดคงที่) แต่ Opacity ซ่อนที่ยังไม่เปิด
              Opacity(
                opacity: step >= 3 ? 1.0 : 0.0,
                child: _buildRowScoreLine('หน้า', frontName, frontScore),
              ),
              Opacity(
                opacity: step >= 2 ? 1.0 : 0.0,
                child: _buildRowScoreLine('กลาง', middleName, middleScore),
              ),
              Opacity(
                opacity: step >= 1 ? 1.0 : 0.0,
                child: _buildRowScoreLine('หลัง', backName, backScore),
              ),
              // Royalties
              Opacity(
                opacity: (step >= 3 && royalties > 0) ? 1.0 : 0.0,
                child: Text(
                  '✨+$royalties',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Total coin change
              Opacity(
                opacity: step >= 3 ? 1.0 : 0.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(
                      height: 6,
                      thickness: 0.5,
                      color: Color(0xFFDAA520),
                    ),
                    Builder(
                      builder: (_) {
                        final cc =
                            (playerResult['coinChange'] as num?)?.toInt() ?? 0;
                        final isW = cc > 0;
                        return Text(
                          '${isW ? "+" : ""}$cc',
                          style: TextStyle(
                            color: isW
                                ? Colors.greenAccent
                                : Colors.red.shade300,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Single row score line: "Back: Full House ✓+25"
  /// แสดงชื่อมือไพ่ + คะแนน — 2 บรรทัด เพื่อให้เห็นชัด
  Widget _buildRowScoreLine(String label, String handName, int score) {
    final isWin = score > 0;
    final isLose = score < 0;
    final color = isWin
        ? Colors.greenAccent
        : isLose
        ? Colors.red.shade300
        : Colors.white54;
    final icon = isWin
        ? '✓'
        : isLose
        ? '✗'
        : '—';
    final scoreText = score > 0 ? '+$score' : '$score';

    // แปลชื่อไพ่เป็นไทย ถ้ายังเป็นอังกฤษ
    final displayName = _translateHandName(handName);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$label ',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
              Text(
                '$icon$scoreText',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (displayName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 1),
              child: Text(
                displayName,
                style: TextStyle(
                  color: const Color(0xFFFFD700).withOpacity(0.85),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }

  /// แปลชื่อมือไพ่จากอังกฤษเป็นไทย
  String _translateHandName(String name) {
    if (name.isEmpty) return '';
    switch (name) {
      case 'High Card':
        return 'ไฮการ์ด';
      case 'Pair':
        return 'คู่';
      case 'One Pair':
        return 'คู่';
      case 'Two Pair':
        return 'ทูแพร์';
      case 'Three of a Kind':
        return 'ตอง';
      case 'Straight':
        return 'สเตรท';
      case 'Flush':
        return 'ฟลัช';
      case 'Full House':
        return 'ฟูลเฮาส์';
      case 'Four of a Kind':
        return 'โฟร์';
      case 'Straight Flush':
        return 'สเตรทฟลัช';
      case 'Royal Flush':
        return 'รอยัลฟลัช';
      default:
        return name; // ถ้าเป็นไทยอยู่แล้วก็ใช้ตรงๆ
    }
  }

  /// Opponent fanned card backs — 3 fan groups stacked (bottom→top)
  /// ใช้ขนาดคงที่ตาม container width (130px) — รองรับทุก device
  Widget _buildOpponentFannedCards() {
    const containerW = 160.0;
    final cardW = (containerW / 3.9);
    final cardH = cardW * 1.42;
    final peekHeight = (cardW * 1.1).clamp(35.0, 55.0);
    final fanWidth = containerW;
    final fanHeight = cardH * 1.5;
    final totalH = fanHeight + peekHeight * 2;

    return SizedBox(
      width: fanWidth,
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: peekHeight * 2,
            left: 0,
            right: 0,
            child: _buildFannedGroupCompact(
              List.filled(3, ''),
              false,
              cardW,
              cardH,
            ),
          ),
          Positioned(
            bottom: peekHeight,
            left: 0,
            right: 0,
            child: _buildFannedGroupCompact(
              List.filled(5, ''),
              false,
              cardW,
              cardH,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildFannedGroupCompact(
              List.filled(5, ''),
              false,
              cardW,
              cardH,
            ),
          ),
        ],
      ),
    );
  }

  /// A single row of card backs — overlapping horizontally like face-up cards
  Widget _buildSolidCardBackRow(int count, double cardW, double cardH) {
    final offset = cardW * 0.65;
    return SizedBox(
      width: cardW + (count - 1) * offset,
      height: cardH,
      child: Stack(
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              left: i * offset,
              child: Container(
                width: cardW,
                height: cardH,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFD42020), Color(0xFF8B0000)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: const Color(0xFFDAA520),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFDAA520),
                        width: 0.8,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '☀',
                        style: TextStyle(fontSize: 6, color: Color(0xFFDAA520)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Opponent cards during showdown — reveals face-up row by row
  Widget _buildOpponentShowdownCards(Map<String, dynamic> p, int seatNum) {
    // During showdown OR result display, get actual cards from result data
    final showingCards = _showdownActive || _showResult;
    Map<String, dynamic>? playerResult;
    if (showingCards && _resultData.isNotEmpty) {
      final found = _resultData.where((r) => r['seat'] == seatNum);
      if (found.isNotEmpty) playerResult = found.first;
    }
    // Fallback: use arranged data from server state
    if (playerResult == null && showingCards) {
      final sp = _serverPlayers[seatNum];
      if (sp != null && sp['arranged'] != null) {
        final arr = Map<String, dynamic>.from(sp['arranged'] as Map);
        playerResult = {
          'seat': seatNum,
          'back': arr['back'] ?? [],
          'middle': arr['middle'] ?? [],
          'front': arr['front'] ?? [],
          'backName': arr['backName'] ?? '',
          'middleName': arr['middleName'] ?? '',
          'frontName': arr['frontName'] ?? '',
          'isFoul': arr['isFoul'] ?? false,
        };
      }
    }

    if (playerResult != null && playerResult.isNotEmpty) {
      final back = List<String>.from(playerResult['back'] ?? []);
      final middle = List<String>.from(playerResult['middle'] ?? []);
      final front = List<String>.from(playerResult['front'] ?? []);

      // ใช้ขนาดคงที่ตาม container width (130px) — รองรับทุก device
      const containerW = 160.0;
      final cW = (containerW / 3.9);
      final cH = cW * 1.42;
      final peekHeight = (cW * 1.1).clamp(35.0, 55.0);
      final fanWidth = containerW;
      final fanHeight = cH * 1.5;
      final totalH = fanHeight + peekHeight * 2;

      // When result is showing, all rows are revealed
      final revealAll = _showResult || _showdownRevealStep >= 4;

      // ล็อกตำแหน่งคงที่ — ใช้ขนาดเท่ากันทั้งหงายและคว่ำ ไม่ใช้ AnimatedSwitcher
      return SizedBox(
        width: fanWidth,
        height: totalH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // กองหน้า — วางก่อน = ด้านหลังสุด (ถูกบัง)
            Positioned(
              bottom: peekHeight * 2,
              left: 0,
              right: 0,
              child: _buildFannedGroupCompact(
                (revealAll || _showdownRevealStep >= 3)
                    ? front
                    : List.filled(3, ''),
                (revealAll || _showdownRevealStep >= 3),
                cW,
                cH,
              ),
            ),
            // กองกลาง — กลาง
            Positioned(
              bottom: peekHeight,
              left: 0,
              right: 0,
              child: _buildFannedGroupCompact(
                (revealAll || _showdownRevealStep >= 2)
                    ? middle
                    : List.filled(5, ''),
                (revealAll || _showdownRevealStep >= 2),
                cW,
                cH,
              ),
            ),
            // กองหลัง — วางสุดท้าย = ด้านหน้าสุด (เห็นเต็ม)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildFannedGroupCompact(
                (revealAll || _showdownRevealStep >= 1)
                    ? back
                    : List.filled(5, ''),
                (revealAll || _showdownRevealStep >= 1),
                cW,
                cH,
              ),
            ),
          ],
        ),
      );
    }
    // Default: show card backs
    return _buildOpponentFannedCards();
  }

  /// Responsive version of opponent showdown cards — ใช้ containerW ที่คำนวณจาก LayoutBuilder
  Widget _buildOpponentShowdownCardsResponsive(
    Map<String, dynamic> p,
    int seatNum,
    double containerW,
  ) {
    // During showdown OR result display, get actual cards from result data
    final showingCards = _showdownActive || _showResult;
    Map<String, dynamic>? playerResult;
    if (showingCards && _resultData.isNotEmpty) {
      final found = _resultData.where((r) => r['seat'] == seatNum);
      if (found.isNotEmpty) playerResult = found.first;
    }
    // Fallback: use arranged data from server state
    if (playerResult == null && showingCards) {
      final sp = _serverPlayers[seatNum];
      if (sp != null && sp['arranged'] != null) {
        final arr = Map<String, dynamic>.from(sp['arranged'] as Map);
        playerResult = {
          'seat': seatNum,
          'back': arr['back'] ?? [],
          'middle': arr['middle'] ?? [],
          'front': arr['front'] ?? [],
          'backName': arr['backName'] ?? '',
          'middleName': arr['middleName'] ?? '',
          'frontName': arr['frontName'] ?? '',
          'isFoul': arr['isFoul'] ?? false,
        };
      }
    }

    if (playerResult != null && playerResult.isNotEmpty) {
      final back = List<String>.from(playerResult['back'] ?? []);
      final middle = List<String>.from(playerResult['middle'] ?? []);
      final front = List<String>.from(playerResult['front'] ?? []);

      final cW = (containerW / 3.9);
      final cH = cW * 1.42;
      final peekHeight = (cW * 1.1).clamp(35.0, 55.0);
      final fanWidth = containerW;
      final fanHeight = cH * 1.5;
      final totalH = fanHeight + peekHeight * 2;

      final revealAll = _showResult || _showdownRevealStep >= 4;

      return SizedBox(
        width: fanWidth,
        height: totalH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              bottom: peekHeight * 2,
              left: 0,
              right: 0,
              child: _buildFannedGroupCompact(
                (revealAll || _showdownRevealStep >= 3)
                    ? front
                    : List.filled(3, ''),
                (revealAll || _showdownRevealStep >= 3),
                cW,
                cH,
              ),
            ),
            Positioned(
              bottom: peekHeight,
              left: 0,
              right: 0,
              child: _buildFannedGroupCompact(
                (revealAll || _showdownRevealStep >= 2)
                    ? middle
                    : List.filled(5, ''),
                (revealAll || _showdownRevealStep >= 2),
                cW,
                cH,
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildFannedGroupCompact(
                (revealAll || _showdownRevealStep >= 1)
                    ? back
                    : List.filled(5, ''),
                (revealAll || _showdownRevealStep >= 1),
                cW,
                cH,
              ),
            ),
          ],
        ),
      );
    }
    // Default: show card backs responsive
    return _buildOpponentFannedCardsResponsive(containerW);
  }

  /// Responsive opponent fanned card backs
  Widget _buildOpponentFannedCardsResponsive(double containerW) {
    final cardW = (containerW / 3.9);
    final cardH = cardW * 1.42;
    final peekHeight = (cardW * 1.1).clamp(35.0, 55.0);
    final fanWidth = containerW;
    final fanHeight = cardH * 1.5;
    final totalH = fanHeight + peekHeight * 2;

    return SizedBox(
      width: fanWidth,
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: peekHeight * 2,
            left: 0,
            right: 0,
            child: _buildFannedGroupCompact(
              List.filled(3, ''),
              false,
              cardW,
              cardH,
            ),
          ),
          Positioned(
            bottom: peekHeight,
            left: 0,
            right: 0,
            child: _buildFannedGroupCompact(
              List.filled(5, ''),
              false,
              cardW,
              cardH,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildFannedGroupCompact(
              List.filled(5, ''),
              false,
              cardW,
              cardH,
            ),
          ),
        ],
      ),
    );
  }

  /// Solid card back group — clearly visible red/gold cards
  Widget _buildSolidCardBack(int count) {
    const cardW = 30.0;
    const cardH = 42.0;
    final offset = cardW * 0.65;

    return SizedBox(
      width: cardW + (count - 1) * offset,
      height: cardH,
      child: Stack(
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              left: i * offset,
              child: Container(
                width: cardW,
                height: cardH,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFD42020), Color(0xFF8B0000)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: const Color(0xFFDAA520),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFDAA520),
                        width: 0.8,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '☀',
                        style: TextStyle(fontSize: 6, color: Color(0xFFDAA520)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  // ═══════════════════════════════════════════════════════════
  // Task 17.1: Table_Top_Bar with "OFC" badge (Req 23.5)
  // ═══════════════════════════════════════════════════════════

  Widget _buildTopBar() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Hamburger menu (Req 23.5)
            GestureDetector(
              onTap: () => setState(() => _showMenu = !_showMenu),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black38,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.menu, color: Colors.white, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            // OFC game type badge (Req 23.5)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFDAA520), Color(0xFFB8860B)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Text(
                'OFC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.table['name'] ?? 'ไพ่สามกอง',
              style: TextStyle(
                color: SunTheme.goldLight,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            // Round indicator
            if (_isPlacingPhase)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: Text(
                  'R$_currentRound/8',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            // Fullscreen toggle (web only) — hides the browser address bar as
            // far as the platform allows. No-op / hidden on native iOS/Android
            // since there's no address bar to hide there.
            if (kIsWeb && isFullscreenSupported())
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () async {
                    if (isFullscreenActive()) {
                      await exitFullscreen();
                    } else {
                      await requestFullscreen();
                    }
                    if (mounted) setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isFullscreenActive()
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
            // Connection indicator
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GameSocket.isConnected ? Colors.greenAccent : Colors.red,
              ),
            ),
            // Chip balance
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2A0A0A), Color(0xFF1A0505)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFDAA520).withOpacity(0.3),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'C${NumberFormatter.formatAbbreviated(_myChips)}',
                style: TextStyle(
                  color: SunTheme.goldLight,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuOverlay() {
    return Positioned(
      top: 80,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _menuItem(Icons.history, 'ประวัติ', () {
              setState(() => _showMenu = false);
              final tid = widget.table['id']?.toString();
              showDialog(
                context: context,
                builder: (_) => HandHistoryPopup(tableId: tid, gameType: 'OFC'),
              );
            }),
            const Divider(height: 16),
            _menuItem(Icons.exit_to_app, 'ออก', () => _fadeOutAndPop()),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: Colors.black87, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(color: Colors.black87, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Task 17.1: Table view with 2–4 Player_Seats (Req 23.6)
  // Task 17.2: Card placement area integration
  // Task 17.3: Point_Score_Display, Foul_Indicator, Fantasyland badge
  // ═══════════════════════════════════════════════════════════

  // Seat positions for 2–4 players around the table (x%, y%)
  // Seat positions for OTHER players only (my seat is not shown)
  static const _seatPositions2 = [
    [0.35, 0.00], // top center (1 opponent)
  ];
  static const _seatPositions3 = [
    [0.02, 0.00], // top left
    [0.65, 0.00], // top right
  ];
  static const _seatPositions4 = [
    [0.35, 0.00], // top center
    [0.00, 0.30], // left
    [0.68, 0.30], // right
  ];

  List<List<double>> get _seatPositions {
    final count = _serverPlayers.length;
    // count includes me, so opponents = count - 1
    if (count <= 2) return _seatPositions2; // 1 opponent
    if (count == 3) return _seatPositions3; // 2 opponents
    return _seatPositions4; // 3 opponents
  }

  Widget _buildTableView() {
    return LayoutBuilder(
      builder: (ctx, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        if (w == 0 || h == 0) return const SizedBox();

        final others = _serverPlayers.entries
            .where((e) => _mySeat > 0 ? e.key != _mySeat : true)
            .toList();

        return Stack(
          children: [
            // Opponent seats around the table
            for (int i = 0; i < others.length && i < _seatPositions.length; i++)
              Positioned(
                left: w * _seatPositions[i][0],
                top: h * _seatPositions[i][1],
                child: _buildOpponentSeat(others[i].value, others[i].key),
              ),

            // My card placement area on the table (Task 17.2)
            if (_front.isNotEmpty || _middle.isNotEmpty || _back.isNotEmpty)
              Positioned(
                left: 20,
                right: 20,
                bottom: 10,
                child: _buildMyPlacementArea(),
              ),

            // My avatar removed — player is already sitting, no need to show own icon

            // Phase indicator
            if (_isPlacingPhase && !_hasJoinedChinese)
              Positioned(
                left: 0,
                right: 0,
                top: h * 0.35,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_serverPlayers.values.where((p) => p['isReady'] == true).length}/${_serverPlayers.length} กำลังจัดไพ่...',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_isPlacingPhase && _isMyTurn)
              Positioned(
                left: 0,
                right: 0,
                top: h * 0.35,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      _currentRound == 1
                          ? 'จัดไพ่ 5 ใบ (รอบ 1)'
                          : 'วางไพ่ 1 ใบ (รอบ $_currentRound)',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),

            if (_phase == 'waiting')
              Positioned(
                left: 0,
                right: 0,
                top: h * 0.4,
                child: Center(
                  child: Text(
                    'รอผู้เล่น...',
                    style: TextStyle(
                      color: SunTheme.gold.withOpacity(0.4),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

            // Task 17.3: Royalty display animation
            if (_royaltyAnimController.isAnimating || _royaltyTargetValue > 0)
              Positioned(
                left: 0,
                right: 0,
                top: h * 0.28,
                child: _buildRoyaltyDisplay(),
              ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Task 17.1: Opponent seat with TurnIndicator (Req 23.6)
  // Task 17.3: Point_Score_Display + Foul_Indicator + Fantasyland badge
  // ═══════════════════════════════════════════════════════════

  Widget _buildOpponentSeat(Map<String, dynamic> p, int seatNum) {
    final isTurn = _currentPlayerSeat == seatNum;
    final isReady = p['isReady'] == true;
    final arranged = p['arranged'];
    final points = _playerPoints[seatNum] ?? 0;
    final isFoul = _playerFouls[seatNum] == true;
    final isFL = _playerFantasyland[seatNum] == true;
    final countryFlag = p['countryFlag'] as String?;

    // Result state
    final isResultPhase = _phase == 'result' || _phase == 'showdown';
    final coinChange = _playerCoinChange[seatNum] ?? 0;
    final isWinnerSeat = isResultPhase && coinChange > 0;
    final isLoserSeat = isResultPhase && coinChange < 0;

    // Placement status
    final placedCards = p['placedCount'] as int? ?? 0;
    final isArranging = _isPlacingPhase && arranged == null && isReady;
    final isDoneArranging = _isPlacingPhase && arranged != null;

    // Avatar border color based on phase
    Color borderColor;
    double borderWidth;
    if (isWinnerSeat) {
      borderColor = Colors.greenAccent;
      borderWidth = 3;
    } else if (isLoserSeat) {
      borderColor = Colors.red;
      borderWidth = 3;
    } else if (isTurn) {
      borderColor = Colors.amber;
      borderWidth = 3;
    } else if (isFoul) {
      borderColor = Colors.red;
      borderWidth = 2;
    } else {
      borderColor = SunTheme.goldLight;
      borderWidth = 2;
    }

    Widget avatarWidget = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
        color: Colors.black54,
        boxShadow: isResultPhase && coinChange != 0
            ? [
                BoxShadow(
                  color: (isWinnerSeat ? Colors.greenAccent : Colors.red)
                      .withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          (p['username'] ?? '?')[0].toUpperCase(),
          style: TextStyle(
            color: SunTheme.goldLight,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    // Task 17.1: Wrap with TurnIndicator (Req 22.1–22.11)
    if (isTurn) {
      avatarWidget = TurnIndicator(
        isActive: true,
        totalSeconds: _turnTotalSeconds,
        remainingSeconds: _turnRemainingSeconds,
        isBetPending: false,
        child: avatarWidget,
      );
    }

    // Status badge overlay on avatar
    Widget avatarWithBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        avatarWidget,
        if (_isPlacingPhase) ...[
          if (isDoneArranging)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: SunTheme.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: SunTheme.green.withOpacity(0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.check, color: Colors.white, size: 10),
                ),
              ),
            )
          else if (isArranging)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.4),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Center(
                  child: SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );

    return SizedBox(
      width: 120,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatarWithBadge,
          const SizedBox(height: 2),
          // Username + chips in dark box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (countryFlag != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Text(
                          countryFlag,
                          style: const TextStyle(fontSize: 8),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        p['username'] ?? 'Seat $seatNum',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  'C${NumberFormatter.formatAbbreviated(p['chips'] ?? 0)}',
                  style: TextStyle(
                    color: SunTheme.goldLight,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Placement progress bar during arranging phase
          if (_isPlacingPhase && isArranging && placedCards > 0)
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 50,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (placedCards / 13).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

          // Placement status text
          if (_isPlacingPhase && !isDoneArranging && isArranging)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                placedCards > 0 ? 'จัดไพ่ $placedCards/13' : '🔄 กำลังจัด...',
                style: TextStyle(
                  color: Colors.amber.withOpacity(0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (_isPlacingPhase && isDoneArranging)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                '✅ จัดเสร็จ',
                style: TextStyle(
                  color: SunTheme.green,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          // Task 17.3: Point_Score_Display (Req 26.2, 29.5)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${points >= 0 ? "+" : ""}$points ${ThaiLabels.points}',
              style: TextStyle(
                color: points >= 0
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFF87171),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Coin change during result phase — โชวจำนวนเงินของผู้เล่นคนอื่น
          if (isResultPhase && coinChange != 0)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isWinnerSeat
                    ? Colors.green.shade800
                    : Colors.red.shade900,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: (isWinnerSeat ? Colors.greenAccent : Colors.red)
                        .withOpacity(0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                '${coinChange >= 0 ? "+" : ""}${NumberFormatter.formatWithCommas(coinChange)}',
                style: TextStyle(
                  color: isWinnerSeat
                      ? Colors.greenAccent
                      : Colors.red.shade200,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          // Task 17.3: Foul_Indicator (Req 26.5, 29.2)
          if (isFoul)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade900,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                ThaiLabels.foul,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          // Task 17.3: Fantasyland badge (Req 27.4, 29.3)
          if (isFL)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.4),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Text(
                ThaiLabels.fantasyland,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          if (isReady && arranged == null && !_isPlacingPhase)
            Text(
              '✅ พร้อม',
              style: TextStyle(color: SunTheme.green, fontSize: 11),
            ),

          // Show opponent cards in result/showdown phase (Req 25.6)
          if ((_phase == 'result' || _phase == 'showdown') &&
              arranged != null) ...[
            const SizedBox(height: 4),
            _buildMiniCardRows(arranged),
          ],
          // Show face-down cards during arranging phase (visual feedback)
          if (_isPlacingPhase && arranged == null && isReady) ...[
            const SizedBox(height: 4),
            _buildMiniCardBacks(),
          ],
          // Show arranged cards when opponent is done
          if (_isPlacingPhase && arranged != null) ...[
            const SizedBox(height: 4),
            _buildMiniCardRows(arranged),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniCardRows(Map<String, dynamic> arranged) {
    final front = List<String>.from(arranged['front'] ?? []);
    final middle = List<String>.from(arranged['middle'] ?? []);
    final back = List<String>.from(arranged['back'] ?? []);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMiniOverlapRow(front),
        const SizedBox(height: 1),
        _buildMiniOverlapRow(middle),
        const SizedBox(height: 1),
        _buildMiniOverlapRow(back),
      ],
    );
  }

  /// Show face-down cards in 3 rows (5+5+3) to indicate opponent has cards
  Widget _buildMiniCardBacks() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMiniBackRow(3), // front
        const SizedBox(height: 1),
        _buildMiniBackRow(5), // middle
        const SizedBox(height: 1),
        _buildMiniBackRow(5), // back
      ],
    );
  }

  Widget _buildMiniBackRow(int count) {
    const double cardW = 16;
    const double cardH = 22;
    const double overlap = 10;
    return SizedBox(
      width: cardW + (count - 1) * overlap,
      height: cardH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              left: i * overlap,
              top: 0,
              child: PlayingCard(
                card: '??',
                faceUp: false,
                width: cardW,
                height: cardH,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniOverlapRow(List<String> cards) {
    const double cardW = 20;
    const double cardH = 28;
    const double overlap = 17; // คลี่ออกเต็มที่ให้เห็นเลข 10
    if (cards.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: cardW + (cards.length - 1) * overlap,
      height: cardH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < cards.length; i++)
            Positioned(
              left: i * overlap,
              top: 0,
              child: PlayingCard(
                card: cards[i],
                faceUp: true,
                width: cardW,
                height: cardH,
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // My seat avatar with timer ring and placement status
  // ═══════════════════════════════════════════════════════════

  Widget _buildMySeatAvatar() {
    final myData = _serverPlayers[_mySeat];
    final username = myData?['username'] ?? 'Me';
    final myPlacedCount = _front.length + _middle.length + _back.length;
    final isDone = _allPlaced;

    // Result state for my seat
    final isResultPhase = _phase == 'result' || _phase == 'showdown';
    final myCoinChange = _playerCoinChange[_mySeat] ?? 0;
    final isMyWin = isResultPhase && myCoinChange > 0;
    final isMyLose = isResultPhase && myCoinChange < 0;

    // Border color
    Color myBorderColor;
    double myBorderWidth;
    if (isMyWin) {
      myBorderColor = Colors.greenAccent;
      myBorderWidth = 3;
    } else if (isMyLose) {
      myBorderColor = Colors.red;
      myBorderWidth = 3;
    } else if (_isMyTurn) {
      myBorderColor = Colors.amber;
      myBorderWidth = 3;
    } else {
      myBorderColor = SunTheme.goldLight;
      myBorderWidth = 2;
    }

    Widget avatarWidget = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: myBorderColor, width: myBorderWidth),
        color: Colors.black54,
        boxShadow: isResultPhase && myCoinChange != 0
            ? [
                BoxShadow(
                  color: (isMyWin ? Colors.greenAccent : Colors.red)
                      .withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          username[0].toUpperCase(),
          style: TextStyle(
            color: SunTheme.goldLight,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );

    // Wrap with TurnIndicator when it's my turn
    if (_isMyTurn && _isPlacingPhase) {
      avatarWidget = TurnIndicator(
        isActive: true,
        totalSeconds: _turnTotalSeconds,
        remainingSeconds: _turnRemainingSeconds,
        isBetPending: false,
        onTimeout: _autoPlaceAndConfirm,
        child: avatarWidget,
      );
    }

    // Status badge
    Widget avatarWithBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        avatarWidget,
        if (_isPlacingPhase) ...[
          if (isDone)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: SunTheme.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: const Center(
                  child: Icon(Icons.check, color: Colors.white, size: 8),
                ),
              ),
            )
          else if (_hand.isNotEmpty)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 7,
                    height: 7,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatarWithBadge,
        const SizedBox(height: 2),
        Text(
          username,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        // Placement progress
        if (_isPlacingPhase && myPlacedCount > 0 && !isDone)
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 44,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (myPlacedCount / 13).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        if (_isPlacingPhase && !isDone && myPlacedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '$myPlacedCount/13',
              style: TextStyle(
                color: Colors.amber.withOpacity(0.7),
                fontSize: 7,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (_isPlacingPhase && isDone)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '✅ จัดเสร็จ',
              style: TextStyle(
                color: SunTheme.green,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        // Coin change during result phase
        if (isResultPhase && myCoinChange != 0)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isMyWin ? Colors.green.shade800 : Colors.red.shade900,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: (isMyWin ? Colors.greenAccent : Colors.red)
                      .withOpacity(0.3),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Text(
              '${myCoinChange >= 0 ? "+" : ""}${NumberFormatter.formatWithCommas(myCoinChange)}',
              style: TextStyle(
                color: isMyWin ? Colors.greenAccent : Colors.red.shade200,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Task 17.2: My card placement area with hand labels (Req 25.5)
  // ═══════════════════════════════════════════════════════════

  Widget _buildMyPlacementArea() {
    // Task 17.3: Check foul in real-time (Req 26.5)
    final showFoul =
        _front.length == 3 &&
        _middle.length == 5 &&
        _back.length == 5 &&
        OFCScorer.isFoul(_front, _middle, _back);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Front hand row
        _buildPlacementRow(ThaiLabels.frontHand, _front, 3, 'front'),
        const SizedBox(height: 3),
        // Middle hand row
        _buildPlacementRow(ThaiLabels.middleHand, _middle, 5, 'middle'),
        // Swap button between Middle and Back
        if (_middle.isNotEmpty && _back.isNotEmpty)
          GestureDetector(
            onTap: _swapMiddleAndBack,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF4CAF50).withOpacity(0.5),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'สลับกลาง↔ล่าง',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_middle.isEmpty || _back.isEmpty) const SizedBox(height: 3),
        // Back hand row
        _buildPlacementRow(ThaiLabels.backHand, _back, 5, 'back'),

        // Task 17.3: Foul indicator for current player (Req 26.5, 29.2)
        if (showFoul)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.shade900,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '⚠ ฟาวล์ — ผิดลำดับกอง',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlacementRow(
    String label,
    List<String> cards,
    int maxCards,
    String row,
  ) {
    String handLabel = '';
    if (row == 'front' && cards.length == 3) {
      final rank = HandEvaluator.evaluate3(cards);
      handLabel = ThaiLabels.handNames[rank.rank] ?? '';
    } else if ((row == 'middle' || row == 'back') && cards.length == 5) {
      final rank = HandEvaluator.evaluate5(cards);
      handLabel = ThaiLabels.handNames[rank.rank] ?? '';
    }

    final isActive = _activeRow == row && _hand.isNotEmpty && _isPlacingPhase;
    final isFull = cards.length >= maxCards;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => !isFull && _canPlace,
      onAcceptWithDetails: (details) {
        _placeCard(details.data, row);
      },
      builder: (context, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: () {
            if (_canPlace) {
              if (!isFull) {
                setState(() => _activeRow = row);
              } else {
                _showRowFullMessage();
              }
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDragOver
                    ? Colors.greenAccent.withOpacity(0.9)
                    : isActive
                    ? SunTheme.goldLight.withOpacity(0.8)
                    : Colors.transparent,
                width: (isDragOver || isActive) ? 2 : 0,
              ),
              color: isDragOver
                  ? Colors.greenAccent.withOpacity(0.1)
                  : isActive
                  ? SunTheme.goldLight.withOpacity(0.06)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                // Row label
                SizedBox(
                  width: 48,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isActive
                              ? SunTheme.goldLight
                              : SunTheme.goldLight.withOpacity(0.7),
                          fontSize: 13,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${cards.length}/$maxCards',
                        style: TextStyle(
                          color: isFull
                              ? Colors.greenAccent.withOpacity(0.6)
                              : Colors.amber.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                      if (isDragOver && !isFull)
                        Text(
                          '↓ วางได้',
                          style: TextStyle(
                            color: Colors.greenAccent.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else if (isActive && !isFull)
                        Text(
                          '◀ วางที่นี่',
                          style: TextStyle(
                            color: Colors.amber.withOpacity(0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                // Overlapping cards in row
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: cards.isEmpty
                        ? Row(
                            children: [
                              for (int i = 0; i < maxCards; i++)
                                _buildEmptySlot(isActive: isActive),
                            ],
                          )
                        : _buildOverlappingRowCards(cards, row),
                  ),
                ),
                const SizedBox(width: 4),
                // Hand label with background + status icon
                if (handLabel.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status icon: ✓ when full, ✗ when invalid
                      if (isFull)
                        Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.green.shade700,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A2E0A).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFDAA520).withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          handLabel,
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (!isFull && cards.isNotEmpty)
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.shade700.withOpacity(0.6),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
              ],
            ),
          ),
        ); // end GestureDetector
      }, // end DragTarget builder
    ); // end DragTarget
  }

  /// Cards in a placement row — no overlap, all faces visible
  Widget _buildOverlappingRowCards(List<String> cards, String row) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth;
        final count = cards.length;
        final gap = 3.0;
        final cardW = ((availableW - (count - 1) * gap) / count).clamp(
          24.0,
          32.0,
        );
        final cardH = cardW * 1.4;

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: SizedBox(
            height: cardH,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < count; i++) ...[
                  AnimatedScale(
                    scale: 1.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.elasticOut,
                    child: GestureDetector(
                      onTap: () => _removeCardFromRow(row, i),
                      child: PlayingCard(
                        card: cards[i],
                        faceUp: true,
                        width: cardW,
                        height: cardH,
                      ),
                    ),
                  ),
                  if (i < count - 1) SizedBox(width: gap),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptySlot({bool isActive = false}) {
    return Container(
      width: 28,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: isActive
            ? SunTheme.goldLight.withOpacity(0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        painter: _DashedSlotPainter(
          color: isActive
              ? SunTheme.goldLight.withOpacity(0.6)
              : SunTheme.gold.withOpacity(0.3),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Task 17.3: Royalty display with gold sparkle animation (Req 26.3, 26.7)
  // ═══════════════════════════════════════════════════════════

  Widget _buildRoyaltyDisplay() {
    return AnimatedBuilder(
      animation: _royaltyCountAnimation,
      builder: (context, _) {
        final currentValue =
            (_royaltyTargetValue * _royaltyCountAnimation.value).round();
        if (currentValue == 0 && !_royaltyAnimController.isAnimating) {
          return const SizedBox.shrink();
        }
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFD700),
                  Color(0xFFFFA500),
                  Color(0xFFFFD700),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withOpacity(0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sparkle icon
                const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${ThaiLabels.royalties} +$currentValue',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Task 17.3: Result view with scoring (Req 26.1–26.7, 29.4–29.10)
  // ═══════════════════════════════════════════════════════════
  // My Result Banner — shows win/lose + coin change prominently
  // ═══════════════════════════════════════════════════════════

  Widget _buildMyResultBanner() {
    final myCoinChange = _playerCoinChange[_mySeat] ?? 0;
    final myPoints = _playerPoints[_mySeat] ?? 0;
    final myFoul = _playerFouls[_mySeat] == true;
    final isWin = myCoinChange > 0;
    final isDraw = myCoinChange == 0;
    final myData = _serverPlayers[_mySeat];
    final username = myData?['username'] ?? 'Me';

    if (myCoinChange == 0 && myPoints == 0 && !myFoul)
      return const SizedBox.shrink();

    // Get per-row scores from result data
    final myResult = _resultData.where((r) => r['seat'] == _mySeat);
    final int frontScore = myResult.isNotEmpty
        ? (myResult.first['frontScore'] ?? 0)
        : 0;
    final int middleScore = myResult.isNotEmpty
        ? (myResult.first['middleScore'] ?? 0)
        : 0;
    final int backScore = myResult.isNotEmpty
        ? (myResult.first['backScore'] ?? 0)
        : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 2, 12, 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isWin
                  ? [const Color(0xFF0A3A0A), const Color(0xFF0A2A0A)]
                  : isDraw
                  ? [const Color(0xFF2A2A0A), const Color(0xFF1A1A0A)]
                  : [const Color(0xFF3A0A0A), const Color(0xFF2A0505)],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isWin
                  ? Colors.greenAccent.withOpacity(0.5)
                  : isDraw
                  ? Colors.amber.withOpacity(0.3)
                  : Colors.red.withOpacity(0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (isWin
                            ? Colors.greenAccent
                            : isDraw
                            ? Colors.amber
                            : Colors.red)
                        .withOpacity(0.2),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar with colored border
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isWin
                        ? Colors.greenAccent
                        : isDraw
                        ? Colors.amber
                        : Colors.red,
                    width: 2,
                  ),
                  color: Colors.black54,
                  boxShadow: [
                    BoxShadow(
                      color: (isWin ? Colors.greenAccent : Colors.red)
                          .withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    username[0].toUpperCase(),
                    style: TextStyle(
                      color: SunTheme.goldLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Name + per-row scores
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (myFoul)
                      const Text(
                        'ฟาวล์ — แพ้ทุกกอง',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (!myFoul &&
                        (frontScore != 0 || middleScore != 0 || backScore != 0))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            _rowScoreChip('หน้า', frontScore),
                            const SizedBox(width: 4),
                            _rowScoreChip('กลาง', middleScore),
                            const SizedBox(width: 4),
                            _rowScoreChip('หลัง', backScore),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // Coin change
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isWin
                      ? Colors.green.shade800
                      : isDraw
                      ? Colors.amber.shade900
                      : Colors.red.shade900,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: (isWin ? Colors.greenAccent : Colors.red)
                          .withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${myCoinChange >= 0 ? "+" : ""}${NumberFormatter.formatWithCommas(myCoinChange)}',
                    style: TextStyle(
                      color: isWin
                          ? Colors.greenAccent
                          : isDraw
                          ? Colors.amber
                          : Colors.red.shade200,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rowScoreChip(String label, int score) {
    final isPositive = score > 0;
    final color = isPositive
        ? Colors.greenAccent
        : score < 0
        ? Colors.red.shade300
        : Colors.white54;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9),
        ),
        const SizedBox(width: 2),
        Text(
          '${isPositive ? "+" : ""}$score',
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════

  Widget _buildResultView() {
    return Column(
      children: [
        _buildMyResultBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final r in _resultData) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: r['seat'] == _mySeat
                        ? SunTheme.gold.withOpacity(0.1)
                        : Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (r['coinChange'] ?? 0) > 0
                          ? Colors.green.withOpacity(0.4)
                          : Colors.red.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Player header with points
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: SunTheme.gold.withOpacity(0.3),
                            child: Text(
                              (r['username'] ?? '?')[0].toUpperCase(),
                              style: TextStyle(
                                color: SunTheme.goldLight,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            r['username'] ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          // Task 17.3: Net points with Thai formatting (Req 26.4, 29.5, 29.10)
                          Text(
                            '${(r['coinChange'] ?? 0) >= 0 ? "+" : ""}${r['coinChange'] ?? 0} ${ThaiLabels.points}',
                            style: TextStyle(
                              color: (r['coinChange'] ?? 0) >= 0
                                  ? const Color(0xFF4ADE80)
                                  : const Color(0xFFF87171),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Task 17.3: Foul indicator in results (Req 26.5, 26.6)
                      if (r['isFoul'] == true)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '⚠ ${ThaiLabels.foul}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      // Task 17.3: Royalty display in results (Req 26.3, 29.4)
                      if ((r['royalties'] ?? 0) > 0)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '✨ ${ThaiLabels.royalties} +${r['royalties']}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      // Task 17.3: Fantasyland qualification (Req 27.1)
                      if (r['qualifiesFantasyland'] == true)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFFD700),
                                Color(0xFFFFA500),
                                Color(0xFFFFD700),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withOpacity(0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Text(
                            '🌟 ${ThaiLabels.fantasyland}!',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      // Card rows with hand names (Req 29.7)
                      Builder(
                        builder: (_) {
                          final front = List<String>.from(r['front'] ?? []);
                          final middle = List<String>.from(r['middle'] ?? []);
                          final back = List<String>.from(r['back'] ?? []);
                          // Use server-sent names or compute client-side as fallback
                          String frontName = (r['frontName'] ?? '') as String;
                          String middleName = (r['middleName'] ?? '') as String;
                          String backName = (r['backName'] ?? '') as String;
                          if (frontName.isEmpty && front.length == 3) {
                            try {
                              frontName = HandEvaluator.evaluate3(front).nameTh;
                            } catch (_) {}
                          }
                          if (middleName.isEmpty && middle.length == 5) {
                            try {
                              middleName = HandEvaluator.evaluate5(
                                middle,
                              ).nameTh;
                            } catch (_) {}
                          }
                          if (backName.isEmpty && back.length == 5) {
                            try {
                              backName = HandEvaluator.evaluate5(back).nameTh;
                            } catch (_) {}
                          }
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _resultRow(
                                ThaiLabels.frontHand,
                                frontName,
                                front,
                              ),
                              const SizedBox(height: 4),
                              _resultRow(
                                ThaiLabels.middleHand,
                                middleName,
                                middle,
                              ),
                              const SizedBox(height: 4),
                              _resultRow(ThaiLabels.backHand, backName, back),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Tap to close hint
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'แตะเพื่อปิด',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 11,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultRow(String label, String handName, List<String> cards) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: TextStyle(
              color: SunTheme.gold.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
        ),
        if (cards.isNotEmpty)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableW = constraints.maxWidth;
                final count = cards.length;
                final cardW = (availableW / count) - 2;
                final clampedW = cardW.clamp(22.0, 38.0);
                final cardH = clampedW * 1.4;
                return SizedBox(
                  height: cardH,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      for (int i = 0; i < count; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            right: i < count - 1 ? 2 : 0,
                          ),
                          child: PlayingCard(
                            card: cards[i],
                            faceUp: true,
                            width: clampedW,
                            height: cardH,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        if (cards.isEmpty) const Expanded(child: SizedBox()),
        const SizedBox(width: 6),
        Text(
          handName,
          style: TextStyle(
            color: SunTheme.goldLight,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Task 17.2: Bottom panel — hand cards + OFCActionBar (Req 28.1–28.8)
  // Task 17.3: Fantasyland mode (Req 27.2–27.6)
  // ═══════════════════════════════════════════════════════════

  Widget _buildBottomPanel() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.40,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A).withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: const Color(0xFFDAA520).withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.8),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Timer + step indicator
            if (_isPlacingPhase && _turnRemainingSeconds > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _turnRemainingSeconds <= 5
                            ? Colors.red.shade900
                            : Colors.amber.shade900,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '⏱ $_turnRemainingSeconds วินาที',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${_labelForRow(_activeRow)} (${_countForRow(_activeRow)}/${_maxForRow(_activeRow)})',
                      style: TextStyle(
                        color: SunTheme.goldLight.withOpacity(0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            // Hand cards
            if (_hand.isNotEmpty)
              Container(
                constraints: const BoxConstraints(
                  minHeight: 70,
                  maxHeight: 100,
                ),
                child: Center(child: _buildOverlappingHand()),
              ),
            // Placement summary when all placed
            if (_hand.isEmpty && _allPlaced) _buildPlacementSummary(),
            const SizedBox(height: 8),
            // Action buttons
            if (_isPlacingPhase && _hasJoinedChinese)
              OFCActionBar(
                onConfirm: _confirmArrangement,
                onReset: _resetPlacement,
                canConfirm: _canConfirm,
              ),
            if (_phase == 'result')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'มือถัดไปกำลังจะเริ่ม...',
                  style: TextStyle(
                    color: SunTheme.gold.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Card arrangement popup — fullscreen with blur background
  Widget _buildCardPopup() {
    return Stack(
      children: [
        // Blur background
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.black.withOpacity(0.7)),
          ),
        ),
        // Content — wrapped in SafeArea to avoid notch/cutout overlap
        Positioned.fill(child: SafeArea(child: _buildFullscreenArrangePopup())),
      ],
    );
  }

  /// Bottom action bar — shows over the table view during placing phase
  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A).withOpacity(0.9),
        border: Border(
          top: BorderSide(color: const Color(0xFFDAA520).withOpacity(0.3)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Foul indicator
            if (_allPlaced)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _isFoulArrangement
                      ? Colors.red.shade800
                      : Colors.green.shade800,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isFoulArrangement ? Icons.close : Icons.check,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isFoulArrangement ? 'ฟาวล์' : 'OK',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            // Re-arrange — แสดงเฉพาะหลังกดยืนยันแล้ว + ยังไม่หมดเวลา (รอคนอื่นจัด)
            if (_hasConfirmedArrangement && _turnRemainingSeconds > 0)
              GestureDetector(
                onTap: () {
                  final allCards = [..._front, ..._middle, ..._back, ..._hand];
                  final rec = OFCAutoArrange.arrange(allCards);
                  if (rec != null) {
                    setState(() {
                      _front = List<String>.from(rec['front']!);
                      _middle = List<String>.from(rec['middle']!);
                      _back = List<String>.from(rec['back']!);
                      _hand = [];
                      _hasConfirmedArrangement =
                          false; // ยกเลิกยืนยัน ให้จัดใหม่
                      _startCountdownTimer(); // เริ่ม timer ใหม่
                    });
                    // ส่งจัดใหม่ไป server
                    GameSocket.arrangeChinese(_front, _middle, _back);
                    setState(() => _hasConfirmedArrangement = true);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade800,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'จัดใหม่',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            // Confirm (พร้อม)
            GestureDetector(
              onTap: _canConfirm ? _confirmArrangement : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: _canConfirm
                      ? const LinearGradient(
                          colors: [Color(0xFFDAA520), Color(0xFFB8860B)],
                        )
                      : null,
                  color: _canConfirm ? null : Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'พร้อม',
                  style: TextStyle(
                    color: _canConfirm ? Colors.white : Colors.white38,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Timer
            if (_turnRemainingSeconds > 0)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _turnRemainingSeconds <= 5
                      ? Colors.red.shade700
                      : const Color(0xFFE8A000),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$_turnRemainingSeconds',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Fullscreen card arrangement — landscape layout
  /// 3 horizontal rows stacked vertically: กองหน้า (3), กองกลาง (5), กองหลัง (5)
  /// Cards arranged left-to-right in each row
  Widget _buildFullscreenArrangePopup() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // Calculate card size to fit 5 cards per row within available width
        // Max 5 cards with 4px horizontal padding each = 5 * (cardW + 4) <= w - 16 (padding)
        final maxCardWFromWidth = ((w - 16) / 5 - 4).clamp(28.0, 64.0);
        final availH = h - 56;
        final maxCardHFromHeight = (availH / 3.2).clamp(40.0, 90.0);
        final cardW = maxCardWFromWidth.clamp(28.0, maxCardHFromHeight / 1.4);
        final cardH = cardW * 1.4;

        return Column(
          children: [
            // 3 rows of cards (takes most of the space)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Row 1: กองหน้า (3 cards)
                    _buildHorizontalCardRow(
                      'front',
                      ThaiLabels.frontHand,
                      _front,
                      3,
                      cardW,
                      cardH,
                    ),
                    // Row 2: กองกลาง (5 cards)
                    _buildHorizontalCardRow(
                      'middle',
                      ThaiLabels.middleHand,
                      _middle,
                      5,
                      cardW,
                      cardH,
                    ),
                    // Row 3: กองหลัง (5 cards) + swap button overlaid at left
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _buildHorizontalCardRow(
                          'back',
                          ThaiLabels.backHand,
                          _back,
                          5,
                          cardW,
                          cardH,
                        ),
                        // Swap button positioned at left side, overlaying
                        if (_middle.isNotEmpty && _back.isNotEmpty)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: GestureDetector(
                                onTap: _swapMiddleAndBack,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF2E7D32),
                                        Color(0xFF1B5E20),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.withOpacity(0.4),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.swap_vert,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'สลับ',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Bottom bar: buttons + timer
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(
                children: [
                  // Foul indicator
                  if (_allPlaced)
                    Flexible(
                      flex: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _isFoulArrangement
                              ? Colors.red.shade800
                              : Colors.green.shade800,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isFoulArrangement ? Icons.close : Icons.check,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _isFoulArrangement ? 'ฟาวล์' : 'OK',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  const Spacer(),
                  // Confirm (พร้อม)
                  Flexible(
                    flex: 0,
                    child: GestureDetector(
                      onTap: _canConfirm ? _confirmArrangement : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: _canConfirm
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFDAA520),
                                    Color(0xFFB8860B),
                                  ],
                                )
                              : null,
                          color: _canConfirm ? null : Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'พร้อม',
                          style: TextStyle(
                            color: _canConfirm ? Colors.white : Colors.white38,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Timer
                  if (_turnRemainingSeconds > 0)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _turnRemainingSeconds <= 5
                            ? Colors.red.shade700
                            : const Color(0xFFE8A000),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$_turnRemainingSeconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  bool get _isFoulArrangement {
    if (!_allPlaced) return false;
    return OFCScorer.isFoul(_front, _middle, _back);
  }

  /// A horizontal row of cards — cards left-to-right, drag between rows
  Widget _buildHorizontalCardRow(
    String row,
    String label,
    List<String> cards,
    int maxCards,
    double cardW,
    double cardH,
  ) {
    final isFull = cards.length >= maxCards;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final card = details.data;
        // Always accept: _placeCard removes from source first, so space will be available
        // Only reject if card is already in this exact row (no-op)
        if (cards.contains(card)) return false;
        return true;
      },
      onAcceptWithDetails: (details) {
        final card = details.data;
        if (!cards.contains(card)) {
          _placeCard(card, row);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isDragOver ? Colors.greenAccent.withOpacity(0.05) : null,
            border: isDragOver
                ? Border.all(
                    color: Colors.greenAccent.withOpacity(0.5),
                    width: 2,
                  )
                : null,
          ),
          child: Row(
            children: [
              // Cards arranged horizontally
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < maxCards; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: i < cards.length
                            ? _buildDraggableRowCardSized(
                                cards[i],
                                row,
                                i,
                                cardW,
                                cardH,
                              )
                            : _buildEmptyCardSlotSized(cardW, cardH),
                      ),
                  ],
                ),
              ),
              // Label on right + hand name
              SizedBox(
                width: 110,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: SunTheme.goldLight,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isFull)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A2E0A).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFDAA520).withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          _getHandName(row, cards),
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Text(
                        '${cards.length}/$maxCards',
                        style: TextStyle(
                          color: SunTheme.goldLight.withOpacity(0.4),
                          fontSize: 14,
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

  /// A draggable card that is also a drop target for swapping
  Widget _buildDraggableRowCardSized(
    String card,
    String row,
    int index,
    double cardW,
    double cardH,
  ) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        // Accept any card that isn't this same card
        return details.data != card;
      },
      onAcceptWithDetails: (details) {
        final droppedCard = details.data;
        // Swap the two cards
        _swapCards(droppedCard, card);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return Draggable<String>(
          data: card,
          feedback: Material(
            color: Colors.transparent,
            child: Transform.scale(
              scale: 1.15,
              child: PlayingCard(
                card: card,
                faceUp: true,
                width: cardW,
                height: cardH,
              ),
            ),
          ),
          childWhenDragging: Container(
            width: cardW,
            height: cardH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber.withOpacity(0.4)),
              color: Colors.amber.withOpacity(0.1),
            ),
          ),
          child: Container(
            decoration: isHovered
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.greenAccent, width: 2),
                  )
                : null,
            child: PlayingCard(
              card: card,
              faceUp: true,
              width: cardW,
              height: cardH,
            ),
          ),
        );
      },
    );
  }

  /// Swap two cards regardless of which row they're in
  void _swapCards(String cardA, String cardB) {
    setState(() {
      // Find positions of both cards
      final rowA = _findCardRow(cardA);
      final rowB = _findCardRow(cardB);
      if (rowA == null || rowB == null) return;

      final listA = _getRowList(rowA);
      final listB = _getRowList(rowB);
      final indexA = listA.indexOf(cardA);
      final indexB = listB.indexOf(cardB);

      if (indexA < 0 || indexB < 0) return;

      // Swap
      listA[indexA] = cardB;
      listB[indexB] = cardA;
    });
  }

  /// Find which row a card is in
  String? _findCardRow(String card) {
    if (_front.contains(card)) return 'front';
    if (_middle.contains(card)) return 'middle';
    if (_back.contains(card)) return 'back';
    if (_hand.contains(card)) return 'hand';
    return null;
  }

  /// Get the list for a row name
  List<String> _getRowList(String row) {
    switch (row) {
      case 'front':
        return _front;
      case 'middle':
        return _middle;
      case 'back':
        return _back;
      default:
        return _hand;
    }
  }

  /// Empty card slot placeholder (with custom size)
  Widget _buildEmptyCardSlotSized(double cardW, double cardH) {
    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: SunTheme.goldLight.withOpacity(0.25),
          width: 1,
        ),
        color: Colors.white.withOpacity(0.03),
      ),
    );
  }

  /// Get hand name for a completed row
  String _getHandName(String row, List<String> cards) {
    if (row == 'front' && cards.length == 3) {
      final rank = HandEvaluator.evaluate3(cards);
      return ThaiLabels.handNames[rank.rank] ?? '';
    } else if ((row == 'middle' || row == 'back') && cards.length == 5) {
      final rank = HandEvaluator.evaluate5(cards);
      return ThaiLabels.handNames[rank.rank] ?? '';
    }
    return '';
  }

  /// Guided step indicator — shows progress: กองหลัง → กองกลาง → กองหน้า
  Widget _buildGuidedStepIndicator() {
    final steps = [
      {'row': 'back', 'label': ThaiLabels.backHand, 'max': 5},
      {'row': 'middle', 'label': ThaiLabels.middleHand, 'max': 5},
      {'row': 'front', 'label': ThaiLabels.frontHand, 'max': 3},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SunTheme.goldLight.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 8,
                  color: SunTheme.goldLight.withOpacity(0.3),
                ),
              ),
            _buildStepChip(
              label: steps[i]['label'] as String,
              row: steps[i]['row'] as String,
              max: steps[i]['max'] as int,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepChip({
    required String label,
    required String row,
    required int max,
  }) {
    final count = _countForRow(row);
    final isActive = _activeRow == row && _hand.isNotEmpty;
    final isDone = count >= max;

    Color bgColor;
    Color textColor;
    if (isDone) {
      bgColor = SunTheme.green.withOpacity(0.3);
      textColor = Colors.greenAccent;
    } else if (isActive) {
      bgColor = SunTheme.goldLight.withOpacity(0.2);
      textColor = SunTheme.goldLight;
    } else {
      bgColor = Colors.white.withOpacity(0.05);
      textColor = Colors.white38;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: isActive
            ? Border.all(color: SunTheme.goldLight.withOpacity(0.5))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDone)
            const Padding(
              padding: EdgeInsets.only(right: 3),
              child: Icon(
                Icons.check_circle,
                size: 14,
                color: Colors.greenAccent,
              ),
            ),
          Text(
            '$label $count/$max',
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Summary panel when all 13 cards are placed — shows hand names + foul check
  Widget _buildPlacementSummary() {
    final frontRank = _front.length == 3
        ? HandEvaluator.evaluate3(_front)
        : null;
    final middleRank = _middle.length == 5
        ? HandEvaluator.evaluate5(_middle)
        : null;
    final backRank = _back.length == 5 ? HandEvaluator.evaluate5(_back) : null;
    final isFoul =
        _front.length == 3 &&
        _middle.length == 5 &&
        _back.length == 5 &&
        OFCScorer.isFoul(_front, _middle, _back);

    final frontRoyalty = OFCScorer.calculateRoyalties(_front, 'front');
    final middleRoyalty = OFCScorer.calculateRoyalties(_middle, 'middle');
    final backRoyalty = OFCScorer.calculateRoyalties(_back, 'back');
    final totalRoyalty = frontRoyalty + middleRoyalty + backRoyalty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isFoul
              ? [
                  Colors.red.shade900.withOpacity(0.5),
                  Colors.red.shade900.withOpacity(0.3),
                ]
              : [
                  const Color(0xFF0A2E0A).withOpacity(0.9),
                  const Color(0xFF0A1F0A).withOpacity(0.8),
                ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFoul
              ? Colors.red.withOpacity(0.6)
              : Colors.greenAccent.withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isFoul
                  ? Colors.red.shade900
                  : Colors.greenAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isFoul ? Icons.warning_amber_rounded : Icons.check_circle,
                  color: isFoul ? Colors.amber : Colors.greenAccent,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isFoul
                      ? 'ฟาวล์ — ลำดับกองไม่ถูกต้อง!'
                      : 'จัดไพ่เรียบร้อย! กดยืนยันได้เลย',
                  style: TextStyle(
                    color: isFoul ? Colors.white : Colors.greenAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Hand summary rows with card counts
          _buildSummaryRow(
            '${ThaiLabels.backHand} (${_back.length} ใบ)',
            backRank?.nameTh ?? '-',
            backRoyalty,
          ),
          const SizedBox(height: 2),
          _buildSummaryRow(
            '${ThaiLabels.middleHand} (${_middle.length} ใบ)',
            middleRank?.nameTh ?? '-',
            middleRoyalty,
          ),
          const SizedBox(height: 2),
          _buildSummaryRow(
            '${ThaiLabels.frontHand} (${_front.length} ใบ)',
            frontRank?.nameTh ?? '-',
            frontRoyalty,
          ),
          if (totalRoyalty > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '✨ รอยัลตี้รวม: +$totalRoyalty แต้ม',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          if (isFoul) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withOpacity(0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '⚠ ฟาวล์ — ผิดลำดับกอง',
                style: TextStyle(color: Colors.white70, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String handName, int royalty) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: SunTheme.goldLight.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0505).withOpacity(0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                handName,
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (royalty > 0)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+$royalty',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Recommendation preview — shows suggested arrangement with confirm/manual buttons
  Widget _buildRecommendationPreview() {
    final rec = _recommendedArrangement!;
    final recFront = rec['front'] ?? [];
    final recMiddle = rec['middle'] ?? [];
    final recBack = rec['back'] ?? [];

    // Evaluate hand names
    String frontName = recFront.length == 3
        ? HandEvaluator.evaluate3(recFront).nameTh
        : '';
    String middleName = recMiddle.length == 5
        ? HandEvaluator.evaluate5(recMiddle).nameTh
        : '';
    String backName = recBack.length == 5
        ? HandEvaluator.evaluate5(recBack).nameTh
        : '';

    // Check foul
    final isFoul =
        recFront.length == 3 &&
        recMiddle.length == 5 &&
        recBack.length == 5 &&
        OFCScorer.isFoul(recFront, recMiddle, recBack);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A0A).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lightbulb, color: Colors.amber, size: 16),
              const SizedBox(width: 6),
              const Text(
                'แนะนำการจัดไพ่',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 3 rows preview
          _buildRecRow(
            ThaiLabels.backHand,
            recBack,
            backName,
            const Color(0xFF1565C0),
          ),
          const SizedBox(height: 4),
          _buildRecRow(
            ThaiLabels.middleHand,
            recMiddle,
            middleName,
            const Color(0xFF2E7D32),
          ),
          const SizedBox(height: 4),
          _buildRecRow(
            ThaiLabels.frontHand,
            recFront,
            frontName,
            const Color(0xFFE65100),
          ),

          if (isFoul)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '⚠ คำเตือน: การจัดนี้อาจฟาวล์',
                style: TextStyle(color: Colors.red.shade300, fontSize: 9),
              ),
            ),

          const SizedBox(height: 10),
          // Action buttons
          Row(
            children: [
              // Manual button
              Expanded(
                child: SunButton(
                  label: 'จัดเอง',
                  onTap: () => setState(() => _showRecommendation = false),
                  colors: const [Color(0xFF444444), Color(0xFF2A2A2A)],
                  height: 44,
                  icon: Icons.touch_app,
                ),
              ),
              const SizedBox(width: 10),
              // Confirm recommendation
              Expanded(
                flex: 2,
                child: SunButton.green(
                  label: 'ยืนยันตามแนะนำ',
                  onTap: () {
                    setState(() {
                      _front = List<String>.from(recFront);
                      _middle = List<String>.from(recMiddle);
                      _back = List<String>.from(recBack);
                      _hand = [];
                      _activeRow = 'front';
                      _showRecommendation = false;
                      _recommendedArrangement = null;
                    });
                  },
                  height: 44,
                  icon: Icons.check_circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Single row in recommendation preview
  Widget _buildRecRow(
    String label,
    List<String> cards,
    String handName,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: TextStyle(
                color: accentColor.withOpacity(0.8),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (cards.isNotEmpty)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableW = constraints.maxWidth;
                  final count = cards.length;
                  // Distribute cards evenly across available width
                  final cardW = (availableW / count) - 2;
                  final clampedW = cardW.clamp(24.0, 44.0);
                  final cardH = clampedW * 1.4;
                  return SizedBox(
                    height: cardH,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        for (int i = 0; i < count; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              right: i < count - 1 ? 2 : 0,
                            ),
                            child: PlayingCard(
                              card: cards[i],
                              faceUp: true,
                              width: clampedW,
                              height: cardH,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (cards.isEmpty) const Spacer(),
          const SizedBox(width: 4),
          if (handName.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                handName,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Overlapping hand cards — bigger, fanned, tap to place
  Widget _buildOverlappingHand() {
    final count = _hand.length;
    final screenW = MediaQuery.of(context).size.width - 24;

    // Always display cards in a single horizontal row
    // Cards are portrait (vertical) orientation, arranged left to right
    final maxCardW = 52.0;
    final gap = 4.0;
    double cardW = ((screenW - (count - 1) * gap) / count).clamp(
      28.0,
      maxCardW,
    );
    double cardH = cardW * 1.4;

    return SizedBox(
      width: screenW,
      height: cardH + 4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < count; i++) ...[
            _canPlace
                ? Draggable<String>(
                    data: _hand[i],
                    feedback: Material(
                      color: Colors.transparent,
                      child: Transform.scale(
                        scale: 1.2,
                        child: PlayingCard(
                          card: _hand[i],
                          faceUp: true,
                          width: cardW,
                          height: cardH,
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: PlayingCard(
                        card: _hand[i],
                        faceUp: true,
                        width: cardW,
                        height: cardH,
                      ),
                    ),
                    onDragCompleted: () {},
                    child: GestureDetector(
                      onTap: () => _guidedPlaceCard(_hand[i]),
                      child: PlayingCard(
                        card: _hand[i],
                        faceUp: true,
                        width: cardW,
                        height: cardH,
                      ),
                    ),
                  )
                : PlayingCard(
                    card: _hand[i],
                    faceUp: true,
                    width: cardW,
                    height: cardH,
                  ),
            if (i < count - 1) SizedBox(width: gap),
          ],
        ],
      ),
    );
  }

  /// Task 17.2: Card placement dialog — tap card to choose row
  void _showCardPlacementDialog(String card) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0505),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: SunTheme.gold.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'วางไพ่ $card ที่กอง:',
              style: TextStyle(
                color: SunTheme.goldLight,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _rowSelectButton(
                  ThaiLabels.frontHand,
                  'front',
                  _front.length,
                  3,
                  card,
                  ctx,
                ),
                _rowSelectButton(
                  ThaiLabels.middleHand,
                  'middle',
                  _middle.length,
                  5,
                  card,
                  ctx,
                ),
                _rowSelectButton(
                  ThaiLabels.backHand,
                  'back',
                  _back.length,
                  5,
                  card,
                  ctx,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _rowSelectButton(
    String label,
    String row,
    int current,
    int max,
    String card,
    BuildContext ctx,
  ) {
    final isFull = current >= max;
    return GestureDetector(
      onTap: isFull
          ? null
          : () {
              Navigator.pop(ctx);
              _placeCard(card, row);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isFull
                ? [const Color(0xFF333333), const Color(0xFF222222)]
                : [const Color(0xFFCC2222), const Color(0xFF8B0000)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFull
                ? Colors.white.withOpacity(0.1)
                : const Color(0xFFFFD700).withOpacity(0.5),
          ),
          boxShadow: isFull
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF8B0000).withOpacity(0.3),
                    blurRadius: 6,
                  ),
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isFull ? Colors.white38 : const Color(0xFFFFD700),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$current/$max',
              style: TextStyle(
                color: isFull
                    ? Colors.white24
                    : const Color(0xFFDAA520).withOpacity(0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Task 17.1: Turn timer with 3-tier color (Req 28.5, 22.4–22.6)
  Widget _buildTurnTimer() {
    final timerColor = TimerLogic.getColor(
      _turnRemainingSeconds,
      _turnTotalSeconds,
    );
    Color ringColor;
    switch (timerColor) {
      case TimerColor.green:
        ringColor = Colors.green;
      case TimerColor.amber:
        ringColor = Colors.amber;
      case TimerColor.red:
        ringColor = Colors.red;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.timer, color: ringColor, size: 14),
        const SizedBox(width: 4),
        Text(
          '${_turnRemainingSeconds}s',
          style: TextStyle(
            color: ringColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    final canStart = _serverPlayers.length >= 2;
    final playerCount = _serverPlayers.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: canStart ? Colors.greenAccent : Colors.orangeAccent,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (canStart ? Colors.greenAccent : Colors.orangeAccent)
                              .withOpacity(0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                canStart
                    ? '$playerCount ผู้เล่นพร้อม — กดเริ่มเล่น'
                    : 'รอผู้เล่น... ($playerCount/2)',
                style: TextStyle(
                  color: const Color(0xFFDAA520).withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: canStart ? () => GameSocket.startChinese() : null,
          child: Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: canStart
                    ? const [
                        Color(0xFF3CB371),
                        Color(0xFF2E8B57),
                        Color(0xFF1E6B3E),
                        Color(0xFF155C30),
                      ]
                    : const [
                        Color(0xFF444444),
                        Color(0xFF333333),
                        Color(0xFF222222),
                        Color(0xFF1A1A1A),
                      ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: canStart
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
                width: 1,
              ),
              boxShadow: canStart
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2E8B57).withOpacity(0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 8,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Stack(
              children: [
                // Glass highlight
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(13),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(canStart ? 0.22 : 0.04),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canStart) ...[
                        Icon(
                          Icons.play_circle_filled_rounded,
                          color: Colors.white.withOpacity(0.9),
                          size: 22,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        canStart ? 'เริ่มเล่น' : 'รอผู้เล่น...',
                        style: TextStyle(
                          color: canStart ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          letterSpacing: 1,
                          shadows: canStart
                              ? const [
                                  Shadow(color: Colors.black, blurRadius: 6),
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Dashed border painter for empty card slots (Req 25.7)
class _DashedSlotPainter extends CustomPainter {
  final Color color;

  _DashedSlotPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(4),
        ),
      );

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      const dashWidth = 4.0;
      const dashSpace = 3.0;
      while (distance < metric.length) {
        final end = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, end.clamp(0, metric.length)),
          paint,
        );
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedSlotPainter old) => color != old.color;
}

/// Minimal AnimatedBuilder for use with Listenable animations.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) => builder(context, null);
}
