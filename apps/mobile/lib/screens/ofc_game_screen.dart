import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/game_socket.dart';
import '../services/audio_manager.dart';
import '../services/runtime_config_service.dart';
import '../utils/number_formatter.dart';
import '../utils/hand_evaluator.dart';
import '../utils/ofc_scorer.dart';
import '../utils/ofc_auto_arrange.dart';
import '../utils/thai_labels.dart';
import '../widgets/playing_card.dart';
import '../widgets/chip_animation.dart';
import '../widgets/deal_to_players_animation.dart';
import '../widgets/game_effects.dart';
import '../widgets/table_seat_layout.dart';
import '../widgets/player_avatar_3d.dart';
import '../widgets/app_background.dart';
import 'lobby_screen.dart';

// Card sizes for OFC game
const double _kCardWidth = 52;
const double _kCardHeight = 74;
const double _kHandCardWidth = 48;
const double _kHandCardHeight = 68;

/// OFC Game Screen — Full landscape layout
/// Designed to match reference images: players around edges, cards center, timer top-right
class OFCGameScreen extends StatefulWidget {
  final Map<String, dynamic> table;
  const OFCGameScreen({super.key, required this.table});
  @override
  State<OFCGameScreen> createState() => _OFCGameScreenState();
}

class _OFCGameScreenState extends State<OFCGameScreen>
    with TickerProviderStateMixin {
  // Game state
  String _phase = 'waiting';
  int _currentRound = 1;
  List<String> _hand = [];
  List<String> _front = [];
  List<String> _middle = [];
  List<String> _back = [];
  int _myChips = 0;
  late int _mySeat;
  bool _hasJoined = true; // Join immediately
  bool _isSpectating = false;
  bool _waitingForNextRound = true; // True until first state received
  bool _gameInProgress = false; // True if entered while game was playing
  Map<int, Map<String, dynamic>> _players = {};
  int _turnSeconds = 60;
  bool _showResult = false;
  List<dynamic> _resultData = [];
  Map<int, int> _coinChanges = {};
  final ChipAnimationController _chipAnim = ChipAnimationController();
  bool _showConfetti = false;

  // Showdown animation — reveal cards row by row
  int _showdownStep = 0; // 0=none, 1=back, 2=middle, 3=front, 4=scores
  bool _showdownActive = false;
  bool _showResultPopup = false; // Full-screen popup during showdown/result
  Map<int, String> _rowResultLabels =
      {}; // seat -> current row result label ("+1", "-1")
  bool _showStartBanner = false; // "เริ่ม!" banner
  bool _showVsBanner = false; // "VS" banner before showdown
  bool _showDragonBanner = false; // "🐉 มังกร!" banner for Dragon
  bool _chipAnimationInProgress = false; // Block next round until chips finish
  bool _waitingBeforeShowdown =
      false; // 5s pause showing "all ready" before showdown
  Map<String, dynamic>? _pendingState; // State received during chip animation
  bool _showTableResult =
      false; // After popup closes, show small cards on table

  // Track the original dealt cards to prevent mismatch from duplicate table states
  List<String> _originalDealtCards = [];
  bool _myReady = false; // Track if we've confirmed arrangement

  // Recommendation
  Map<String, List<String>>? _recommendation;
  String _activeRow = 'back';

  // Deal animation
  bool _isDealingAnimation = false;
  bool _showDealToPlayers = false; // Cards fly from dealer to all players
  List<String> _pendingDealCards = [];
  List<String> _dealtCards = [];

  // Shuffle animation
  bool _isShuffling = false;
  late AnimationController _shuffleController;
  late Animation<double> _shuffleAnim;

  // Local countdown timer
  late final _countdownTimer = Stream.periodic(const Duration(seconds: 1));
  StreamSubscription? _countdownSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _mySeat = 1;
    _myChips = toInt(widget.table['_buyIn'] ?? 10000);
    _hasJoined = false;
    _isSpectating = true;
    _waitingForNextRound = true; // Will check first state to decide

    // Shuffle animation controller
    _shuffleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _shuffleAnim = CurvedAnimation(
      parent: _shuffleController,
      curve: Curves.easeInOut,
    );

    // Start local countdown timer
    _countdownSub = _countdownTimer.listen((_) {
      if (!mounted) return;
      if (_isArranging &&
          _turnSeconds > 0 &&
          !_isDealingAnimation &&
          !_isShuffling &&
          !_showDealToPlayers) {
        setState(() => _turnSeconds--);
        // Auto-confirm when timer reaches 0
        if (_turnSeconds <= 0 && !_myReady && _canConfirm) {
          debugPrint('⏰ [OFC] Timer expired — auto-confirming arrangement');
          _doConfirmArrangement();
        }
      }
    });

    _connectSocket();
  }

  @override
  void dispose() {
    _countdownSub?.cancel();
    _shuffleController.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    GameSocket.disconnect();
    super.dispose();
  }

  void _connectSocket() {
    debugPrint(
      '🎮 [OFC] _connectSocket() called, tableId=${widget.table['id']}',
    );
    // Disconnect any existing connection first to prevent dual-table states
    GameSocket.disconnect();
    GameSocket.connectChinese(
      onState: (state) {
        if (!mounted) return;
        final serverPhase = state['phase'] ?? 'waiting';
        final round = state['currentRound'] ?? _currentRound;
        final turnSec = state['turnRemainingSeconds'] ?? 60;
        final rawPlayers = state['players'] as Map<String, dynamic>? ?? {};

        // Filter: during arranging phase, only accept state that contains our hand
        // (server sends both generic state and personalized state)
        if (serverPhase == 'arranging' && _originalDealtCards.isNotEmpty) {
          final myData = rawPlayers['$_mySeat'] as Map<String, dynamic>?;
          // Check if player was kicked (not in players list anymore)
          if (myData == null && _hasJoined && rawPlayers.isNotEmpty) {
            debugPrint(
              '🚫 [OFC] Player not in game anymore — busted or kicked',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('ชิปหมด — ออกจากห้อง'),
                  backgroundColor: Colors.red,
                ),
              );
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  SystemChrome.setPreferredOrientations([
                    DeviceOrientation.portraitUp,
                  ]);
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LobbyScreen()),
                  );
                }
              });
            }
            return;
          }
          final serverHand = List<String>.from(myData?['hand'] ?? []);
          if (serverHand.isEmpty && myData?['front'] == null) {
            debugPrint(
              '🚫 [OFC] Ignoring generic state (no hand data for my seat during arranging)',
            );
            return;
          }
        }

        debugPrint(
          '📡 [OFC] onState: phase=$serverPhase, round=$round, turnSec=$turnSec, players=${rawPlayers.keys.toList()}',
        );

        // First state received — determine if game is in progress
        if (_waitingForNextRound && !_hasJoined) {
          _waitingForNextRound = false;
          if (serverPhase == 'waiting' && rawPlayers.isEmpty) {
            // Empty room — spectate briefly then join (bots won't start without us)
            debugPrint('👀 [OFC] Empty room — will join in 2 seconds');
            _gameInProgress = false;
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && !_hasJoined) {
                debugPrint('🎮 [OFC] No game started — joining now');
                _joinGame();
              }
            });
          } else if (serverPhase == 'waiting' && rawPlayers.isNotEmpty) {
            // Players present but waiting — join now (between rounds)
            debugPrint('🎮 [OFC] Players waiting — joining now');
            _joinGame();
            return;
          } else {
            // Game in progress — spectate and wait for next round
            debugPrint(
              '👀 [OFC] Game in progress (phase=$serverPhase) — spectating until next round',
            );
            _gameInProgress = true;
          }
        }

        // Auto-join conditions:
        // 1. Game was in progress → wait for waiting phase
        // 2. Empty room → wait for first result phase to pass, then join on next waiting
        if (!_hasJoined && _isSpectating) {
          if (serverPhase == 'waiting' && rawPlayers.isNotEmpty) {
            // Round ended with players present — join now
            debugPrint('🎮 [OFC] Round ended — auto-joining for next round');
            _joinGame();
            return;
          }
          // Track that game has started (for empty room case)
          if (serverPhase == 'arranging' || serverPhase == 'result') {
            _gameInProgress = true;
          }
        }

        setState(() {
          // Don't process state changes while showdown is active or chip animation running
          if (_showdownActive ||
              _showResultPopup ||
              _chipAnimationInProgress ||
              _waitingBeforeShowdown) {
            // Save latest arranging state to replay after animations finish
            if (serverPhase == 'arranging') {
              _pendingState = state;
            }
            // Only update players data, don't change phase
            _players = {};
            rawPlayers.forEach((s, d) {
              final seat = int.tryParse(s) ?? 0;
              _players[seat] = Map<String, dynamic>.from(d);
            });
            // Check if player was kicked during showdown
            if (serverPhase == 'arranging' &&
                !_players.containsKey(_mySeat) &&
                _hasJoined) {
              debugPrint(
                '🚫 [OFC] Player kicked during showdown — clearing and exiting',
              );
              _showdownActive = false;
              _showResultPopup = false;
              _showTableResult = false;
              _showResult = false;
              Future.microtask(() {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ชิปหมด — ออกจากห้อง'),
                    backgroundColor: Colors.red,
                  ),
                );
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                    ]);
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LobbyScreen()),
                    );
                  }
                });
              });
              return;
            }
            debugPrint(
              '⏸️ [OFC] Ignoring phase change during showdown (phase=$serverPhase)',
            );
            return;
          }

          // Transition from result → arranging (new round) — only if chip animation finished
          if ((_showResult || _showTableResult || _phase == 'result') &&
              serverPhase == 'arranging' &&
              !_chipAnimationInProgress) {
            debugPrint(
              '🔄 [OFC] Transitioning from RESULT → ARRANGING (new round)',
            );
            _showResult = false;
            _showResultPopup = false;
            _showTableResult = false;
            _hand = [];
            _front = [];
            _middle = [];
            _back = [];
            _coinChanges = {};
            _resultData = [];
            _dealtCards = [];
            _originalDealtCards = [];
            _myReady = false;
            _showdownActive = false;
            _showdownStep = 0;
            _showStartBanner = false;
            _showVsBanner = false;
            _showDealToPlayers = false;
            _rowResultLabels = {};
            _chipAnimationInProgress = false;
          }
          _phase = serverPhase;
          _currentRound = round;
          _turnSeconds = turnSec;

          _players = {};
          rawPlayers.forEach((s, d) {
            final seat = int.tryParse(s) ?? 0;
            _players[seat] = Map<String, dynamic>.from(d);
            if (seat == _mySeat && _hasJoined) {
              _myChips = _players[seat]!['chips'] ?? _myChips;
              // Only process hand if we're in arranging phase AND don't already have cards
              // AND not currently dealing (prevents duplicate table state from overwriting)
              final hasNoCards =
                  _hand.isEmpty &&
                  _front.isEmpty &&
                  _middle.isEmpty &&
                  _back.isEmpty;
              final isAnimating = _isDealingAnimation || _isShuffling;
              debugPrint(
                '👤 [OFC] My seat=$_mySeat, chips=$_myChips, hasNoCards=$hasNoCards, isAnimating=$isAnimating, phase=$_phase',
              );
              debugPrint(
                '   hand=${(_players[seat]!['hand'] as List?)?.length ?? 0}, front=${(_players[seat]!['front'] as List?)?.length ?? 0}, middle=${(_players[seat]!['middle'] as List?)?.length ?? 0}, back=${(_players[seat]!['back'] as List?)?.length ?? 0}',
              );

              if ((_phase == 'arranging' || _phase == 'placing') &&
                  hasNoCards &&
                  !isAnimating) {
                final newHand = List<String>.from(
                  _players[seat]!['hand'] ?? [],
                );
                final serverFront = List<String>.from(
                  _players[seat]!['front'] ?? [],
                );
                final serverMiddle = List<String>.from(
                  _players[seat]!['middle'] ?? [],
                );
                final serverBack = List<String>.from(
                  _players[seat]!['back'] ?? [],
                );

                debugPrint(
                  '🃏 [OFC] Processing cards: newHand=${newHand.length}, serverFront=${serverFront.length}, serverMiddle=${serverMiddle.length}, serverBack=${serverBack.length}',
                );

                if (newHand.isNotEmpty &&
                    serverFront.isEmpty &&
                    serverMiddle.isEmpty &&
                    serverBack.isEmpty) {
                  // Only accept cards if we haven't already received a set for this round
                  if (_originalDealtCards.isEmpty) {
                    debugPrint(
                      '🎴 [OFC] → Starting deal animation with ${newHand.length} cards',
                    );
                    _originalDealtCards = List<String>.from(newHand);
                    _startDealAnimation(newHand);
                  } else {
                    debugPrint(
                      '⚠️ [OFC] → IGNORING duplicate hand (already have ${_originalDealtCards.length} cards from this round)',
                    );
                  }
                } else if (newHand.isNotEmpty || serverFront.isNotEmpty) {
                  debugPrint('📋 [OFC] → Restoring state from server');
                  _hand = newHand;
                  _front = serverFront;
                  _middle = serverMiddle;
                  _back = serverBack;
                  _originalDealtCards = [
                    ...newHand,
                    ...serverFront,
                    ...serverMiddle,
                    ...serverBack,
                  ];
                  if (_hand.length == 13 &&
                      _front.isEmpty &&
                      _middle.isEmpty &&
                      _back.isEmpty) {
                    debugPrint('🤖 [OFC] → Auto-arranging 13 cards');
                    _recommendation = OFCAutoArrange.arrange(_hand);
                  }
                }
              } else {
                debugPrint(
                  '⏭️ [OFC] Skipping card processing: phase=$_phase, hasNoCards=$hasNoCards, isAnimating=$isAnimating, _hand=${_hand.length}, _front=${_front.length}',
                );
              }
            }
          });

          // Check if player was kicked out (not in players list) or busted (chips <= 0)
          if (serverPhase == 'arranging' &&
              !_players.containsKey(_mySeat) &&
              _hasJoined) {
            debugPrint(
              '🚫 [OFC] Player not in game anymore — busted or kicked',
            );
            Future.microtask(() {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('ชิปหมด — ออกจากห้อง'),
                  backgroundColor: Colors.red,
                ),
              );
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  SystemChrome.setPreferredOrientations([
                    DeviceOrientation.portraitUp,
                  ]);
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LobbyScreen()),
                  );
                }
              });
            });
          }
        });
      },
      onResult: (result) {
        if (!mounted) return;
        debugPrint('🏆 [OFC] onResult received: ${result.keys.toList()}');
        final results = List<Map<String, dynamic>>.from(
          (result['results'] as List?)?.map(
                (r) => Map<String, dynamic>.from(r),
              ) ??
              [],
        );
        debugPrint('🏆 [OFC] Results count: ${results.length}');
        for (final r in results) {
          debugPrint(
            '   seat=${r['seat']}, coinChange=${r['coinChange']}, front=${(r['front'] as List?)?.length ?? 0}',
          );
        }
        setState(() {
          _resultData = results;
          _phase = 'result';
          _coinChanges = {};
          bool myWin = false;
          for (final r in results) {
            final seat = r['seat'] as int? ?? 0;
            _coinChanges[seat] = r['coinChange'] ?? 0;
            if (seat == _mySeat && (r['coinChange'] ?? 0) > 0) myWin = true;
          }
          // Don't start showdown yet — show "all ready" state for 5 seconds first
          _showdownActive = false;
          _showdownStep = 0;
          _showResult = false;
          _showConfetti = false;
          _waitingBeforeShowdown = true;
          // Keep phase as arranging briefly so the waiting overlay stays visible
          _phase = 'arranging';
        });

        // Wait 5 seconds showing "all players ready" before starting showdown
        Future.delayed(
          Duration(
            seconds: RuntimeConfigService.integer('showdown_ready_delay_sec'),
          ),
          () {
            if (!mounted) return;
            setState(() {
              _waitingBeforeShowdown = false;
              _phase = 'result';
              _showdownActive = true;
              _showdownStep = 0;
              _showResult = false;
            });

            // Check if busted immediately (chips + coinChange <= 0)
            final myCoinChange = _coinChanges[_mySeat] ?? 0;
            final newChips = _myChips + myCoinChange;
            if (newChips <= 0 && _hasJoined) {
              debugPrint(
                '💀 [OFC] Busted! chips=$_myChips + coinChange=$myCoinChange = $newChips',
              );
              _runShowdownSequence(results).then((_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ชิปหมด — ออกจากห้อง'),
                    backgroundColor: Colors.red,
                  ),
                );
                Future.delayed(const Duration(seconds: 1), () {
                  if (mounted) {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                    ]);
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LobbyScreen()),
                    );
                  }
                });
              });
            } else {
              _runShowdownSequence(results);
            }
          },
        );
      },
      onError: (msg) {
        debugPrint('❌ [OFC] onError: $msg');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
      },
    );
    final tid = widget.table['id'];
    if (tid != null) {
      // Spectate first — will auto-join when round ends (phase=waiting)
      debugPrint(
        '🎮 [OFC] Spectating table $tid (will auto-join on next round)',
      );
      GameSocket.spectateChinese(
        tid,
        accessToken: widget.table['_roomAccessToken'],
      );
    } else {
      debugPrint('⚠️ [OFC] No table ID found! table=${widget.table}');
    }
  }

  /// Join the game when player is ready
  void _joinGame() {
    final tid = widget.table['id'];
    if (tid == null) return;
    final buyIn = toInt(widget.table['_buyIn'] ?? 1000);

    // Find an empty seat
    final maxSeats = 4;
    final occupiedSeats = _players.keys.toSet();
    int? emptySeat;
    for (int i = 1; i <= maxSeats; i++) {
      if (!occupiedSeats.contains(i)) {
        emptySeat = i;
        break;
      }
    }

    if (emptySeat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่มีที่นั่งว่าง'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _mySeat = emptySeat!;
      _hasJoined = true;
      _isSpectating = false;
      _myChips = buyIn;
    });
    debugPrint('🎮 [OFC] Joining table $tid, seat=$_mySeat, buyIn=$buyIn');
    GameSocket.joinChinese(
      tid,
      _mySeat,
      buyIn,
      accessToken: widget.table['_roomAccessToken'],
    );
  }

  void _placeCard(String card, String row) {
    setState(() {
      _hand.remove(card);
      switch (row) {
        case 'front':
          if (_front.length < 3)
            _front.add(card);
          else {
            _hand.add(card);
          }
        case 'middle':
          if (_middle.length < 5)
            _middle.add(card);
          else {
            _hand.add(card);
          }
        case 'back':
          if (_back.length < 5)
            _back.add(card);
          else {
            _hand.add(card);
          }
      }
      // Auto advance
      if (_activeRow == 'back' && _back.length >= 5)
        _activeRow = 'middle';
      else if (_activeRow == 'middle' && _middle.length >= 5)
        _activeRow = 'front';
    });
  }

  void _removeCard(String row, int index) {
    setState(() {
      switch (row) {
        case 'front':
          _hand.add(_front.removeAt(index));
        case 'middle':
          _hand.add(_middle.removeAt(index));
        case 'back':
          _hand.add(_back.removeAt(index));
      }
      if (_back.length < 5)
        _activeRow = 'back';
      else if (_middle.length < 5)
        _activeRow = 'middle';
      else
        _activeRow = 'front';
    });
  }

  void _resetCards() {
    setState(() {
      _hand.addAll(_front);
      _hand.addAll(_middle);
      _hand.addAll(_back);
      _front = [];
      _middle = [];
      _back = [];
      _activeRow = 'back';
      _recommendation = OFCAutoArrange.arrange(_hand);
    });
  }

  /// Showdown sequence: reveal cards row by row with delays
  Future<void> _runShowdownSequence(List<Map<String, dynamic>> results) async {
    // Check for Dragon (player with +13 points per opponent = Dragon)
    final opponentCount = results.length - 1;
    final dragonPlayer = results
        .where((r) => r['points'] != null && r['points'] == 13 * opponentCount)
        .firstOrNull;
    if (dragonPlayer != null) {
      setState(() => _showDragonBanner = true);
      AudioManager.instance.play(SoundEffect.winCelebration);
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() => _showDragonBanner = false);
    }

    // Show "เทียบไพ่!" banner with excitement
    setState(() {
      _showVsBanner = true;
      _rowResultLabels = {};
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _showVsBanner = false;
      _showResultPopup = true;
    });

    // Brief pause — show all cards face-down first
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // Step 1: Reveal FRONT row (top - weakest)
    setState(() {
      _showdownStep = 1;
      _rowResultLabels = _calculateRowResults(results, 'front');
    });
    AudioManager.instance.play(SoundEffect.cardFlip);

    // Step 2: Reveal MIDDLE row
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      _showdownStep = 2;
      _rowResultLabels = _calculateRowResults(results, 'middle');
    });
    AudioManager.instance.play(SoundEffect.cardFlip);

    // Step 3: Reveal BACK row (bottom - strongest)
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      _showdownStep = 3;
      _rowResultLabels = _calculateRowResults(results, 'back');
    });
    AudioManager.instance.play(SoundEffect.cardFlip);

    // Step 4: Show total scores + close popup + trigger chips per row
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      _showdownStep = 4;
      _showdownActive = false;
      _showResult = true;
      _rowResultLabels = {};
      final myWin = results.any(
        (r) => r['seat'] == _mySeat && (r['coinChange'] ?? 0) > 0,
      );
      _showConfetti = myWin;
    });

    // Close popup first so chips are visible on the game table
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() {
      _showResultPopup = false;
      _showResult = false; // Hide result overlay so chips are visible
      _chipAnimationInProgress = true; // Block next round
    });

    // Now trigger chip animations per row (visible on game table)
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _triggerRowChipAnimation(results, 'front');
    AudioManager.instance.play(SoundEffect.chipToss);

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _triggerRowChipAnimation(results, 'middle');
    AudioManager.instance.play(SoundEffect.chipToss);

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _triggerRowChipAnimation(results, 'back');

    // Sound for final result
    if (results.any(
      (r) => r['seat'] == _mySeat && (r['coinChange'] ?? 0) > 0,
    )) {
      AudioManager.instance.play(SoundEffect.winCelebration);
    } else {
      AudioManager.instance.play(SoundEffect.chipToss);
    }

    // Wait for chip animations to finish
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    // Show winner highlight for 2 seconds before resetting
    setState(() {
      _showResult = true; // Re-enable to show winner badges on avatars
      _showConfetti = results.any(
        (r) => r['seat'] == _mySeat && (r['coinChange'] ?? 0) > 0,
      );
    });
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    // Clear chip animation flag and force reset for next round
    final pendingState = _pendingState;
    setState(() {
      _chipAnimationInProgress = false;
      _waitingBeforeShowdown = false;
      _pendingState = null;
      _showResultPopup = false;
      _showResult = false;
      _showdownStep = 0;
      _resultData = [];
      _coinChanges = {};
      _showdownActive = false;
      _showTableResult = false;
      _rowResultLabels = {};
      _showStartBanner = false;
      _showVsBanner = false;
      _showDealToPlayers = false;
      _hand = [];
      _front = [];
      _middle = [];
      _back = [];
      _dealtCards = [];
      _originalDealtCards = [];
      _myReady = false;
      _phase = 'waiting';
    });

    // If we have a pending state from server, process it now
    if (pendingState != null && mounted) {
      debugPrint('🔄 [OFC] Replaying pending state after chip animation');
      // Trigger onState callback manually with the saved state
      final serverPhase = pendingState['phase'] ?? 'waiting';
      final rawPlayers = pendingState['players'] as Map<String, dynamic>? ?? {};
      final myData = rawPlayers['$_mySeat'] as Map<String, dynamic>?;
      if (myData != null && serverPhase == 'arranging') {
        final newHand = List<String>.from(myData['hand'] ?? []);
        if (newHand.length == 13) {
          _startDealAnimation(newHand);
        }
      }
    }
  }

  /// Calculate per-row win/lose labels for each seat
  Map<int, String> _calculateRowResults(
    List<Map<String, dynamic>> results,
    String row,
  ) {
    final labels = <int, String>{};
    final allCards = <int, List<String>>{};

    // Collect cards for each player
    for (final r in results) {
      final seat = r['seat'] as int? ?? 0;
      List<String> cards;
      if (seat == _mySeat) {
        cards = row == 'back'
            ? _back
            : row == 'middle'
            ? _middle
            : _front;
      } else {
        final raw = r[row];
        cards = raw is List ? List<String>.from(raw) : [];
      }
      if (cards.isNotEmpty) allCards[seat] = cards;
    }

    // Compare each player against all others
    for (final seat in allCards.keys) {
      int wins = 0, losses = 0;
      final myCards = allCards[seat]!;

      for (final otherSeat in allCards.keys) {
        if (otherSeat == seat) continue;
        final otherCards = allCards[otherSeat]!;

        try {
          int cmp;
          if (row == 'front' && myCards.length == 3 && otherCards.length == 3) {
            cmp = HandEvaluator.compare(
              HandEvaluator.evaluate3(myCards),
              HandEvaluator.evaluate3(otherCards),
            );
          } else if (myCards.length == 5 && otherCards.length == 5) {
            cmp = HandEvaluator.compare(
              HandEvaluator.evaluate5(myCards),
              HandEvaluator.evaluate5(otherCards),
            );
          } else {
            continue;
          }
          if (cmp > 0)
            wins++;
          else if (cmp < 0)
            losses++;
        } catch (_) {}
      }

      final net = wins - losses;
      // Get hand name for this player's row
      String handName = '';
      try {
        if (row == 'front' && myCards.length == 3) {
          handName = HandEvaluator.evaluate3(myCards).nameTh;
        } else if (myCards.length == 5) {
          handName = HandEvaluator.evaluate5(myCards).nameTh;
        }
      } catch (_) {}

      if (net > 0) {
        labels[seat] = '$handName\n+$net ชนะ';
      } else if (net < 0) {
        labels[seat] = '$handName\n$net แพ้';
      } else {
        labels[seat] = '$handName\nเสมอ';
      }
    }

    return labels;
  }

  /// Trigger chip animation for a single row — losers pay winners of that row
  void _triggerRowChipAnimation(
    List<Map<String, dynamic>> results,
    String row,
  ) {
    debugPrint(
      '💰 [OFC] _triggerRowChipAnimation: row=$row, results=${results.length}',
    );
    final others = _players.entries.where((e) => e.key != _mySeat).toList();

    // Calculate who won/lost this specific row
    final allCards = <int, List<String>>{};
    for (final r in results) {
      final seat = r['seat'] as int? ?? 0;
      List<String> cards;
      if (seat == _mySeat) {
        cards = row == 'back'
            ? _back
            : row == 'middle'
            ? _middle
            : _front;
      } else {
        final raw = r[row];
        cards = raw is List ? List<String>.from(raw) : [];
      }
      if (cards.isNotEmpty) allCards[seat] = cards;
    }

    // Find row winners and losers
    final rowWinners = <int>{};
    final rowLosers = <int>{};
    for (final seat in allCards.keys) {
      int wins = 0, losses = 0;
      for (final otherSeat in allCards.keys) {
        if (otherSeat == seat) continue;
        try {
          int cmp;
          if (row == 'front' &&
              allCards[seat]!.length == 3 &&
              allCards[otherSeat]!.length == 3) {
            cmp = HandEvaluator.compare(
              HandEvaluator.evaluate3(allCards[seat]!),
              HandEvaluator.evaluate3(allCards[otherSeat]!),
            );
          } else if (allCards[seat]!.length == 5 &&
              allCards[otherSeat]!.length == 5) {
            cmp = HandEvaluator.compare(
              HandEvaluator.evaluate5(allCards[seat]!),
              HandEvaluator.evaluate5(allCards[otherSeat]!),
            );
          } else {
            continue;
          }
          if (cmp > 0)
            wins++;
          else if (cmp < 0)
            losses++;
        } catch (_) {}
      }
      if (wins > losses)
        rowWinners.add(seat);
      else if (losses > wins)
        rowLosers.add(seat);
    }

    if (rowWinners.isEmpty || rowLosers.isEmpty) {
      debugPrint('💰 [OFC] No winners/losers for row $row');
      return;
    }
    debugPrint('💰 [OFC] Row $row: winners=$rowWinners, losers=$rowLosers');

    // Calculate positions using showdown table dimensions
    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top + 40.0;
    final tableAreaH = screenSize.height - safeTop - 60;
    final positions = TableSeatLayout.calculatePositions(
      width: screenSize.width,
      height: tableAreaH,
      seatCount: others.length,
      seatWidth: 150,
      seatHeight: 140,
    );

    Offset seatPos(int seat) {
      if (seat == _mySeat)
        return Offset(screenSize.width / 2, safeTop + tableAreaH - 30);
      final idx = others.indexWhere((e) => e.key == seat);
      if (idx >= 0 && idx < positions.length)
        return Offset(positions[idx].dx + 75, safeTop + positions[idx].dy + 70);
      return Offset(screenSize.width / 2, safeTop + tableAreaH / 2);
    }

    // Animate chips from losers to winners
    for (final winner in rowWinners) {
      final toPos = seatPos(winner);
      for (final loser in rowLosers) {
        final fromPos = seatPos(loser);
        debugPrint(
          '💰 [OFC] Chip: from seat $loser ($fromPos) → to seat $winner ($toPos)',
        );
        _chipAnim.betToPot(from: fromPos, to: toPos, amount: 1, chipCount: 2);
      }
    }
    AudioManager.instance.play(SoundEffect.chipToss);
  }

  /// Trigger chip animations from losers to winners (total)
  void _triggerOFCChipAnimations(List<Map<String, dynamic>> results) {
    final screenSize = MediaQuery.of(context).size;
    final others = _players.entries.where((e) => e.key != _mySeat).toList();

    // Find winners and losers
    final winners = results.where((r) => (r['coinChange'] ?? 0) > 0).toList();
    final losers = results.where((r) => (r['coinChange'] ?? 0) < 0).toList();

    if (winners.isEmpty || losers.isEmpty) return;

    // Calculate positions using TableSeatLayout math
    final tableHeight = screenSize.height * 0.55;
    final safeTop = MediaQuery.of(context).padding.top + 36.0;
    final positions = TableSeatLayout.calculatePositions(
      width: screenSize.width,
      height: tableHeight,
      seatCount: others.length,
      seatWidth: 100,
      seatHeight: 90,
    );

    Offset _seatPos(int seat) {
      if (seat == _mySeat) {
        return Offset(screenSize.width / 2, safeTop + tableHeight + 20);
      }
      final idx = others.indexWhere((e) => e.key == seat);
      if (idx >= 0 && idx < positions.length) {
        return Offset(positions[idx].dx + 50, safeTop + positions[idx].dy + 30);
      }
      return Offset(screenSize.width / 2, safeTop + tableHeight / 2);
    }

    // Animate chips from each loser to each winner
    for (final winner in winners) {
      final winSeat = winner['seat'] as int? ?? 0;
      final winAmount = (winner['coinChange'] ?? 0) as int;
      final toPos = _seatPos(winSeat);

      for (final loser in losers) {
        final loseSeat = loser['seat'] as int? ?? 0;
        final fromPos = _seatPos(loseSeat);
        final chipCount = winAmount > 100 ? 4 : (winAmount > 20 ? 3 : 2);
        _chipAnim.betToPot(
          from: fromPos,
          to: toPos,
          amount: winAmount.abs(),
          chipCount: chipCount,
        );
      }
    }
  }

  void _confirmArrangement() {
    debugPrint(
      '✋ [OFC] _confirmArrangement: front=${_front.length}, middle=${_middle.length}, back=${_back.length}',
    );
    if (_front.length != 3 || _middle.length != 5 || _back.length != 5) {
      debugPrint('⚠️ [OFC] Cannot confirm — invalid card counts!');
      return;
    }

    // Check foul and warn player
    final isFoul = OFCScorer.isFoul(_front, _middle, _back);
    if (isFoul) {
      // Show warning dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A0606),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text(
                'ฟาวล์!',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          content: const Text(
            'ไพ่เรียงผิดกฎ (หลัง ต้องแรงกว่า กลาง ต้องแรงกว่า หน้า)\n\nถ้าส่งแบบนี้จะเสียคะแนนทั้งหมด ต้องการส่งต่อไหม?',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'กลับไปแก้',
                style: TextStyle(color: Colors.amber),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _doConfirmArrangement();
              },
              child: const Text('ส่งเลย', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      return;
    }

    _doConfirmArrangement();
  }

  void _doConfirmArrangement() {
    debugPrint(
      '📤 [OFC] Sending arrangement to server: front=$_front, middle=$_middle, back=$_back',
    );
    final isFoul = OFCScorer.isFoul(_front, _middle, _back);
    debugPrint('📤 [OFC] Foul: $isFoul');
    setState(() => _myReady = true);
    GameSocket.arrangeChinese(_front, _middle, _back);
    AudioManager.instance.play(SoundEffect.buttonTap);
  }

  void _exitGame() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0505),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'ออกจากเกม',
          style: TextStyle(
            color: Color(0xFFFFD700),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'ต้องการออกจากห้องนี้หรือไม่?\nชิปที่เหลือจะถูกคืนให้',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              GameSocket.disconnect();
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.portraitUp,
              ]);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LobbyScreen()),
              );
            },
            child: const Text(
              'ออก',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _applyRecommendation() {
    if (_recommendation == null) return;
    setState(() {
      _front = List<String>.from(_recommendation!['front']!);
      _middle = List<String>.from(_recommendation!['middle']!);
      _back = List<String>.from(_recommendation!['back']!);
      _hand = [];
      _activeRow = 'front';
    });
  }

  /// Receive cards — skip animations, go straight to arranging.
  void _startDealAnimation(List<String> cards) {
    debugPrint('🎴 [OFC] _startDealAnimation: ${cards.length} cards');
    if (_isDealingAnimation || _isShuffling) {
      debugPrint('⚠️ [OFC] _startDealAnimation SKIPPED (already animating)');
      return;
    }
    _originalDealtCards = List<String>.from(cards);

    // Show "เริ่ม!" banner first, then proceed to arrangement
    setState(() {
      _showStartBanner = true;
      _myReady = false;
      _phase = 'arranging'; // Ensure phase is set for proper rendering
    });
    AudioManager.instance.play(SoundEffect.cardDeal);

    // After 1.2 seconds, hide banner and show arrangement
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _showStartBanner = false;
        _hand = List<String>.from(cards);
        _front = [];
        _middle = [];
        _back = [];
        _pendingDealCards = [];
        _dealtCards = List<String>.from(cards);
        _isDealingAnimation = false;
        _isShuffling = false;
        _showDealToPlayers = false;
        _phase = 'arranging';

        // Auto-arrange into 3 rows
        if (_hand.length == 13) {
          _recommendation = OFCAutoArrange.arrange(_hand);
          if (_recommendation != null) {
            _front = List<String>.from(_recommendation!['front']!);
            _middle = List<String>.from(_recommendation!['middle']!);
            _back = List<String>.from(_recommendation!['back']!);
            _hand = [];
            _activeRow = 'front';
          }
        }
      });
    });
  }

  void _beginShuffleAndDeal() {
    // Phase 1: Shuffle animation (600ms) + deal-to-players
    setState(() {
      _isShuffling = true;
      _showDealToPlayers = true;
    });
    AudioManager.instance.play(SoundEffect.cardShuffle);
    _shuffleController.reset();
    _shuffleController.forward().then((_) {
      if (!mounted) return;
      setState(() => _isShuffling = false);
      // Wait for deal-to-players to finish before dealing to hand
      _waitForDealToPlayersAndDeal();
    });
  }

  void _waitForDealToPlayersAndDeal() async {
    // Wait until deal-to-players animation completes (max 3 seconds)
    int waited = 0;
    while (_showDealToPlayers && mounted && waited < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited++;
    }
    if (!mounted) return;
    // Force clear in case animation didn't complete
    if (_showDealToPlayers) {
      setState(() => _showDealToPlayers = false);
    }
    // Phase 2: Deal cards one by one
    setState(() => _isDealingAnimation = true);
    _dealNextCard();
  }

  void _dealNextCard() async {
    if (_pendingDealCards.isEmpty) {
      debugPrint('✅ [OFC] All cards dealt! hand=${_hand.length}');
      // All cards dealt — auto-arrange into 3 rows
      setState(() {
        _isDealingAnimation = false;
        if (_hand.length == 13 &&
            _front.isEmpty &&
            _middle.isEmpty &&
            _back.isEmpty) {
          debugPrint('🤖 [OFC] Auto-arranging 13 cards into rows');
          _recommendation = OFCAutoArrange.arrange(_hand);
          if (_recommendation != null) {
            _front = List<String>.from(_recommendation!['front']!);
            _middle = List<String>.from(_recommendation!['middle']!);
            _back = List<String>.from(_recommendation!['back']!);
            _hand = [];
            _activeRow = 'front';
          }
        }
      });
      // REMOVED: auto-confirm. Player must press "พร้อม"
      return;
    }
    // Stop dealing if result already came in
    if (_showResult) {
      setState(() {
        _isDealingAnimation = false;
        _pendingDealCards = [];
      });
      return;
    }
    // Deal one card every 50ms — faster, smoother dealing
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    setState(() {
      final card = _pendingDealCards.removeAt(0);
      _dealtCards.add(card);
      _hand.add(card);
    });
    AudioManager.instance.play(SoundEffect.cardDeal);
    _dealNextCard();
  }

  bool get _canConfirm =>
      _front.length == 3 && _middle.length == 5 && _back.length == 5;
  bool get _isArranging => _phase == 'arranging' || _phase == 'placing';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // App theme background
          Positioned.fill(
            child: AppBackground(
              overlayOpacity: 0.7,
              child: const SizedBox.expand(),
            ),
          ),
          // Main layout using shared TableSeatLayout
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildGameTable()),
              ],
            ),
          ),
          // Deal animation overlay
          // Card arrangement popup (full screen overlay when arranging)
          if (_hasJoined &&
              _isArranging &&
              !_myReady &&
              !_isDealingAnimation &&
              !_isShuffling &&
              (_canConfirm || _hand.isNotEmpty))
            _buildArrangementPopup(),
          // Waiting for others overlay (after confirm, before showdown)
          if (_hasJoined && _isArranging && _myReady && !_showResultPopup)
            _buildWaitingForOthersOverlay(),
          // Showdown/Result popup (full screen overlay)
          if (_showResultPopup && _resultData.isNotEmpty) _buildShowdownPopup(),
          // Chip animation — ABOVE popup so chips are visible
          Positioned.fill(child: ChipAnimationOverlay(controller: _chipAnim)),
          // Confetti — ABOVE everything
          if (_showConfetti)
            Positioned.fill(
              child: ConfettiEffect(
                onComplete: () => setState(() => _showConfetti = false),
              ),
            ),
          // "เริ่ม!" banner
          if (_showStartBanner)
            Positioned.fill(
              child: _buildCenterBanner(
                '🎴 เริ่มรอบใหม่!',
                const Color(0xFFFFD700),
              ),
            ),
          // "VS" banner before showdown
          if (_showVsBanner)
            Positioned.fill(
              child: _buildCenterBanner('⚔️ เทียบไพ่!', Colors.red),
            ),
          // "🐉 มังกร!" Dragon banner
          if (_showDragonBanner)
            Positioned.fill(
              child: _buildCenterBanner('🐉 มังกร!', const Color(0xFF9C27B0)),
            ),
          if (_isDealingAnimation) _buildDealOverlay(),
          // Shuffle animation overlay
          if (_isShuffling) _buildShuffleOverlay(),
          // Deal-to-players animation — cards fly from dealer to each player
          if (_showDealToPlayers)
            Positioned.fill(
              child: IgnorePointer(
                child: DealToPlayersAnimation(
                  key: ValueKey('ofcDeal_$_currentRound'),
                  playerCount: _players.length.clamp(2, 4),
                  cardsPerPlayer: 13,
                  onComplete: () {
                    if (mounted) setState(() => _showDealToPlayers = false);
                  },
                ),
              ),
            ),
          // Spectator indicator — small badge, bottom-left corner
          if (_isSpectating && !_hasJoined)
            Positioned(
              bottom: 16,
              left: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'รอเล่นรอบถัดไป (${_players.length} คนกำลังเล่น)',
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
        ],
      ),
    );
  }

  /// Full-screen popup for card arrangement — large cards, responsive layout
  Widget _buildArrangementPopup() {
    return Positioned.fill(
      child: AppBackground(
        overlayOpacity: 0.8,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape = constraints.maxWidth > constraints.maxHeight;

              if (isLandscape) {
                return _buildLandscapeArrangement(constraints);
              } else {
                return _buildPortraitArrangement(constraints);
              }
            },
          ),
        ),
      ),
    );
  }

  /// Waiting overlay — centered text on table showing waiting status
  Widget _buildWaitingForOthersOverlay() {
    final others = _players.entries.where((e) => e.key != _mySeat).toList();
    final readyCount = others.where((e) {
      final p = e.value;
      return p['isReady'] == true || p['arranged'] != null;
    }).length;
    final totalOthers = others.length;

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFDAA520).withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⏳', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 6),
                const Text(
                  'รอผู้เล่นคนอื่นจัดไพ่...',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'พร้อม ${readyCount + 1}/${totalOthers + 1} คน',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _turnSeconds > 10
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '⏱ $_turnSeconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Full-screen popup for showdown/result — shows table with cards + details
  Widget _buildShowdownPopup() {
    return Positioned.fill(
      child: AppBackground(
        overlayOpacity: 0.75,
        child: SafeArea(
          child: Column(
            children: [
              // Header bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _showdownStep == 0
                            ? '🃏 เตรียมเปิดไพ่...'
                            : _showdownStep == 1
                            ? '🃏 เปิดกองหน้า (บน)'
                            : _showdownStep == 2
                            ? '🃏 เปิดกองกลาง'
                            : _showdownStep == 3
                            ? '🃏 เปิดกองหลัง (ล่าง)'
                            : '🏆 ผลการแข่งขัน',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_showdownStep >= 1) ...[
                      Builder(
                        builder: (_) {
                          // Progressive coin display based on revealed rows
                          final totalCoins = _coinChanges[_mySeat] ?? 0;
                          int progressiveCoins = 0;

                          if (_showdownStep >= 3) {
                            // All rows revealed — show actual total
                            progressiveCoins = totalCoins;
                          } else {
                            // Calculate actual per-row net scores
                            int fNet = 0, mNet = 0;
                            for (final r in _resultData) {
                              if (r['seat'] == _mySeat) continue;
                              final oF = r['front'] is List
                                  ? List<String>.from(r['front'])
                                  : <String>[];
                              final oM = r['middle'] is List
                                  ? List<String>.from(r['middle'])
                                  : <String>[];
                              try {
                                if (oF.length == 3 && _front.length == 3) {
                                  final c = HandEvaluator.compare(
                                    HandEvaluator.evaluate3(_front),
                                    HandEvaluator.evaluate3(oF),
                                  );
                                  if (c > 0)
                                    fNet++;
                                  else if (c < 0)
                                    fNet--;
                                }
                              } catch (_) {}
                              try {
                                if (oM.length == 5 && _middle.length == 5) {
                                  final c = HandEvaluator.compare(
                                    HandEvaluator.evaluate5(_middle),
                                    HandEvaluator.evaluate5(oM),
                                  );
                                  if (c > 0)
                                    mNet++;
                                  else if (c < 0)
                                    mNet--;
                                }
                              } catch (_) {}
                            }
                            int netPoints = 0;
                            if (_showdownStep >= 1) netPoints += fNet;
                            if (_showdownStep >= 2) netPoints += mNet;
                            // Multiply by bigBlind unit
                            final bigBlind =
                                (widget.table['big_blind'] as int?) ?? 20;
                            progressiveCoins = netPoints * bigBlind;
                          }
                          if (progressiveCoins == 0)
                            return const SizedBox.shrink();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: progressiveCoins > 0
                                    ? [
                                        const Color(0xFF2E7D32),
                                        const Color(0xFF1B5E20),
                                      ]
                                    : [
                                        const Color(0xFFC62828),
                                        const Color(0xFF8B0000),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              progressiveCoins > 0
                                  ? '+$progressiveCoins'
                                  : '$progressiveCoins',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              // Table with cards — per-player results shown at each avatar's cards
              Expanded(child: _buildShowdownTableWithDetails()),
            ],
          ),
        ),
      ),
    );
  }

  /// Build row-by-row comparison summary showing win/lose per row
  Widget _buildRowComparisonSummary() {
    // Get my cards and compare against each opponent
    if (_front.length != 3 || _middle.length != 5 || _back.length != 5)
      return const SizedBox.shrink();

    final isFoul = OFCScorer.isFoul(_front, _middle, _back);
    if (isFoul) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '❌ ฟาวล์! เสียทุกกอง (-6 แต้ม/คน)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Compare my hand against opponents
    int backWins = 0, backLosses = 0;
    int middleWins = 0, middleLosses = 0;
    int frontWins = 0, frontLosses = 0;

    String myBackName = '', myMiddleName = '', myFrontName = '';
    try {
      myBackName = HandEvaluator.evaluate5(_back).nameTh;
    } catch (_) {}
    try {
      myMiddleName = HandEvaluator.evaluate5(_middle).nameTh;
    } catch (_) {}
    try {
      myFrontName = HandEvaluator.evaluate3(_front).nameTh;
    } catch (_) {}

    for (final r in _resultData) {
      if (r['seat'] == _mySeat) continue;
      final oFront = r['front'] is List
          ? List<String>.from(r['front'])
          : <String>[];
      final oMiddle = r['middle'] is List
          ? List<String>.from(r['middle'])
          : <String>[];
      final oBack = r['back'] is List
          ? List<String>.from(r['back'])
          : <String>[];

      if (oBack.length == 5) {
        final cmp = HandEvaluator.compare(
          HandEvaluator.evaluate5(_back),
          HandEvaluator.evaluate5(oBack),
        );
        if (cmp > 0)
          backWins++;
        else if (cmp < 0)
          backLosses++;
      }
      if (oMiddle.length == 5) {
        final cmp = HandEvaluator.compare(
          HandEvaluator.evaluate5(_middle),
          HandEvaluator.evaluate5(oMiddle),
        );
        if (cmp > 0)
          middleWins++;
        else if (cmp < 0)
          middleLosses++;
      }
      if (oFront.length == 3) {
        final cmp = HandEvaluator.compare(
          HandEvaluator.evaluate3(_front),
          HandEvaluator.evaluate3(oFront),
        );
        if (cmp > 0)
          frontWins++;
        else if (cmp < 0)
          frontLosses++;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDAA520).withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRowResult('หลัง', myBackName, backWins, backLosses),
            const SizedBox(height: 3),
            _buildRowResult('กลาง', myMiddleName, middleWins, middleLosses),
            const SizedBox(height: 3),
            _buildRowResult('หน้า', myFrontName, frontWins, frontLosses),
            if (backWins + middleWins + frontWins ==
                (_resultData.length - 1) * 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFDAA520)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '🎉 กวาดทุกกอง! (Scoop +3)',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 10,
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

  Widget _buildRowResult(
    String rowName,
    String handName,
    int wins,
    int losses,
  ) {
    final net = wins - losses;
    final isWin = net > 0;
    final isLose = net < 0;
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            rowName,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Text(
            handName,
            style: TextStyle(
              color: isWin
                  ? const Color(0xFF4ADE80)
                  : isLose
                  ? Colors.red.shade300
                  : Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: isWin
                ? Colors.green.withOpacity(0.3)
                : isLose
                ? Colors.red.withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isWin
                ? '✓ ชนะ $wins'
                : isLose
                ? '✗ แพ้ $losses'
                : '= เสมอ',
            style: TextStyle(
              color: isWin
                  ? const Color(0xFF4ADE80)
                  : isLose
                  ? Colors.red.shade300
                  : Colors.white54,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  /// Right-side detail panel showing per-row results (like reference image)
  Widget _buildRightSideDetailPanel() {
    final myCoinChange = _coinChanges[_mySeat] ?? 0;
    final isMyWin = myCoinChange > 0;

    // Get hand names for my rows
    String frontName = '', middleName = '', backName = '';
    int frontNet = 0, middleNet = 0, backNet = 0;
    try {
      if (_front.length == 3)
        frontName = HandEvaluator.evaluate3(_front).nameTh;
    } catch (_) {}
    try {
      if (_middle.length == 5)
        middleName = HandEvaluator.evaluate5(_middle).nameTh;
    } catch (_) {}
    try {
      if (_back.length == 5) backName = HandEvaluator.evaluate5(_back).nameTh;
    } catch (_) {}

    // Calculate net per row against all opponents
    for (final r in _resultData) {
      if (r['seat'] == _mySeat) continue;
      final oF = r['front'] is List
          ? List<String>.from(r['front'])
          : <String>[];
      final oM = r['middle'] is List
          ? List<String>.from(r['middle'])
          : <String>[];
      final oB = r['back'] is List ? List<String>.from(r['back']) : <String>[];
      try {
        if (oF.length == 3 && _front.length == 3) {
          final c = HandEvaluator.compare(
            HandEvaluator.evaluate3(_front),
            HandEvaluator.evaluate3(oF),
          );
          if (c > 0)
            frontNet++;
          else if (c < 0)
            frontNet--;
        }
      } catch (_) {}
      try {
        if (oM.length == 5 && _middle.length == 5) {
          final c = HandEvaluator.compare(
            HandEvaluator.evaluate5(_middle),
            HandEvaluator.evaluate5(oM),
          );
          if (c > 0)
            middleNet++;
          else if (c < 0)
            middleNet--;
        }
      } catch (_) {}
      try {
        if (oB.length == 5 && _back.length == 5) {
          final c = HandEvaluator.compare(
            HandEvaluator.evaluate5(_back),
            HandEvaluator.evaluate5(oB),
          );
          if (c > 0)
            backNet++;
          else if (c < 0)
            backNet--;
        }
      } catch (_) {}
    }

    return Container(
      width: 90,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isMyWin
              ? [const Color(0xFF1A3A1A), const Color(0xFF0D1F0D)]
              : [const Color(0xFF3A1A1A), const Color(0xFF1F0D0D)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMyWin ? const Color(0xFFFFD700) : Colors.red.shade700,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isMyWin ? const Color(0xFFFFD700) : Colors.red).withOpacity(
              0.3,
            ),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Winner/Loser badge — only show final result when all rows revealed
          if (_showdownStep >= 3)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isMyWin
                      ? [const Color(0xFFFFD700), const Color(0xFFDAA520)]
                      : [const Color(0xFFC62828), const Color(0xFF8B0000)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isMyWin ? '🏆 ชนะ' : '💀 แพ้',
                style: TextStyle(
                  color: isMyWin ? Colors.black : Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDAA520).withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFDAA520).withOpacity(0.5),
                ),
              ),
              child: const Text(
                '⚔️ เทียบ',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          const SizedBox(height: 6),

          // Front row detail
          if (_showdownStep >= 1)
            _buildDetailRowCard(
              'หน้า',
              frontName,
              frontNet,
              _showdownStep >= 1,
            ),
          if (_showdownStep >= 2) ...[
            const SizedBox(height: 4),
            _buildDetailRowCard(
              'กลาง',
              middleName,
              middleNet,
              _showdownStep >= 2,
            ),
          ],
          if (_showdownStep >= 3) ...[
            const SizedBox(height: 4),
            _buildDetailRowCard('หลัง', backName, backNet, _showdownStep >= 3),
          ],

          // Total score — progressive: accumulates as each row is revealed
          if (_showdownStep >= 1) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (_) {
                // Calculate progressive total based on revealed rows
                int progressiveTotal = 0;
                if (_showdownStep >= 1) progressiveTotal += frontNet;
                if (_showdownStep >= 2) progressiveTotal += middleNet;
                if (_showdownStep >= 3) progressiveTotal += backNet;
                // Add scoop bonus if all 3 rows won (only when all revealed)
                if (_showdownStep >= 3 &&
                    frontNet > 0 &&
                    middleNet > 0 &&
                    backNet > 0) {
                  progressiveTotal +=
                      (_resultData.length - 1); // +1 per opponent for scoop
                }
                final isProgWin = progressiveTotal > 0;
                final isProgLose = progressiveTotal < 0;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isProgWin
                        ? const Color(0xFFFFD700).withOpacity(0.2)
                        : isProgLose
                        ? Colors.red.withOpacity(0.2)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isProgWin
                          ? const Color(0xFFFFD700).withOpacity(0.5)
                          : isProgLose
                          ? Colors.red.withOpacity(0.5)
                          : Colors.white.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    '${progressiveTotal > 0 ? "+" : ""}$progressiveTotal แต้ม',
                    style: TextStyle(
                      color: isProgWin
                          ? const Color(0xFFFFD700)
                          : isProgLose
                          ? Colors.red.shade300
                          : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRowCard(
    String rowLabel,
    String handName,
    int net,
    bool revealed,
  ) {
    final isWin = net > 0;
    final isLose = net < 0;
    final color = isWin
        ? const Color(0xFFFFD700)
        : isLose
        ? Colors.red.shade300
        : Colors.white54;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: isWin
            ? const Color(0xFFFFD700).withOpacity(0.1)
            : isLose
            ? Colors.red.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                rowLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                isWin
                    ? '+$net'
                    : isLose
                    ? '$net'
                    : '0',
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Text(
            revealed && handName.isNotEmpty ? handName : '...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            isWin
                ? '✓ ชนะกอง'
                : isLose
                ? '✗ แพ้กอง'
                : '= เสมอ',
            style: TextStyle(color: color, fontSize: 7),
          ),
        ],
      ),
    );
  }

  /// Showdown table — green felt with cards at each seat position
  Widget _buildShowdownTableWithDetails() {
    final others = _players.entries.where((e) => e.key != _mySeat).toList();
    final opponentWidgets = others
        .map((e) => _buildShowdownSeatWithInfo(e.value, e.key))
        .toList();

    return TableSeatLayout(
      opponentWidgets: opponentWidgets,
      myWidget: _buildShowdownMySeatWithInfo(),
      centerWidget: null,
      dealerWidget: null,
      overlayWidgets: const [],
      seatWidth: 150.0,
      seatHeight: 140.0,
    );
  }

  /// Showdown seat for opponent — cards + name + royalty info
  Widget _buildShowdownSeatWithInfo(Map<String, dynamic> p, int seat) {
    final coinChange = _coinChanges[seat] ?? 0;
    final isWin = coinChange > 0;
    final username = p['username'] ?? 'Player $seat';
    final opResult = _resultData.where((r) => r['seat'] == seat).firstOrNull;

    // Calculate royalty for this player's cards
    int royalty = 0;
    if (_showResult && opResult != null) {
      final rawBack = opResult['back'];
      final rawMiddle = opResult['middle'];
      final rawFront = opResult['front'];
      if (rawBack is List && rawBack.length == 5)
        royalty += OFCScorer.calculateRoyalties(
          List<String>.from(rawBack),
          'back',
        );
      if (rawMiddle is List && rawMiddle.length == 5)
        royalty += OFCScorer.calculateRoyalties(
          List<String>.from(rawMiddle),
          'middle',
        );
      if (rawFront is List && rawFront.length == 3)
        royalty += OFCScorer.calculateRoyalties(
          List<String>.from(rawFront),
          'front',
        );
    }

    return Transform.translate(
      offset: const Offset(0, -30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Winner/Loser highlight banner — show only at final result
          if (_showResult && coinChange != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isWin
                      ? [const Color(0xFFFFD700), const Color(0xFFDAA520)]
                      : [const Color(0xFFC62828), const Color(0xFF8B0000)],
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: isWin
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.6),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                isWin ? '🏆 ชนะ +$coinChange' : '💀 $coinChange',
                style: TextStyle(
                  color: isWin ? Colors.black : Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          // Fantasy Land indicator
          if (_showResult &&
              opResult != null &&
              opResult['qualifiesFantasyland'] == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9C27B0), Color(0xFF6A1B9A)],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '🏰 Fantasy Land!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          // Name
          Text(
            username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 7,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          // Per-row result popup (during showdown steps 1-3)
          if (_rowResultLabels.containsKey(seat))
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(
                scale: v,
                child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                margin: const EdgeInsets.only(top: 2, bottom: 2),
                decoration: BoxDecoration(
                  color: (_rowResultLabels[seat]?.contains('ชนะ') ?? false)
                      ? Colors.green.withOpacity(0.9)
                      : (_rowResultLabels[seat]?.contains('แพ้') ?? false)
                      ? Colors.red.withOpacity(0.9)
                      : Colors.grey.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  _rowResultLabels[seat] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // Win/Lose + royalty badges (final result)
          if (_showResult && (coinChange != 0 || royalty > 0))
            Padding(
              padding: const EdgeInsets.only(top: 1, bottom: 1),
              child: Wrap(
                spacing: 3,
                children: [
                  if (coinChange != 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isWin
                              ? [
                                  const Color(0xFFFFD700),
                                  const Color(0xFFDAA520),
                                ]
                              : [
                                  const Color(0xFFC62828),
                                  const Color(0xFF8B0000),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isWin ? '+$coinChange' : '$coinChange',
                        style: TextStyle(
                          color: isWin ? Colors.black : Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  if (royalty > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '✨+$royalty',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // Cards
          if (opResult != null)
            _buildOpponentRevealedCards(opResult)
          else
            _buildOpponentRevealedCards({'front': 3, 'middle': 5, 'back': 5}),
        ],
      ),
    );
  }

  /// Showdown seat for me — cards + name + royalty info
  Widget _buildShowdownMySeatWithInfo() {
    final myCoinChange = _coinChanges[_mySeat] ?? 0;
    final isWin = myCoinChange > 0;
    final myData = _players[_mySeat] ?? {};
    final username = myData['username'] ?? 'คุณ';

    // Check foul
    final isFoul =
        _front.length == 3 && _middle.length == 5 && _back.length == 5
        ? OFCScorer.isFoul(_front, _middle, _back)
        : false;

    // Calculate my royalty
    int royalty = 0;
    if (_showResult && !isFoul) {
      if (_back.length == 5)
        royalty += OFCScorer.calculateRoyalties(_back, 'back');
      if (_middle.length == 5)
        royalty += OFCScorer.calculateRoyalties(_middle, 'middle');
      if (_front.length == 3)
        royalty += OFCScorer.calculateRoyalties(_front, 'front');
    }

    final myCards = {
      'seat': _mySeat,
      'front': _front,
      'middle': _middle,
      'back': _back,
    };

    return Transform.translate(
      offset: const Offset(0, -20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Winner/Loser highlight banner — progressive during showdown
          if (_showdownActive || _showResult) ...[
            Builder(
              builder: (_) {
                // Calculate progressive coin change based on revealed rows
                int progressiveCoins = 0;
                if (_showResult || _showdownStep >= 3) {
                  progressiveCoins = myCoinChange;
                } else {
                  final bigBlind = (widget.table['big_blind'] as int?) ?? 20;
                  int netPoints = 0;
                  for (final r in _resultData) {
                    if (r['seat'] == _mySeat) continue;
                    final oF = r['front'] is List
                        ? List<String>.from(r['front'])
                        : <String>[];
                    final oM = r['middle'] is List
                        ? List<String>.from(r['middle'])
                        : <String>[];
                    final oB = r['back'] is List
                        ? List<String>.from(r['back'])
                        : <String>[];
                    if (_showdownStep >= 1) {
                      try {
                        if (oF.length == 3 && _front.length == 3) {
                          final c = HandEvaluator.compare(
                            HandEvaluator.evaluate3(_front),
                            HandEvaluator.evaluate3(oF),
                          );
                          if (c > 0)
                            netPoints++;
                          else if (c < 0)
                            netPoints--;
                        }
                      } catch (_) {}
                    }
                    if (_showdownStep >= 2) {
                      try {
                        if (oM.length == 5 && _middle.length == 5) {
                          final c = HandEvaluator.compare(
                            HandEvaluator.evaluate5(_middle),
                            HandEvaluator.evaluate5(oM),
                          );
                          if (c > 0)
                            netPoints++;
                          else if (c < 0)
                            netPoints--;
                        }
                      } catch (_) {}
                    }
                    if (_showdownStep >= 3) {
                      try {
                        if (oB.length == 5 && _back.length == 5) {
                          final c = HandEvaluator.compare(
                            HandEvaluator.evaluate5(_back),
                            HandEvaluator.evaluate5(oB),
                          );
                          if (c > 0)
                            netPoints++;
                          else if (c < 0)
                            netPoints--;
                        }
                      } catch (_) {}
                    }
                  }
                  progressiveCoins = netPoints * bigBlind;
                }
                if (progressiveCoins == 0 && !_showResult)
                  return const SizedBox.shrink();
                final pWin = progressiveCoins > 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: pWin
                          ? [const Color(0xFFFFD700), const Color(0xFFDAA520)]
                          : [const Color(0xFFC62828), const Color(0xFF8B0000)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: pWin
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withOpacity(0.6),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    pWin ? '+$progressiveCoins' : '$progressiveCoins',
                    style: TextStyle(
                      color: pWin ? Colors.black : Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                );
              },
            ),
          ],
          // Name
          Text(
            username,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 7,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Per-row result popup (during showdown steps 1-3)
          if (_rowResultLabels.containsKey(_mySeat))
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(
                scale: v,
                child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                margin: const EdgeInsets.only(top: 2, bottom: 2),
                decoration: BoxDecoration(
                  color: (_rowResultLabels[_mySeat]?.contains('ชนะ') ?? false)
                      ? Colors.green.withOpacity(0.9)
                      : (_rowResultLabels[_mySeat]?.contains('แพ้') ?? false)
                      ? Colors.red.withOpacity(0.9)
                      : Colors.grey.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  _rowResultLabels[_mySeat] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // Win/Lose + royalty badges (final result)
          if (_showResult && (myCoinChange != 0 || royalty > 0))
            Padding(
              padding: const EdgeInsets.only(top: 1, bottom: 1),
              child: Wrap(
                spacing: 3,
                children: [
                  if (myCoinChange != 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isWin
                              ? [
                                  const Color(0xFFFFD700),
                                  const Color(0xFFDAA520),
                                ]
                              : [
                                  const Color(0xFFC62828),
                                  const Color(0xFF8B0000),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isWin ? '+$myCoinChange' : '$myCoinChange',
                        style: TextStyle(
                          color: isWin ? Colors.black : Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  if (royalty > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '✨+$royalty',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // Fantasy Land indicator for my seat
          if (_showResult &&
              _resultData.any(
                (r) =>
                    r['seat'] == _mySeat && r['qualifiesFantasyland'] == true,
              ))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9C27B0), Color(0xFF6A1B9A)],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '🏰 Fantasy Land!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          // Cards
          _buildOpponentRevealedCards(myCards),
        ],
      ),
    );
  }

  /// Detailed result for one player — shows each row with hand name and win/lose per row
  Widget _buildDetailedPlayerResult(dynamic r) {
    final seat = r['seat'] as int? ?? 0;
    final isMe = seat == _mySeat;
    final coinChange = _coinChanges[seat] ?? 0;
    final isWin = coinChange > 0;
    final username = isMe
        ? (_players[_mySeat]?['username'] ?? 'คุณ')
        : (_players[seat]?['username'] ?? 'Player $seat');

    // Get cards
    List<String> front, middle, back;
    if (isMe && _front.isNotEmpty) {
      front = _front;
      middle = _middle;
      back = _back;
    } else {
      final rawFront = r['front'];
      final rawMiddle = r['middle'];
      final rawBack = r['back'];
      front = rawFront is List ? List<String>.from(rawFront) : [];
      middle = rawMiddle is List ? List<String>.from(rawMiddle) : [];
      back = rawBack is List ? List<String>.from(rawBack) : [];
    }

    // Evaluate hand names
    String frontName = '';
    String middleName = '';
    String backName = '';
    HandRank? frontRank, middleRank, backRank;
    if (front.length == 3) {
      try {
        frontRank = HandEvaluator.evaluate3(front);
        frontName = frontRank.nameTh;
      } catch (_) {}
    }
    if (middle.length == 5) {
      try {
        middleRank = HandEvaluator.evaluate5(middle);
        middleName = middleRank.nameTh;
      } catch (_) {}
    }
    if (back.length == 5) {
      try {
        backRank = HandEvaluator.evaluate5(back);
        backName = backRank.nameTh;
      } catch (_) {}
    }

    // Compare this player's rows against all other players
    int frontWins = 0, frontLosses = 0;
    int middleWins = 0, middleLosses = 0;
    int backWins = 0, backLosses = 0;

    if (_showResult &&
        frontRank != null &&
        middleRank != null &&
        backRank != null) {
      for (final other in _resultData) {
        final otherSeat = other['seat'] as int? ?? 0;
        if (otherSeat == seat) continue;

        // Get other player's cards
        List<String> oFront, oMiddle, oBack;
        if (otherSeat == _mySeat && _front.isNotEmpty) {
          oFront = _front;
          oMiddle = _middle;
          oBack = _back;
        } else {
          final of = other['front'];
          final om = other['middle'];
          final ob = other['back'];
          oFront = of is List ? List<String>.from(of) : [];
          oMiddle = om is List ? List<String>.from(om) : [];
          oBack = ob is List ? List<String>.from(ob) : [];
        }

        // Compare front (3-card)
        if (oFront.length == 3) {
          try {
            final oRank = HandEvaluator.evaluate3(oFront);
            final cmp = HandEvaluator.compare(frontRank!, oRank);
            if (cmp > 0)
              frontWins++;
            else if (cmp < 0)
              frontLosses++;
          } catch (_) {}
        }
        // Compare middle (5-card)
        if (oMiddle.length == 5) {
          try {
            final oRank = HandEvaluator.evaluate5(oMiddle);
            final cmp = HandEvaluator.compare(middleRank!, oRank);
            if (cmp > 0)
              middleWins++;
            else if (cmp < 0)
              middleLosses++;
          } catch (_) {}
        }
        // Compare back (5-card)
        if (oBack.length == 5) {
          try {
            final oRank = HandEvaluator.evaluate5(oBack);
            final cmp = HandEvaluator.compare(backRank!, oRank);
            if (cmp > 0)
              backWins++;
            else if (cmp < 0)
              backLosses++;
          } catch (_) {}
        }
      }
    }

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isMe
                ? [const Color(0xFF1A2A1A), const Color(0xFF0A1A0A)]
                : [const Color(0xFF1A1A2A), const Color(0xFF0A0A1A)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isWin
                ? const Color(0xFFFFD700).withOpacity(0.6)
                : coinChange < 0
                ? Colors.red.withOpacity(0.4)
                : Colors.white.withOpacity(0.1),
            width: isWin ? 2 : 1,
          ),
          boxShadow: isWin
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.2),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Player header with name + total score
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isWin
                        ? const Color(0xFFFFD700).withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
                    border: Border.all(
                      color: isWin
                          ? const Color(0xFFFFD700)
                          : const Color(0xFFDAA520),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      username[0].toUpperCase(),
                      style: TextStyle(
                        color: isWin ? const Color(0xFFFFD700) : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isMe ? '$username (คุณ)' : username,
                    style: TextStyle(
                      color: isMe ? const Color(0xFFFFD700) : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_showResult && coinChange != 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isWin
                            ? [const Color(0xFFFFD700), const Color(0xFFDAA520)]
                            : [
                                const Color(0xFFC62828),
                                const Color(0xFF8B0000),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isWin ? '🏆 +$coinChange' : '$coinChange',
                      style: TextStyle(
                        color: isWin ? Colors.black : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Card rows with hand names + win/lose per row + royalties
            _buildDetailedCardRow(
              'กองหลัง',
              back,
              backName,
              _showdownStep >= 1,
              backWins,
              backLosses,
              _showResult && back.length == 5
                  ? OFCScorer.calculateRoyalties(back, 'back')
                  : 0,
            ),
            const SizedBox(height: 4),
            _buildDetailedCardRow(
              'กองกลาง',
              middle,
              middleName,
              _showdownStep >= 2,
              middleWins,
              middleLosses,
              _showResult && middle.length == 5
                  ? OFCScorer.calculateRoyalties(middle, 'middle')
                  : 0,
            ),
            const SizedBox(height: 4),
            _buildDetailedCardRow(
              'กองหน้า',
              front,
              frontName,
              _showdownStep >= 3,
              frontWins,
              frontLosses,
              _showResult && front.length == 3
                  ? OFCScorer.calculateRoyalties(front, 'front')
                  : 0,
            ),
            // Summary: total row wins + total royalties
            if (_showResult)
              _buildResultSummaryRow(
                frontWins + middleWins + backWins,
                frontLosses + middleLosses + backLosses,
                (front.length == 3
                        ? OFCScorer.calculateRoyalties(front, 'front')
                        : 0) +
                    (middle.length == 5
                        ? OFCScorer.calculateRoyalties(middle, 'middle')
                        : 0) +
                    (back.length == 5
                        ? OFCScorer.calculateRoyalties(back, 'back')
                        : 0),
              ),
          ],
        ),
      ),
    );
  }

  /// Summary row showing total wins/losses + royalties
  Widget _buildResultSummaryRow(
    int totalWins,
    int totalLosses,
    int totalRoyalty,
  ) {
    if (totalWins == 0 && totalLosses == 0 && totalRoyalty == 0)
      return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (totalWins > 0 || totalLosses > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ชนะ $totalWins กอง / แพ้ $totalLosses กอง',
                style: TextStyle(
                  color: totalWins > totalLosses
                      ? Colors.greenAccent
                      : Colors.red.shade300,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (totalRoyalty > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '✨ รอยัลตี้รวม +$totalRoyalty แต้ม',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Single card row with hand name label + win/lose indicator + royalty per row
  Widget _buildDetailedCardRow(
    String label,
    List<String> cards,
    String handName,
    bool revealed,
    int wins,
    int losses,
    int royalty,
  ) {
    const cardW = 30.0;
    const cardH = 42.0;
    final int count = cards.isNotEmpty
        ? cards.length
        : (label == 'กองหน้า' ? 3 : 5);

    // Row result indicator
    String rowResult = '';
    Color rowResultColor = Colors.white54;
    if (revealed && _showResult && (wins > 0 || losses > 0)) {
      if (wins > losses) {
        rowResult = '✓ ชนะ $wins';
        rowResultColor = Colors.greenAccent;
      } else if (losses > wins) {
        rowResult = '✗ แพ้ $losses';
        rowResultColor = Colors.red.shade300;
      } else {
        rowResult = '= เสมอ';
        rowResultColor = Colors.amber;
      }
    }

    // Royalty name mapping
    String royaltyLabel = '';
    if (revealed && royalty > 0) {
      if (label == 'กองหน้า') {
        if (handName.contains('ตอง'))
          royaltyLabel = 'ตอง';
        else
          royaltyLabel = 'คู่สูง';
      } else if (label == 'กองกลาง') {
        if (royalty >= 50)
          royaltyLabel = 'รอยัลฟลัช';
        else if (royalty >= 30)
          royaltyLabel = 'สเตรทฟลัช';
        else if (royalty >= 20)
          royaltyLabel = 'โฟร์';
        else if (royalty >= 12)
          royaltyLabel = 'ฟูลเฮาส์';
        else if (royalty >= 8)
          royaltyLabel = 'ฟลัช';
        else if (royalty >= 4)
          royaltyLabel = 'สเตรท';
        else if (royalty >= 2)
          royaltyLabel = 'ตอง';
      } else {
        // กองหลัง
        if (royalty >= 25)
          royaltyLabel = 'รอยัลฟลัช';
        else if (royalty >= 15)
          royaltyLabel = 'สเตรทฟลัช';
        else if (royalty >= 10)
          royaltyLabel = 'โฟร์';
        else if (royalty >= 6)
          royaltyLabel = 'ฟูลเฮาส์';
        else if (royalty >= 4)
          royaltyLabel = 'ฟลัช';
        else if (royalty >= 2)
          royaltyLabel = 'สเตรท';
      }
    }

    return Row(
      children: [
        // Row label + hand name + result + royalty
        SizedBox(
          width: 62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: const Color(0xFFDAA520).withOpacity(0.8),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (revealed && handName.isNotEmpty)
                Text(
                  handName,
                  style: const TextStyle(
                    color: Color(0xFF4ADE80),
                    fontSize: 7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (rowResult.isNotEmpty)
                Text(
                  rowResult,
                  style: TextStyle(
                    color: rowResultColor,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              if (revealed && royalty > 0)
                Text(
                  '✨ $royaltyLabel +$royalty',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
        // Cards
        Expanded(
          child: Wrap(
            spacing: 2,
            children: [
              if (cards.isNotEmpty)
                ...cards.map(
                  (card) => revealed
                      ? PlayingCard(
                          card: card,
                          faceUp: true,
                          width: cardW,
                          height: cardH,
                        )
                      : PlayingCard(
                          card: '??',
                          faceUp: false,
                          width: cardW,
                          height: cardH,
                        ),
                )
              else
                for (int i = 0; i < count; i++)
                  PlayingCard(
                    card: '??',
                    faceUp: false,
                    width: cardW,
                    height: cardH,
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitArrangement(BoxConstraints constraints) {
    // Calculate responsive card size — increased
    final availableWidth =
        constraints.maxWidth - 64; // minus left label (48) + padding
    final availableHeight =
        constraints.maxHeight - 100; // extra space for per-row labels
    // Card width: fit 5 cards in a row with spacing
    final cardW = ((availableWidth - 20) / 5).clamp(36.0, 52.0);
    // Card height
    final rowCount = _hand.isNotEmpty ? 4.2 : 3.2;
    final maxCardHByHeight = (availableHeight / rowCount - 20).clamp(
      46.0,
      70.0,
    );
    final cardH = (cardW * 1.4).clamp(46.0, maxCardHByHeight);
    final finalCardW = cardH / 1.4;
    final handCardW = (finalCardW - 2).clamp(30.0, 44.0);
    final handCardH = handCardW * 1.4;

    return Column(
      children: [
        // Header
        _buildArrangementHeader(),
        // Foul/Valid status indicator
        if (_canConfirm) _buildFoulIndicator(),
        // Card slots — centered
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPopupSlotRowWithLabel(
                _front,
                3,
                'front',
                'หน้า (3)',
                finalCardW,
                cardH,
              ),
              const SizedBox(height: 5),
              _buildPopupSlotRowWithLabel(
                _middle,
                5,
                'middle',
                'กลาง (5)',
                finalCardW,
                cardH,
              ),
              const SizedBox(height: 5),
              _buildPopupSlotRowWithLabel(
                _back,
                5,
                'back',
                'หลัง (5)',
                finalCardW,
                cardH,
              ),
              if (_hand.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'กดไพ่เพื่อวาง / ลากไพ่ไปวางในกอง',
                  style: TextStyle(color: Colors.white54, fontSize: 8),
                ),
                const SizedBox(height: 3),
                _buildHandCardsResponsive(handCardW, handCardH),
              ],
            ],
          ),
        ),
        // Buttons at bottom
        _buildArrangementButtons(),
      ],
    );
  }

  Widget _buildLandscapeArrangement(BoxConstraints constraints) {
    // Calculate responsive card size — reduced two levels
    final availableHeight = constraints.maxHeight - 60;
    final rowCount = _hand.isNotEmpty ? 4.2 : 3.2;
    final maxCardH = (availableHeight / rowCount - 12).clamp(42.0, 68.0);
    final cardH = maxCardH;
    final cardW = cardH / 1.4;
    final handCardW = (cardW - 4).clamp(28.0, 44.0);
    final handCardH = handCardW * 1.4;

    return Row(
      children: [
        // Card slots (left side — takes most space)
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                _buildSideSwapIndicator(),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildArrangementHeader(),
                      if (_canConfirm) _buildFoulIndicator(),
                      const SizedBox(height: 4),
                      _buildPopupSlotRowWithLabel(
                        _front,
                        3,
                        'front',
                        'หน้า (3)',
                        cardW,
                        cardH,
                      ),
                      const SizedBox(height: 4),
                      _buildPopupSlotRowWithLabel(
                        _middle,
                        5,
                        'middle',
                        'กลาง (5)',
                        cardW,
                        cardH,
                      ),
                      const SizedBox(height: 4),
                      _buildPopupSlotRowWithLabel(
                        _back,
                        5,
                        'back',
                        'หลัง (5)',
                        cardW,
                        cardH,
                      ),
                      if (_hand.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _buildHandCardsResponsive(handCardW, handCardH),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Buttons (right side — vertical)
        SizedBox(
          width: 80,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildVerticalBtn('← ออก', Colors.grey.shade700, _exitGame),
                const SizedBox(height: 12),
                _buildVerticalBtn(
                  'เรียงใหม่',
                  Colors.green.shade700,
                  _reArrangeCards,
                ),
                const SizedBox(height: 12),
                _buildVerticalBtn(
                  '✓ พร้อม',
                  _canConfirm ? const Color(0xFFDAA520) : Colors.grey,
                  _canConfirm ? _confirmArrangement : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArrangementHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Text(
            'จัดไพ่ 3 กอง',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _turnSeconds > 10
                  ? Colors.green.shade700
                  : Colors.red.shade700,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '⏱ $_turnSeconds',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows foul/valid status and royalty points with detailed explanation
  Widget _buildFoulIndicator() {
    final isFoul = OFCScorer.isFoul(_front, _middle, _back);
    // Get hand names
    final backName = _back.length == 5 ? _getHandName(_back, 'back') : '';
    final middleName = _middle.length == 5
        ? _getHandName(_middle, 'middle')
        : '';
    final frontName = _front.length == 3 ? _getHandName(_front, 'front') : '';

    // Calculate royalties
    int royalty = 0;
    if (!isFoul) {
      if (_back.length == 5)
        royalty += OFCScorer.calculateRoyalties(_back, 'back');
      if (_middle.length == 5)
        royalty += OFCScorer.calculateRoyalties(_middle, 'middle');
      if (_front.length == 3)
        royalty += OFCScorer.calculateRoyalties(_front, 'front');
    }

    // Determine foul reason
    String foulReason = '';
    if (isFoul) {
      // Check which comparison fails
      if (_front.length == 3 && _middle.length == 5) {
        final frontRank = HandEvaluator.evaluate3(_front);
        final middleRank = HandEvaluator.evaluate5(_middle);
        if (frontRank.rank >= middleRank.rank) {
          foulReason = 'หน้า($frontName) ≥ กลาง($middleName)';
        }
      }
      if (foulReason.isEmpty && _middle.length == 5 && _back.length == 5) {
        final middleRank = HandEvaluator.evaluate5(_middle);
        final backRank = HandEvaluator.evaluate5(_back);
        if (HandEvaluator.compare(middleRank, backRank) >= 0) {
          foulReason = 'กลาง($middleName) ≥ หลัง($backName)';
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isFoul
                ? [const Color(0xFFC62828), const Color(0xFF8B0000)]
                : [const Color(0xFF1B5E20), const Color(0xFF2E7D32)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFoul ? Colors.red.shade300 : Colors.green.shade300,
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isFoul ? Icons.warning_rounded : Icons.check_circle,
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  isFoul ? '❌ ฟาวล์!' : '✅ เรียงถูกต้อง',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!isFoul && royalty > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '✨ โบนัส +$royalty',
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
            const SizedBox(height: 2),
            if (isFoul && foulReason.isNotEmpty)
              Text(
                foulReason,
                style: const TextStyle(
                  color: Colors.yellow,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              )
            else if (!isFoul)
              Text(
                'หลัง($backName) > กลาง($middleName) > หน้า($frontName)',
                style: const TextStyle(color: Colors.white70, fontSize: 8),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  /// Evaluates and returns the hand name for a row
  String _getHandName(List<String> cards, String row) {
    try {
      if (row == 'front' && cards.length == 3) {
        return HandEvaluator.evaluate3(cards).nameTh;
      } else if (cards.length == 5) {
        return HandEvaluator.evaluate5(cards).nameTh;
      }
    } catch (_) {}
    return '';
  }

  /// Slot row with hand evaluation label and foul status per row
  Widget _buildPopupSlotRowWithLabel(
    List<String> cards,
    int max,
    String row,
    String label,
    double cardW,
    double cardH,
  ) {
    final handName = _getHandName(cards, row);
    final isFull =
        (row == 'front' && cards.length == 3) ||
        (row != 'front' && cards.length == 5);
    // Calculate royalty for this specific row
    int rowRoyalty = 0;
    if (isFull) {
      rowRoyalty = OFCScorer.calculateRoyalties(cards, row);
    }

    // Check per-row foul status
    String rowError = '';
    bool rowHasError = false;
    if (_canConfirm) {
      if (row == 'front' && _front.length == 3 && _middle.length == 5) {
        final frontRank = HandEvaluator.evaluate3(_front);
        final middleRank = HandEvaluator.evaluate5(_middle);
        if (_compare3vs5ForUI(frontRank, middleRank) >= 0) {
          rowError = '≥ กลาง!';
          rowHasError = true;
        }
      } else if (row == 'middle' && _middle.length == 5 && _back.length == 5) {
        final middleRank = HandEvaluator.evaluate5(_middle);
        final backRank = HandEvaluator.evaluate5(_back);
        if (HandEvaluator.compare(middleRank, backRank) >= 0) {
          rowError = '≥ หลัง!';
          rowHasError = true;
        }
      } else if (row == 'back' && _middle.length == 5 && _back.length == 5) {
        final middleRank = HandEvaluator.evaluate5(_middle);
        final backRank = HandEvaluator.evaluate5(_back);
        if (HandEvaluator.compare(middleRank, backRank) >= 0) {
          rowError = '≤ กลาง!';
          rowHasError = true;
        }
      }
    }

    // Left label widget
    Widget leftLabel = SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label.split(' ').first,
            style: TextStyle(
              color: rowHasError ? Colors.red.shade300 : Colors.white54,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (isFull && handName.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              handName,
              style: TextStyle(
                color: rowHasError
                    ? Colors.red.shade300
                    : (rowRoyalty > 0
                          ? const Color(0xFFFFD700)
                          : Colors.white70),
                fontSize: 7,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (rowRoyalty > 0 && !rowHasError)
              Text(
                '+$rowRoyalty',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                ),
              ),
            if (rowHasError)
              Text(
                rowError,
                style: TextStyle(
                  color: Colors.red.shade300,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
          if (isFull &&
              !rowHasError &&
              _canConfirm &&
              !OFCScorer.isFoul(_front, _middle, _back))
            const Icon(Icons.check_circle, color: Colors.green, size: 10),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        leftLabel,
        _buildPopupSlotRow(cards, max, row, label, cardW, cardH),
      ],
    );
  }

  /// Compare 3-card vs 5-card for UI foul detection
  int _compare3vs5ForUI(HandRank front3, HandRank middle5) {
    if (front3.rank != middle5.rank) return front3.rank - middle5.rank;
    final len = front3.kickers.length < middle5.kickers.length
        ? front3.kickers.length
        : middle5.kickers.length;
    for (var i = 0; i < len; i++) {
      if (front3.kickers[i] != middle5.kickers[i])
        return front3.kickers[i] - middle5.kickers[i];
    }
    return 0;
  }

  /// Center banner animation (for "เริ่ม!" and "VS")
  Widget _buildCenterBanner(String text, Color color) {
    return IgnorePointer(
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(
              scale: 0.5 + v * 0.5,
              child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Side swap indicator — single vertical arrow with label on the side
  Widget _buildSideSwapIndicator() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.swap_vert_rounded,
          color: Colors.white.withOpacity(0.5),
          size: 22,
        ),
        const SizedBox(height: 2),
        RotatedBox(
          quarterTurns: 3,
          child: Text(
            'ลากสลับ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  /// Swap arrows indicator between rows (kept for compatibility)
  Widget _buildSwapArrows() {
    return const SizedBox(height: 3);
  }

  Widget _buildHandCards() {
    return _buildHandCardsResponsive(50, 70);
  }

  Widget _buildHandCardsResponsive(double cardW, double cardH) {
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      alignment: WrapAlignment.center,
      children: [
        for (int i = 0; i < _hand.length; i++)
          Draggable<Map<String, dynamic>>(
            data: {'card': _hand[i], 'row': 'hand', 'index': i},
            feedback: Material(
              color: Colors.transparent,
              child: Transform.scale(
                scale: 1.1,
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
            child: GestureDetector(
              onTap: () => _placeCard(_hand[i], _activeRow),
              child: PlayingCard(
                card: _hand[i],
                faceUp: true,
                width: cardW,
                height: cardH,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildArrangementButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Exit button
          GestureDetector(
            onTap: _exitGame,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '← ออก',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: _canConfirm ? _confirmArrangement : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: _canConfirm
                      ? const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFDAA520)],
                        )
                      : null,
                  color: _canConfirm ? null : Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '✓ พร้อม',
                    style: TextStyle(
                      color: _canConfirm ? Colors.black : Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: _reArrangeCards,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'เรียงใหม่',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
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

  Widget _buildVerticalBtn(String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// A slot row in the popup — large cards with drag support
  Widget _buildPopupSlotRow(
    List<String> cards,
    int max,
    String row,
    String label, [
    double cardW = 56,
    double cardH = 78,
  ]) {
    final isActive = _activeRow == row && _hand.isNotEmpty;
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (_) =>
          true, // Always accept — we handle swap logic
      onAcceptWithDetails: (details) {
        final data = details.data;
        final draggedCard = data['card'] as String;
        final fromRow = data['row'] as String?;
        final fromIndex = data['index'] as int?;

        setState(() {
          // Same row — swap positions within the row
          if (fromRow == row && fromIndex != null) {
            final targetIdx = cards.length - 1; // swap with last position
            if (fromIndex < cards.length && fromIndex != targetIdx) {
              final temp = cards[targetIdx];
              cards[targetIdx] = cards[fromIndex];
              cards[fromIndex] = temp;
            }
            return;
          }

          // Different row — remove from source
          if (fromRow != null && fromIndex != null) {
            switch (fromRow) {
              case 'front':
                if (fromIndex < _front.length) _front.removeAt(fromIndex);
              case 'middle':
                if (fromIndex < _middle.length) _middle.removeAt(fromIndex);
              case 'back':
                if (fromIndex < _back.length) _back.removeAt(fromIndex);
              case 'hand':
                _hand.remove(draggedCard);
            }
          } else {
            _hand.remove(draggedCard);
          }

          // Get target row list and max
          List<String> targetList;
          switch (row) {
            case 'front':
              targetList = _front;
            case 'middle':
              targetList = _middle;
            case 'back':
              targetList = _back;
            default:
              targetList = _back;
          }

          if (targetList.length < max) {
            // Row has space — just add
            targetList.add(draggedCard);
          } else {
            // Row full — swap: put displaced card back to SOURCE row
            final swapped = targetList.removeLast();
            targetList.add(draggedCard);
            if (fromRow != null && fromRow != 'hand' && fromRow != row) {
              switch (fromRow) {
                case 'front':
                  _front.insert(
                    fromIndex! < _front.length ? fromIndex : _front.length,
                    swapped,
                  );
                case 'middle':
                  _middle.insert(
                    fromIndex! < _middle.length ? fromIndex : _middle.length,
                    swapped,
                  );
                case 'back':
                  _back.insert(
                    fromIndex! < _back.length ? fromIndex : _back.length,
                    swapped,
                  );
              }
            } else {
              _hand.add(swapped);
            }
          }

          // Update active row
          if (_back.length < 5)
            _activeRow = 'back';
          else if (_middle.length < 5)
            _activeRow = 'middle';
          else if (_front.length < 3)
            _activeRow = 'front';
        });
      },
      builder: (ctx, candidate, _) {
        final dragOver = candidate.isNotEmpty;
        return GestureDetector(
          onTap: () => setState(() => _activeRow = row),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: dragOver
                    ? Colors.greenAccent
                    : isActive
                    ? Colors.amber
                    : Colors.white.withOpacity(0.15),
                width: dragOver
                    ? 2
                    : isActive
                    ? 2
                    : 1,
              ),
              color: dragOver
                  ? Colors.greenAccent.withOpacity(0.05)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < max; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: i < cards.length
                        ? _buildDraggableSlotCard(
                            cards[i],
                            row,
                            i,
                            cardW,
                            cardH,
                          )
                        : Container(
                            width: cardW,
                            height: cardH,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1.5,
                              ),
                              color: Colors.white.withOpacity(0.02),
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

  /// Individual card DragTarget — allows within-row reordering
  Widget _buildDraggableSlotCard(
    String card,
    String row,
    int index,
    double cardW,
    double cardH,
  ) {
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) {
        // Accept cards from same row for reordering
        return details.data['row'] == row && details.data['index'] != index;
      },
      onAcceptWithDetails: (details) {
        final fromIndex = details.data['index'] as int;
        setState(() {
          // Swap within same row
          List<String> rowList;
          switch (row) {
            case 'front':
              rowList = _front;
            case 'middle':
              rowList = _middle;
            case 'back':
              rowList = _back;
            default:
              return;
          }
          if (fromIndex < rowList.length && index < rowList.length) {
            final temp = rowList[index];
            rowList[index] = rowList[fromIndex];
            rowList[fromIndex] = temp;
          }
        });
      },
      builder: (ctx, candidate, _) {
        final dragOver = candidate.isNotEmpty;
        return Draggable<Map<String, dynamic>>(
          data: {'card': card, 'row': row, 'index': index},
          feedback: Material(
            color: Colors.transparent,
            child: Transform.scale(
              scale: 1.2,
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
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: Colors.amber.withOpacity(0.4),
                width: 1.5,
              ),
              color: Colors.amber.withOpacity(0.05),
            ),
          ),
          child: Container(
            decoration: dragOver
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.greenAccent, width: 2),
                  )
                : null,
            child: GestureDetector(
              onTap: () => _removeCard(row, index),
              child: PlayingCard(
                card: card,
                faceUp: true,
                width: cardW,
                height: cardH,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build the game table using the shared TableSeatLayout widget.
  /// This ensures consistent player positioning in ALL phases.
  Widget _buildGameTable() {
    // Spectator sees all players; joined player sees others as opponents
    final others = _isSpectating
        ? _players.entries.toList()
        : _players.entries.where((e) => e.key != _mySeat).toList();
    final opponentWidgets = others
        .map((e) => _buildOpponent(e.value, e.key))
        .toList();

    debugPrint(
      '🖼️ [OFC] _buildGameTable: phase=$_phase, showResult=$_showResult, opponents=${others.length}, hand=${_hand.length}, front=${_front.length}, middle=${_middle.length}, back=${_back.length}',
    );

    // Center content depends on phase
    Widget? centerContent;
    if (_showResult || _showdownActive || _chipAnimationInProgress) {
      debugPrint(
        '🖼️ [OFC] → Rendering RESULT phase (cards shown next to avatars)',
      );
      centerContent = null;
    } else if (_phase == 'result') {
      debugPrint(
        '🖼️ [OFC] → Rendering RESULT phase (waiting for showResult flag)',
      );
      centerContent = null;
    } else if (_isArranging || _phase == 'placing') {
      debugPrint('🖼️ [OFC] → Rendering ARRANGING phase (popup overlay)');
      // Card arrangement is now a full-screen popup overlay — no center content needed
      centerContent = null;
    } else if (_phase == 'waiting') {
      debugPrint('🖼️ [OFC] → Rendering WAITING phase');
      centerContent = const Center(
        child: Text(
          'รอผู้เล่น...',
          style: TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    } else {
      debugPrint('🖼️ [OFC] → Unknown phase: $_phase');
    }

    // Overlay widgets — no action buttons needed (popup has its own)
    final overlays = <Widget>[];

    return TableSeatLayout(
      opponentWidgets: opponentWidgets,
      myWidget: _isSpectating ? const SizedBox.shrink() : _buildMySection(),
      centerWidget: centerContent,
      dealerWidget: null,
      overlayWidgets: overlays,
      seatWidth: 180.0,
      seatHeight: 170.0,
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

  /// My section at the bottom — shows my info during result, or name/chips otherwise
  Widget _buildMySection() {
    final myCoinChange = _coinChanges[_mySeat] ?? 0;
    final myData = _players[_mySeat] ?? {};
    final username = myData['username'] ?? 'คุณ';

    // Get my result data for revealed cards
    final myResult = (_showResult || _showdownActive)
        ? _resultData.where((r) => r['seat'] == _mySeat).firstOrNull
        : null;

    // Build my cards data — use result data if available, otherwise use local state
    Map<String, dynamic>? myCardsForDisplay;
    if ((_showResult ||
            _showdownActive ||
            _showTableResult ||
            _chipAnimationInProgress) &&
        !_showResultPopup) {
      if (myResult != null &&
          myResult['front'] is List &&
          (myResult['front'] as List).isNotEmpty) {
        myCardsForDisplay = myResult;
      } else if (_front.isNotEmpty || _middle.isNotEmpty || _back.isNotEmpty) {
        myCardsForDisplay = {
          'seat': _mySeat,
          'front': _front,
          'middle': _middle,
          'back': _back,
        };
      }
    } else if (_myReady &&
        _isArranging &&
        (_front.isNotEmpty || _middle.isNotEmpty || _back.isNotEmpty)) {
      myCardsForDisplay = {
        'seat': _mySeat,
        'front': _front,
        'middle': _middle,
        'back': _back,
      };
    }

    // During result — show avatar + cards + score
    if (myCardsForDisplay != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showResult && myCoinChange != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: myCoinChange > 0
                      ? [const Color(0xFFFFD700), const Color(0xFFDAA520)]
                      : [const Color(0xFFC62828), const Color(0xFF8B0000)],
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color:
                        (myCoinChange > 0
                                ? const Color(0xFFFFD700)
                                : Colors.red)
                            .withOpacity(0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                myCoinChange > 0 ? '+$myCoinChange' : '$myCoinChange',
                style: TextStyle(
                  color: myCoinChange > 0 ? Colors.black : Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Yellow glow for winner
                      if (_showResult && myCoinChange > 0)
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withOpacity(0.8),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      PlayerAvatar3D(
                        size: 30,
                        borderColor: _showResult && myCoinChange > 0
                            ? const Color(0xFFFFD700)
                            : const Color(0xFFDAA520),
                      ),
                      // "ชนะ" overlay
                      if (_showResult && myCoinChange > 0)
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFFD700).withOpacity(0.7),
                          ),
                          child: const Center(
                            child: Text('🏆', style: TextStyle(fontSize: 14)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (_showResult && myCoinChange > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'ชนะ',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  else
                    Text(
                      username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              _buildOpponentRevealedCards(myCardsForDisplay),
            ],
          ),
        ],
      );
    }

    // During arranging — show avatar with ready/countdown status
    if (_isArranging) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (!_myReady)
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    value: _turnSeconds / 30.0,
                    strokeWidth: 3,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _turnSeconds > 10
                          ? Colors.greenAccent
                          : _turnSeconds > 5
                          ? Colors.amber
                          : Colors.redAccent,
                    ),
                  ),
                ),
              PlayerAvatar3D(
                size: 40,
                borderColor: _myReady
                    ? Colors.greenAccent
                    : const Color(0xFFDAA520),
                overlay: _myReady
                    ? Container(
                        color: Colors.green.withOpacity(0.7),
                        child: const Icon(
                          Icons.check,
                          size: 18,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (_myReady) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '✓ พร้อม',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 3),
            // Face-down cards (3 rows: 3+5+5) showing my arrangement is locked
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: PlayingCard(
                      card: '??',
                      faceUp: false,
                      width: 10,
                      height: 14,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: PlayingCard(
                      card: '??',
                      faceUp: false,
                      width: 10,
                      height: 14,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: PlayingCard(
                      card: '??',
                      faceUp: false,
                      width: 10,
                      height: 14,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 2),
          Text(
            username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'C${NumberFormatter.formatAbbreviated(_myChips)}',
            style: const TextStyle(color: Color(0xFFDAA520), fontSize: 7),
          ),
        ],
      );
    }

    // Default state (waiting/dealing)
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerAvatar3D(size: 40, borderColor: const Color(0xFFDAA520)),
        const SizedBox(height: 2),
        Text(
          username,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'C${NumberFormatter.formatAbbreviated(_myChips)}',
          style: const TextStyle(color: Color(0xFFDAA520), fontSize: 7),
        ),
      ],
    );
  }

  Widget _buildDealOverlay() {
    final totalCards = _dealtCards.length + _pendingDealCards.length;
    final dealt = _dealtCards.length;
    final playerCount = _players.length; // total players including me

    // Calculate which player is receiving the current card (round-robin)
    final currentPlayerIdx = dealt % playerCount.clamp(1, 9);

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // Card stack at dealer position (top center)
            Positioned(
              top: MediaQuery.of(context).padding.top + 40,
              left: 0,
              right: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated card stack shrinking as cards are dealt
                    SizedBox(
                      width: 60,
                      height: 80,
                      child: Stack(
                        children: [
                          for (
                            int i = 0;
                            i < (_pendingDealCards.length.clamp(0, 6));
                            i++
                          )
                            Positioned(
                              left: i * 1.5,
                              top: i * 1.0,
                              child: Container(
                                width: 44,
                                height: 62,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFCC2222),
                                      Color(0xFF8B0000),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFFDAA520),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 3,
                                      offset: const Offset(1, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Progress: show dealing to each player
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'แจกไพ่ $dealt/$totalCards',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Show card flying to each player's avatar position
            for (int i = 0; i < _players.length; i++)
              if (i == currentPlayerIdx) _buildFlyingCardIndicator(i),
          ],
        ),
      ),
    );
  }

  /// Shows a small card indicator near each player during dealing
  Widget _buildFlyingCardIndicator(int playerIdx) {
    // Position based on player index — simplified center indicator
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 60),
        builder: (context, value, child) {
          return Opacity(
            opacity: (1.0 - value).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.8 + value * 0.3,
              child: Container(
                width: 30,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFCC2222), Color(0xFF8B0000)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: const Color(0xFFDAA520),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShuffleOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedWidget2(
          listenable: _shuffleAnim,
          builder: (context) {
            final t = _shuffleAnim.value;
            return Stack(
              alignment: Alignment.topCenter,
              children: [
                // Semi-transparent backdrop
                Container(color: Colors.black.withOpacity(0.3 * t)),
                // Shuffle card stack animation — at dealer position (top center)
                Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 50,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: _buildShuffleCards(t),
                  ),
                ),
                // Label
                Positioned(
                  top: MediaQuery.of(context).padding.top + 150,
                  child: Opacity(
                    opacity: (t * 2).clamp(0.0, 1.0),
                    child: const Text(
                      '🔀 สับไพ่...',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildShuffleCards(double t) {
    final cards = <Widget>[];
    const cardW = 56.0;
    const cardH = 80.0;
    const totalCards = 10;

    for (int i = 0; i < totalCards; i++) {
      // Each card has a phase offset for staggered shuffle effect
      final phase = (i / totalCards);
      final cardT = ((t * 3) - phase).clamp(0.0, 1.0);

      // Shuffle motion: cards split left/right then merge back
      final cycle = (cardT * pi * 2);
      final isLeft = i % 2 == 0;
      final spreadX = sin(cycle) * (isLeft ? -40.0 : 40.0) * (1 - cardT * 0.5);
      final spreadY = cos(cycle * 0.5) * 8.0;
      final rotation = sin(cycle) * 0.15 * (isLeft ? -1 : 1);
      final verticalOffset = -sin(cardT * pi) * 20;

      cards.add(
        Positioned(
          child: Transform.translate(
            offset: Offset(spreadX, spreadY + verticalOffset),
            child: Transform.rotate(
              angle: rotation,
              child: Container(
                width: cardW,
                height: cardH,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFCC1111),
                      Color(0xFF8B0000),
                      Color(0xFF5C0000),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFDAA520).withOpacity(0.7),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(2, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: cardW * 0.6,
                    height: cardH * 0.7,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: const Color(0xFFDAA520).withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '♠',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFFDAA520),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return cards;
  }

  /// A single player's result display — same size for everyone
  Widget _buildResultPlayer(
    Map<String, dynamic> p,
    int seat, {
    bool isMe = false,
  }) {
    final coinChange = _coinChanges[seat] ?? 0;
    final isWin = coinChange > 0;
    final isLose = coinChange < 0;
    final username = p['username'] ?? '?';
    final opResult = _resultData.where((r) => r['seat'] == seat).firstOrNull;

    final front = List<String>.from(opResult?['front'] ?? []);
    final middle = List<String>.from(opResult?['middle'] ?? []);
    final back = List<String>.from(opResult?['back'] ?? []);

    // Same card size for all players — larger
    const cardW = 30.0;
    const cardH = 42.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Win/Lose badge
        if (coinChange != 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isWin
                    ? [const Color(0xFF2E7D32), const Color(0xFF1B5E20)]
                    : [const Color(0xFFC62828), const Color(0xFF8B0000)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isWin ? 'ชนะ!' : 'แพ้',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),

        // 3 stacked fans — back on top (z-order)
        SizedBox(
          width: 140,
          height: 105,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                bottom: 46,
                child: _buildMiniFan(
                  front,
                  spreadX: 6.5,
                  angle: 0.06,
                  cardW: cardW * 0.85,
                  cardH: cardH * 0.85,
                ),
              ),
              Positioned(
                bottom: 23,
                child: _buildMiniFan(
                  middle,
                  spreadX: 6.0,
                  angle: 0.07,
                  cardW: cardW * 0.92,
                  cardH: cardH * 0.92,
                ),
              ),
              Positioned(
                bottom: 0,
                child: _buildMiniFan(
                  back,
                  spreadX: 6.5,
                  angle: 0.08,
                  cardW: cardW,
                  cardH: cardH,
                ),
              ),
            ],
          ),
        ),

        // Avatar + name + chips
        const SizedBox(height: 3),
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
          'C${NumberFormatter.formatAbbreviated(p['chips'] ?? 0)}',
          style: const TextStyle(color: Color(0xFFDAA520), fontSize: 8),
        ),
        // Score badge
        if (coinChange != 0)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (isWin ? Colors.green : Colors.red).withOpacity(0.25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'ทั้งหมด ${coinChange > 0 ? "+" : ""}$coinChange',
              style: TextStyle(
                color: isWin ? Colors.greenAccent : Colors.red,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLeftPanel() {
    final others = _players.entries.where((e) => e.key != _mySeat).toList();
    final half = (others.length / 2).ceil();
    final leftOpponents = others.take(half).toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Opponents
        for (final o in leftOpponents) ...[
          _buildOpponent(o.value, o.key),
          const SizedBox(height: 6),
        ],
        // Action buttons (when arranging)
        if (_isArranging && _hasJoined && _canConfirm) ...[
          const SizedBox(height: 10),
          _buildActionButtons(),
        ],
      ],
    );
  }

  Widget _buildRightPanel() {
    final others = _players.entries.where((e) => e.key != _mySeat).toList();
    final half = (others.length / 2).ceil();
    final rightOpponents = others.skip(half).toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Timer
        if (_isArranging) ...[_buildTimer(), const SizedBox(height: 12)],
        // Opponents
        for (final o in rightOpponents) ...[
          _buildOpponent(o.value, o.key),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  /// Vertical action buttons (like reference: เรียงใหม่, พร้อม)
  Widget _buildActionButtons() {
    final isFoul = OFCScorer.isFoul(_front, _middle, _back);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Re-arrange
        GestureDetector(
          onTap: _reArrangeCards,
          child: Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E6B30), Color(0xFF1A4520)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Text(
                'เรียงใหม่',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Confirm
        GestureDetector(
          onTap: isFoul ? null : _confirmArrangement,
          child: Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              gradient: isFoul
                  ? null
                  : const LinearGradient(
                      colors: [Color(0xFFDAA520), Color(0xFFB8860B)],
                    ),
              color: isFoul ? Colors.grey.shade700 : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                isFoul ? 'ฟาวล์!' : 'พร้อม',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  // TOP BAR
  // ═══════════════════════════════════════════════

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.portraitUp,
              ]);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LobbyScreen()),
              );
            },
            child: const Icon(
              Icons.arrow_back_ios,
              color: Color(0xFFFFD700),
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFDAA520), Color(0xFFB8860B)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'OFC',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.table['name'] ?? 'ไพ่สามกอง',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (_isArranging)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
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
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2A0A0A), Color(0xFF1A0505)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFDAA520).withOpacity(0.3),
              ),
            ),
            child: Text(
              'C${NumberFormatter.formatAbbreviated(_myChips)}',
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // SIDE OPPONENTS
  // ═══════════════════════════════════════════════

  Widget _buildTimer() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFDAA520)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 10),
        ],
      ),
      child: Center(
        child: Text(
          '$_turnSeconds',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildOpponent(Map<String, dynamic> p, int seat) {
    final arranged = p['arranged'] as Map<String, dynamic>?;
    final isReady = arranged != null || p['isReady'] == true;
    final username = p['username'] ?? '?';
    final coinChange = _coinChanges[seat] ?? 0;
    final isWin = (_showResult || _chipAnimationInProgress) && coinChange > 0;
    final isLose = (_showResult || _chipAnimationInProgress) && coinChange < 0;

    // Get result data for this opponent (during showdown or result or chip animation)
    final opResult =
        (_showResult || _showdownActive || _chipAnimationInProgress)
        ? _resultData.where((r) => r['seat'] == seat).firstOrNull
        : null;

    // During result/showdown/table result/chip animation — show avatar + revealed cards side by side
    if ((_showResult ||
            _showdownActive ||
            _showTableResult ||
            _chipAnimationInProgress) &&
        !_showResultPopup &&
        opResult != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Coin change badge — LEFT side of avatar
          if (coinChange != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isWin
                      ? [const Color(0xFFFFD700), const Color(0xFFDAA520)]
                      : [const Color(0xFFC62828), const Color(0xFF8B0000)],
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: (isWin ? const Color(0xFFFFD700) : Colors.red)
                        .withOpacity(0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isWin ? '+$coinChange' : '$coinChange',
                    style: TextStyle(
                      color: isWin ? Colors.black : Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_showResult)
                    Text(
                      isWin ? 'ชนะ' : 'แพ้',
                      style: TextStyle(
                        color: isWin ? Colors.black : Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          // Avatar + cards column
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar with winner highlight
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_showResult && isWin)
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFFD700,
                                    ).withOpacity(0.8),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          PlayerAvatar3D(
                            size: 30,
                            borderColor: _showResult && isWin
                                ? const Color(0xFFFFD700)
                                : isLose
                                ? Colors.red
                                : const Color(0xFFDAA520),
                          ),
                          if (_showResult && isWin)
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFFD700).withOpacity(0.7),
                              ),
                              child: const Center(
                                child: Text(
                                  '🏆',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (_showResult && isWin)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'ชนะ',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 7,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      else
                        Text(
                          username,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  // Cards to the right
                  _buildOpponentRevealedCards(opResult),
                ],
              ),
            ],
          ),
        ],
      );
    }

    // During arranging — show avatar with status overlay
    if (_isArranging) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with ready/countdown overlay
          Stack(
            alignment: Alignment.center,
            children: [
              // Countdown ring (when not ready)
              if (!isReady)
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    value: _turnSeconds / 30.0,
                    strokeWidth: 3,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _turnSeconds > 10
                          ? Colors.greenAccent
                          : _turnSeconds > 5
                          ? Colors.amber
                          : Colors.redAccent,
                    ),
                  ),
                ),
              PlayerAvatar3D(
                size: 42,
                borderColor: isReady
                    ? Colors.greenAccent
                    : const Color(0xFFDAA520),
                overlay: isReady
                    ? Container(
                        color: Colors.green.withOpacity(0.7),
                        child: const Icon(
                          Icons.check,
                          size: 20,
                          color: Colors.white,
                        ),
                      )
                    : Container(
                        color: Colors.black.withOpacity(0.5),
                        child: Center(
                          child: Text(
                            '$_turnSeconds',
                            style: TextStyle(
                              color: _turnSeconds > 10
                                  ? Colors.white
                                  : Colors.redAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Status label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isReady
                  ? Colors.green.withOpacity(0.3)
                  : Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isReady ? '✓ พร้อม' : 'กำลังจัด...',
              style: TextStyle(
                color: isReady ? Colors.greenAccent : Colors.amber,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          // Face-down cards (3 rows: 3+5+5) when ready
          if (isReady) ...[
            const SizedBox(height: 3),
            // Front row (3 cards)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: PlayingCard(
                      card: '??',
                      faceUp: false,
                      width: 10,
                      height: 14,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 1),
            // Middle row (5 cards)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: PlayingCard(
                      card: '??',
                      faceUp: false,
                      width: 10,
                      height: 14,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 1),
            // Back row (5 cards)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: PlayingCard(
                      card: '??',
                      faceUp: false,
                      width: 10,
                      height: 14,
                    ),
                  ),
              ],
            ),
          ],
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
          Text(
            'C${NumberFormatter.formatAbbreviated(p['chips'] ?? 0)}',
            style: const TextStyle(color: Color(0xFFDAA520), fontSize: 7),
          ),
        ],
      );
    }

    // Default state (waiting/dealing)
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerAvatar3D(
          size: 42,
          borderColor: const Color(0xFFDAA520),
          overlay: _isDealingAnimation
              ? Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Center(
                    child: Text(
                      '${_dealtCards.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )
              : null,
        ),
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
        Text(
          'C${NumberFormatter.formatAbbreviated(p['chips'] ?? 0)}',
          style: const TextStyle(color: Color(0xFFDAA520), fontSize: 7),
        ),
      ],
    );
  }

  /// Show opponent's revealed cards as 3 stacked fans (front/middle/back)
  Widget _buildOpponentRevealedCards(dynamic result) {
    // Handle both List<String> (actual cards) and int (card count) from server
    List<String> front;
    List<String> middle;
    List<String> back;

    final rawFront = result['front'];
    final rawMiddle = result['middle'];
    final rawBack = result['back'];

    if (rawFront is List) {
      front = List<String>.from(rawFront);
    } else {
      front = [];
    }
    if (rawMiddle is List) {
      middle = List<String>.from(rawMiddle);
    } else {
      middle = [];
    }
    if (rawBack is List) {
      back = List<String>.from(rawBack);
    } else {
      back = [];
    }

    // If no actual card data, show face-down cards based on count
    final int frontCount = front.isNotEmpty
        ? front.length
        : (rawFront is int ? rawFront : 3);
    final int middleCount = middle.isNotEmpty
        ? middle.length
        : (rawMiddle is int ? rawMiddle : 5);
    final int backCount = back.isNotEmpty
        ? back.length
        : (rawBack is int ? rawBack : 5);

    // Show cards based on showdown step (reveal row by row: front→middle→back)
    final showFront = _showdownStep >= 1 || !_showdownActive;
    final showMiddle = _showdownStep >= 2 || !_showdownActive;
    final showBack = _showdownStep >= 3 || !_showdownActive;

    // Card sizes — smaller when showing on table after popup closes (4 levels down)
    final double cW = _showTableResult ? 28.0 : 44.0;
    final double cH = _showTableResult ? 39.0 : 62.0;
    final double spread = _showTableResult ? 6.0 : 8.0;
    final double containerW = _showTableResult ? 90.0 : 120.0;
    final double containerH = _showTableResult ? 80.0 : 100.0;
    final double rowGap1 = _showTableResult ? 26.0 : 32.0;
    final double rowGap2 = _showTableResult ? 52.0 : 64.0;

    // Evaluate hand names + royalties + win/lose for animated labels
    String frontLabel = '';
    String middleLabel = '';
    String backLabel = '';
    int frontRoyalty = 0, middleRoyalty = 0, backRoyalty = 0;
    String frontResult = '', middleResult = '', backResult = '';

    if ((_showResult || (_showdownActive && _showdownStep >= 1)) &&
        !_showTableResult) {
      // Get seat number for this player
      final seat = result['seat'] as int? ?? 0;

      if (front.length == 3 && _showdownStep >= 1) {
        try {
          frontLabel = HandEvaluator.evaluate3(front).nameTh;
        } catch (_) {}
        frontRoyalty = OFCScorer.calculateRoyalties(front, 'front');
        frontResult = _getRowWinLose(front, 'front', seat);
      }
      if (middle.length == 5 && _showdownStep >= 2) {
        try {
          middleLabel = HandEvaluator.evaluate5(middle).nameTh;
        } catch (_) {}
        middleRoyalty = OFCScorer.calculateRoyalties(middle, 'middle');
        middleResult = _getRowWinLose(middle, 'middle', seat);
      }
      if (back.length == 5 && _showdownStep >= 3) {
        try {
          backLabel = HandEvaluator.evaluate5(back).nameTh;
        } catch (_) {}
        backRoyalty = OFCScorer.calculateRoyalties(back, 'back');
        backResult = _getRowWinLose(back, 'back', seat);
      }
    }

    return SizedBox(
      width: containerW,
      height: containerH,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Front row (top) — revealed last
          if (showFront && front.isNotEmpty)
            Positioned(
              top: 0,
              child: _buildMiniFan(
                front,
                spreadX: spread,
                angle: 0.04,
                cardW: cW * 0.9,
                cardH: cH * 0.9,
              ),
            )
          else
            Positioned(
              top: 0,
              child: _buildFaceDownFan(
                frontCount,
                spreadX: spread,
                cardW: cW * 0.9,
                cardH: cH * 0.9,
              ),
            ),
          // Middle row
          if (showMiddle && middle.isNotEmpty)
            Positioned(
              top: rowGap1,
              child: _buildMiniFan(
                middle,
                spreadX: spread * 0.9,
                angle: 0.05,
                cardW: cW,
                cardH: cH,
              ),
            )
          else
            Positioned(
              top: rowGap1,
              child: _buildFaceDownFan(
                middleCount,
                spreadX: spread * 0.9,
                cardW: cW,
                cardH: cH,
              ),
            ),
          // Back row (bottom) — revealed first
          if (showBack && back.isNotEmpty)
            Positioned(
              top: rowGap2,
              child: _buildMiniFan(
                back,
                spreadX: spread,
                angle: 0.06,
                cardW: cW,
                cardH: cH,
              ),
            )
          else
            Positioned(
              top: rowGap2,
              child: _buildFaceDownFan(
                backCount,
                spreadX: spread,
                cardW: cW,
                cardH: cH,
              ),
            ),
          // Total result summary box — right side of cards (shows from first row reveal)
          if (_showdownStep >= 1 && result is Map && result['seat'] != null)
            Positioned(
              top: 0,
              right: -(containerW * 0.3),
              child: _buildTotalResultBadge(result['seat'] as int),
            ),
        ],
      ),
    );
  }

  /// Small total result badge shown beside cards for each player
  Widget _buildTotalResultBadge(int seat) {
    final coinChange = _coinChanges[seat] ?? 0;
    final isWin = coinChange > 0;
    final bigBlind = (widget.table['big_blind'] as int?) ?? 20;

    // Calculate per-row results for this seat
    int frontNet = 0, middleNet = 0, backNet = 0;
    final seatCards = _resultData.where((r) => r['seat'] == seat).firstOrNull;
    if (seatCards != null) {
      List<String> myF, myM, myB;
      if (seat == _mySeat) {
        myF = _front;
        myM = _middle;
        myB = _back;
      } else {
        myF = seatCards['front'] is List
            ? List<String>.from(seatCards['front'])
            : [];
        myM = seatCards['middle'] is List
            ? List<String>.from(seatCards['middle'])
            : [];
        myB = seatCards['back'] is List
            ? List<String>.from(seatCards['back'])
            : [];
      }
      for (final r in _resultData) {
        if (r['seat'] == seat) continue;
        final oF = r['front'] is List
            ? List<String>.from(r['front'])
            : <String>[];
        final oM = r['middle'] is List
            ? List<String>.from(r['middle'])
            : <String>[];
        final oB = r['back'] is List
            ? List<String>.from(r['back'])
            : <String>[];
        try {
          if (myF.length == 3 && oF.length == 3) {
            final c = HandEvaluator.compare(
              HandEvaluator.evaluate3(myF),
              HandEvaluator.evaluate3(oF),
            );
            if (c > 0)
              frontNet++;
            else if (c < 0)
              frontNet--;
          }
        } catch (_) {}
        try {
          if (myM.length == 5 && oM.length == 5) {
            final c = HandEvaluator.compare(
              HandEvaluator.evaluate5(myM),
              HandEvaluator.evaluate5(oM),
            );
            if (c > 0)
              middleNet++;
            else if (c < 0)
              middleNet--;
          }
        } catch (_) {}
        try {
          if (myB.length == 5 && oB.length == 5) {
            final c = HandEvaluator.compare(
              HandEvaluator.evaluate5(myB),
              HandEvaluator.evaluate5(oB),
            );
            if (c > 0)
              backNet++;
            else if (c < 0)
              backNet--;
          }
        } catch (_) {}
      }
    }

    // Convert net points to coins
    final frontCoins = frontNet * bigBlind;
    final middleCoins = middleNet * bigBlind;
    final backCoins = backNet * bigBlind;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(
        scale: v,
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF1A8A7A), const Color(0xFF0D5A4A)],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow('หน้า:', frontCoins, _showdownStep >= 1),
            _summaryRow('กลาง:', middleCoins, _showdownStep >= 2),
            _summaryRow('หลัง:', backCoins, _showdownStep >= 3),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.3),
                    width: 0.5,
                  ),
                ),
              ),
              child: Builder(
                builder: (_) {
                  // Progressive total — accumulate only revealed rows (in coins)
                  int progressiveCoins = 0;
                  if (_showdownStep >= 1) progressiveCoins += frontCoins;
                  if (_showdownStep >= 2) progressiveCoins += middleCoins;
                  if (_showdownStep >= 3) progressiveCoins += backCoins;
                  final pWin = progressiveCoins > 0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'ทั้งหมด:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${progressiveCoins > 0 ? "+" : ""}$progressiveCoins',
                        style: TextStyle(
                          color: pWin
                              ? const Color(0xFFFFD700)
                              : progressiveCoins < 0
                              ? Colors.red.shade300
                              : Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, int net, bool revealed) {
    final isWin = net > 0;
    final isLose = net < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 7),
          ),
          const SizedBox(width: 8),
          if (revealed && net != 0)
            Text(
              '${isWin ? "+" : ""}$net',
              style: TextStyle(
                color: isWin ? const Color(0xFFFFD700) : Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }

  /// Animated badge showing hand name + royalty for a card row
  Widget _buildRowInfoBadge(String handName, int royalty) {
    return _buildRowInfoBadgeWithResult(handName, royalty, '');
  }

  /// Get win/lose result string for a specific row of a specific seat
  String _getRowWinLose(List<String> cards, String row, int seat) {
    if (_resultData.isEmpty) return '';
    int wins = 0, losses = 0;

    for (final r in _resultData) {
      final otherSeat = r['seat'] as int? ?? 0;
      if (otherSeat == seat) continue;

      List<String> otherCards;
      if (otherSeat == _mySeat) {
        otherCards = row == 'back'
            ? _back
            : row == 'middle'
            ? _middle
            : _front;
      } else {
        final raw = r[row];
        otherCards = raw is List ? List<String>.from(raw) : [];
      }

      if (otherCards.isEmpty) continue;

      try {
        int cmp;
        if (row == 'front' && cards.length == 3 && otherCards.length == 3) {
          cmp = HandEvaluator.compare(
            HandEvaluator.evaluate3(cards),
            HandEvaluator.evaluate3(otherCards),
          );
        } else if (cards.length == 5 && otherCards.length == 5) {
          cmp = HandEvaluator.compare(
            HandEvaluator.evaluate5(cards),
            HandEvaluator.evaluate5(otherCards),
          );
        } else {
          continue;
        }
        if (cmp > 0)
          wins++;
        else if (cmp < 0)
          losses++;
      } catch (_) {}
    }

    final net = wins - losses;
    if (net > 0) return '+$net';
    if (net < 0) return '$net';
    return '0';
  }

  /// Animated badge showing hand name + royalty + win/lose result
  Widget _buildRowInfoBadgeWithResult(
    String handName,
    int royalty,
    String result,
  ) {
    final isWin = result.startsWith('+');
    final isLose = result.startsWith('-');
    final borderColor = isWin
        ? const Color(0xFFFFD700)
        : isLose
        ? Colors.red
        : const Color(0xFF4ADE80);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        alignment: Alignment.centerRight,
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor.withOpacity(0.7), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  handName,
                  style: TextStyle(
                    color: borderColor,
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (royalty > 0)
                  Text(
                    '✨+$royalty',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 6,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            if (result.isNotEmpty) ...[
              const SizedBox(width: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: isWin
                      ? const Color(0xFFFFD700).withOpacity(0.2)
                      : isLose
                      ? Colors.red.withOpacity(0.2)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  result,
                  style: TextStyle(
                    color: isWin
                        ? const Color(0xFFFFD700)
                        : isLose
                        ? Colors.red.shade300
                        : Colors.white54,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Face-down card fan (for unrevealed rows during showdown) with slide-in animation
  Widget _buildFaceDownFan(
    int count, {
    double spreadX = 5,
    double cardW = 18,
    double cardH = 26,
  }) {
    final totalWidth = (count - 1) * spreadX + cardW;
    return SizedBox(
      width: totalWidth + 4,
      height: cardH + 4,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              left: i * spreadX,
              top: 2,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 200 + i * 40),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Transform.translate(
                  offset: Offset(0, (1 - value) * 10),
                  child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                ),
                child: PlayingCard(
                  card: '??',
                  faceUp: false,
                  width: cardW,
                  height: cardH,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build a small fan of cards with smooth pop-in animation
  Widget _buildMiniFan(
    List<String> cards, {
    double spreadX = 5,
    double angle = 0.08,
    double cardW = 18,
    double cardH = 26,
  }) {
    final count = cards.length;
    if (count == 0) return const SizedBox.shrink();
    final startAngle = -(count - 1) / 2 * angle;

    return SizedBox(
      width: count * spreadX + cardW + 10,
      height: cardH + 6,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              bottom: 0,
              left:
                  (count * spreadX + 10) / 2 -
                  cardW / 2 +
                  (i - (count - 1) / 2) * spreadX,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 300 + i * 50),
                curve: Curves.easeOutBack,
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                ),
                child: Transform.rotate(
                  angle: startAngle + i * angle,
                  alignment: Alignment.bottomCenter,
                  child: PlayingCard(
                    card: cards[i],
                    faceUp: true,
                    width: cardW,
                    height: cardH,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Card fan showing "ready" state with cards fanned out
  Widget _buildReadyCardFan() {
    return SizedBox(
      width: 70,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < 7; i++)
            Transform.translate(
              offset: Offset((i - 3) * 4.0, 0),
              child: Transform.rotate(
                angle: (i - 3) * 0.08,
                child: Container(
                  width: 18,
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFCC3333), Color(0xFF8B0000)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: Colors.white, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 2,
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

  Widget _buildCardFan({required bool isReady, bool showFace = false}) {
    return SizedBox(
      width: 65,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < 5; i++)
            Transform.rotate(
              angle: (i - 2) * 0.13,
              child: Container(
                width: 16,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFFCC3333),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.white, width: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // CENTER: CARD ARRANGEMENT (Modal Layer Style)
  // ═══════════════════════════════════════════════

  Widget _buildCardCenter() {
    if (_hand.isEmpty && !_canConfirm && _phase != 'waiting') {
      return const Center(
        child: Text(
          'รอแจกไพ่...',
          style: TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }
    if (_phase == 'waiting') {
      return const Center(
        child: Text(
          'รอผู้เล่น...',
          style: TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availH = constraints.maxHeight;
        final availW = constraints.maxWidth;

        // Card sizes — responsive to available space
        final cardH = (availH * 0.15).clamp(44.0, 72.0);
        final cardW = cardH * 0.7;
        final handCardH = (availH * 0.14).clamp(40.0, 64.0);
        final handCardW = handCardH * 0.7;

        // Validation
        final isFoul = _canConfirm
            ? OFCScorer.isFoul(_front, _middle, _back)
            : false;

        return Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // ── Status Bar: hand names for each row ──
              _buildStatusBar(isFoul),
              const SizedBox(height: 4),

              // ── 3 Slot Rows ──
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSlotRow(_front, 3, 'front', 'หน้า', cardW, cardH),
                    const SizedBox(height: 6),
                    _buildSlotRow(_middle, 5, 'middle', 'กลาง', cardW, cardH),
                    const SizedBox(height: 6),
                    _buildSlotRow(_back, 5, 'back', 'หลัง', cardW, cardH),
                  ],
                ),
              ),

              // ── Hand Cards (overlapping at bottom) ──
              if (_hand.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildHandStrip(handCardW, handCardH, availW),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Status bar showing hand names + validation icons
  Widget _buildStatusBar(bool isFoul) {
    String frontName = _front.length == 3
        ? HandEvaluator.evaluate3(_front).nameTh
        : '';
    String middleName = _middle.length == 5
        ? HandEvaluator.evaluate5(_middle).nameTh
        : '';
    String backName = _back.length == 5
        ? HandEvaluator.evaluate5(_back).nameTh
        : '';

    return Row(
      children: [
        // Front
        _handBadge(frontName, _front.length == 3, 'หน้า'),
        const SizedBox(width: 6),
        // Middle
        _handBadge(middleName, _middle.length == 5, 'กลาง'),
        const SizedBox(width: 6),
        // Back
        _handBadge(backName, _back.length == 5, 'หลัง'),
        const Spacer(),
        // Foul indicator
        if (_canConfirm)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isFoul
                  ? Colors.red.withOpacity(0.2)
                  : Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isFoul ? Icons.close : Icons.check,
                  color: isFoul ? Colors.red : Colors.greenAccent,
                  size: 12,
                ),
                const SizedBox(width: 2),
                Text(
                  isFoul ? 'ผิดกฎ' : 'ถูกกฎ',
                  style: TextStyle(
                    color: isFoul ? Colors.red : Colors.greenAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _handBadge(String name, bool isFull, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isFull
            ? const Color(0xFF1B5E20).withOpacity(0.6)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isFull
              ? Colors.greenAccent.withOpacity(0.5)
              : Colors.white.withOpacity(0.15),
        ),
      ),
      child: Text(
        name.isNotEmpty ? name : label,
        style: TextStyle(
          color: isFull ? Colors.greenAccent : Colors.white54,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// A single slot row with drag target, glow effect, and placeholder slots
  Widget _buildSlotRow(
    List<String> cards,
    int max,
    String row,
    String label,
    double cardW,
    double cardH,
  ) {
    final isFull = cards.length >= max;
    final isActive = _activeRow == row && _hand.isNotEmpty;

    return DragTarget<_CardDragData>(
      onWillAcceptWithDetails: (details) =>
          !isFull || details.data.fromRow != row,
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data.fromRow == 'hand') {
          _placeCard(data.card, row);
        } else {
          _moveCardBetweenRows(data.card, data.fromRow, row);
        }
      },
      builder: (ctx, candidate, _) {
        final dragOver = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: dragOver
                  ? Colors.greenAccent
                  : isActive
                  ? Colors.amber.withOpacity(0.5)
                  : Colors.white.withOpacity(0.1),
              width: dragOver ? 2 : 1,
            ),
            color: dragOver
                ? Colors.greenAccent.withOpacity(0.06)
                : Colors.transparent,
            boxShadow: dragOver
                ? [
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.3),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Cards in slots
              for (int i = 0; i < max; i++)
                i < cards.length
                    ? Draggable<_CardDragData>(
                        data: _CardDragData(
                          card: cards[i],
                          fromRow: row,
                          index: i,
                        ),
                        feedback: Material(
                          color: Colors.transparent,
                          child: Transform.scale(
                            scale: 1.15,
                            child: PlayingCard(
                              card: cards[i],
                              faceUp: true,
                              width: cardW,
                              height: cardH,
                            ),
                          ),
                        ),
                        childWhenDragging: _emptySlot(
                          cardW,
                          cardH,
                          highlight: true,
                        ),
                        child: GestureDetector(
                          onTap: () => _removeCard(row, i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: PlayingCard(
                              card: cards[i],
                              faceUp: true,
                              width: cardW,
                              height: cardH,
                            ),
                          ),
                        ),
                      )
                    : _emptySlot(cardW, cardH),
            ],
          ),
        );
      },
    );
  }

  /// Empty placeholder slot with dashed border
  Widget _emptySlot(double w, double h, {bool highlight = false}) {
    return Container(
      width: w,
      height: h,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: highlight
              ? Colors.amber.withOpacity(0.5)
              : Colors.white.withOpacity(0.2),
          width: 1.5,
        ),
        color: highlight
            ? Colors.amber.withOpacity(0.05)
            : Colors.white.withOpacity(0.02),
      ),
    );
  }

  /// Hand cards strip at bottom — overlapping, scrollable, draggable
  Widget _buildHandStrip(double cardW, double cardH, double maxWidth) {
    final cardCount = _hand.length;
    if (cardCount == 0) return const SizedBox.shrink();

    // Calculate spacing so cards overlap to fit
    final totalNeeded = cardW * cardCount;
    final available = maxWidth * 0.9;
    final spacing = totalNeeded > available
        ? (available - cardW) / (cardCount - 1).clamp(1, 99)
        : cardW + 3;
    final stackWidth = spacing * (cardCount - 1) + cardW;

    return SizedBox(
      width: stackWidth.clamp(0.0, available + cardW),
      height: cardH + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < cardCount; i++)
            Positioned(
              left: i * spacing,
              top: 0,
              child: Draggable<_CardDragData>(
                data: _CardDragData(card: _hand[i], fromRow: 'hand', index: i),
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
                  opacity: 0.25,
                  child: PlayingCard(
                    card: _hand[i],
                    faceUp: true,
                    width: cardW,
                    height: cardH,
                  ),
                ),
                child: GestureDetector(
                  onTap: () => _placeCard(_hand[i], _activeRow),
                  child: PlayingCard(
                    card: _hand[i],
                    faceUp: true,
                    width: cardW,
                    height: cardH,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Move a card from one row to another (swap if target full)
  void _moveCardBetweenRows(String card, String fromRow, String toRow) {
    setState(() {
      switch (fromRow) {
        case 'front':
          _front.remove(card);
        case 'middle':
          _middle.remove(card);
        case 'back':
          _back.remove(card);
      }
      final targetMax = toRow == 'front' ? 3 : 5;
      final targetList = toRow == 'front'
          ? _front
          : toRow == 'middle'
          ? _middle
          : _back;
      if (targetList.length < targetMax) {
        targetList.add(card);
      } else {
        final swapped = targetList.removeLast();
        targetList.add(card);
        switch (fromRow) {
          case 'front':
            _front.add(swapped);
          case 'middle':
            _middle.add(swapped);
          case 'back':
            _back.add(swapped);
        }
      }
    });
  }

  // ═══════════════════════════════════════════════
  // CENTER: RESULT VIEW
  // ═══════════════════════════════════════════════

  Widget _buildResultCenter() {
    final myResult = _resultData.where((r) => r['seat'] == _mySeat).firstOrNull;
    final myCoinChange = _coinChanges[_mySeat] ?? 0;
    final isWin = myCoinChange > 0;

    final myFront = List<String>.from(myResult?['front'] ?? _front);
    final myMiddle = List<String>.from(myResult?['middle'] ?? _middle);
    final myBack = List<String>.from(myResult?['back'] ?? _back);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availH = constraints.maxHeight;
        final cardH = (availH * 0.18).clamp(40.0, 70.0);
        final cardW = cardH * 0.7;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Win/Lose banner
            if (myCoinChange != 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isWin
                        ? [const Color(0xFF2E7D32), const Color(0xFF1B5E20)]
                        : [const Color(0xFFC62828), const Color(0xFF8B0000)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: (isWin ? Colors.green : Colors.red).withOpacity(
                        0.6,
                      ),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Text(
                  isWin ? 'ชนะ!' : 'แพ้',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

            // 3 stacked fans (front on top, back on bottom)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: (cardW * 5 * 0.55 + cardW + 20).clamp(150.0, 300.0),
                  height: cardH * 3 + 20,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    clipBehavior: Clip.none,
                    children: [
                      // Front (bottom z-layer, visually at top position)
                      Positioned(
                        bottom: cardH * 1.4,
                        child: _buildResultFan(
                          myFront,
                          cardW: cardW * 0.85,
                          cardH: cardH * 0.85,
                          spreadX: cardW * 0.5,
                          angle: 0.05,
                        ),
                      ),
                      // Middle (middle z-layer)
                      Positioned(
                        bottom: cardH * 0.7,
                        child: _buildResultFan(
                          myMiddle,
                          cardW: cardW * 0.9,
                          cardH: cardH * 0.9,
                          spreadX: cardW * 0.45,
                          angle: 0.06,
                        ),
                      ),
                      // Back (top z-layer — drawn last, overlaps on top)
                      Positioned(
                        bottom: 0,
                        child: _buildResultFan(
                          myBack,
                          cardW: cardW,
                          cardH: cardH,
                          spreadX: cardW * 0.5,
                          angle: 0.07,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Score table
                if (myResult != null) _buildScoreTable(myResult, myCoinChange),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Build a fan for result display
  Widget _buildResultFan(
    List<String> cards, {
    double cardW = 42,
    double cardH = 60,
    double spreadX = 20,
    double angle = 0.07,
  }) {
    final count = cards.length;
    if (count == 0) return const SizedBox.shrink();
    final startAngle = -(count - 1) / 2 * angle;
    final fanWidth = count * spreadX + cardW + 10;

    return SizedBox(
      width: fanWidth,
      height: cardH + 8,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              bottom: 0,
              left: fanWidth / 2 - cardW / 2 + (i - (count - 1) / 2) * spreadX,
              child: Transform.rotate(
                angle: startAngle + i * angle,
                alignment: Alignment.bottomCenter,
                child: PlayingCard(
                  card: cards[i],
                  faceUp: true,
                  width: cardW,
                  height: cardH,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreTable(dynamic myResult, int totalChange) {
    final frontScore = myResult['frontScore'] ?? 0;
    final middleScore = myResult['middleScore'] ?? 0;
    final backScore = myResult['backScore'] ?? 0;
    final isWin = totalChange > 0;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDAA520).withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _scoreTableRow('หน้า:', frontScore),
          _scoreTableRow('กลาง:', middleScore),
          _scoreTableRow('หลัง:', backScore),
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.2),
            margin: const EdgeInsets.symmetric(vertical: 3),
          ),
          _scoreTableRow(
            'ทั้งหมด:',
            totalChange,
            isBold: true,
            color: isWin ? Colors.greenAccent : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _scoreTableRow(
    String label,
    int score, {
    bool isBold = false,
    Color? color,
  }) {
    final isPositive = score > 0;
    final c =
        color ??
        (isPositive
            ? Colors.greenAccent
            : score < 0
            ? Colors.red
            : Colors.white70);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isPositive ? "+" : ""}$score',
            style: TextStyle(
              color: c,
              fontSize: isBold ? 12 : 10,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // RE-ARRANGE
  // ═══════════════════════════════════════════════

  /// Re-arrange all cards with a new auto-arrangement
  void _reArrangeCards() {
    final allCards = [..._front, ..._middle, ..._back, ..._hand];
    if (allCards.length != 13) return;
    final newArrangement = OFCAutoArrange.arrange(allCards);
    if (newArrangement == null) return;
    setState(() {
      _front = List<String>.from(newArrangement['front']!);
      _middle = List<String>.from(newArrangement['middle']!);
      _back = List<String>.from(newArrangement['back']!);
      _hand = [];
      _activeRow = 'front';
    });
    AudioManager.instance.play(SoundEffect.buttonTap);
  }

  // ═══════════════════════════════════════════════
  // SEAT SELECTION
  // ═══════════════════════════════════════════════

  Widget _buildSeatSelection() {
    final maxSeats = toInt(widget.table['max_players'] ?? 4);
    final occupied = _players.keys.toSet();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0606).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDAA520).withOpacity(0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'เลือกที่นั่ง',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              for (int i = 1; i <= maxSeats; i++)
                if (!occupied.contains(i))
                  GestureDetector(
                    onTap: () => _joinGame(),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.4),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.event_seat,
                            color: Colors.green,
                            size: 20,
                          ),
                          Text(
                            '$i',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Simple animated widget that rebuilds on animation tick
class AnimatedWidget2 extends StatelessWidget {
  final Listenable listenable;
  final Widget Function(BuildContext context) builder;

  const AnimatedWidget2({
    super.key,
    required this.listenable,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => builder(context),
    );
  }
}

/// Data class for dragging cards between rows
class _CardDragData {
  final String card;
  final String fromRow; // 'front', 'middle', 'back', 'hand'
  final int index;

  const _CardDragData({
    required this.card,
    required this.fromRow,
    required this.index,
  });
}
