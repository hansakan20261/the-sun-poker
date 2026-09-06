// Hand evaluator for Texas Hold'em and Chinese Poker (OFC)
const RANK_VALUES = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'T':10,'J':11,'Q':12,'K':13,'A':14 };

// Standard 5-card hand rankings (0-9 scale for OFC)
const HAND_RANKS = {
  HIGH_CARD: 0,
  ONE_PAIR: 1,
  TWO_PAIR: 2,
  THREE_OF_A_KIND: 3,
  STRAIGHT: 4,
  FLUSH: 5,
  FULL_HOUSE: 6,
  FOUR_OF_A_KIND: 7,
  STRAIGHT_FLUSH: 8,
  ROYAL_FLUSH: 9,
};

function parseCard(card) {
  return { rank: RANK_VALUES[card[0]], suit: card[1], str: card };
}

function evaluate(cards) {
  // cards = array of 5-7 card strings like ['Ah', 'Kd', ...]
  const parsed = cards.map(parseCard);
  const combos = getCombinations(parsed, 5);
  let best = null;
  for (const combo of combos) {
    const score = scoreHand(combo);
    if (!best || compareScores(score, best) > 0) best = score;
  }
  return best;
}

function scoreHand(cards) {
  const sorted = [...cards].sort((a, b) => b.rank - a.rank);
  const ranks = sorted.map(c => c.rank);
  const suits = sorted.map(c => c.suit);
  const isFlush = suits.every(s => s === suits[0]);
  const straightResult = checkStraight(ranks);
  const isStraight = straightResult.isStraight;
  const groups = groupByRank(ranks);

  // For straights, use the correct high card for kickers
  const straightKickers = isStraight
    ? [straightResult.highCard, straightResult.highCard - 1, straightResult.highCard - 2, straightResult.highCard - 3, straightResult.highCard - 4]
    : ranks;

  if (isFlush && isStraight && straightResult.highCard === 14) return { hand: HAND_RANKS.ROYAL_FLUSH, kickers: straightKickers };
  if (isFlush && isStraight) return { hand: HAND_RANKS.STRAIGHT_FLUSH, kickers: straightKickers };
  if (groups[0].count === 4) return { hand: HAND_RANKS.FOUR_OF_A_KIND, kickers: [groups[0].rank, groups[1].rank] };
  if (groups[0].count === 3 && groups.length >= 2 && groups[1].count === 2) return { hand: HAND_RANKS.FULL_HOUSE, kickers: [groups[0].rank, groups[1].rank] };
  if (isFlush) return { hand: HAND_RANKS.FLUSH, kickers: ranks };
  if (isStraight) return { hand: HAND_RANKS.STRAIGHT, kickers: straightKickers };
  if (groups[0].count === 3) return { hand: HAND_RANKS.THREE_OF_A_KIND, kickers: [groups[0].rank, ...ranks.filter(r => r !== groups[0].rank)] };
  if (groups[0].count === 2 && groups.length >= 2 && groups[1].count === 2) return { hand: HAND_RANKS.TWO_PAIR, kickers: [groups[0].rank, groups[1].rank, ...ranks.filter(r => r !== groups[0].rank && r !== groups[1].rank)] };
  if (groups[0].count === 2) return { hand: HAND_RANKS.ONE_PAIR, kickers: [groups[0].rank, ...ranks.filter(r => r !== groups[0].rank)] };
  return { hand: HAND_RANKS.HIGH_CARD, kickers: ranks };
}

function checkStraight(ranks) {
  // Normal straight check
  let isNormal = true;
  for (let i = 0; i < ranks.length - 1; i++) {
    if (ranks[i] - ranks[i+1] !== 1) { isNormal = false; break; }
  }
  if (isNormal) return { isStraight: true, highCard: ranks[0] };

  // Wheel: A-2-3-4-5 (A counts as 1)
  if (ranks[0] === 14 && ranks[1] === 5 && ranks[2] === 4 && ranks[3] === 3 && ranks[4] === 2) {
    return { isStraight: true, highCard: 5 }; // 5-high straight
  }

  return { isStraight: false, highCard: 0 };
}

function groupByRank(ranks) {
  const map = {};
  ranks.forEach(r => map[r] = (map[r] || 0) + 1);
  return Object.entries(map).map(([rank, count]) => ({ rank: Number(rank), count }))
    .sort((a, b) => b.count - a.count || b.rank - a.rank);
}

function compareScores(a, b) {
  if (a.hand !== b.hand) return a.hand - b.hand;
  for (let i = 0; i < Math.min(a.kickers.length, b.kickers.length); i++) {
    if (a.kickers[i] !== b.kickers[i]) return a.kickers[i] - b.kickers[i];
  }
  return 0;
}

function getCombinations(arr, k) {
  if (k === arr.length) return [arr];
  if (k === 1) return arr.map(x => [x]);
  const result = [];
  for (let i = 0; i <= arr.length - k; i++) {
    const rest = getCombinations(arr.slice(i + 1), k - 1);
    rest.forEach(combo => result.push([arr[i], ...combo]));
  }
  return result;
}

function findWinners(players, communityCards) {
  // players = [{ id, holeCards: ['Ah','Kd'] }, ...]
  const results = players.map(p => ({
    ...p,
    score: evaluate([...p.holeCards, ...communityCards]),
  }));
  results.sort((a, b) => compareScores(b.score, a.score));
  const bestScore = results[0].score;
  return results.filter(r => compareScores(r.score, bestScore) === 0);
}

module.exports = { evaluate, findWinners, HAND_RANKS, compareScores, groupByRank, parseCard };
