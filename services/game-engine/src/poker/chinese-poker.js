// Chinese Poker (ไพ่สามกอง / Open Face Chinese - OFC) Game Logic
const { newShuffledDeck } = require('./deck');

const RANK_VALUES = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'T':10,'J':11,'Q':12,'K':13,'A':14 };

// 5-card hand rankings (0-9) — used for middle & back rows
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

// 3-card hand rankings (front row) — only High Card, Pair, Trips possible
const FRONT_HAND_RANKS = {
  HIGH_CARD: 0,
  ONE_PAIR: 1,
  THREE_OF_A_KIND: 3,
};

function log(tableId, ...args) {
  console.log(`[Chinese ${tableId}]`, ...args);
}

function parseCard(c) { return { rank: RANK_VALUES[c[0]], suit: c[1] }; }

/**
 * Evaluate a 5-card hand (middle or back row).
 * Returns { hand: number(0-9), kickers: number[] }
 */
function evaluate5(cards) {
  const parsed = cards.map(parseCard);
  const sorted = [...parsed].sort((a, b) => b.rank - a.rank);
  const ranks = sorted.map(c => c.rank);
  const suits = sorted.map(c => c.suit);
  const isFlush = suits.every(s => s === suits[0]);
  const isStraight = checkStraight(ranks);
  const groups = groupByRank(ranks);

  // Wheel (A-2-3-4-5) straight kickers
  let straightKickers = ranks;
  if (isStraight && ranks[0] === 14 && ranks[1] === 5) {
    straightKickers = [5, 4, 3, 2, 1];
  }

  if (isFlush && isStraight && ranks[0] === 14 && ranks[1] === 13)
    return { hand: HAND_RANKS.ROYAL_FLUSH, kickers: ranks };
  if (isFlush && isStraight)
    return { hand: HAND_RANKS.STRAIGHT_FLUSH, kickers: straightKickers };
  if (groups[0].count === 4)
    return { hand: HAND_RANKS.FOUR_OF_A_KIND, kickers: [groups[0].rank, groups[1].rank] };
  if (groups[0].count === 3 && groups.length >= 2 && groups[1].count === 2)
    return { hand: HAND_RANKS.FULL_HOUSE, kickers: [groups[0].rank, groups[1].rank] };
  if (isFlush)
    return { hand: HAND_RANKS.FLUSH, kickers: ranks };
  if (isStraight)
    return { hand: HAND_RANKS.STRAIGHT, kickers: straightKickers };
  if (groups[0].count === 3)
    return { hand: HAND_RANKS.THREE_OF_A_KIND, kickers: [groups[0].rank, ...ranks.filter(r => r !== groups[0].rank)] };
  if (groups[0].count === 2 && groups.length >= 2 && groups[1].count === 2)
    return { hand: HAND_RANKS.TWO_PAIR, kickers: [groups[0].rank, groups[1].rank, ...ranks.filter(r => r !== groups[0].rank && r !== groups[1].rank)] };
  if (groups[0].count === 2)
    return { hand: HAND_RANKS.ONE_PAIR, kickers: [groups[0].rank, ...ranks.filter(r => r !== groups[0].rank)] };
  return { hand: HAND_RANKS.HIGH_CARD, kickers: ranks };
}

/**
 * Evaluate a 3-card hand (front row).
 * Only possible hands: High Card, One Pair, Three of a Kind.
 * Returns { hand: number(0,1,3), kickers: number[] }
 */
function evaluate3(cards) {
  const parsed = cards.map(parseCard);
  const sorted = [...parsed].sort((a, b) => b.rank - a.rank);
  const ranks = sorted.map(c => c.rank);
  const groups = groupByRank(ranks);

  if (groups[0].count === 3)
    return { hand: FRONT_HAND_RANKS.THREE_OF_A_KIND, kickers: [groups[0].rank] };
  if (groups[0].count === 2)
    return { hand: FRONT_HAND_RANKS.ONE_PAIR, kickers: [groups[0].rank, ...ranks.filter(r => r !== groups[0].rank)] };
  return { hand: FRONT_HAND_RANKS.HIGH_CARD, kickers: ranks };
}

function checkStraight(ranks) {
  // Must be exactly 5 cards
  if (ranks.length !== 5) return false;

  let isNormal = true;
  for (let i = 0; i < ranks.length - 1; i++) {
    if (ranks[i] - ranks[i + 1] !== 1) { isNormal = false; break; }
  }
  if (isNormal) return true;

  // Wheel: A-2-3-4-5
  if (ranks[0] === 14 && ranks[1] === 5 && ranks[2] === 4 && ranks[3] === 3 && ranks[4] === 2) return true;

  return false;
}

function groupByRank(ranks) {
  const map = {};
  ranks.forEach(r => map[r] = (map[r] || 0) + 1);
  return Object.entries(map).map(([rank, count]) => ({ rank: Number(rank), count }))
    .sort((a, b) => b.count - a.count || b.rank - a.rank);
}

/**
 * Compare two hand scores. Returns:
 *   > 0 if a is stronger
 *   < 0 if b is stronger
 *   0 if equal
 */
function compareScores(a, b) {
  if (a.hand !== b.hand) return a.hand - b.hand;
  for (let i = 0; i < Math.min(a.kickers.length, b.kickers.length); i++) {
    if (a.kickers[i] !== b.kickers[i]) return a.kickers[i] - b.kickers[i];
  }
  return 0;
}

/**
 * Get display name for a hand score.
 * Works for both 3-card (front) and 5-card (middle/back) hands.
 */
function handName(score, isFrontRow = false) {
  if (isFrontRow) {
    // 3-card hand names
    const names = { 0: 'High Card', 1: 'Pair', 3: 'Three of a Kind' };
    return names[score.hand] || 'High Card';
  }
  // 5-card hand names
  const names = {
    0: 'High Card', 1: 'Pair', 2: 'Two Pair', 3: 'Three of a Kind',
    4: 'Straight', 5: 'Flush', 6: 'Full House', 7: 'Four of a Kind',
    8: 'Straight Flush', 9: 'Royal Flush'
  };
  return names[score.hand] || 'Unknown';
}

// ═══════════════════════════════════════════════════════════════
// OFC ROYALTIES (Bonuses)
// ═══════════════════════════════════════════════════════════════

/**
 * Front row royalties:
 *   Pair 6-6 = +1, Pair 7-7 = +2, ... Pair A-A = +9
 *   Trips 2-2-2 = +10, Trips 3-3-3 = +11, ... Trips A-A-A = +22
 */
function frontRoyalty(score) {
  if (score.hand === FRONT_HAND_RANKS.THREE_OF_A_KIND) {
    // Trips 2=+10, 3=+11, ..., A=+22
    return 10 + (score.kickers[0] - 2);
  }
  if (score.hand === FRONT_HAND_RANKS.ONE_PAIR) {
    const r = score.kickers[0]; // rank of the pair
    // Pair 6=+1, 7=+2, 8=+3, 9=+4, T=+5, J=+6, Q=+7, K=+8, A=+9
    if (r >= 6) return r - 5;
  }
  return 0;
}

/**
 * Middle row royalties (same hands as back but DOUBLED):
 *   Trips = +2, Straight = +4, Flush = +8, Full House = +12,
 *   Quads = +20, Straight Flush = +30, Royal Flush = +50
 */
function middleRoyalty(score) {
  switch (score.hand) {
    case HAND_RANKS.THREE_OF_A_KIND: return 2;
    case HAND_RANKS.STRAIGHT: return 4;
    case HAND_RANKS.FLUSH: return 8;
    case HAND_RANKS.FULL_HOUSE: return 12;
    case HAND_RANKS.FOUR_OF_A_KIND: return 20;
    case HAND_RANKS.STRAIGHT_FLUSH: return 30;
    case HAND_RANKS.ROYAL_FLUSH: return 50;
    default: return 0;
  }
}

/**
 * Back row royalties:
 *   Straight = +2, Flush = +4, Full House = +6,
 *   Quads = +10, Straight Flush = +15, Royal Flush = +25
 */
function backRoyalty(score) {
  switch (score.hand) {
    case HAND_RANKS.STRAIGHT: return 2;
    case HAND_RANKS.FLUSH: return 4;
    case HAND_RANKS.FULL_HOUSE: return 6;
    case HAND_RANKS.FOUR_OF_A_KIND: return 10;
    case HAND_RANKS.STRAIGHT_FLUSH: return 15;
    case HAND_RANKS.ROYAL_FLUSH: return 25;
    default: return 0;
  }
}

// ═══════════════════════════════════════════════════════════════
// Chinese Poker Room
// ═══════════════════════════════════════════════════════════════

class ChinesePokerRoom {
  constructor(tableId, config) {
    const required = [
      'smallBlind', 'bigBlind', 'ante', 'minBuyIn', 'maxBuyIn', 'maxSeats',
      'turnTimeSec', 'autoStartAt', 'autoStartDelaySec', 'minPlayMinutes',
      'rakePercent', 'rakeCap',
    ];
    for (const field of required) {
      if (!Number.isFinite(Number(config[field]))) throw new Error(`Missing required room config: ${field}`);
    }
    this.tableId = tableId;
    this.config = config;
    this.policy = config.chinesePolicy || {};
    if (this.policy.royalty_table_version && this.policy.royalty_table_version !== 'v1') {
      throw new Error(`Unsupported Chinese poker royalty table: ${this.policy.royalty_table_version}`);
    }
    this.players = new Map();
    this.seatReservations = new Map();
    this.deck = [];
    this.handNumber = 0;
    this.phase = 'waiting';
    this.lastResult = null;
    // Timer
    this.turnTimeSec = Number(config.turnTimeSec);
    this._arrangeTimer = null;
    this._arrangeStartTime = null;
    this._arrangeDeadlineAt = null;
    this._autoStartTimer = null;
    this._autoStartStartedAt = null;
    this._autoStartDeadlineAt = null;
    // Minimum play time: 30 minutes (starts counting from first hand played, not from join)
    this.minPlayMinutes = config.minPlayMinutes;
    this._playerJoinTime = new Map(); // seat -> join timestamp
    this._playerFirstPlayTime = new Map(); // seat -> timestamp of first hand actually played
  }

  addPlayer(seat, player) {
    this.players.set(seat, {
      ...player, hand: [], arranged: null,
      sittingOut: this.phase === 'arranging', // Join mid-game → wait for next hand
    });
    this._playerJoinTime.set(seat, Date.now());
    // Don't set _playerFirstPlayTime yet — only set when they actually play
    log(this.tableId, `➕ ${player.username} joined seat ${seat} (chips: ${player.chips})${this.phase === 'arranging' ? ' [sitting out]' : ''}`);
  }

  removePlayer(seat) {
    const p = this.players.get(seat);
    log(this.tableId, `➖ ${p?.username || '?'} left seat ${seat}`);
    this.players.delete(seat);
    this._playerJoinTime.delete(seat);
    this._playerFirstPlayTime.delete(seat);
  }

  canLeave(seat) {
    // If player hasn't played any hand yet (still spectating/waiting), allow leave immediately
    const firstPlayTime = this._playerFirstPlayTime.get(seat);
    if (!firstPlayTime) return { allowed: true };

    // Player has played — check minimum play time from first hand
    const elapsed = (Date.now() - firstPlayTime) / 1000 / 60; // minutes
    if (elapsed < this.minPlayMinutes) {
      const remaining = Math.ceil(this.minPlayMinutes - elapsed);
      return { allowed: false, remainingMinutes: remaining, message: `ต้องอยู่ในเกมอีก ${remaining} นาที (ขั้นต่ำ ${this.minPlayMinutes} นาที)` };
    }
    return { allowed: true };
  }

  startHand() {
    if (this.phase === 'arranging') {
      log(this.tableId, `⚠️ startHand() called during arranging — ignoring`);
      return null;
    }
    // Count active players (not sitting out)
    const activePlayers = [...this.players.entries()].filter(([_, p]) => !p.sittingOut);
    if (activePlayers.length < 2) {
      // Clear sittingOut for next attempt
      for (const [_, p] of this.players) p.sittingOut = false;
      if (this.players.size < 2) return null;
      // Retry with all players
      return this.startHand();
    }

    this.handNumber++;
    this.deck = newShuffledDeck();
    this.phase = 'arranging';
    this.lastResult = null;

    for (const [_, p] of this.players) {
      if (p.sittingOut) {
        p.hand = []; p.arranged = null;
        continue; // Don't deal cards to sitting out players
      }
      p.hand = []; p.arranged = null;
      for (let i = 0; i < 13; i++) p.hand.push(this.deck.pop());
      p.hand.sort((a, b) => RANK_VALUES[b[0]] - RANK_VALUES[a[0]]);
    }

    // Mark first play time for time lock (only first time playing)
    for (const [seat, p] of this.players) {
      if (!p.sittingOut && !this._playerFirstPlayTime.has(seat)) {
        this._playerFirstPlayTime.set(seat, Date.now());
        log(this.tableId, `  ⏱️ Seat ${seat} first hand — time lock starts now`);
      }
    }

    // Misdeal check: verify all players got exactly 13 cards
    for (const [seat, p] of this.players) {
      if (p.sittingOut) continue;
      if (p.hand.length !== 13) {
        log(this.tableId, `  ⚠️ MISDEAL: Seat ${seat} got ${p.hand.length} cards instead of 13 — redealing`);
        this.deck = newShuffledDeck();
        for (const [_, pl] of this.players) { if (!pl.sittingOut) pl.hand = []; }
        for (const [_, pl] of this.players) {
          if (pl.sittingOut) continue;
          for (let i = 0; i < 13; i++) pl.hand.push(this.deck.pop());
          pl.hand.sort((a, b) => RANK_VALUES[b[0]] - RANK_VALUES[a[0]]);
        }
        break;
      }
    }

    log(this.tableId, `\n${'='.repeat(50)}`);
    log(this.tableId, `🀄 HAND #${this.handNumber} START | ${this.players.size} players`);
    for (const [seat, p] of this.players) {
      log(this.tableId, `  🂠 Seat ${seat} (${p.username}): [${p.hand.join(', ')}]`);
    }
    log(this.tableId, `  ⏳ Waiting for all players to arrange cards...`);

    return this.getState();
  }

  arrangeCards(seat, front, middle, back) {
    const p = this.players.get(seat);
    if (!p) return { error: 'Player not found' };
    if (this.phase !== 'arranging') return { error: 'Not in arranging phase' };

    log(this.tableId, `\n  🃏 Seat ${seat} (${p.username}) arranging cards:`);
    log(this.tableId, `    Front (3): [${front.join(', ')}]`);
    log(this.tableId, `    Middle(5): [${middle.join(', ')}]`);
    log(this.tableId, `    Back  (5): [${back.join(', ')}]`);

    if (front.length !== 3 || middle.length !== 5 || back.length !== 5) {
      log(this.tableId, `    ❌ Invalid card count: front=${front.length} middle=${middle.length} back=${back.length}`);
      return { error: 'Front=3, Middle=5, Back=5 cards required' };
    }

    const all = [...front, ...middle, ...back];
    if (all.length !== 13) return { error: 'Must use all 13 cards' };
    const handSet = new Set(p.hand);
    if (!all.every(c => handSet.has(c))) {
      log(this.tableId, `    ❌ Cards don't match dealt hand`);
      return { error: 'Cards do not match dealt hand' };
    }

    const frontScore = evaluate3(front);
    const middleScore = evaluate5(middle);
    const backScore = evaluate5(back);

    log(this.tableId, `    Front : ${handName(frontScore, true)} [${frontScore.kickers}]`);
    log(this.tableId, `    Middle: ${handName(middleScore)} [${middleScore.kickers}]`);
    log(this.tableId, `    Back  : ${handName(backScore)} [${backScore.kickers}]`);

    // Foul check: front must be weakest, back must be strongest
    // Compare back vs middle (back must be >= middle)
    // Compare middle vs front (middle must be >= front)
    const isFoul = compareScores(backScore, middleScore) < 0 || compareScores(middleScore, frontScore) < 0;

    if (isFoul && this.policy.force_foul_on_invalid === false) {
      return { error: 'Invalid arrangement: back must be strongest and front weakest' };
    }

    if (isFoul) {
      log(this.tableId, `    ⚠️ FOUL: Back must be strongest, Front weakest — will lose all rows`);
    } else {
      log(this.tableId, `    ✅ Valid arrangement`);
    }

    p.arranged = {
      front, middle, back, frontScore, middleScore, backScore,
      frontName: handName(frontScore, true),
      middleName: handName(middleScore, false),
      backName: handName(backScore, false),
      isFoul,
    };

    const readyCount = [...this.players.values()].filter(pl => pl.arranged).length;
    const activeCount = [...this.players.values()].filter(pl => !pl.sittingOut).length;
    log(this.tableId, `  📊 ${readyCount}/${activeCount} players ready`);

    const allArranged = [...this.players.values()].filter(pl => !pl.sittingOut).every(pl => pl.arranged);
    if (allArranged) {
      log(this.tableId, `\n  🏁 All players arranged → SCORING`);
      return this._scoring();
    }
    return this.getState();
  }

  /**
   * OFC Scoring Rules (head-to-head between all player pairs):
   *
   * 1. Compare each row: winner +1, loser -1, tie = 0
   * 2. If one player wins ALL 3 rows → SCOOP: +3 extra bonus
   *    (total for winner = +3 rows + 3 bonus = +6, loser = -6)
   * 3. Fouled player auto-loses all 3 rows + scoop to every non-fouled player
   * 4. Add royalty difference between players
   * 5. coinChange = totalPoints × unit
   */
  _scoring() {
    this.clearArrangeTimer();
    this.phase = 'result';
    const players = [...this.players.entries()]
      .filter(([_, p]) => !p.sittingOut && p.arranged)
      .map(([seat, p]) => ({ seat, ...p }));
    for (const p of players) p.totalPoints = 0;
    const scoopBonus = Number(this.policy.scoop_bonus_points ?? 3);
    const foulPenalty = Number(this.policy.foul_penalty_points ?? scoopBonus + 3);

    // ═══ Dragon check (13 different ranks = instant win) ═══
    function isDragon(hand) {
      const ranks = new Set(hand.map(c => c[0]));
      return ranks.size === 13;
    }

    const dragonPlayers = players.filter(p => {
      const allCards = [...(p.arranged.front || []), ...(p.arranged.middle || []), ...(p.arranged.back || [])];
      return isDragon(allCards) && !p.arranged.isFoul;
    });

    const dragonSeats = new Set(dragonPlayers.map(p => p.seat));

    if (dragonPlayers.length > 0) {
      for (const dragon of dragonPlayers) {
        for (const other of players) {
          if (other.seat === dragon.seat) continue;
          if (dragonSeats.has(other.seat)) continue; // Dragon vs Dragon = cancel
          dragon.totalPoints += 13;
          other.totalPoints -= 13;
        }
        log(this.tableId, `  🐉 Seat ${dragon.seat} (${dragon.username}) has DRAGON! +13 from each opponent`);
      }
    }

    // Filter out dragon players from normal comparison
    const normalPlayers = players.filter(p => !dragonSeats.has(p.seat));

    // ═══ Head-to-head comparison for all player pairs ═══
    for (let i = 0; i < normalPlayers.length; i++) {
      for (let j = i + 1; j < normalPlayers.length; j++) {
        const a = normalPlayers[i], b = normalPlayers[j];
        const aFoul = a.arranged.isFoul;
        const bFoul = b.arranged.isFoul;

        // Per-row points tracking (for display)
        let aFrontPts = 0, aMiddlePts = 0, aBackPts = 0;
        let bFrontPts = 0, bMiddlePts = 0, bBackPts = 0;

        // Base scoring: row wins/losses
        let aBasePoints = 0, bBasePoints = 0;

        if (aFoul && bFoul) {
          // Both foul — no points exchanged
          log(this.tableId, `  ⚔️ Seat ${a.seat} vs Seat ${b.seat}: BOTH FOUL — no points`);
        } else if (aFoul) {
          // A fouls — B wins all 3 rows + scoop automatically
          // B gets the configured foul penalty.
          aBasePoints = -foulPenalty;
          bBasePoints = +foulPenalty;
          aFrontPts = -foulPenalty / 3; aMiddlePts = -foulPenalty / 3; aBackPts = -foulPenalty / 3;
          bFrontPts = +foulPenalty / 3; bMiddlePts = +foulPenalty / 3; bBackPts = +foulPenalty / 3;

          // B's royalties still apply (A forfeits theirs)
          const bRoy = frontRoyalty(b.arranged.frontScore) + middleRoyalty(b.arranged.middleScore) + backRoyalty(b.arranged.backScore);
          aBasePoints -= bRoy;
          bBasePoints += bRoy;

          // Per-row royalty display
          const bFrontRoy = frontRoyalty(b.arranged.frontScore);
          const bMiddleRoy = middleRoyalty(b.arranged.middleScore);
          const bBackRoy = backRoyalty(b.arranged.backScore);
          bFrontPts += bFrontRoy; bMiddlePts += bMiddleRoy; bBackPts += bBackRoy;
          aFrontPts -= bFrontRoy; aMiddlePts -= bMiddleRoy; aBackPts -= bBackRoy;

          log(this.tableId, `  ⚔️ Seat ${a.seat} vs Seat ${b.seat}: [A FOUL] → B wins +6, B royalty +${bRoy}`);
        } else if (bFoul) {
          // B fouls — A wins all 3 rows + scoop automatically
          aBasePoints = +foulPenalty;
          bBasePoints = -foulPenalty;
          aFrontPts = +foulPenalty / 3; aMiddlePts = +foulPenalty / 3; aBackPts = +foulPenalty / 3;
          bFrontPts = -foulPenalty / 3; bMiddlePts = -foulPenalty / 3; bBackPts = -foulPenalty / 3;

          // A's royalties still apply (B forfeits theirs)
          const aRoy = frontRoyalty(a.arranged.frontScore) + middleRoyalty(a.arranged.middleScore) + backRoyalty(a.arranged.backScore);
          aBasePoints += aRoy;
          bBasePoints -= aRoy;

          // Per-row royalty display
          const aFrontRoy = frontRoyalty(a.arranged.frontScore);
          const aMiddleRoy = middleRoyalty(a.arranged.middleScore);
          const aBackRoy = backRoyalty(a.arranged.backScore);
          aFrontPts += aFrontRoy; aMiddlePts += aMiddleRoy; aBackPts += aBackRoy;
          bFrontPts -= aFrontRoy; bMiddlePts -= aMiddleRoy; bBackPts -= aBackRoy;

          log(this.tableId, `  ⚔️ Seat ${a.seat} vs Seat ${b.seat}: [B FOUL] → A wins +6, A royalty +${aRoy}`);
        } else {
          // Normal comparison — compare each row head-to-head
          let aRowWins = 0, bRowWins = 0;

          // Front row comparison
          const fc = compareScores(a.arranged.frontScore, b.arranged.frontScore);
          if (fc > 0) { aRowWins++; aFrontPts += 1; bFrontPts -= 1; }
          else if (fc < 0) { bRowWins++; bFrontPts += 1; aFrontPts -= 1; }
          // tie = 0 for both

          // Middle row comparison
          const mc = compareScores(a.arranged.middleScore, b.arranged.middleScore);
          if (mc > 0) { aRowWins++; aMiddlePts += 1; bMiddlePts -= 1; }
          else if (mc < 0) { bRowWins++; bMiddlePts += 1; aMiddlePts -= 1; }

          // Back row comparison
          const bc = compareScores(a.arranged.backScore, b.arranged.backScore);
          if (bc > 0) { aRowWins++; aBackPts += 1; bBackPts -= 1; }
          else if (bc < 0) { bRowWins++; bBackPts += 1; aBackPts -= 1; }

          // Base points from row results
          aBasePoints = aRowWins - bRowWins;
          bBasePoints = bRowWins - aRowWins;

          // SCOOP bonus: if one player wins ALL 3 rows, add configured bonus
          const scoopPerRow = scoopBonus / 3;
          if (aRowWins === 3) {
            aBasePoints += scoopBonus;
            bBasePoints -= scoopBonus;
            // Display: distribute scoop bonus across rows
            aFrontPts += scoopPerRow; aMiddlePts += scoopPerRow; aBackPts += scoopPerRow;
            bFrontPts -= scoopPerRow; bMiddlePts -= scoopPerRow; bBackPts -= scoopPerRow;
          } else if (bRowWins === 3) {
            bBasePoints += scoopBonus;
            aBasePoints -= scoopBonus;
            bFrontPts += scoopPerRow; bMiddlePts += scoopPerRow; bBackPts += scoopPerRow;
            aFrontPts -= scoopPerRow; aMiddlePts -= scoopPerRow; aBackPts -= scoopPerRow;
          }

          // Royalties: each player collects their royalty from opponent
          // Net effect: add royalty difference to TOTAL POINTS only (not per-row display)
          const aRoyalty = frontRoyalty(a.arranged.frontScore) + middleRoyalty(a.arranged.middleScore) + backRoyalty(a.arranged.backScore);
          const bRoyalty = frontRoyalty(b.arranged.frontScore) + middleRoyalty(b.arranged.middleScore) + backRoyalty(b.arranged.backScore);

          aBasePoints += (aRoyalty - bRoyalty);
          bBasePoints += (bRoyalty - aRoyalty);

          log(this.tableId, `  ⚔️ Seat ${a.seat} vs Seat ${b.seat}:`);
          log(this.tableId, `    Front : ${a.arranged.frontName} vs ${b.arranged.frontName} → ${fc > 0 ? 'A' : fc < 0 ? 'B' : 'TIE'}`);
          log(this.tableId, `    Middle: ${a.arranged.middleName} vs ${b.arranged.middleName} → ${mc > 0 ? 'A' : mc < 0 ? 'B' : 'TIE'}`);
          log(this.tableId, `    Back  : ${a.arranged.backName} vs ${b.arranged.backName} → ${bc > 0 ? 'A' : bc < 0 ? 'B' : 'TIE'}`);
          log(this.tableId, `    Rows  : A=${aRowWins} B=${bRowWins} ${aRowWins === 3 ? '(A SCOOP!)' : bRowWins === 3 ? '(B SCOOP!)' : ''}`);
          log(this.tableId, `    Royalty: A=${aRoyalty} B=${bRoyalty}`);
          log(this.tableId, `    Points: A=${aBasePoints > 0 ? '+' : ''}${aBasePoints} B=${bBasePoints > 0 ? '+' : ''}${bBasePoints}`);
        }

        // Accumulate total points
        a.totalPoints += aBasePoints;
        b.totalPoints += bBasePoints;

        // Accumulate per-row scores for display
        a.frontPts = (a.frontPts || 0) + aFrontPts;
        a.middlePts = (a.middlePts || 0) + aMiddlePts;
        a.backPts = (a.backPts || 0) + aBackPts;
        b.frontPts = (b.frontPts || 0) + bFrontPts;
        b.middlePts = (b.middlePts || 0) + bMiddlePts;
        b.backPts = (b.backPts || 0) + bBackPts;
      }
    }

    // ═══ Convert points to coins ═══
    const unit = this.config.bigBlind;
    const rakePercent = this.config.rakePercent;
    const results = players.map(p => {
      const coinChange = p.totalPoints * unit;
      const player = this.players.get(p.seat);
      player.chips += coinChange;
      const frontPts = p.frontPts || 0;
      const middlePts = p.middlePts || 0;
      const backPts = p.backPts || 0;
      return {
        seat: p.seat, id: p.id, username: p.username,
        points: p.totalPoints, coinChange, chips: player.chips,
        front: p.arranged.front, middle: p.arranged.middle, back: p.arranged.back,
        frontName: p.arranged.frontName, middleName: p.arranged.middleName, backName: p.arranged.backName,
        frontScore: frontPts * unit, middleScore: middlePts * unit, backScore: backPts * unit,
        frontPts, middlePts, backPts,
        royalties: (p.arranged.isFoul ? 0 : frontRoyalty(p.arranged.frontScore) + middleRoyalty(p.arranged.middleScore) + backRoyalty(p.arranged.backScore)),
        isFoul: p.arranged.isFoul || false,
        qualifiesFantasyland: this.policy.fantasyland_enabled !== false && !p.arranged.isFoul && p.arranged.frontScore.hand >= FRONT_HAND_RANKS.ONE_PAIR && p.arranged.frontScore.kickers[0] >= 12,
      };
    });

    // ═══ RAKE: หัก % จากผู้ชนะ (รวม practice tables) ═══
    let totalRake = 0;
    {
      const rakeCap = Number(this.config.rakeCap || 0);
      const rakeEntries = results
        .filter(r => r.coinChange > 0)
        .map(r => ({ result: r, rake: Math.floor(r.coinChange * rakePercent / 100) }));
      const uncappedRake = rakeEntries.reduce((sum, entry) => sum + entry.rake, 0);
      totalRake = rakeCap > 0 ? Math.min(uncappedRake, rakeCap) : uncappedRake;
      for (const { result: r, rake } of rakeEntries) {
        const deducted = uncappedRake > 0 ? Math.floor(rake * totalRake / uncappedRake) : 0;
        const player = this.players.get(r.seat);
        if (player) player.chips -= deducted;
        r.chips = player?.chips || r.chips;
        r.rakeDeducted = deducted;
        r.coinChange -= deducted;
      }
      if (totalRake > 0) {
        log(this.tableId, `  💸 RAKE (Chinese): ${totalRake} total (${rakePercent}% from winners, cap: ${rakeCap || 'none'})`);
      }
    }
    this.rakeAmount = totalRake;

    log(this.tableId, `\n  💰 HAND #${this.handNumber} RESULTS (unit: ${unit}):`);
    for (const r of results) {
      const sign = r.coinChange >= 0 ? '+' : '';
      log(this.tableId, `    Seat ${r.seat} (${r.username}): ${r.points} pts → ${sign}${r.coinChange} coins (total: ${r.chips})${r.rakeDeducted ? ' [rake: -' + r.rakeDeducted + ']' : ''}`);
    }
    log(this.tableId, `${'='.repeat(50)}\n`);

    this.lastResult = { results, unit, handNumber: this.handNumber, rakeAmount: totalRake, rakePercent };
    return { ...this.getState(), result: this.lastResult };
  }

  /// Start the arrange timer. Calls onTimeout(room) when time runs out.
  startArrangeTimer(onTimeout) {
    this.clearArrangeTimer();
    this._arrangeStartTime = Date.now();
    this._arrangeDeadlineAt = this._arrangeStartTime + this.turnTimeSec * 1000;
    this._arrangeTimer = setTimeout(() => {
      this._arrangeTimer = null;
      if (this.phase !== 'arranging') return;
      log(this.tableId, `⏰ Arrange timer expired! Auto-arranging for remaining players...`);
      if (onTimeout) onTimeout(this);
    }, this.turnTimeSec * 1000);
    log(this.tableId, `  ⏱️ Arrange timer started: ${this.turnTimeSec}s`);
  }

  clearArrangeTimer() {
    if (this._arrangeTimer) {
      clearTimeout(this._arrangeTimer);
      this._arrangeTimer = null;
    }
    this._arrangeStartTime = null;
    this._arrangeDeadlineAt = null;
  }

  getRemainingSeconds() {
    if (!this._arrangeDeadlineAt || this.phase !== 'arranging') return this.turnTimeSec;
    return Math.max(0, Math.ceil((this._arrangeDeadlineAt - Date.now()) / 1000));
  }

  /// Auto-arrange cards for a seat — tries multiple strategies, picks best non-foul.
  /// Used by BOTS to arrange their cards intelligently.
  autoArrangeForSeat(seat) {
    const p = this.players.get(seat);
    if (!p || p.arranged || p.sittingOut || p.hand.length !== 13) return null;

    const sorted = [...p.hand].sort((a, b) => RANK_VALUES[b[0]] - RANK_VALUES[a[0]]);

    // Try all C(13,3) = 286 front combinations, pick best valid
    let bestArr = null;
    let bestScore = -99999;

    for (let i = 0; i < 13; i++) {
      for (let j = i + 1; j < 13; j++) {
        for (let k = j + 1; k < 13; k++) {
          const front = [sorted[i], sorted[j], sorted[k]];
          const remaining = [];
          for (let x = 0; x < 13; x++) {
            if (x !== i && x !== j && x !== k) remaining.push(sorted[x]);
          }
          const back = remaining.slice(0, 5);
          const middle = remaining.slice(5, 10);

          const backScore = evaluate5(back);
          const middleScore = evaluate5(middle);
          const frontScore = evaluate3(front);

          // Check valid (no foul): back >= middle >= front
          if (compareScores(backScore, middleScore) < 0) continue;
          if (compareScores(middleScore, frontScore) < 0) continue;

          const score = backScore.hand * 300 + middleScore.hand * 200 + frontScore.hand * 100 +
            (backScore.kickers[0] || 0) * 3 + (middleScore.kickers[0] || 0) * 2 + (frontScore.kickers[0] || 0);
          if (score > bestScore) {
            bestScore = score;
            bestArr = { front, middle, back };
          }
        }
      }
    }

    // Fallback: simple split (may be a foul)
    if (!bestArr) {
      bestArr = {
        back: sorted.slice(0, 5),
        middle: sorted.slice(5, 10),
        front: sorted.slice(10, 13),
      };
    }

    log(this.tableId, `  🤖 Auto-arranging seat ${seat} (${p.username}): F=[${bestArr.front}] M=[${bestArr.middle}] B=[${bestArr.back}]`);
    return this.arrangeCards(seat, bestArr.front, bestArr.middle, bestArr.back);
  }

  /// Force FOUL for a seat when timer expires — penalty for not confirming in time.
  forceFoulForSeat(seat) {
    const p = this.players.get(seat);
    if (!p || p.arranged || p.sittingOut || p.hand.length !== 13) return null;

    const sorted = [...p.hand].sort((a, b) => RANK_VALUES[b[0]] - RANK_VALUES[a[0]]);

    // Force FOUL: strongest cards in front, weakest in back (guaranteed invalid)
    const foulArr = {
      front: sorted.slice(0, 3),   // strongest 3 in front
      middle: sorted.slice(3, 8),  // next 5 in middle
      back: sorted.slice(8, 13),   // weakest 5 in back
    };

    log(this.tableId, `  ⏰ TIMEOUT FOUL seat ${seat} (${p.username}): forced foul arrangement`);
    return this.arrangeCards(seat, foulArr.front, foulArr.middle, foulArr.back);
  }

  getState(forSeat = null) {
    const players = {};
    for (const [seat, p] of this.players) {
      players[seat] = {
        id: p.id, username: p.username, chips: p.chips,
        hand: forSeat === seat ? p.hand : (this.phase === 'result' ? p.hand : []),
        arranged: this.phase === 'result' ? p.arranged : (forSeat === seat ? p.arranged : null),
        isReady: !!p.arranged,
        sittingOut: p.sittingOut || false,
        countryFlag: p.countryFlag || null,
      };
    }
    return {
      tableId: this.tableId, handNumber: this.handNumber,
      phase: this.phase, players, lastResult: this.lastResult,
      turnTotalSeconds: this.turnTimeSec,
      turnStartedAt: this._arrangeStartTime,
      turnDeadlineAt: this._arrangeDeadlineAt,
      turnRemainingSeconds: this.getRemainingSeconds(),
      seatReservations: [...this.seatReservations.entries()].map(([seatNumber, reservation]) => ({ seatNumber, userId: reservation.userId, expiresAt: reservation.expiresAt })),
      minimumPlayMinutes: this.minPlayMinutes,
      autoStartAt: this.config.autoStartAt,
      autoStartStartedAt: this._autoStartStartedAt,
      autoStartDeadlineAt: this._autoStartDeadlineAt,
      autoStartRemainingSeconds: this._autoStartDeadlineAt === null
        ? null
        : Math.max(0, Math.ceil((this._autoStartDeadlineAt - Date.now()) / 1000)),
    };
  }
}

module.exports = ChinesePokerRoom;
