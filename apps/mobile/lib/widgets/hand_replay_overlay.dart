import 'package:flutter/material.dart';
import '../models/replay_step.dart';
import '../theme.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';
import 'replay_controls.dart';
import 'replay_timeline.dart';

/// Full-screen overlay for step-by-step hand replay.
///
/// Parses hand action log into ReplayStep list, renders table state,
/// step navigation with animations, community card reveals on street
/// transitions, showdown hole card reveal, Thai action labels, error handling.
/// Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 2.5
class HandReplayOverlay extends StatefulWidget {
  final Map<String, dynamic> handData;
  final VoidCallback onClose;

  const HandReplayOverlay({
    super.key,
    required this.handData,
    required this.onClose,
  });

  @override
  State<HandReplayOverlay> createState() => HandReplayOverlayState();
}

class HandReplayOverlayState extends State<HandReplayOverlay> {
  List<ReplayStep> _steps = [];
  int _currentStep = 0;
  bool _isPlaying = false;
  int _speed = 1;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _parseHandData();
  }

  void _parseHandData() {
    try {
      final actions = widget.handData['actions'] as List<dynamic>?;
      if (actions == null || actions.isEmpty) {
        setState(() => _errorMessage = 'ไม่มีข้อมูลการเล่น');
        return;
      }

      final communityCards = List<String>.from(
        widget.handData['community_cards'] ?? [],
      );
      final players = widget.handData['players'] as Map<String, dynamic>? ?? {};

      final steps = <ReplayStep>[];
      for (var i = 0; i < actions.length; i++) {
        final action = actions[i] as Map<String, dynamic>;
        final actionType = action['action_type'] as String? ?? 'unknown';
        final seat = action['seat'] as int? ?? 0;
        final amount = action['amount'] as int? ?? 0;
        final round = action['round'] as String? ?? 'preflop';
        final playerName = _resolvePlayerName(players, seat, action);

        // Determine community cards visible at this step
        final visibleCards = _communityCardsForRound(round, communityCards);

        // Determine revealed hole cards at showdown
        final revealedHoleCards = <int, List<String>>{};
        if (round == 'showdown') {
          _populateShowdownCards(players, revealedHoleCards);
        }

        steps.add(
          ReplayStep(
            stepIndex: i,
            playerName: playerName,
            playerSeat: seat,
            actionType: actionType,
            actionLabelTh: _actionToThai(actionType),
            amount: amount,
            round: round,
            communityCardsRevealed: visibleCards,
            revealedHoleCards: revealedHoleCards,
          ),
        );
      }

      setState(() {
        _steps = steps;
        _currentStep = 0;
        _isPlaying = false;
      });
    } catch (e) {
      setState(() => _errorMessage = 'ไม่มีข้อมูลการเล่น');
    }
  }

  String _resolvePlayerName(
    Map<String, dynamic> players,
    int seat,
    Map<String, dynamic> action,
  ) {
    // Try action-level name first
    if (action['player_name'] != null) {
      return action['player_name'] as String;
    }
    // Try players map by seat
    final seatKey = seat.toString();
    if (players.containsKey(seatKey)) {
      final p = players[seatKey];
      if (p is Map<String, dynamic>) {
        return p['username'] as String? ?? 'Seat $seat';
      }
    }
    return 'Seat $seat';
  }

  static List<String> _communityCardsForRound(
    String round,
    List<String> allCommunity,
  ) {
    return switch (round) {
      'preflop' => <String>[],
      'flop' =>
        allCommunity.length >= 3 ? allCommunity.sublist(0, 3) : allCommunity,
      'turn' =>
        allCommunity.length >= 4 ? allCommunity.sublist(0, 4) : allCommunity,
      'river' || 'showdown' => allCommunity,
      _ => <String>[],
    };
  }

  void _populateShowdownCards(
    Map<String, dynamic> players,
    Map<int, List<String>> target,
  ) {
    for (final entry in players.entries) {
      final p = entry.value;
      if (p is Map<String, dynamic>) {
        final cards = p['hole_cards'];
        final seat = p['seat'] as int? ?? int.tryParse(entry.key) ?? 0;
        if (cards is List && cards.isNotEmpty) {
          target[seat] = List<String>.from(cards);
        }
      }
    }
  }

  static String _actionToThai(String actionType) {
    return switch (actionType) {
      'fold' => ThaiLabels.fold,
      'call' => ThaiLabels.call,
      'raise' => ThaiLabels.raise,
      'check' => ThaiLabels.check,
      'all_in' => ThaiLabels.allIn,
      _ => actionType,
    };
  }

  void _goToStep(int step) {
    if (_steps.isEmpty) return;
    setState(() {
      _currentStep = step.clamp(0, _steps.length - 1);
    });
  }

  void _togglePlayPause() {
    setState(() => _isPlaying = !_isPlaying);
  }

  ReplayStep? get _current => _steps.isNotEmpty ? _steps[_currentStep] : null;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.9),
      child: SafeArea(
        child: _errorMessage != null
            ? _buildError()
            : _steps.isEmpty
            ? _buildLoading()
            : _buildReplay(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _errorMessage!,
            style: TextStyle(
              color: SunTheme.gold.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: SunTheme.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SunTheme.gold.withOpacity(0.3)),
              ),
              child: const Text(
                ThaiLabels.close,
                style: TextStyle(color: SunTheme.goldLight, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: SunTheme.goldLight),
    );
  }

  Widget _buildReplay() {
    final step = _current!;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text(
                ThaiLabels.replay,
                style: TextStyle(
                  color: SunTheme.goldLight,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                step.round.toUpperCase(),
                style: TextStyle(
                  color: SunTheme.gold.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // Table area
        Expanded(child: _buildTableState(step)),
        // Timeline
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ReplayTimeline(
            currentStep: _currentStep,
            totalSteps: _steps.length,
          ),
        ),
        const SizedBox(height: 8),
        // Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ReplayControls(
            isPlaying: _isPlaying,
            speed: _speed,
            currentStep: _currentStep,
            totalSteps: _steps.length,
            onPlayPause: _togglePlayPause,
            onNext: () => _goToStep(_currentStep + 1),
            onPrevious: () => _goToStep(_currentStep - 1),
            onSpeedChange: (s) => setState(() => _speed = s),
            onClose: widget.onClose,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildTableState(ReplayStep step) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Community cards
            if (step.communityCardsRevealed.isNotEmpty) ...[
              Text(
                'ไพ่กลาง',
                style: TextStyle(
                  color: SunTheme.gold.withOpacity(0.5),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: step.communityCardsRevealed
                    .map((c) => _buildCard(c, true))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
            // Current action display
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey(_currentStep),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _actionColor(step.actionType).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _actionColor(step.actionType).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      step.playerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          step.actionLabelTh,
                          style: TextStyle(
                            color: _actionColor(step.actionType),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (step.amount > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            NumberFormatter.formatWithCommas(step.amount),
                            style: const TextStyle(
                              color: SunTheme.goldLight,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Showdown hole cards
            if (step.revealedHoleCards.isNotEmpty) ...[
              Text(
                'Showdown',
                style: TextStyle(
                  color: SunTheme.gold.withOpacity(0.5),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: step.revealedHoleCards.entries.map((e) {
                  final seatLabel = 'Seat ${e.key}';
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        seatLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: e.value
                            .map((c) => _buildCard(c, true))
                            .toList(),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String card, bool faceUp) {
    return Container(
      width: 36,
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: faceUp ? Colors.white : const Color(0xFF2A0A0A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: faceUp
              ? SunTheme.gold.withOpacity(0.4)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Center(
        child: Text(
          faceUp ? card : '?',
          style: TextStyle(
            color: faceUp ? _cardColor(card) : Colors.white24,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _cardColor(String card) {
    if (card.length < 2) return Colors.black;
    return switch (card[card.length - 1]) {
      'h' || 'd' => Colors.red,
      _ => Colors.black,
    };
  }

  Color _actionColor(String actionType) {
    return switch (actionType) {
      'fold' => Colors.grey,
      'call' => Colors.greenAccent,
      'raise' => Colors.orangeAccent,
      'check' => Colors.blueAccent,
      'all_in' => Colors.redAccent,
      _ => Colors.white,
    };
  }
}
