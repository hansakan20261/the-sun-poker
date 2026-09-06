import 'dart:math';
import 'free_tips_engine.dart';
import 'hand_evaluator.dart';

/// Decision result from a bot.
class BotDecision {
  final String action; // 'fold', 'call', 'raise', 'check', 'all_in'
  final int raiseAmount;
  const BotDecision({required this.action, this.raiseAmount = 0});
}

/// AI decision-making for practice room bots.
/// Uses FreeTipsEngine internally with ±10% confidence jitter.
class BotStrategyEngine {
  static final _rng = Random();

  /// Produce a bot action for NLH based on hand strength + pot odds.
  static BotDecision decideNLH({
    required List<String> holeCards,
    required List<String> communityCards,
    required String phase,
    required int potSize,
    required int callAmount,
    required int botChips,
    required int minRaise,
    required int maxRaise,
    required int bigBlind,
  }) {
    if (botChips <= 0) return const BotDecision(action: 'fold');

    final tip = FreeTipsEngine.analyze(
      holeCards: holeCards,
      communityCards: communityCards,
      phase: phase,
      potSize: potSize,
      callAmount: callAmount,
    );

    // Apply ±10% jitter to confidence
    final jitter = ((_rng.nextDouble() - 0.5) * 0.2);
    final adjustedConfidence = (tip.confidence + jitter).clamp(0.0, 1.0);
    final category = FreeTipsEngine.classifyStrength(adjustedConfidence);

    // If can't afford to call, fold or all-in
    if (callAmount > botChips) {
      if (category == HandStrengthCategory.strong) {
        return const BotDecision(action: 'all_in');
      }
      return const BotDecision(action: 'fold');
    }

    switch (tip.action) {
      case 'raise':
        if (minRaise > botChips) {
          return const BotDecision(action: 'call');
        }
        // Raise between min and 3x BB
        final raiseAmt =
            (minRaise +
                    _rng.nextInt(
                      (bigBlind * 2).clamp(1, maxRaise - minRaise + 1),
                    ))
                .clamp(minRaise, maxRaise.clamp(minRaise, botChips));
        return BotDecision(action: 'raise', raiseAmount: raiseAmt);
      case 'call':
        if (callAmount == 0) return const BotDecision(action: 'check');
        return const BotDecision(action: 'call');
      case 'fold':
        if (callAmount == 0) return const BotDecision(action: 'check');
        return const BotDecision(action: 'fold');
      default:
        return const BotDecision(action: 'check');
    }
  }

  /// Produce a bot card placement for OFC.
  static String decideOFCPlacement({
    required String card,
    required List<String> currentFront,
    required List<String> currentMiddle,
    required List<String> currentBack,
  }) {
    // Simple strategy: fill back first, then middle, then front
    if (currentBack.length < 5) return 'back';
    if (currentMiddle.length < 5) return 'middle';
    if (currentFront.length < 3) return 'front';
    return 'back'; // fallback
  }
}
