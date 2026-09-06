import 'dart:ui' show Color;

import 'hand_evaluator.dart';
import 'thai_labels.dart';

/// Classification of a player's current hand strength for the game guide.
enum HandStrengthCategory { strong, medium, weak }

/// Result of a FREE TIPS gameplay recommendation.
class TipResult {
  /// Recommended action: 'fold', 'call', or 'raise'.
  final String action;

  /// Thai translation of the action: 'หมอบ', 'ตาม', or 'เก'.
  final String actionTh;

  /// Thai-language explanation of the reasoning.
  final String reasoning;

  /// Confidence level from 0.0 to 1.0.
  final double confidence;

  const TipResult({
    required this.action,
    required this.actionTh,
    required this.reasoning,
    required this.confidence,
  });

  @override
  String toString() =>
      'TipResult(action: $action, actionTh: $actionTh, confidence: $confidence)';
}

/// Pure utility for gameplay recommendations.
///
/// Analyzes hole cards, community cards, game phase, pot size, and call amount
/// to produce a [TipResult] with a recommended action, Thai label, reasoning,
/// and confidence score.
class FreeTipsEngine {
  /// Analyze hand and recommend action.
  ///
  /// [holeCards] — the player's 2 hole cards (e.g. ['Ah', 'Ks']).
  /// [communityCards] — 0–5 community cards on the board.
  /// [phase] — 'preflop', 'flop', 'turn', or 'river'.
  /// [potSize] — current pot size (non-negative).
  /// [callAmount] — amount required to call (non-negative).
  static TipResult analyze({
    required List<String> holeCards,
    required List<String> communityCards,
    required String phase,
    required int potSize,
    required int callAmount,
  }) {
    if (phase == 'preflop') {
      return _analyzePreFlop(holeCards, potSize, callAmount);
    }
    return _analyzePostFlop(
      holeCards,
      communityCards,
      phase,
      potSize,
      callAmount,
    );
  }

  /// Pre-flop hand strength ranking (0.0 to 1.0).
  ///
  /// Ranks hands based on standard pre-flop hand charts:
  /// - AA, KK, QQ, AKs → very strong (0.85–1.0)
  /// - JJ, TT, AQs, AKo → strong (0.7–0.85)
  /// - Medium pairs, suited connectors → medium (0.4–0.7)
  /// - Low unsuited cards → weak (0.0–0.4)
  static double preFlopStrength(List<String> holeCards) {
    if (holeCards.length != 2) return 0.0;

    final v1 = _cardValue(holeCards[0]);
    final v2 = _cardValue(holeCards[1]);
    final high = v1 >= v2 ? v1 : v2;
    final low = v1 >= v2 ? v2 : v1;
    final suited = holeCards[0][1] == holeCards[1][1];
    final isPair = v1 == v2;

    // Pocket pairs
    if (isPair) {
      if (high >= 14) return 1.0; // AA
      if (high >= 13) return 0.95; // KK
      if (high >= 12) return 0.90; // QQ
      if (high >= 11) return 0.80; // JJ
      if (high >= 10) return 0.75; // TT
      if (high >= 9) return 0.65; // 99
      if (high >= 8) return 0.60; // 88
      if (high >= 7) return 0.55; // 77
      if (high >= 6) return 0.50; // 66
      return 0.45; // 22-55
    }

    // Ace-high hands
    if (high == 14) {
      if (low >= 13) return suited ? 0.95 : 0.85; // AKs / AKo
      if (low >= 12) return suited ? 0.80 : 0.70; // AQs / AQo
      if (low >= 11) return suited ? 0.75 : 0.65; // AJs / AJo
      if (low >= 10) return suited ? 0.70 : 0.60; // ATs / ATo
      return suited ? 0.55 : 0.35; // Ax suited / Ax offsuit
    }

    // King-high hands
    if (high == 13) {
      if (low >= 12) return suited ? 0.70 : 0.60; // KQs / KQo
      if (low >= 11) return suited ? 0.65 : 0.55; // KJs / KJo
      if (low >= 10) return suited ? 0.60 : 0.50; // KTs / KTo
      return suited ? 0.45 : 0.30; // Kx suited / Kx offsuit
    }

    // Queen-high hands
    if (high == 12) {
      if (low >= 11) return suited ? 0.60 : 0.50; // QJs / QJo
      if (low >= 10) return suited ? 0.55 : 0.45; // QTs / QTo
      return suited ? 0.40 : 0.25;
    }

    // Suited connectors and one-gappers
    if (suited && (high - low == 1)) {
      // Suited connectors: JTs, T9s, 98s, etc.
      if (high >= 11) return 0.55; // JTs
      if (high >= 9) return 0.50; // T9s, 98s
      return 0.45; // 87s, 76s, etc.
    }

    if (suited && (high - low == 2)) {
      // Suited one-gappers
      if (high >= 11) return 0.50;
      return 0.40;
    }

    // Offsuit connectors
    if (!suited && (high - low == 1)) {
      if (high >= 11) return 0.45; // JTo
      if (high >= 9) return 0.40; // T9o, 98o
      return 0.35;
    }

    // Remaining suited hands
    if (suited) return 0.35;

    // Remaining offsuit hands
    return 0.20;
  }

  // ---------------------------------------------------------------------------
  // Game Guide helpers
  // ---------------------------------------------------------------------------

  /// Classify hand strength from a [TipResult.confidence] value.
  ///
  /// * confidence > 0.7 → [HandStrengthCategory.strong]
  /// * 0.4 – 0.7       → [HandStrengthCategory.medium]
  /// * < 0.4           → [HandStrengthCategory.weak]
  static HandStrengthCategory classifyStrength(double confidence) {
    if (confidence > 0.7) return HandStrengthCategory.strong;
    if (confidence >= 0.4) return HandStrengthCategory.medium;
    return HandStrengthCategory.weak;
  }

  /// Thai explanation string for a given [category].
  static String getExplanationTh(HandStrengthCategory category) {
    switch (category) {
      case HandStrengthCategory.strong:
        return '${ThaiLabels.strongHand} ${ThaiLabels.shouldRaise}';
      case HandStrengthCategory.medium:
        return '${ThaiLabels.mediumHand} ${ThaiLabels.shouldCall}';
      case HandStrengthCategory.weak:
        return '${ThaiLabels.weakHand} ${ThaiLabels.shouldFold}';
    }
  }

  /// Recommendation badge color for a given [category].
  ///
  /// * strong → green (0xFF4CAF50)
  /// * medium → yellow (0xFFFFC107)
  /// * weak   → red (0xFFF44336)
  static Color getRecommendationColor(HandStrengthCategory category) {
    switch (category) {
      case HandStrengthCategory.strong:
        return const Color(0xFF4CAF50);
      case HandStrengthCategory.medium:
        return const Color(0xFFFFC107);
      case HandStrengthCategory.weak:
        return const Color(0xFFF44336);
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static int _cardValue(String card) {
    switch (card[0]) {
      case 'A':
        return 14;
      case 'K':
        return 13;
      case 'Q':
        return 12;
      case 'J':
        return 11;
      case 'T':
        return 10;
      case '9':
        return 9;
      case '8':
        return 8;
      case '7':
        return 7;
      case '6':
        return 6;
      case '5':
        return 5;
      case '4':
        return 4;
      case '3':
        return 3;
      case '2':
        return 2;
      default:
        return 0;
    }
  }

  static TipResult _analyzePreFlop(
    List<String> holeCards,
    int potSize,
    int callAmount,
  ) {
    final strength = preFlopStrength(holeCards);

    if (strength > 0.7) {
      return TipResult(
        action: 'raise',
        actionTh: ThaiLabels.raise,
        reasoning: 'ไพ่เริ่มต้นแข็งมาก ควรเก',
        confidence: strength.clamp(0.0, 1.0),
      );
    }

    if (strength >= 0.4) {
      // Medium hand — consider pot odds if there's a call amount
      if (callAmount > 0 && potSize > 0) {
        final potOdds = callAmount / (potSize + callAmount);
        if (potOdds > 0.5) {
          return TipResult(
            action: 'fold',
            actionTh: ThaiLabels.fold,
            reasoning: 'ไพ่ปานกลาง แต่ต้องจ่ายเยอะเกินไป ควรหมอบ',
            confidence: (1.0 - strength).clamp(0.0, 1.0),
          );
        }
      }
      return TipResult(
        action: 'call',
        actionTh: ThaiLabels.call,
        reasoning: 'ไพ่เริ่มต้นปานกลาง ควรตาม',
        confidence: strength.clamp(0.0, 1.0),
      );
    }

    // Weak hand
    return TipResult(
      action: 'fold',
      actionTh: ThaiLabels.fold,
      reasoning: 'ไพ่เริ่มต้นอ่อน ควรหมอบ',
      confidence: (1.0 - strength).clamp(0.0, 1.0),
    );
  }

  static TipResult _analyzePostFlop(
    List<String> holeCards,
    List<String> communityCards,
    String phase,
    int potSize,
    int callAmount,
  ) {
    final allCards = [...holeCards, ...communityCards];

    // Need at least 5 cards for a proper evaluation
    if (allCards.length < 5) {
      // Fallback: use pre-flop strength as a rough guide
      return _analyzePreFlop(holeCards, potSize, callAmount);
    }

    final handRank = HandEvaluator.evaluateBest5(allCards);
    final rank = handRank.rank;

    // Normalise hand rank to 0.0–1.0 strength
    // rank 0 (high card) → ~0.1, rank 9 (royal flush) → 1.0
    final handStrength = (rank + 1) / 10.0;

    // Consider pot odds
    double potOdds = 0.0;
    if (callAmount > 0 && potSize > 0) {
      potOdds = callAmount / (potSize + callAmount);
    }

    final handNameTh = handRank.nameTh;

    // Strong hand (two pair or better, rank >= 2)
    if (handStrength > 0.3) {
      // Very strong (straight or better, rank >= 4)
      if (rank >= 4) {
        return TipResult(
          action: 'raise',
          actionTh: ThaiLabels.raise,
          reasoning: 'มือแข็งมาก ($handNameTh) ควรเก',
          confidence: handStrength.clamp(0.0, 1.0),
        );
      }
      // Decent hand — raise if no call needed, otherwise call
      if (callAmount == 0) {
        return TipResult(
          action: 'raise',
          actionTh: ThaiLabels.raise,
          reasoning: 'มือดี ($handNameTh) ควรเก',
          confidence: handStrength.clamp(0.0, 1.0),
        );
      }
      return TipResult(
        action: 'call',
        actionTh: ThaiLabels.call,
        reasoning: 'มือดี ($handNameTh) ควรตาม',
        confidence: handStrength.clamp(0.0, 1.0),
      );
    }

    // Marginal hand (pair or high card)
    if (rank == 1) {
      // One pair — consider pot odds
      if (callAmount == 0) {
        return TipResult(
          action: 'call',
          actionTh: ThaiLabels.call,
          reasoning: 'มีคู่ ($handNameTh) ตรวจสอบหรือตาม',
          confidence: 0.4,
        );
      }
      if (potOdds <= 0.35) {
        return TipResult(
          action: 'call',
          actionTh: ThaiLabels.call,
          reasoning: 'มีคู่ ($handNameTh) พ็อตออดส์ดี ควรตาม',
          confidence: 0.4,
        );
      }
      return TipResult(
        action: 'fold',
        actionTh: ThaiLabels.fold,
        reasoning: 'มีแค่คู่ ($handNameTh) ต้องจ่ายเยอะ ควรหมอบ',
        confidence: 0.5,
      );
    }

    // High card only — generally fold unless free to check
    if (callAmount == 0) {
      return TipResult(
        action: 'call',
        actionTh: ThaiLabels.call,
        reasoning: 'ไม่มีมือ ($handNameTh) แต่ไม่ต้องจ่าย ตาม',
        confidence: 0.2,
      );
    }

    return TipResult(
      action: 'fold',
      actionTh: ThaiLabels.fold,
      reasoning: 'ไม่มีมือ ($handNameTh) ควรหมอบ',
      confidence: 0.7,
    );
  }
}
