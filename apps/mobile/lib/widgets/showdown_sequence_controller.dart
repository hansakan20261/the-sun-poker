import 'package:flutter/material.dart';
import '../utils/showdown_anim_config.dart';

/// Phases of the showdown animation sequence.
enum ShowdownPhase {
  cardReveal,
  amountLabels,
  loserDeduction,
  winnerFlight,
  resultPopup,
}

/// Orchestrates the 5-phase showdown animation sequence.
/// Not a widget — instantiated by the screen and driven via [runShowdown].
class ShowdownSequenceController {
  final TickerProvider vsync;
  bool _skipped = false;
  bool _disposed = false;

  ShowdownSequenceController({required this.vsync});

  /// Run the full 5-phase showdown sequence.
  /// Returns when the sequence completes or is skipped.
  Future<void> runShowdown({
    required List<int> activePlayers,
    required List<Map<String, dynamic>> winners,
    required List<Map<String, dynamic>> losers,
    required Function(ShowdownPhase phase, Map<String, dynamic> data)
    onPhaseUpdate,
  }) async {
    _skipped = false;

    // Phase 1: Sequential Card Reveal
    if (!_skipped && !_disposed) {
      onPhaseUpdate(ShowdownPhase.cardReveal, {'started': true});
      for (int i = 0; i < activePlayers.length; i++) {
        if (_skipped || _disposed) break;
        onPhaseUpdate(ShowdownPhase.cardReveal, {
          'seat': activePlayers[i],
          'index': i,
        });
        await _delay(
          ShowdownAnimConfig.cardFlipDuration +
              ShowdownAnimConfig.playerStaggerDelay,
        );
      }
    }

    // Phase 2: Win/Loss Amount Labels
    if (!_skipped && !_disposed) {
      onPhaseUpdate(ShowdownPhase.amountLabels, {
        'winners': winners,
        'losers': losers,
      });
      await _delay(ShowdownAnimConfig.amountLabelAnimDuration);
      await _delay(ShowdownAnimConfig.pauseAfterLabels);
    }

    // Phase 3: Loser Chip Deduction (concurrent for all losers)
    if (!_skipped && !_disposed) {
      onPhaseUpdate(ShowdownPhase.loserDeduction, {'losers': losers});
      await _delay(
        ShowdownAnimConfig.loserChipFlightDuration +
            Duration(
              milliseconds:
                  ShowdownAnimConfig.loserChipCount *
                  ShowdownAnimConfig.loserChipStagger.inMilliseconds,
            ),
      );
      await _delay(ShowdownAnimConfig.pauseAfterLoserDeduction);
    }

    // Phase 4: Winner Chip Flight
    if (!_skipped && !_disposed) {
      onPhaseUpdate(ShowdownPhase.winnerFlight, {'winners': winners});
      await _delay(ShowdownAnimConfig.winnerFlightTotalDuration);
    }

    // Phase 5: Result Popup
    if (!_disposed) {
      await _delay(ShowdownAnimConfig.pauseBeforePopup);
      onPhaseUpdate(ShowdownPhase.resultPopup, {
        'winners': winners,
        'losers': losers,
      });
    }
  }

  /// Skip remaining animations and jump to result popup.
  void skip() {
    _skipped = true;
  }

  Future<void> _delay(Duration d) async {
    if (_skipped || _disposed) return;
    await Future.delayed(d);
  }

  void dispose() {
    _disposed = true;
  }
}
