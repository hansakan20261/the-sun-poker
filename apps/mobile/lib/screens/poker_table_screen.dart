import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/game_socket.dart';
import '../services/runtime_config_service.dart';
import '../services/audio_manager.dart';
import '../services/profile_provider.dart';
import '../services/animation/animation_coordinator.dart';
import '../services/animation/animation_action_blocker.dart';
import '../layout/responsive_layout_engine.dart';
import '../utils/number_formatter.dart';
import '../utils/hand_evaluator.dart';
import '../utils/free_tips_engine.dart';
import '../utils/thai_labels.dart';
import '../utils/timer_logic.dart';
import '../utils/seat_rotation_map.dart';
import '../widgets/playing_card.dart';
import '../widgets/result_overlay.dart';
import '../widgets/deal_animation_overlay.dart';
import '../widgets/deal_to_players_animation.dart';
import '../widgets/hand_history_sheet.dart';
import '../widgets/seat_selection_overlay.dart';
import '../widgets/dealer_button.dart';
import '../widgets/betting_panel.dart';
import '../widgets/turn_indicator.dart';
import '../widgets/tip_overlay.dart';
import '../widgets/rake_display.dart';
import '../widgets/all_in_effect.dart';
import '../widgets/win_celebration_effect.dart';
import '../widgets/showdown_sequence_controller.dart';
import '../widgets/amount_label.dart';
import '../widgets/spectator_status_bar.dart';
import '../widgets/recommendation_badge.dart';
import '../widgets/app_background.dart';
import '../widgets/sun_button.dart';
import '../widgets/chip_animation.dart';
import '../widgets/game_effects.dart';
import '../widgets/table_seat_layout.dart';
import '../widgets/perspective_table_layout.dart';
import '../widgets/player_avatar_3d.dart';
import '../widgets/app_background.dart';
import '../models/practice_session.dart';
import 'lobby_screen.dart';

class PokerTableScreen extends StatefulWidget {
  final Map<String, dynamic> table;
  const PokerTableScreen({super.key, required this.table});
  @override
  State<PokerTableScreen> createState() => _PokerTableScreenState();
}

class _PokerTableScreenState extends State<PokerTableScreen>
    with
        TickerProviderStateMixin,
        AnimationActionBlocker,
        WidgetsBindingObserver {
  String _phase = 'waiting';
  List<String> _myCards = [];
  List<String> _communityCards = [];
  int _pot = 0, _myChips = 0, _currentBet = 0, _resultAmount = 0;
  int _previousPot = 0; // Task 13.1: for counting-up animation
  int? _currentPlayerSeat;
  late int _mySeat;
  bool _showResult = false, _isWinner = false, _showMenu = false;
  bool _showDealAnimation = false;
  bool _showDealToPlayers = false; // Deal cards flying to all players
  Map<String, dynamic>? _tournamentInfo; // Tournament state from server
  bool _newHandStarted = false; // Prevent double-deal on new hand
  bool _hasJoined = false; // Track if player has selected a seat
  List<String> _dealCards = [];
  String _lastDealtCardKey = ''; // Guard against re-triggering deal animation
  Map<int, Map<String, dynamic>> _serverPlayers = {};
  String _resultHand = '';
  List<Map<String, dynamic>> _resultWinners = [];
  List<Map<String, dynamic>> _resultLosers = [];
  List<String> _resultCommunity = [];
  // Enhanced game state fields
  int? _dealerSeat;
  int? _smallBlindSeat;
  int? _bigBlindSeat;
  int _minRaise = 0;
  int _maxBet = 0;
  List<Map<String, dynamic>> _sidePots = [];
  // Task 15.1: FREE TIPS state
  bool _showTipOverlay = false;
  TipResult? _tipResult;
  bool _tipLoading = false;
  // Task 11.2: Rake state
  int _rakeAmount = 0;
  double _rakePercent = 5.0;
  int _rakeCap = 0;
  // Task 11.3: All-in and win celebration state
  Set<int> _allInSeats = {};
  bool _triggerWinCelebration = false;
  // Showdown animation state
  ShowdownSequenceController? _showdownController;
  ShowdownPhase? _showdownPhase;
  Set<int> _revealedSeats = {};
  Map<int, int> _amountLabels =
      {}; // seat → amount (positive=win, negative=loss)
  bool _showdownActive = false;
  // Spectator state
  SpectatorState _spectatorState = SpectatorState.notSpectating;
  // Game guide state
  bool _guideEnabled = true;
  HandStrengthCategory? _guideCategory;
  String _guideExplanation = '';

  // Turn countdown timer
  Timer? _turnTimer;
  int _turnTotalSeconds = 0;
  int _turnCountdown = 0;
  int _turnDeadlineAt = 0;
  int _minimumPlayMinutes = 0;
  // Sitting out: waiting for next hand after joining mid-game
  bool _isSittingOut = false;
  // Slide-in error notification
  String? _errorMessage;
  Timer? _errorTimer;

  // ── Pre-action system ──────────────────────────────────────
  // ผู้เล่นสามารถกด "ตามทุกจำนวน" ก่อนถึงรอบตัวเองได้
  // เมื่อถึงรอบจะ execute อัตโนมัติทันที
  String? _preAction; // 'call_any' | 'check_fold' | null
  bool _preActionArmed = false; // true เมื่อ pre-action ถูก set แล้ว
  // Chip animation
  final ChipAnimationController _chipAnimController = ChipAnimationController();
  final GlobalKey _potKey = GlobalKey();
  final Map<int, GlobalKey> _seatKeys = {};
  // Cached last actions — persists for 2s after server clears them
  final Map<int, String> _cachedActions = {};
  // Action text & confetti
  String? _actionText;
  bool _showConfetti = false;

  // Task 11.7: Responsive layout engine (Req 8.1, 8.7, 9.4, 9.5)
  ResponsiveLayoutEngine? _layoutEngine;

  /// Responsive layout engine accessor — always returns the current engine.
  /// Initialized at the start of each build cycle from screen width.
  ResponsiveLayoutEngine get engine => _layoutEngine!;

  /// Animation scale factor based on screen size (Req 9.4).
  /// Use to scale animation distances/durations proportionally.
  double get animationScale => _layoutEngine?.animationScale ?? 1.0;

  // Task 3.4: Animation coordinator for action blocking (Req 2.4)
  AnimationCoordinator? _animationCoordinator;

  @override
  AnimationCoordinator? get animationCoordinator => _animationCoordinator;

  /// Set the animation coordinator for action blocking.
  /// Called when the coordinator is created (e.g., during feature flag wiring).
  set animationCoordinatorInstance(AnimationCoordinator? coordinator) {
    _animationCoordinator = coordinator;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Allow both orientations — layout adapts to either
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Restore portrait only when leaving
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _animationCoordinator?.dispose(); // Task 3.4: Clean up coordinator
    _showdownController?.dispose();
    _turnTimer?.cancel();
    _errorTimer?.cancel();
    _chipAnimController.dispose();
    GameSocket.disconnect();
    super.dispose();
  }

  /// เมื่อ app กลับจาก background → reconnect socket + resync timer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [NLH] App resumed — reconnecting and resyncing timer');
      if (!GameSocket.isConnected) {
        _init(); // reconnect socket and rejoin table
      } else {
        // Request fresh state from server
        final tid = widget.table['id'];
        if (tid != null) {
          GameSocket.joinTable(
            tid,
            _mySeat,
            0,
            accessToken: widget.table['_roomAccessToken'],
          ); // rejoin with 0 = resync
        }
      }
      // Restart turn timer if game is active
      if (_currentPlayerSeat != null &&
          _phase != 'waiting' &&
          _phase != 'result') {
        _turnTimer?.cancel();
        _turnTimer = null;
        // Timer will restart from next state update with correct turnRemainingSeconds
      }
    } else if (state == AppLifecycleState.paused) {
      debugPrint('⏸️ [NLH] App paused — stopping local timer');
      _turnTimer?.cancel();
      _turnTimer = null;
    }
  }

  /// Trigger chip animation from the last acting player to the pot center.
  void _triggerBetAnimation(int amount) {
    _triggerBetAnimationFrom(_currentPlayerSeat, amount);
  }

  /// Trigger chip animation from a specific player's avatar to the pot center.
  void _triggerBetAnimationFrom(int? fromSeat, int amount) {
    if (amount <= 0) return;
    AudioManager.instance.play(SoundEffect.chipToss);

    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;

    final tableAreaTop = safeTop + 36.0;
    final tableAreaWidth = screenSize.width;
    final tableAreaHeight =
        screenSize.height - tableAreaTop - 200; // exclude action bar

    // Pot = center of table (where community cards are)
    final potCenter = Offset(
      tableAreaWidth / 2,
      tableAreaTop + tableAreaHeight * 0.35,
    );

    // Use PerspectiveTableLayout fixed seat positions (percentage-based)
    final others = _serverPlayers.entries
        .where((e) => e.key != _mySeat)
        .toList();

    // Fixed seat positions matching PerspectiveTableLayout._seatPositions
    const seatXPercents = [0.02, 0.02, 0.12, 0.72, 0.82, 0.82, 0.70];
    const seatYPercents = [0.62, 0.42, 0.20, 0.20, 0.42, 0.62, 0.78];

    Offset? fromPos;

    if (fromSeat == _mySeat) {
      // My seat — bottom center
      fromPos = Offset(tableAreaWidth / 2, screenSize.height - 120);
    } else if (fromSeat != null) {
      final idx = others.indexWhere((e) => e.key == fromSeat);
      if (idx >= 0 && idx < seatXPercents.length) {
        fromPos = Offset(
          seatXPercents[idx] * tableAreaWidth + 45,
          seatYPercents[idx] * screenSize.height + 30,
        );
      }
    }

    fromPos ??= potCenter;

    final chipCount = amount > 100 ? 5 : (amount > 20 ? 3 : 2);
    _chipAnimController.betToPot(
      from: fromPos,
      to: potCenter,
      amount: amount,
      chipCount: chipCount,
    );
  }

  /// Trigger chip animation from pot to winner seat.
  void _triggerWinChipAnimation(int winnerSeat, int amount) {
    AudioManager.instance.play(SoundEffect.winCelebration);
    Future.delayed(const Duration(milliseconds: 300), () {
      AudioManager.instance.play(SoundEffect.coinCascade);
    });

    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;
    final tableAreaTop = safeTop + 36.0;
    final tableAreaWidth = screenSize.width;
    final tableAreaHeight = screenSize.height - tableAreaTop - 200;

    final potCenter = Offset(
      tableAreaWidth / 2,
      tableAreaTop + tableAreaHeight * 0.35,
    );

    // Fixed seat positions matching PerspectiveTableLayout._seatPositions
    const seatXPercents = [0.02, 0.02, 0.12, 0.72, 0.82, 0.82, 0.70];
    const seatYPercents = [0.62, 0.42, 0.20, 0.20, 0.42, 0.62, 0.78];

    Offset toPos;
    if (winnerSeat == _mySeat) {
      toPos = Offset(tableAreaWidth / 2, screenSize.height - 120);
    } else {
      final others = _serverPlayers.entries
          .where((e) => e.key != _mySeat)
          .toList();
      final idx = others.indexWhere((e) => e.key == winnerSeat);
      if (idx >= 0 && idx < seatXPercents.length) {
        toPos = Offset(
          seatXPercents[idx] * tableAreaWidth + 45,
          seatYPercents[idx] * screenSize.height + 30,
        );
      } else {
        toPos = Offset(
          tableAreaWidth / 2,
          tableAreaTop + tableAreaHeight * 0.3,
        );
      }
    }

    final chipCount = amount > 500 ? 6 : (amount > 100 ? 5 : 4);
    _chipAnimController.potToWinner(
      from: potCenter,
      to: toPos,
      amount: amount,
      chipCount: chipCount,
    );
  }

  GlobalKey _getSeatKey(int seat) {
    _seatKeys.putIfAbsent(seat, () => GlobalKey());
    return _seatKeys[seat]!;
  }

  // Time lock: player must stay minimum 15 minutes (starts from first hand played, not from join)
  late DateTime _joinedAt;
  DateTime? _firstHandPlayedAt; // null = hasn't played yet → can leave freely
  // Think-time bank: player can add +15s once per turn
  bool _usedThinkTimeThisTurn = false;
  int _thinkTimeBank = 3; // max 3 uses per session

  Future<void> _init() async {
    _joinedAt = DateTime.now();
    _mySeat = 1; // Auto-join seat 1
    _hasJoined = true;

    // Practice mode: use practice chips as initial display
    final isPractice = widget.table['_isPractice'] == true;

    if (isPractice) {
      _myChips = toInt(widget.table['_buyIn'] ?? 10000);
    } else {
      // Show buy-in amount initially, server will update with actual chips after join
      _myChips = toInt(
        widget.table['_buyIn'] ?? widget.table['min_buy_in'] ?? 0,
      );
    }

    _connectSocket();
  }

  void _connectSocket() {
    debugPrint(
      '🎮 [NLH] _connectSocket() called, tableId=${widget.table['id']}',
    );
    GameSocket.connect();
    GameSocket.onGameState = (state) {
      if (!mounted) return;
      final isPlaying = state['isPlaying'] == true;
      final round = state['currentRound'] ?? 'waiting';
      final pot = state['pot'] ?? 0;
      final currentPlayer = state['currentPlayerSeat'];
      final rawPlayers = state['players'] as Map<String, dynamic>? ?? {};
      final serverTurnTotal = toInt(state['turnTotalSeconds']);
      final serverTurnDeadline = toInt(state['turnDeadlineAt']);
      final serverTurnRemaining = toInt(
        state['turnRemainingSeconds'],
      ).clamp(0, serverTurnTotal).toInt();
      debugPrint(
        '📡 [NLH] onState: isPlaying=$isPlaying, round=$round, pot=$pot, currentPlayer=$currentPlayer, players=${rawPlayers.keys.toList()}',
      );

      setState(() {
        _turnTotalSeconds = serverTurnTotal;
        _turnDeadlineAt = serverTurnDeadline;
        _turnCountdown = serverTurnRemaining;
        _minimumPlayMinutes = toInt(state['minimumPlayMinutes']);
        // Extract tournament info if present
        if (state['tournament'] != null) {
          _tournamentInfo = Map<String, dynamic>.from(state['tournament']);
        }

        final newCommunity = List<String>.from(state['communityCards'] ?? []);
        // Play community card sound when new cards appear (flop/turn/river)
        if (newCommunity.length > _communityCards.length &&
            newCommunity.isNotEmpty) {
          debugPrint(
            '🃏 [NLH] Community cards: ${_communityCards.length} → ${newCommunity.length}',
          );
          AudioManager.instance.play(SoundEffect.cardCommunity);
        }
        _communityCards = newCommunity;
        _previousPot = _pot; // Task 13.1: track previous pot for animation
        final newPot = state['pot'] ?? 0;

        // The player who just bet is the current player BEFORE it changes
        final previousCurrentPlayer = _currentPlayerSeat;

        // Trigger chip-to-pot animation when pot increases (from the player who just bet)
        if (newPot > _pot && _pot > 0 && !_showDealAnimation) {
          _triggerBetAnimationFrom(previousCurrentPlayer, newPot - _pot);
        }

        _pot = newPot;
        final isPlaying = state['isPlaying'] == true;
        final round = state['currentRound'] ?? 'waiting';
        _phase = isPlaying ? round : 'waiting';

        // Reset _newHandStarted when game ends (result/waiting) — ready for next hand
        if (!isPlaying) {
          _newHandStarted = false;
          // Clear pre-action when hand ends
          _preAction = null;
          _preActionArmed = false;
        }

        // Parse enhanced game state fields
        _dealerSeat = state['dealerSeat'];
        _smallBlindSeat = state['smallBlindSeat'];
        _bigBlindSeat = state['bigBlindSeat'];
        _minRaise = state['minRaise'] ?? 0;
        _maxBet = state['maxBet'] ?? 0;
        _sidePots = List<Map<String, dynamic>>.from(
          (state['sidePots'] as List?)?.map(
                (s) => Map<String, dynamic>.from(s),
              ) ??
              [],
        );

        // Task 11.2: Read rake config from table/game state
        _rakePercent =
            (state['rakePercent'] ?? widget.table['rake_percent'] ?? 5.0)
                .toDouble();
        _rakeCap = toInt(state['rakeCap'] ?? widget.table['rake_cap'] ?? 0);

        // Task 11.3: Track all-in seats
        final newAllInSeats = <int>{};

        // Detect new hand: server sends isPlaying=true but we still have old result state
        // Use _newHandStarted as a one-shot flag that persists until game ends (!isPlaying)
        final wasShowingResult = _showResult || _showdownActive;
        if (isPlaying && wasShowingResult && !_newHandStarted) {
          // New hand starting — play shuffle sound (only once)
          debugPrint('🔄 [NLH] New hand starting (was showing result)');
          AudioManager.instance.play(SoundEffect.cardShuffle);
          _showResult = false;
          _showdownActive = false;
          _showdownController?.dispose();
          _showdownController = null;
          _showDealAnimation = false;
          _showDealToPlayers = true; // Trigger deal-to-players animation
          _myCards = [];
          _dealCards = [];
          _amountLabels = {};
          _cachedActions.clear();
          _lastDealtCardKey = '';
          _newHandStarted =
              true; // Flag stays true until game ends (!isPlaying)
        }
        // Clear labels when new hand starts
        if (isPlaying && _amountLabels.isNotEmpty) {
          _amountLabels = {};
        }
        // Detect current player change → reset countdown + reset think-time flag
        final newCurrentPlayer = state['currentPlayerSeat'];
        if (newCurrentPlayer != _currentPlayerSeat) {
          _turnTimer?.cancel();
          _turnTimer = null;
          _usedThinkTimeThisTurn = false; // reset per-turn think-time usage

          // ── Execute pre-action when it becomes our turn ──
          if (newCurrentPlayer == _mySeat &&
              _preActionArmed &&
              _preAction != null) {
            final action = _preAction!;
            _preAction = null;
            _preActionArmed = false;
            // Delay 1 frame so state finishes updating first
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_phase != 'waiting' && _phase != 'result' && !_showResult) {
                _executePreAction(action);
              }
            });
          }
        }
        _currentPlayerSeat = newCurrentPlayer;
        final raw = state['players'] as Map<String, dynamic>? ?? {};
        _serverPlayers = {};
        raw.forEach((s, d) {
          final seat = int.tryParse(s) ?? 0;
          final p = Map<String, dynamic>.from(d);
          _serverPlayers[seat] = p;
          // Cache last action for display persistence
          final serverAction = p['lastAction'] as String?;
          if (serverAction != null && serverAction != 'blind') {
            _cachedActions[seat] = serverAction;
          }
          // Task 11.3: Detect all-in players
          if (p['isAllIn'] == true || p['allIn'] == true) {
            newAllInSeats.add(seat);
          }
          if (seat == _mySeat) {
            _myChips = toInt(p['chips'], _myChips);
            _currentBet = toInt(p['currentBet']);
            _isSittingOut = p['sittingOut'] == true;
            final cards = List<String>.from(p['holeCards'] ?? []);
            debugPrint(
              '👤 [NLH] My seat=$_mySeat, chips=$_myChips, bet=$_currentBet, cards=${cards.length}, sittingOut=$_isSittingOut',
            );
            if (cards.isNotEmpty && cards[0] != '??') {
              // Mark first hand played time for time lock
              _firstHandPlayedAt ??= DateTime.now();
              // Only trigger deal animation once per unique set of cards
              final cardKey = cards.join(',');
              if (cardKey != _lastDealtCardKey && !_showDealAnimation) {
                debugPrint('🎴 [NLH] New hole cards dealt: $cards');
                _dealCards = List<String>.from(cards);
                _lastDealtCardKey = cardKey;
                AudioManager.instance.play(SoundEffect.cardDeal);
                // Only show deal animation after deal-to-players finishes
                if (!_showDealToPlayers) {
                  _showDealAnimation = true;
                }
              }
              _myCards = cards;
            }
          }
        });

        // Task 11.3: Play all-in sound for newly all-in seats
        for (final seat in newAllInSeats) {
          if (!_allInSeats.contains(seat)) {
            AudioManager.instance.play(SoundEffect.allInPush);
          }
        }
        _allInSeats = newAllInSeats;

        // Auto-detect if we're already seated (reconnection case)
        if (!_hasJoined && _mySeat > 0 && _serverPlayers.containsKey(_mySeat)) {
          _hasJoined = true;
        }
      });

      // Turn countdown timer — runs for ALL players (shows time bar on current player's avatar)
      // Reset countdown whenever current player changes
      if (_currentPlayerSeat != null &&
          _phase != 'waiting' &&
          _phase != 'result' &&
          _turnDeadlineAt > 0) {
        if (_turnTimer == null) {
          _turnTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) {
              t.cancel();
              return;
            }
            final remaining = (_turnCountdown - 1)
                .clamp(0, _turnTotalSeconds)
                .toInt();
            setState(() => _turnCountdown = remaining);
            // Countdown sounds (only when it's my turn)
            if (_isMyTurn) {
              if (_turnCountdown <= 5 && _turnCountdown > 0) {
                AudioManager.instance.play(SoundEffect.countdownUrgent);
              } else if (_turnCountdown <= 10 && _turnCountdown > 5) {
                AudioManager.instance.play(SoundEffect.countdownTick);
              }
            }
            if (_turnCountdown <= 0) {
              t.cancel();
              _turnTimer = null;
              // Server performs the authoritative auto-check or auto-fold at the deadline
            }
          });
        }
      } else if (_currentPlayerSeat == null ||
          _phase == 'waiting' ||
          _phase == 'result' ||
          _turnDeadlineAt <= 0) {
        _turnTimer?.cancel();
        _turnTimer = null;
      }
    };
    GameSocket.onGameResult = (r) {
      if (!mounted) return;
      debugPrint('🏆 [NLH] onGameResult received');
      // Cancel turn timer immediately when result arrives
      _turnTimer?.cancel();
      _turnTimer = null;
      final winners = List<Map<String, dynamic>>.from(
        (r['winners'] as List?)?.map((w) => Map<String, dynamic>.from(w)) ?? [],
      );
      final losers = List<Map<String, dynamic>>.from(
        (r['losers'] as List?)?.map((l) => Map<String, dynamic>.from(l)) ?? [],
      );
      debugPrint(
        '🏆 [NLH] Winners: ${winners.map((w) => 'seat=${w['seat']}, hand=${w['handName']}, amount=${w['amount']}').toList()}',
      );
      debugPrint(
        '🏆 [NLH] Losers: ${losers.map((l) => 'seat=${l['seat']}, folded=${l['folded']}').toList()}',
      );
      final community = List<String>.from(r['communityCards'] ?? []);
      final prize = r['prizePerWinner'] ?? 0;
      final isWin = winners.any((w) => w['seat'] == _mySeat);
      final winnerName = winners.isNotEmpty
          ? (winners.first['handName'] ?? '')
          : '';
      // Task 11.2: Read rake from result
      final resultRake = toInt(r['rake_amount'] ?? r['rakeAmount'] ?? 0);
      setState(() {
        _showResult = true;
        _isWinner = isWin;
        _resultAmount = prize;
        _resultHand = isWin ? 'Winner! $winnerName' : 'Better luck next time';
        _resultWinners = winners;
        _resultLosers = losers;
        _resultCommunity = community;
        _phase = 'result';
        _rakeAmount = resultRake;
        _triggerWinCelebration = isWin;
        _showConfetti = isWin;
        _allInSeats = {};
        // Start showdown animation
        _showdownActive = true;
        _showdownPhase = null;
        _revealedSeats = {};
        _amountLabels = {};
        // Set amount labels immediately (fallback for spectators)
        for (final w in winners) {
          final seat = w['seat'] as int? ?? 0;
          _amountLabels[seat] = (w['amount'] as int?) ?? prize;
          // Force reveal hole cards from result data
          if (_serverPlayers.containsKey(seat) && w['holeCards'] != null) {
            _serverPlayers[seat]!['holeCards'] = List<String>.from(
              w['holeCards'],
            );
            _serverPlayers[seat]!['_result'] = 'win';
            _serverPlayers[seat]!['_handName'] = w['handName'] ?? '';
          }
        }
        for (final l in losers) {
          final seat = l['seat'] as int? ?? 0;
          final lostAmount = (l['amount'] as int?) ?? 0;
          if (lostAmount > 0) {
            _amountLabels[seat] = -lostAmount;
          }
          // Force reveal hole cards for ALL losers (including folded)
          if (_serverPlayers.containsKey(seat) && l['holeCards'] != null) {
            _serverPlayers[seat]!['holeCards'] = List<String>.from(
              l['holeCards'],
            );
            _serverPlayers[seat]!['_result'] = 'lose';
          }
        }
      });
      // Run showdown sequence
      _showdownController?.dispose();
      _showdownController = ShowdownSequenceController(vsync: this);
      final activePlayers = winners.map((w) => w['seat'] as int? ?? 0).toList()
        ..addAll(
          losers
              .where((l) => l['folded'] != true)
              .map((l) => l['seat'] as int? ?? 0),
        );
      _showdownController!.runShowdown(
        activePlayers: activePlayers,
        winners: winners,
        losers: losers,
        onPhaseUpdate: (phase, data) {
          if (!mounted) return;
          setState(() {
            _showdownPhase = phase;
            if (phase == ShowdownPhase.cardReveal && data['seat'] != null) {
              _revealedSeats.add(data['seat'] as int);
            }
            if (phase == ShowdownPhase.amountLabels) {
              for (final w in winners) {
                final seat = w['seat'] as int? ?? 0;
                _amountLabels[seat] = (w['amount'] as int?) ?? prize;
              }
              for (final l in losers) {
                final seat = l['seat'] as int? ?? 0;
                final lostAmount = (l['amount'] as int?) ?? 0;
                if (lostAmount > 0) _amountLabels[seat] = -lostAmount;
              }
              // Trigger chip animation: side pots → respective winners
              final screenSize = MediaQuery.of(context).size;
              final safeTop = MediaQuery.of(context).padding.top;
              final tableAreaTop = safeTop + 36.0;
              final tableAreaHeight = screenSize.height - tableAreaTop - 200;
              final potCenter = Offset(
                screenSize.width / 2,
                tableAreaTop + tableAreaHeight * 0.35,
              );

              if (_sidePots.length > 1) {
                // Multiple side pots: split animation then distribute
                final sidePotAmounts = _sidePots
                    .skip(1)
                    .map((p) => toInt(p['amount'] ?? 0))
                    .toList();
                _chipAnimController.splitPot(
                  potCenter: potCenter,
                  mainPotAmount: toInt(_sidePots.first['amount'] ?? 0),
                  sidePotAmounts: sidePotAmounts,
                );

                // Build winner positions map
                final winnerPositions = <int, Offset>{};
                final winnerSeats = winners
                    .map((w) => w['seat'] as int? ?? 0)
                    .toList();
                for (final w in winners) {
                  final seat = w['seat'] as int? ?? 0;
                  if (seat == _mySeat) {
                    winnerPositions[seat] = Offset(
                      screenSize.width / 2,
                      screenSize.height - 120,
                    );
                  } else {
                    final others = _serverPlayers.entries
                        .where((e) => e.key != _mySeat)
                        .toList();
                    final idx = others.indexWhere((e) => e.key == seat);
                    const seatXPercents = [
                      0.02,
                      0.02,
                      0.12,
                      0.70,
                      0.78,
                      0.78,
                      0.68,
                    ];
                    const seatYPercents = [
                      0.62,
                      0.42,
                      0.20,
                      0.20,
                      0.42,
                      0.62,
                      0.78,
                    ];
                    if (idx >= 0 && idx < seatXPercents.length) {
                      winnerPositions[seat] = Offset(
                        seatXPercents[idx] * screenSize.width + 45,
                        seatYPercents[idx] * screenSize.height + 30,
                      );
                    }
                  }
                }

                // Delay side pot distribution after split animation
                Future.delayed(const Duration(milliseconds: 600), () {
                  if (!mounted) return;
                  _chipAnimController.sidePotToWinners(
                    potCenter: potCenter,
                    sidePots: _sidePots,
                    winnerPositions: winnerPositions,
                    winnerSeats: winnerSeats,
                  );
                });
              } else {
                // Single pot: simple pot → winner animation
                for (final w in winners) {
                  final seat = w['seat'] as int? ?? 0;
                  final winAmount = (w['amount'] as int?) ?? prize;
                  _triggerWinChipAnimation(seat, winAmount);
                }
              }
            }
            if (phase == ShowdownPhase.resultPopup) {
              _showdownActive = false;
              _showResult = true;
            }
          });
        },
      );
      // Task 11.3: Play win sound
      if (isWin) {
        AudioManager.instance.play(SoundEffect.coinCascade);
      }
      // Chips are managed by server — don't override with wallet balance
      Future.delayed(
        Duration(seconds: RuntimeConfigService.integer('result_display_sec')),
        () {
          if (mounted && _showResult) {
            setState(() {
              _showResult = false;
              _myCards = [];
              _dealCards = [];
              _showDealAnimation = false;
              _triggerWinCelebration = false;
              _amountLabels = {};
              // Note: _lastDealtCardKey is cleared only when new hand actually starts (isPlaying && _showResult)
              // Clear result flags from server players
              for (final p in _serverPlayers.values) {
                p.remove('_result');
              }
            });
          }
        },
      );
    };
    GameSocket.onError = (m) {
      debugPrint('❌ [NLH] onError: $m');
      if (mounted) {
        // Translate common server errors to Thai
        final thaiMsg = m.contains('Seat is already taken')
            ? 'ที่นั่งนี้มีคนนั่งแล้ว'
            : m.contains('already seated')
            ? 'คุณนั่งอยู่แล้ว'
            : m.contains('Invalid seat')
            ? 'ที่นั่งไม่ถูกต้อง'
            : m.contains('Minimum raise')
            ? 'เก ขั้นต่ำ ${RegExp(r'\d+').firstMatch(m)?.group(0) ?? ''}'
            : m;
        // Show slide-in notification instead of SnackBar
        _errorTimer?.cancel();
        setState(() => _errorMessage = thaiMsg);
        _errorTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _errorMessage = null);
        });
      }
    };
    // Connect socket but don't join yet — wait for seat selection
    final tid = widget.table['id'];
    if (tid != null) {
      // Auto-join seat 1 immediately (no seat selection)
      final buyIn = toInt(
        widget.table['_buyIn'] ?? widget.table['min_buy_in'] ?? 1000,
      );
      debugPrint('🎮 [NLH] Joining table $tid, seat=$_mySeat, buyIn=$buyIn');
      GameSocket.joinTable(
        tid,
        _mySeat,
        buyIn,
        accessToken: widget.table['_roomAccessToken'],
      );
    } else {
      debugPrint('⚠️ [NLH] No table ID found! table=${widget.table}');
    }
  }

  void _onSeatSelected(int seatNumber) {
    final tid = widget.table['id'];
    if (tid == null) return;
    final buyIn = toInt(
      widget.table['_buyIn'] ?? widget.table['min_buy_in'] ?? 1000,
    );
    // If game is in progress, mark as sitting out until next hand
    final gameInProgress = _phase != 'waiting' && _phase != 'result';
    setState(() {
      _mySeat = seatNumber;
      _hasJoined = true;
      if (gameInProgress) _isSittingOut = true;
    });
    GameSocket.joinTable(
      tid,
      seatNumber,
      buyIn,
      accessToken: widget.table['_roomAccessToken'],
    );
  }

  void _showSeatSelectionSheet() {
    final seats = _buildSeatMap();
    final emptySeats = seats.entries
        .where((e) => e.value == null)
        .map((e) => e.key)
        .toList();
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
                    _onSeatSelected(seat);
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

  bool get _isMyTurn => _currentPlayerSeat == _mySeat && _phase != 'waiting';

  // Task 19.1: Slide-left 300ms back to Lobby (Req 11.1–11.5)
  Future<void> _fadeOutAndPop() async {
    if (!mounted) return;

    final isPractice = widget.table['_isPractice'] == true;
    // ──────────────────────────────────────────────
    // กฎการออกห้อง:
    //  1. Practice → ออกได้เสมอ
    //  2. เสียหมด (chips = 0) → ออกได้ทันที
    //  3. เงินต่ำกว่า min_buy_in (ต้องเติม) → ออกได้
    //  4. ยังไม่ได้เริ่มเล่น (ยังไม่ได้แจกไพ่) → ออกได้เลย
    //  5. เล่นแล้ว + ผ่าน 15 นาทีจากมือแรก → ออกได้
    //  6. กำลังแจกไพ่อยู่ (hand in progress) → แจกให้ครบก่อนออก
    // ──────────────────────────────────────────────
    if (!isPractice) {
      final bb = toInt(widget.table['big_blind'] ?? 2);
      final minBuy = toInt(widget.table['min_buy_in'] ?? bb * 40);
      final minDuration = Duration(minutes: _minimumPlayMinutes);
      final handInProgress = _phase != 'waiting' && _phase != 'result';

      // กรณีเสียหมด — ออกได้ทันที
      if (_myChips <= 0) {
        // allow exit
      }
      // กรณีเงินต่ำกว่าจำนวนที่ต้องเติม — ออกได้
      else if (_myChips < minBuy) {
        // allow exit
      }
      // ยังไม่ได้เริ่มเล่น (ไม่เคยได้ไพ่) — ออกได้เลย
      else if (_firstHandPlayedAt == null) {
        // allow exit — player is just spectating/waiting
      }
      // เล่นแล้ว — ยังไม่ครบ 15 นาทีจากมือแรก
      else if (_firstHandPlayedAt != null &&
          DateTime.now().difference(_firstHandPlayedAt!) < minDuration) {
        final remaining =
            minDuration - DateTime.now().difference(_firstHandPlayedAt!);
        final mins = remaining.inMinutes;
        final secs = remaining.inSeconds % 60;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'ต้องอยู่ในห้องอย่างน้อย $_minimumPlayMinutes นาที (เหลือ $mins นาที $secs วินาที)',
              ),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      // ครบ 15 นาทีแล้ว แต่กำลังแจกไพ่อยู่ — รอให้จบมือก่อน
      else if (handInProgress) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Flexible(child: Text('รอให้แจกไพ่ครบก่อน แล้วจะออกห้องได้')),
                ],
              ),
              backgroundColor: Colors.blueGrey.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
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

  double _fadeOutOpacity = 1.0;

  // Task 15.1: FREE TIPS badge tap handler
  void _onFreeTipsTap() {
    if (_tipLoading || _myCards.length < 2) return;
    setState(() => _tipLoading = true);
    try {
      final phase = _phase == 'waiting' || _phase == 'result'
          ? 'preflop'
          : _phase;
      int maxBet = 0;
      _serverPlayers.forEach((s, p) {
        final b = toInt(p['currentBet']);
        if (b > maxBet) maxBet = b;
      });
      final callAmt = maxBet > _currentBet ? maxBet - _currentBet : 0;
      final tip = FreeTipsEngine.analyze(
        holeCards: _myCards,
        communityCards: _communityCards,
        phase: phase,
        potSize: _pot,
        callAmount: callAmt,
      );
      if (mounted) {
        setState(() {
          _tipResult = tip;
          _showTipOverlay = true;
          _tipLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tipResult = null; // error state
          _showTipOverlay = true;
          _tipLoading = false;
        });
      }
    }
  }

  String _formatMoney(int amount) {
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000)
      return '${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}K';
    return amount.toString();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    // Task 11.7: Initialize responsive layout engine from screen width (Req 8.1, 8.7, 9.4, 9.5)
    _layoutEngine = ResponsiveLayoutEngine(MediaQuery.of(context).size.width);
    // Task 6.2: Wrap in AnimatedOpacity for fade-out back navigation
    return AnimatedOpacity(
      opacity: _fadeOutOpacity,
      duration: const Duration(milliseconds: 300),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _fadeOutAndPop();
        },
        child: GestureDetector(
          onTap: () {
            if (_showdownActive && _showdownController != null) {
              _showdownController!.skip();
              setState(() {
                _showdownActive = false;
                _showResult = true;
              });
            }
          },
          child: Scaffold(
            body: Stack(
              children: [
                // Background image — poker room
                Positioned.fill(
                  child: Image.asset(
                    'assets/bg_poker_room.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned.fill(
                  child: Stack(
                    children: [
                      // Main content — uses shared TableSeatLayout for consistent positioning
                      SafeArea(
                        child: Column(
                          children: [
                            SizedBox(height: 36, child: _topBar()),
                            Expanded(child: _buildPokerTableLayout()),
                          ],
                        ),
                      ),
                      if (_showMenu) _menuOv(),
                      // Chip animation overlay
                      Positioned.fill(
                        child: ChipAnimationOverlay(
                          controller: _chipAnimController,
                        ),
                      ),
                      // Action text removed — actions shown on player avatars instead
                      // Confetti on win
                      if (_showConfetti)
                        Positioned.fill(
                          child: ConfettiEffect(
                            onComplete: () {
                              if (mounted)
                                setState(() => _showConfetti = false);
                            },
                          ),
                        ),
                      // Deal animation — use Offstage to keep widget alive and prevent re-creation
                      Positioned.fill(
                        child: _showDealAnimation && _dealCards.isNotEmpty
                            ? DealAnimationOverlay(
                                key: ValueKey('deal_$_lastDealtCardKey'),
                                cards: _dealCards,
                                onComplete: () {
                                  if (mounted)
                                    setState(() => _showDealAnimation = false);
                                },
                              )
                            : const SizedBox.shrink(),
                      ),
                      // Deal-to-players animation — cards fly from dealer to each player
                      if (_showDealToPlayers)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DealToPlayersAnimation(
                              key: ValueKey('dealToPlayers_$_lastDealtCardKey'),
                              playerCount: _serverPlayers.length.clamp(2, 9),
                              cardsPerPlayer: 2,
                              onComplete: () {
                                if (!mounted) return;
                                setState(() => _showDealToPlayers = false);
                                // After deal-to-players finishes, trigger hole cards reveal
                                if (_dealCards.isNotEmpty &&
                                    !_showDealAnimation) {
                                  setState(() => _showDealAnimation = true);
                                }
                              },
                            ),
                          ),
                        ),
                      // Result: show win/loss amounts on table (no popup)
                      // Results shown inline at player avatar positions
                      // Task 11.3: Win celebration effect overlay
                      WinCelebrationEffect(
                        trigger: _triggerWinCelebration,
                        onComplete: () {
                          if (mounted)
                            setState(() => _triggerWinCelebration = false);
                        },
                      ),
                      // Task 15.1: TipOverlay (Req 21.3)
                      if (_showTipOverlay)
                        Positioned.fill(
                          child: TipOverlay(
                            tip: _tipResult,
                            onDismiss: () {
                              if (mounted)
                                setState(() => _showTipOverlay = false);
                            },
                          ),
                        ),
                      // Slide-in error notification from right
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        right: _errorMessage != null ? 12 : -300,
                        top: MediaQuery.of(context).padding.top + 80,
                        child: GestureDetector(
                          onTap: () => setState(() => _errorMessage = null),
                          onHorizontalDragEnd: (_) =>
                              setState(() => _errorMessage = null),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 220),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFCC2222), Color(0xFF8B0000)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.shade300.withOpacity(0.3),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.6),
                                  blurRadius: 12,
                                  offset: const Offset(-2, 4),
                                ),
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.2),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _errorMessage ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
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
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // LANDSCAPE LAYOUT PANELS (like OFC game)
  // ═══════════════════════════════════════════════

  /// All opponents in a horizontal row at the top
  Widget _buildOpponentsRow() {
    final others = _serverPlayers.entries
        .where((e) => e.key != _mySeat)
        .toList();
    if (others.isEmpty) return const SizedBox(height: 8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final entry in others) _compactSeat(entry.value, entry.key),
        ],
      ),
    );
  }

  /// Position opponents around the table (like sitting at a real poker table)
  /// Build the poker table using the shared TableSeatLayout widget.
  /// This ensures consistent player positioning in ALL phases.
  Widget _buildPokerTableLayout() {
    final others = _serverPlayers.entries
        .where((e) => e.key != _mySeat)
        .toList();
    // ALL opponents show cards ABOVE avatar (no exceptions)
    final opponentWidgets = others
        .map((e) => _compactSeat(e.value, e.key, cardsAbove: true))
        .toList();

    // Action bar is OUTSIDE the table layout — full width at bottom
    return Column(
      children: [
        Expanded(
          child: PerspectiveTableLayout(
            opponentWidgets: opponentWidgets,
            myWidget: _myCompactSection(),
            centerWidget: _buildPokerCenter(),
            dealerWidget: null,
            showTableBackground: false,
          ),
        ),
        // Action bar — full width, not constrained by table layout
        _actionBar(),
      ],
    );
  }

  Widget _buildPokerLeftPanel() {
    final others = _serverPlayers.entries
        .where((e) => e.key != _mySeat)
        .toList();
    final half = (others.length / 2).ceil();
    final leftPlayers = others.take(half).toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final entry in leftPlayers) _compactSeat(entry.value, entry.key),
      ],
    );
  }

  Widget _buildPokerRightPanel() {
    final others = _serverPlayers.entries
        .where((e) => e.key != _mySeat)
        .toList();
    final half = (others.length / 2).ceil();
    final rightPlayers = others.skip(half).toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final entry in rightPlayers) _compactSeat(entry.value, entry.key),
      ],
    );
  }

  /// Compact player seat with 3D avatar, time bar, and chip badge
  /// [cardsAbove] = true means cards show above avatar (for side/bottom positions)
  Widget _compactSeat(
    Map<String, dynamic> p,
    int seatNum, {
    bool cardsAbove = true,
  }) {
    final isTurn = _currentPlayerSeat == seatNum;
    final cards = List<String>.from(p['holeCards'] ?? []);
    final isDealer = p['isDealer'] == true || seatNum == _dealerSeat;
    final isSB = p['isSB'] == true || seatNum == _smallBlindSeat;
    final isBB = p['isBB'] == true || seatNum == _bigBlindSeat;
    final lastAction = p['lastAction'] as String? ?? _cachedActions[seatNum];
    final isFolded = p['folded'] == true;
    final amountLabel = _amountLabels[seatNum];
    final currentBet = toInt(p['currentBet']);

    // Build cards widget — larger, more visible
    Widget cardsWidget;
    // Card size — responsive based on screen width
    final screenW = MediaQuery.of(context).size.width;
    final cW = (screenW * 0.09).clamp(28.0, 46.0);
    final cH = cW * 1.4;
    final overlap = cW * 0.5;

    if (isFolded) {
      cardsWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'FOLD',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (cards.isNotEmpty) {
      final shouldAnimate = cards[0] == '??' && _phase == 'preflop';
      cardsWidget = SizedBox(
        width: cW + overlap,
        height: cH,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              child: PlayingCard(
                key: ValueKey('seat${seatNum}_c0_${cards[0]}'),
                card: cards[0],
                faceUp: cards[0] != '??',
                width: cW,
                height: cH,
                animate: shouldAnimate,
                delay: Duration(milliseconds: seatNum * 100),
              ),
            ),
            Positioned(
              left: overlap,
              child: PlayingCard(
                key: ValueKey(
                  'seat${seatNum}_c1_${cards.length > 1 ? cards[1] : "??"}',
                ),
                card: cards.length > 1 ? cards[1] : '??',
                faceUp: cards.length > 1 && cards[1] != '??',
                width: cW,
                height: cH,
                animate: shouldAnimate,
                delay: Duration(milliseconds: seatNum * 100 + 80),
              ),
            ),
          ],
        ),
      );
    } else {
      cardsWidget = SizedBox(
        width: cW + overlap,
        height: cH,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              child: PlayingCard(
                card: '??',
                faceUp: false,
                width: cW,
                height: cH,
              ),
            ),
            Positioned(
              left: overlap,
              child: PlayingCard(
                card: '??',
                faceUp: false,
                width: cW,
                height: cH,
              ),
            ),
          ],
        ),
      );
    }

    // Fixed width — PerspectiveTableLayout handles scaling via Transform.scale
    final seatBoxWidth = (MediaQuery.of(context).size.width * 0.30).clamp(
      100.0,
      140.0,
    );
    final seatBoxHeight = (MediaQuery.of(context).size.height * 0.14).clamp(
      90.0,
      130.0,
    );

    return SizedBox(
      width: seatBoxWidth,
      height: seatBoxHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main content — anchored at bottom of fixed box
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar row: avatar + cards side by side
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Avatar
                    SizedBox(
                      width: (screenW * 0.11).clamp(36.0, 50.0),
                      height: (screenW * 0.11).clamp(36.0, 50.0),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (amountLabel != null && amountLabel > 0)
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFFD700,
                                    ).withOpacity(0.9),
                                    blurRadius: 14,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                          if (isTurn)
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                value:
                                    _turnCountdown /
                                    _turnTotalSeconds.clamp(1, 3600),
                                strokeWidth: 3,
                                backgroundColor: Colors.white.withOpacity(0.1),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _turnCountdown > 5
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                ),
                              ),
                            ),
                          PlayerAvatar3D(
                            size: (screenW * 0.09).clamp(30.0, 42.0),
                            borderColor:
                                (amountLabel != null && amountLabel > 0)
                                ? const Color(0xFFFFD700)
                                : isTurn
                                ? Colors.greenAccent
                                : isFolded
                                ? Colors.grey
                                : const Color(0xFFDAA520),
                            showShadow: !isFolded,
                            imageProvider: seatNum == _mySeat
                                ? ProfileProvider.instance.avatarImage
                                : null,
                          ),
                          if (isDealer || isSB || isBB)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDealer
                                      ? Colors.white
                                      : isSB
                                      ? Colors.blue
                                      : Colors.orange,
                                  border: Border.all(
                                    color: Colors.black,
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    isDealer
                                        ? 'D'
                                        : isSB
                                        ? 'SB'
                                        : 'BB',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 6,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Win/Lose overlay
                          if (_showResult && amountLabel != null)
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: amountLabel > 0
                                    ? const Color(0xFFFFD700).withOpacity(0.85)
                                    : Colors.red.shade900.withOpacity(0.85),
                              ),
                              child: Center(
                                child: Text(
                                  amountLabel > 0 ? 'ชนะ' : 'แพ้',
                                  style: TextStyle(
                                    color: amountLabel > 0
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          if (_showResult && isFolded && amountLabel == null)
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey.shade800.withOpacity(0.85),
                              ),
                              child: const Center(
                                child: Text(
                                  'หมอบ',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 2),
                    // Cards beside avatar
                    cardsWidget,
                  ],
                ),
                const SizedBox(height: 2),
                // Name + Chips box (with bet if any)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name + chips
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: (screenW * 0.22).clamp(70.0, 100.0),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isTurn
                              ? Colors.greenAccent.withOpacity(0.7)
                              : const Color(0xFFDAA520).withOpacity(0.4),
                          width: isTurn ? 1.5 : 0.8,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  seatNum == _mySeat
                                      ? ProfileProvider.instance.displayName
                                      : (p['username'] ?? 'Seat $seatNum'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (p['countryFlag'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 2),
                                  child: Text(
                                    p['countryFlag'] as String,
                                    style: const TextStyle(fontSize: 8),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            'C${NumberFormatter.formatWithCommas(toInt(p['chips']))}',
                            style: const TextStyle(
                              color: Color(0xFFDAA520),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bet chip beside name box
                    if (currentBet > 0) ...[
                      const SizedBox(width: 3),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CustomPaint(painter: _PotChipPainter()),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '$currentBet',
                              style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                // Hand name + Win/Lose amount — combined badge (prominent display)
                if (_showResult && amountLabel != null) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: amountLabel > 0
                          ? Colors.green.shade900
                          : Colors.red.shade900,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: amountLabel > 0
                            ? Colors.greenAccent.withOpacity(0.6)
                            : Colors.red.withOpacity(0.6),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (amountLabel > 0
                                      ? Colors.greenAccent
                                      : Colors.red)
                                  .withOpacity(0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (p['_handName'] != null &&
                            (p['_handName'] as String).isNotEmpty)
                          Text(
                            _translateHandName(p['_handName'] as String),
                            style: TextStyle(
                              color: amountLabel > 0
                                  ? Colors.greenAccent
                                  : const Color(0xFFFFD700),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        Text(
                          '${amountLabel > 0 ? "+" : ""}${NumberFormatter.formatWithCommas(amountLabel)}',
                          style: TextStyle(
                            color: amountLabel > 0
                                ? Colors.white
                                : Colors.red.shade200,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if ((amountLabel != null || _showdownActive) &&
                    p['_handName'] != null &&
                    (p['_handName'] as String).isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: const Color(0xFFDAA520).withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _translateHandName(p['_handName'] as String),
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
                // Cards BELOW avatar removed — cards are now beside avatar
              ],
            ),
          ),
          // Action label — overlay at top, doesn't shift layout
          if (lastAction != null && !isFolded && !_showResult)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _actionColor(lastAction),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _actionLabel(lastAction),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Dealer avatar at top center of table — circular
  Widget _buildDealerAvatar() {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDAA520), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDAA520).withOpacity(0.4),
            blurRadius: 8,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset('assets/dealer_girl.png', fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildPokerCenter() {
    return SizedBox(
      height: 140, // Fixed height — prevents position shift
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Pot chip — fixed just above community cards
          if (_pot > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(child: _buildPotDisplay()),
            ),
          // Community cards — fixed below pot
          if (_communityCards.isNotEmpty)
            Positioned(
              top: 28,
              left: 0,
              right: 0,
              child: Center(child: _buildCommunityCards()),
            ),
          // SB/BB label — fixed position
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'SB/BB: ${toInt(widget.table['small_blind'] ?? 1)}/${toInt(widget.table['big_blind'] ?? 2)} • เกขั้นต่ำ: ${_minRaise > 0 ? _minRaise : toInt(widget.table['big_blind'] ?? 2)}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 9,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPotDisplay() {
    if (_sidePots.length > 1) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < _sidePots.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 20,
                  child: Stack(
                    children: [
                      Positioned(
                        bottom: 0,
                        left: 1,
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CustomPaint(
                            painter: _PotChipPainter(
                              color: i == 0
                                  ? const Color(0xFFCC2222)
                                  : const Color(0xFF1565C0),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        left: 3,
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CustomPaint(
                            painter: _PotChipPainter(
                              color: i == 0
                                  ? const Color(0xFFCC2222)
                                  : const Color(0xFF1565C0),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 4,
                        left: 2,
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CustomPaint(
                            painter: _PotChipPainter(
                              color: i == 0
                                  ? const Color(0xFFCC2222)
                                  : const Color(0xFF1565C0),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'C${NumberFormatter.formatWithCommas(toInt(_sidePots[i]['amount'] ?? 0))}',
                  style: TextStyle(
                    color: i == 0
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF90CAF9),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CustomPaint(painter: _PotChipPainter()),
        ),
        const SizedBox(width: 4),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: _previousPot, end: _pot),
          duration: const Duration(milliseconds: 300),
          builder: (_, value, __) => Text(
            'C${NumberFormatter.formatWithCommas(value)}',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final availableWidth = constraints.maxWidth > 0
            ? constraints.maxWidth * 0.70
            : screenWidth * 0.55;
        final cardCount = _communityCards.length;
        final maxCardWidth =
            ((availableWidth - (cardCount - 1) * 4) / cardCount).clamp(
              26.0,
              40.0,
            );
        final cardHeight = maxCardWidth * 1.4;
        // During result — determine winning cards to highlight
        Set<String> winningCards = {};
        if (_showResult) {
          final winner = _serverPlayers.entries.where(
            (e) => e.value['_result'] == 'win',
          );
          if (winner.isNotEmpty) {
            final holeCards = List<String>.from(
              winner.first.value['holeCards'] ?? [],
            );
            final all7 = [...holeCards, ..._communityCards];
            if (all7.length >= 5) {
              // Find best 5-card combo
              List<String>? bestCombo;
              HandRank? bestRank;
              for (int a = 0; a < all7.length; a++) {
                for (int b = a + 1; b < all7.length; b++) {
                  for (int c = b + 1; c < all7.length; c++) {
                    for (int d = c + 1; d < all7.length; d++) {
                      for (int e = d + 1; e < all7.length; e++) {
                        final combo = [
                          all7[a],
                          all7[b],
                          all7[c],
                          all7[d],
                          all7[e],
                        ];
                        final rank = HandEvaluator.evaluate5(combo);
                        if (bestRank == null ||
                            HandEvaluator.compare(rank, bestRank) > 0) {
                          bestRank = rank;
                          bestCombo = combo;
                        }
                      }
                    }
                  }
                }
              }
              if (bestCombo != null) winningCards = bestCombo.toSet();
            }
          }
        }
        // Always use same perspective transform (same plane as during play)
        final useTransform = true;
        final cardRow = SizedBox(
          width: availableWidth,
          height: cardHeight + 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < cardCount; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Opacity(
                  // Dim cards NOT in winning hand, keep winning cards bright
                  opacity:
                      _showResult &&
                          winningCards.isNotEmpty &&
                          !winningCards.contains(_communityCards[i])
                      ? 0.4
                      : 1.0,
                  child: PlayingCard(
                    key: ValueKey('community_${_communityCards[i]}_$i'),
                    card: _communityCards[i],
                    faceUp: true,
                    width: maxCardWidth,
                    height: cardHeight,
                    animate: !_showResult,
                    delay: Duration(milliseconds: 150 * i),
                  ),
                ),
              ],
            ],
          ),
        );
        if (useTransform) {
          return Transform(
            alignment: Alignment.topCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.003)
              ..rotateX(-0.7),
            child: cardRow,
          );
        }
        return cardRow;
      },
    );
  }

  /// Compact my section — same layout as opponents (avatar + cards + name box)
  Widget _myCompactSection() {
    if (!_hasJoined) return const SizedBox.shrink();
    final isDealer = _mySeat == _dealerSeat;
    final isSB = _mySeat == _smallBlindSeat;
    final isBB = _mySeat == _bigBlindSeat;
    final myPosition = isDealer
        ? 'D'
        : isSB
        ? 'SB'
        : isBB
        ? 'BB'
        : '';
    final amountLabel = _amountLabels[_mySeat];
    final myPlayer = _serverPlayers[_mySeat];
    final myLastAction = myPlayer?['lastAction'] as String?;
    final myFolded = myPlayer?['folded'] == true;

    // My cards widget
    final myCardsWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_myCards.isNotEmpty)
          ...(_myCards.map(
            (c) => PlayingCard(
              card: c,
              faceUp: true,
              width: engine.cardSize.width,
              height: engine.cardSize.height,
            ),
          ))
        else ...[
          PlayingCard(
            card: '??',
            faceUp: false,
            width: engine.cardSize.width,
            height: engine.cardSize.height,
          ),
          PlayingCard(
            card: '??',
            faceUp: false,
            width: engine.cardSize.width,
            height: engine.cardSize.height,
          ),
        ],
      ],
    );

    return SizedBox(
      width: 160,
      height: 120,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main content at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar row: avatar + cards side by side
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Avatar
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (amountLabel != null && amountLabel > 0)
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFFD700,
                                    ).withOpacity(0.9),
                                    blurRadius: 14,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                          if (_isMyTurn)
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                value:
                                    _turnCountdown /
                                    _turnTotalSeconds.clamp(1, 3600),
                                strokeWidth: 3,
                                backgroundColor: Colors.white.withOpacity(0.1),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _turnCountdown > 5
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                ),
                              ),
                            ),
                          PlayerAvatar3D(
                            size: 40,
                            borderColor:
                                (amountLabel != null && amountLabel > 0)
                                ? const Color(0xFFFFD700)
                                : _isMyTurn
                                ? Colors.greenAccent
                                : const Color(0xFFDAA520),
                            showShadow: true,
                            imageProvider: ProfileProvider.instance.avatarImage,
                          ),
                          if (myPosition.isNotEmpty)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDealer
                                      ? Colors.white
                                      : isSB
                                      ? Colors.blue
                                      : Colors.orange,
                                  border: Border.all(
                                    color: Colors.black,
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    myPosition,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 6,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_isMyTurn)
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: _turnCountdown > 5
                                      ? Colors.green.shade800
                                      : Colors.red.shade800,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '$_turnCountdown',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          if (_showResult && amountLabel != null)
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: amountLabel > 0
                                    ? const Color(0xFFFFD700).withOpacity(0.85)
                                    : Colors.red.shade900.withOpacity(0.85),
                              ),
                              child: Center(
                                child: Text(
                                  amountLabel > 0 ? 'ชนะ' : 'แพ้',
                                  style: TextStyle(
                                    color: amountLabel > 0
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 3),
                    // Cards
                    myCardsWidget,
                  ],
                ),
                const SizedBox(height: 2),
                // Hand name
                if (_myCards.isNotEmpty)
                  Text(
                    HandEvaluator.getThaiHandName(_myCards, _communityCards),
                    style: TextStyle(
                      color: const Color(0xFFFFD700).withOpacity(0.8),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                // Name + chips box (with bet)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 100),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _isMyTurn
                              ? Colors.greenAccent.withOpacity(0.7)
                              : const Color(0xFFDAA520).withOpacity(0.4),
                          width: _isMyTurn ? 1.5 : 0.8,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ProfileProvider.instance.displayName.isNotEmpty
                                ? ProfileProvider.instance.displayName
                                : (myPlayer?['username'] ?? 'คุณ'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'C${NumberFormatter.formatWithCommas(_myChips)}',
                            style: const TextStyle(
                              color: Color(0xFFDAA520),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_currentBet > 0) ...[
                      const SizedBox(width: 3),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CustomPaint(painter: _PotChipPainter()),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '$_currentBet',
                              style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Action label overlay above cards
          if (myLastAction != null && !myFolded && !_showResult)
            Positioned(
              top: -18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _actionColor(myLastAction),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _actionLabel(myLastAction),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          // Win amount overlay at top
          if (_showResult && amountLabel != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: amountLabel > 0
                        ? Colors.green.shade900
                        : Colors.red.shade900,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: amountLabel > 0
                          ? Colors.greenAccent.withOpacity(0.6)
                          : Colors.red.withOpacity(0.6),
                    ),
                  ),
                  child: Text(
                    '${amountLabel > 0 ? "+" : ""}${NumberFormatter.formatWithCommas(amountLabel)}',
                    style: TextStyle(
                      color: amountLabel > 0
                          ? Colors.greenAccent
                          : Colors.red.shade200,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Compact action buttons for landscape center
  Widget _buildCompactActions() {
    final bb = toInt(widget.table['big_blind'] ?? 20);
    int maxBet = 0;
    _serverPlayers.forEach((s, p) {
      final b = toInt(p['currentBet']);
      if (b > maxBet) maxBet = b;
    });
    final needCall = maxBet > _currentBet;
    final callAmt = maxBet - _currentBet;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _miniBtn('หมอบ', Colors.red.shade700, () {
              setState(() => _actionText = 'FOLD');
              GameSocket.sendAction('fold');
            }),
            const SizedBox(width: 4),
            if (!needCall)
              _miniBtn('เช็ค', Colors.green.shade700, () {
                setState(() => _actionText = 'CHECK');
                GameSocket.sendAction('check');
              })
            else
              _miniBtn('ตาม $callAmt', Colors.green.shade700, () {
                setState(() => _actionText = 'CALL');
                GameSocket.sendAction('call');
              }),
            const SizedBox(width: 4),
            _miniBtn('เก', Colors.orange.shade700, () {
              setState(() => _actionText = 'RAISE');
              GameSocket.sendAction(
                'raise',
                amount: _minRaise > 0 ? _minRaise : bb * 2,
              );
            }),
          ],
        ),
        // +เวลาคิด 15 วินาที
        if (_thinkTimeBank > 0 && !_usedThinkTimeThisTurn) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _addThinkTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade700,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.blueGrey.shade300.withOpacity(0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color: Colors.white,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '+15วิ ($_thinkTimeBank)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _miniBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Add +15 seconds think time (once per turn, max 3 per session)
  void _addThinkTime() {
    if (_usedThinkTimeThisTurn || _thinkTimeBank <= 0) return;
    setState(() {
      _turnCountdown += 15;
      _usedThinkTimeThisTurn = true;
      _thinkTimeBank--;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '+15วิ (เหลือ $_thinkTimeBank)',
          style: const TextStyle(fontSize: 11),
        ),
        backgroundColor: Colors.blueGrey.shade700,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 80, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── Pre-action methods ──────────────────────────────────────

  /// Set a pre-action to be executed when it becomes our turn.
  void _setPreAction(String action) {
    setState(() {
      if (_preAction == action) {
        // Toggle off if tapping same button again
        _preAction = null;
        _preActionArmed = false;
      } else {
        _preAction = action;
        _preActionArmed = true;
      }
    });
    // Show feedback
    final label = action == 'call_any' ? 'ตามทุกจำนวน' : 'หมอบถ้ามีเดิมพัน';
    if (_preAction != null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ตั้งไว้: $label',
            style: const TextStyle(fontSize: 11),
          ),
          backgroundColor: const Color(0xFFCC4400),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 80, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  /// Cancel any pending pre-action.
  void _cancelPreAction() {
    if (_preActionArmed) {
      setState(() {
        _preAction = null;
        _preActionArmed = false;
      });
    }
  }

  /// Execute the pre-action when it's now our turn.
  void _executePreAction(String action) {
    if (!mounted) return;
    if (_phase == 'waiting' || _phase == 'result') return;

    int maxBet = 0;
    _serverPlayers.forEach((s, p) {
      final b = toInt(p['currentBet']);
      if (b > maxBet) maxBet = b;
    });
    final needCall = maxBet > _currentBet;

    switch (action) {
      case 'call_any':
        // Call any amount — if no bet then check
        if (needCall) {
          setState(() => _actionText = 'CALL');
          GameSocket.sendAction('call');
        } else {
          setState(() => _actionText = 'CHECK');
          GameSocket.sendAction('check');
        }
      case 'check_fold':
        // Check if possible, otherwise fold
        if (!needCall) {
          setState(() => _actionText = 'CHECK');
          GameSocket.sendAction('check');
        } else {
          setState(() => _actionText = 'FOLD');
          GameSocket.sendAction('fold');
        }
    }
  }

  /// Build seat map for SeatSelectionOverlay from server players.
  Map<int, PlayerInfo?> _buildSeatMap() {
    final maxSeats = toInt(widget.table['max_players'] ?? 9);
    final map = <int, PlayerInfo?>{};
    for (int i = 1; i <= maxSeats; i++) {
      final p = _serverPlayers[i];
      if (p != null) {
        map[i] = PlayerInfo(
          id: p['id']?.toString() ?? '',
          username: p['username'] ?? 'Player',
          countryFlag: p['countryFlag'],
          chipCount: toInt(p['chips']),
          avatarUrl: p['avatarUrl'],
        );
      } else {
        map[i] = null;
      }
    }
    return map;
  }

  Widget _topBar() {
    final sb = toInt(widget.table['small_blind'] ?? 1);
    final bb = toInt(widget.table['big_blind'] ?? 2);
    final minBuy = toInt(widget.table['min_buy_in'] ?? bb * 40);
    final maxBuy = toInt(widget.table['max_buy_in'] ?? bb * 100);
    final isTournament = widget.table['_isTournament'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _fadeOutAndPop(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Table name + blinds info / Tournament info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.table['name'] ?? 'POKER',
                style: TextStyle(
                  color: SunTheme.goldLight,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              if (isTournament && _tournamentInfo != null)
                Text(
                  'Level ${_tournamentInfo!['currentBlindLevel'] ?? '?'} • ${_tournamentInfo!['smallBlind'] ?? sb}/${_tournamentInfo!['bigBlind'] ?? bb} • ${_tournamentInfo!['playersRemaining'] ?? '?'}/${_tournamentInfo!['totalPlayers'] ?? '?'} players',
                  style: TextStyle(
                    color: Colors.orangeAccent.withOpacity(0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                Text(
                  'Blinds $sb/$bb • Buy-in $minBuy-$maxBuy',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 9,
                  ),
                ),
            ],
          ),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GameSocket.isConnected ? Colors.greenAccent : Colors.red,
            ),
          ),
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
              'C$_myChips',
              style: TextStyle(
                color: SunTheme.goldLight,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _showMenu = !_showMenu),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.menu, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuOv() => Positioned(
    top: 80,
    right: 16,
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
          _mi(Icons.history, 'ประวัติ', () {
            setState(() => _showMenu = false);
            showDialog(
              context: context,
              builder: (_) =>
                  HandHistoryPopup(tableId: widget.table['id']?.toString()),
            );
          }),
          const Divider(height: 16),
          _mi(Icons.exit_to_app, 'ออกห้อง', () => _fadeOutAndPop()),
        ],
      ),
    ),
  );

  Widget _mi(IconData ic, String l, VoidCallback f) => GestureDetector(
    onTap: f,
    child: Row(
      children: [
        Icon(ic, color: Colors.black87, size: 18),
        const SizedBox(width: 10),
        Text(l, style: const TextStyle(color: Colors.black87, fontSize: 14)),
      ],
    ),
  );

  // Seat positions for portrait layout — symmetrical around oval table
  // Calculated from ellipse with center at (0.5, 0.4), rx=0.42, ry=0.38
  static const _seatPcts8 = [
    [0.08, 0.02], // top-left
    [0.58, 0.02], // top-right
    [0.00, 0.28], // mid-left-upper
    [0.76, 0.28], // mid-right-upper (symmetric with left)
    [0.00, 0.56], // mid-left-lower
    [0.76, 0.56], // mid-right-lower (symmetric with left)
    [0.08, 0.78], // bottom-left
    [0.58, 0.78], // bottom-right
  ];

  static const _seatPcts6 = [
    [0.34, 0.00], // top-center
    [0.00, 0.22], // mid-left-upper
    [0.72, 0.22], // mid-right-upper (symmetric)
    [0.00, 0.55], // mid-left-lower
    [0.72, 0.55], // mid-right-lower (symmetric)
    [0.34, 0.78], // bottom-center
  ];

  List<List<double>> get _seatPcts {
    final maxSeats = toInt(widget.table['max_players'] ?? 9);
    return maxSeats <= 6 ? _seatPcts6 : _seatPcts8;
  }

  Widget _gameArea() {
    final maxSeats = toInt(widget.table['max_players'] ?? 9);
    return LayoutBuilder(
      builder: (ctx, box) {
        final w = box.maxWidth, h = box.maxHeight;
        if (w == 0 || h == 0) return const SizedBox();

        // Task 11.1: Build seat widgets using SeatRotationMap
        final seatWidgets = <Widget>[];
        final seatCount = _seatPcts.length;
        final bottomIdx = seatCount <= 6 ? seatCount - 1 : 6;
        for (int visualIdx = 0; visualIdx < seatCount; visualIdx++) {
          final serverSeat = _mySeat > 0
              ? SeatRotationMap.toServerSeat(
                  mySeat: _mySeat,
                  visualIndex: visualIdx,
                  maxSeats: maxSeats > seatCount ? seatCount : maxSeats,
                  bottomCenterIndex: bottomIdx,
                )
              : visualIdx + 1;
          final player = _serverPlayers[serverSeat];
          final isAllIn = _allInSeats.contains(serverSeat);

          Widget seatWidget;
          if (player != null && serverSeat != _mySeat) {
            seatWidget = _seatW(player, serverSeat);
            if (isAllIn) {
              seatWidget = AllInEffect(trigger: true, child: seatWidget);
            }
          } else if (player != null && serverSeat == _mySeat) {
            continue; // My seat shown in bottom section
          } else {
            if (_hasJoined) continue; // Hide empty seats when playing
            seatWidget = _emptyW();
          }

          seatWidgets.add(
            Positioned(
              key: _getSeatKey(serverSeat),
              left: (w * _seatPcts[visualIdx][0]).clamp(0.0, w - 84),
              top: (h * _seatPcts[visualIdx][1]).clamp(0.0, h - 90),
              child: seatWidget,
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Community cards + pot
            Positioned(
              left: 4,
              right: 4,
              top: h * 0.40,
              child: SizedBox(
                height: 60,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < _communityCards.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: PlayingCard(
                            card: _communityCards[i],
                            faceUp: true,
                            width: engine.communityCardSize.width,
                            height: engine.communityCardSize.height,
                            animate: true,
                            delay: Duration(milliseconds: 200 * i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_pot > 0)
              Positioned(
                left: 0,
                right: 0,
                top: h * 0.40 + 64,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF2A0A0A),
                          Color(0xFF1A0505),
                          Color(0xFF2A0A0A),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFDAA520).withOpacity(0.4),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                        BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.1),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Chip stack icon
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Stack(
                            children: [
                              Positioned(
                                bottom: 0,
                                left: 2,
                                child: Container(
                                  width: 20,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFB8860B),
                                        Color(0xFF8B6914),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFFFF8DC),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 5,
                                left: 2,
                                child: Container(
                                  width: 20,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFDAA520),
                                        Color(0xFFB8860B),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFFFF8DC),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 10,
                                left: 2,
                                child: Container(
                                  width: 20,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFFD700),
                                        Color(0xFFDAA520),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFFFF8DC),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        TweenAnimationBuilder<int>(
                          tween: IntTween(begin: _previousPot, end: _pot),
                          duration: const Duration(milliseconds: 300),
                          builder: (_, value, __) => Text(
                            NumberFormatter.formatWithCommas(value),
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Task 11.2: RakeDisplay near pot during result phase
            if (_phase == 'result' && _rakeAmount > 0)
              Positioned(
                left: 0,
                right: 0,
                top: h * 0.40 + 84,
                child: Center(
                  child: RakeDisplay(
                    rakeAmount: _rakeAmount,
                    rakePercent: _rakePercent,
                    rakeCap: _rakeCap,
                  ),
                ),
              ),
            // Task 11.1: Seat widgets with rotation applied
            ...seatWidgets,
            // Turn indicator
            if (_currentPlayerSeat != null && _phase != 'waiting')
              Positioned(
                left: 0,
                right: 0,
                top: h * 0.35,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _isMyTurn
                          ? Colors.amber
                          : Colors.amber.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isMyTurn
                          ? 'YOUR TURN'
                          : '${_serverPlayers[_currentPlayerSeat]?['username'] ?? 'Opponent'} กำลังคิด...',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _seatW(Map<String, dynamic> p, int seatNum) {
    final isTurn = _currentPlayerSeat == seatNum;
    final cards = List<String>.from(p['holeCards'] ?? ['??', '??']);
    // Task 11.1: Dealer/SB/BB use server seat numbers (rotation handled at layout level)
    final isDealer = p['isDealer'] == true || seatNum == _dealerSeat;
    final isSB = p['isSB'] == true || seatNum == _smallBlindSeat;
    final isBB = p['isBB'] == true || seatNum == _bigBlindSeat;
    final countryFlag = p['countryFlag'] as String?;
    final avatarUrl = p['avatarUrl'] as String?;

    // Use ProfileProvider avatar for my own seat
    final isMyAvatar = seatNum == _mySeat;
    ImageProvider? myAvatarImage;
    if (isMyAvatar) {
      myAvatarImage = ProfileProvider.instance.avatarImage;
    }

    // Task 10.2: Wrap avatar with TurnIndicator (Req 6.1, 6.2)
    Widget avatarWidget = Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isTurn ? Colors.greenAccent : SunTheme.goldLight,
          width: isTurn ? 3 : 2,
        ),
        boxShadow: isTurn
            ? [
                BoxShadow(
                  color: Colors.greenAccent.withOpacity(0.6),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ]
            : null,
        image: isMyAvatar && myAvatarImage != null
            ? DecorationImage(image: myAvatarImage, fit: BoxFit.cover)
            : (avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl),
                      fit: BoxFit.cover,
                    )
                  : const DecorationImage(
                      image: AssetImage('assets/logo.png'),
                      fit: BoxFit.cover,
                    )),
      ),
    );

    if (isTurn) {
      avatarWidget = TurnIndicator(
        isActive: true,
        totalSeconds: _turnTotalSeconds,
        remainingSeconds:
            _turnCountdown, // Wired from game state when available
        isBetPending:
            toInt(p['currentBet']) <
            (_serverPlayers.values.fold<int>(0, (max, pl) {
              final b = toInt(pl['currentBet']);
              return b > max ? b : max;
            })),
        onTimeout: () {
          // Task 15.3: Auto-action via TimerLogic (Req 22.8, 22.9)
          final maxBetInRound = _serverPlayers.values.fold<int>(0, (max, pl) {
            final b = toInt(pl['currentBet']);
            return b > max ? b : max;
          });
          final betPending = toInt(p['currentBet']) < maxBetInRound;
          final autoAction = TimerLogic.getAutoAction(isBetPending: betPending);
          GameSocket.sendAction(autoAction);
        },
        child: avatarWidget,
      );
    }

    return SizedBox(
      width: 120,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Action label on top — BIGGER
          if (p['lastAction'] != null && p['folded'] != true)
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _actionColor(p['lastAction']),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: _actionColor(p['lastAction']).withOpacity(0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                _actionLabel(p['lastAction']),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          // Position indicators
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDealer)
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: DealerButton(size: 18),
                ),
              if (isSB)
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: BlindIndicator(label: 'SB'),
                ),
              if (isBB) const BlindIndicator(label: 'BB'),
            ],
          ),
          const SizedBox(height: 2),
          avatarWidget,
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isTurn
                    ? Colors.greenAccent.withOpacity(0.7)
                    : const Color(0xFFDAA520).withOpacity(0.4),
                width: isTurn ? 1.5 : 0.8,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (countryFlag != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Text(
                          countryFlag,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        isMyAvatar
                            ? ProfileProvider.instance.displayName
                            : (p['username'] ?? 'Seat $seatNum'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  'C${NumberFormatter.formatWithCommas(toInt(p['chips']))}',
                  style: TextStyle(
                    color: SunTheme.goldLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (toInt(p['currentBet']) > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.orangeAccent.withOpacity(0.4),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                            ),
                            border: Border.all(
                              color: const Color(0xFFFFF8DC),
                              width: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${NumberFormatter.formatWithCommas(toInt(p['currentBet']))}',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Cards below info
          if (p['folded'] == true && (cards.isEmpty || cards[0] == '??'))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.shade900,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'FOLD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else if (cards.isNotEmpty && cards[0] != '??')
            // Show actual card faces — overlapping
            SizedBox(
              width: engine.cardSize.width * 0.5 + 10,
              height: engine.cardSize.height * 0.5,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    child: PlayingCard(
                      card: cards[0],
                      faceUp: true,
                      width: engine.cardSize.width * 0.5,
                      height: engine.cardSize.height * 0.5,
                    ),
                  ),
                  Positioned(
                    left: 10,
                    child: PlayingCard(
                      card: cards.length > 1 ? cards[1] : '??',
                      faceUp: cards.length > 1 && cards[1] != '??',
                      width: engine.cardSize.width * 0.5,
                      height: engine.cardSize.height * 0.5,
                    ),
                  ),
                ],
              ),
            )
          else
            // Face-down cards — overlapping
            SizedBox(
              width: engine.opponentCardSize.width + 8,
              height: engine.opponentCardSize.height,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    child: PlayingCard(
                      card: '??',
                      faceUp: false,
                      width: engine.opponentCardSize.width,
                      height: engine.opponentCardSize.height,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    child: PlayingCard(
                      card: '??',
                      faceUp: false,
                      width: engine.opponentCardSize.width,
                      height: engine.opponentCardSize.height,
                    ),
                  ),
                ],
              ),
            ),
          // Win/loss amount label + WIN/LOSE text — BIGGER
          if (_amountLabels.containsKey(seatNum)) ...[
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _amountLabels[seatNum]! > 0
                    ? Colors.green.shade800
                    : Colors.red.shade800,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color:
                        (_amountLabels[seatNum]! > 0
                                ? Colors.green
                                : Colors.red)
                            .withOpacity(0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Text(
                _amountLabels[seatNum]! > 0 ? 'WIN' : 'LOSE',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _amountLabels[seatNum]! > 0
                    ? Colors.green.withOpacity(0.85)
                    : Colors.red.withOpacity(0.85),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color:
                        (_amountLabels[seatNum]! > 0
                                ? Colors.green
                                : Colors.red)
                            .withOpacity(0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                '${_amountLabels[seatNum]! > 0 ? '+' : ''}${_amountLabels[seatNum]}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            // Hand name (e.g. "สองคู่", "ฟลัช")
            if (p['_handName'] != null && (p['_handName'] as String).isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  _translateHandName(p['_handName']),
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _emptyW() => SizedBox(
    width: 78,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black26,
            border: Border.all(color: Colors.white24),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Empty',
          style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8),
        ),
      ],
    ),
  );

  // Card label: show rank + suit as colored text
  Widget _cardLabel(String card) {
    if (card.length < 2) return const SizedBox();
    final rank = card.substring(0, card.length - 1);
    final suit = card[card.length - 1];
    const suitSymbols = {'h': '♥', 'd': '♦', 'c': '♣', 's': '♠'};
    final isRed = suit == 'h' || suit == 'd';
    final displayRank = rank == 'T' ? '10' : rank;
    return Text(
      '$displayRank${suitSymbols[suit] ?? ''}',
      style: TextStyle(
        color: isRed ? Colors.red.shade700 : Colors.black87,
        fontSize: 13,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  String _actionLabel(String? action) {
    switch (action) {
      case 'fold':
        return 'หมอบ';
      case 'call':
        return 'ตาม';
      case 'raise':
        return 'เก';
      case 'check':
        return 'เช็ค';
      case 'all_in':
        return 'ALL-IN';
      case 'blind':
        return 'บลายด์';
      default:
        return '';
    }
  }

  String _translateHandName(String? name) {
    if (name == null) return '';
    const map = {
      'Royal Flush': 'รอยัลฟลัช',
      'Straight Flush': 'สเตรทฟลัช',
      'Four of a Kind': 'โฟร์ออฟอะไคนด์',
      'Full House': 'ฟูลเฮาส์',
      'Flush': 'ฟลัช',
      'Straight': 'สเตรท',
      'Three of a Kind': 'ทริปส์',
      'Two Pair': 'สองคู่',
      'One Pair': 'คู่',
      'High Card': 'ไฮการ์ด',
    };
    return map[name] ?? name;
  }

  Color _actionColor(String? action) {
    switch (action) {
      case 'fold':
        return Colors.red.shade800;
      case 'call':
        return Colors.blue.shade700;
      case 'raise':
        return Colors.orange.shade800;
      case 'check':
        return Colors.green.shade700;
      case 'all_in':
        return Colors.purple.shade700;
      case 'blind':
        return Colors.grey.shade700;
      default:
        return Colors.grey.shade800;
    }
  }

  Widget _mySection() {
    if (!_hasJoined) return const SizedBox(height: 0);
    final myPlayer = _serverPlayers[_mySeat];
    final myLastAction = myPlayer?['lastAction'] as String?;
    final myAmountLabel = _amountLabels[_mySeat];
    final myResult = myPlayer?['_result'] as String?; // 'win' or 'lose'
    final myHandName = myPlayer?['_handName'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF0A0000).withOpacity(0.9),
            const Color(0xFF0A0000),
          ],
        ),
      ),
      child: Row(
        children: [
          // Avatar with green glow when my turn
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // WIN/LOSE label during result
              if (_showResult && myAmountLabel != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: myAmountLabel > 0
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: (myAmountLabel > 0 ? Colors.green : Colors.red)
                            .withOpacity(0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Text(
                    myAmountLabel > 0
                        ? 'WIN +$myAmountLabel'
                        : 'LOSE $myAmountLabel',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (myHandName != null && myHandName.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFFFFD700).withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      _translateHandName(myHandName),
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _showResult && myAmountLabel != null
                        ? (myAmountLabel > 0
                              ? Colors.greenAccent
                              : Colors.redAccent)
                        : _isMyTurn
                        ? Colors.greenAccent
                        : SunTheme.goldLight,
                    width: _isMyTurn || (_showResult && myAmountLabel != null)
                        ? 3
                        : 2,
                  ),
                  boxShadow: _isMyTurn
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent.withOpacity(0.6),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.green.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ]
                      : _showResult &&
                            myAmountLabel != null &&
                            myAmountLabel > 0
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent.withOpacity(0.6),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
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
              // Action label overlay on my avatar
              if (myLastAction != null && !_showResult)
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _actionColor(myLastAction).withOpacity(0.8),
                  ),
                  child: Center(
                    child: Text(
                      _actionLabel(myLastAction),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              // Win/Lose overlay on my avatar during result
              if (_showResult && myAmountLabel != null)
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: myAmountLabel > 0
                        ? const Color(0xFFFFD700).withOpacity(0.85)
                        : Colors.red.shade900.withOpacity(0.85),
                  ),
                  child: Center(
                    child: Text(
                      myAmountLabel > 0 ? 'ชนะ' : 'แพ้',
                      style: TextStyle(
                        color: myAmountLabel > 0 ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'YOU',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_isMyTurn) ...[
                    const SizedBox(width: 6),
                    // Countdown timer
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.greenAccent.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        '⏱ ${_turnCountdown}s',
                        style: TextStyle(
                          color: _turnCountdown <= 5
                              ? Colors.redAccent
                              : Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                'C$_myChips',
                style: TextStyle(
                  color: SunTheme.goldLight,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_spectatorState != SpectatorState.notSpectating)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ThaiLabels.waitForBB,
                    style: const TextStyle(color: Colors.amber, fontSize: 8),
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (_myCards.isNotEmpty) ...[
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < _myCards.length; i++)
                        PlayingCard(
                          card: _myCards[i],
                          faceUp: true,
                          width: engine.cardSize.width,
                          height: engine.cardSize.height,
                        ),
                    ],
                  ),
                  // Task 15.1: Hand_Label below hole cards (Req 14.4)
                  const SizedBox(height: 2),
                  Text(
                    HandEvaluator.getThaiHandName(_myCards, _communityCards),
                    style: TextStyle(
                      color: SunTheme.goldLight.withOpacity(0.8),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_myCards.isEmpty) ...[
            PlayingCard(
              card: '??',
              faceUp: false,
              width: engine.cardSize.width,
              height: engine.cardSize.height,
            ),
            PlayingCard(
              card: '??',
              faceUp: false,
              width: engine.cardSize.width,
              height: engine.cardSize.height,
            ),
          ],
          const Spacer(),
          if (_currentBet > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFCC1111), Color(0xFF8B0000)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B0000).withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'BET C$_currentBet',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Compact action bar for landscape mode — vertical buttons
  Widget _actionBarCompact() {
    if (!_hasJoined || !_isMyTurn) return const SizedBox.shrink();
    final bb = toInt(widget.table['big_blind'] ?? 20);
    final callAmount =
        _serverPlayers.values.fold<int>(0, (max, p) {
          final b = toInt(p['currentBet']);
          return b > max ? b : max;
        }) -
        _currentBet;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _compactBtn('หมอบ', Colors.red.shade700, () {
            setState(() => _actionText = 'FOLD');
            GameSocket.sendAction('fold');
          }),
          const SizedBox(height: 4),
          if (callAmount <= 0)
            _compactBtn('เช็ค', Colors.blue.shade700, () {
              setState(() => _actionText = 'CHECK');
              GameSocket.sendAction('check');
            })
          else
            _compactBtn('ตาม $callAmount', Colors.green.shade700, () {
              setState(() => _actionText = 'CALL');
              GameSocket.sendAction('call');
            }),
          const SizedBox(height: 4),
          _compactBtn('เก ${bb * 2}', Colors.amber.shade700, () {
            setState(() => _actionText = 'RAISE');
            GameSocket.sendAction('raise', amount: bb * 2);
          }),
          // +เวลาคิด 15 วินาที
          if (_thinkTimeBank > 0 && !_usedThinkTimeThisTurn) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _addThinkTime,
              child: Container(
                width: 80,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade700,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.blueGrey.shade300.withOpacity(0.4),
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '+15วิ ($_thinkTimeBank)',
                        style: const TextStyle(
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
          ],
        ],
      ),
    );
  }

  Widget _compactBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionBar() {
    // Not joined yet — don't show action bar (seat selection button is in the stack)
    if (!_hasJoined) return const SizedBox(height: 0);

    final bb = toInt(widget.table['big_blind'] ?? 20);
    final isPractice = widget.table['_isPractice'] == true;

    // Out of chips — show message
    if (_myChips <= 0 && _phase != 'result' && !_showResult) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              const Color(0xFF0A0000).withOpacity(0.95),
              const Color(0xFF0A0000),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.red.shade300.withOpacity(0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.money_off, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'ชิปหมด — เล่นไม่ได้',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFCC8800), Color(0xFF8B6000)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isPractice ? 'กลับเลือกห้อง' : 'ออกจากห้อง',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Spectator mode: show SpectatorStatusBar
    if (_spectatorState != SpectatorState.notSpectating) {
      return SpectatorStatusBar(
        bigBlindAmount: bb,
        playerChips: _myChips,
        handInProgress: _phase != 'waiting' && _phase != 'result',
        onPostBehind: () {
          GameSocket.sendAction('post_behind', amount: bb);
          setState(() => _spectatorState = SpectatorState.notSpectating);
        },
      );
    }

    // Game in progress but sitting out — waiting for next hand
    final gameActive = _phase != 'waiting' && _phase != 'result';
    if (_isSittingOut && gameActive) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              const Color(0xFF0A0000).withOpacity(0.95),
              const Color(0xFF0A0000),
            ],
          ),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.amber,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'รอรอบถัดไป...',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_phase == 'waiting') {
      final canStart = _serverPlayers.length >= 2;
      final isPractice = widget.table['_isPractice'] == true;

      // Practice tables: auto-start, show waiting message
      if (isPractice) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                const Color(0xFF0A0000).withOpacity(0.95),
                const Color(0xFF0A0000),
              ],
            ),
          ),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.greenAccent,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'กำลังเริ่มเกม...',
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
        );
      }

      return Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              const Color(0xFF0A0000).withOpacity(0.95),
              const Color(0xFF0A0000),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status text
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
                      color: canStart
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      boxShadow: [
                        BoxShadow(
                          color:
                              (canStart
                                      ? Colors.greenAccent
                                      : Colors.orangeAccent)
                                  .withOpacity(0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    canStart
                        ? '${_serverPlayers.length + (_hasJoined && !_serverPlayers.containsKey(_mySeat) ? 1 : 0)} ผู้เล่นพร้อม — กดเริ่มเล่น'
                        : 'รอผู้เล่น... (${_serverPlayers.length + (_hasJoined && !_serverPlayers.containsKey(_mySeat) ? 1 : 0)}/2)',
                    style: TextStyle(
                      color: SunTheme.gold.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 3D START button
            GestureDetector(
              onTap: canStart ? () => GameSocket.startGame() : null,
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
                          BoxShadow(
                            color: const Color(0xFF4ADE80).withOpacity(0.15),
                            blurRadius: 20,
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
                    // Bottom inset shadow
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(13),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.3),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Icon + Text
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
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 6,
                                      ),
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
        ),
      );
    }
    if (_phase == 'result' && !_isMyTurn) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              const Color(0xFF0A0000).withOpacity(0.95),
            ],
          ),
        ),
        child: Center(
          child: Text(
            'มือถัดไปกำลังจะเริ่ม...',
            style: TextStyle(
              color: SunTheme.gold.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    int maxBet = 0;
    _serverPlayers.forEach((s, p) {
      final b = toInt(p['currentBet']);
      if (b > maxBet) maxBet = b;
    });
    final needCall = maxBet > _currentBet;
    final callAmt = maxBet - _currentBet;

    // Update game guide on turn
    if (_isMyTurn && _guideEnabled && _myCards.length >= 2) {
      _updateGameGuide();
    }

    // Task 15.2: Use BettingPanel with Thai labels and presets
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Game guide badge
        if (_guideEnabled && _guideCategory != null && _isMyTurn)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RecommendationBadge(
              category: _guideCategory!,
              explanationTh: _guideExplanation,
            ),
          ),
        // +เวลาคิด 15 วินาที — แสดงเฉพาะตอนเป็นตาของเรา
        if (_isMyTurn && _thinkTimeBank > 0 && !_usedThinkTimeThisTurn)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _addThinkTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade800,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blueGrey.shade400.withOpacity(0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '+15',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        BettingPanel(
          currentPot: _pot,
          playerChips: _myChips,
          minRaise:
              (_minRaise > 0 ? _minRaise : bb) +
              callAmt, // total = call + raise
          maxRaise: _myChips,
          callAmount: callAmt,
          isMyTurn: _isMyTurn,
          needCall: needCall,
          phase: _phase,
          bigBlind: bb,
          isAnimationBlocking:
              areActionsBlocked, // Task 3.4: Block during animation (Req 2.4)
          preAction: _preAction,
          onSetPreAction: (action) => _setPreAction(action),
          onAction: (action, {int amount = 0}) {
            // Guard: only send action if it's actually my turn
            if (!_isMyTurn) return;

            // Cancel any pending pre-action when player acts manually
            _cancelPreAction();

            // Task 3.4: Guard — reject betting actions while animation is playing (Req 2.4)
            if (!tryExecuteAction(action, () {})) return;

            // Show action text pop
            final label = action == 'fold'
                ? 'FOLD'
                : action == 'call'
                ? 'CALL'
                : action == 'check'
                ? 'CHECK'
                : action == 'all_in'
                ? 'ALL IN'
                : action == 'raise'
                ? 'RAISE ${amount > 0 ? amount : ""}'
                : action.toUpperCase();
            setState(() => _actionText = label);

            if (amount > 0) {
              GameSocket.sendAction(action, amount: amount);
            } else {
              GameSocket.sendAction(action);
            }
          },
        ),
      ],
    );
  }

  void _updateGameGuide() {
    if (_myCards.length < 2) return;
    final phase = _phase == 'waiting' || _phase == 'result'
        ? 'preflop'
        : _phase;
    int maxBet = 0;
    _serverPlayers.forEach((s, p) {
      final b = toInt(p['currentBet']);
      if (b > maxBet) maxBet = b;
    });
    final callAmt = maxBet > _currentBet ? maxBet - _currentBet : 0;
    final tip = FreeTipsEngine.analyze(
      holeCards: _myCards,
      communityCards: _communityCards,
      phase: phase,
      potSize: _pot,
      callAmount: callAmt,
    );
    final cat = FreeTipsEngine.classifyStrength(tip.confidence);
    _guideCategory = cat;
    _guideExplanation = FreeTipsEngine.getExplanationTh(cat);
  }
}

// ═══════════════════════════════════════════════════════════
// Table Painter
// ═══════════════════════════════════════════════════════════

/// Pot chip stack — uses the same casino chip design as the flying chips
class _PotChipPainter extends CustomPainter {
  final Color color;
  _PotChipPainter({this.color = const Color(0xFFCC2222)});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 2;

    // Single casino chip
    // Shadow
    canvas.drawCircle(
      Offset(cx, cy + 2),
      r,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Main chip body
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [color.withOpacity(0.9), color, color.withOpacity(0.7)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );

    // Outer ring
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withOpacity(0.8),
    );

    // Inner ring
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withOpacity(0.5),
    );

    // 8 edge dashes
    for (int i = 0; i < 8; i++) {
      final angle = i * 3.14159 * 2 / 8;
      final innerR = r * 0.82;
      final outerR = r * 0.98;
      canvas.drawLine(
        Offset(cx + innerR * cos(angle), cy + innerR * sin(angle)),
        Offset(cx + outerR * cos(angle), cy + outerR * sin(angle)),
        Paint()
          ..color = Colors.white.withOpacity(0.9)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Highlight
    canvas.drawCircle(
      Offset(cx - r * 0.2, cy - r * 0.2),
      r * 0.25,
      Paint()
        ..shader =
            RadialGradient(
              colors: [Colors.white.withOpacity(0.3), Colors.transparent],
            ).createShader(
              Rect.fromCircle(
                center: Offset(cx - r * 0.2, cy - r * 0.2),
                radius: r * 0.25,
              ),
            ),
    );

    // Center "C"
    final tp = TextPainter(
      text: TextSpan(
        text: 'C',
        style: TextStyle(
          color: Colors.white,
          fontSize: r * 0.8,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PotChipPainter oldDelegate) =>
      oldDelegate.color != color;
}
