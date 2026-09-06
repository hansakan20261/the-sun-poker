const { newShuffledDeck } = require('./deck');
const { findWinners } = require('./hand-evaluator');

function log(tableId, ...args) {
  console.log(`[Table ${tableId}]`, ...args);
}

class GameRoom {
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
    this.players = new Map();
    this.seatReservations = new Map();
    this.deck = [];
    this.communityCards = [];
    this.pot = 0;
    this.sidePots = [];
    this.currentRound = null;
    this.currentPlayerSeat = null;
    this.dealerSeat = null;
    this.handNumber = 0;
    this.actions = [];
    this.turnTimer = null;
    this._turnTimer = null;
    this._turnTotalSeconds = null;
    this._turnStartedAt = null;
    this._turnDeadlineAt = null;
    this._autoStartTimer = null;
    this._autoStartStartedAt = null;
    this._autoStartDeadlineAt = null;
    this.isPlaying = false;
    this.lastAggressor = null;
    this.minRaise = 0;
    this.lastResult = null;
    this.smallBlindSeat = null;
    this.bigBlindSeat = null;
    this.straddleSeat = null;
    this.maxSeats = Number(config.maxSeats);
    this.texasPolicy = config.texasPolicy || {};
    this._raisesThisRound = 0;
    this._roomCreatedAt = Date.now();
    this.closedReason = null;
    // Minimum play time starts from first hand played
    this.minPlayMinutes = config.minPlayMinutes;
    this._playerFirstPlayTime = new Map(); // seat -> timestamp of first hand played
  }

  addPlayer(seatNumber, player) {
    const seated = {
      ...player, holeCards: [], folded: false,
      currentBet: 0, allIn: false, hasActed: false,
      countryFlag: player.countryFlag || null,
      avatarUrl: player.avatarUrl || null,
      timeBankRemaining: Number(this.texasPolicy.time_bank_sec || 0),
      // If game is in progress, mark as sitting out until next hand
      sittingOut: this.isPlaying,
      sitOutTimer: null,
    };
    this.players.set(seatNumber, seated);
    if (seated.sittingOut) {
      const timeoutSec = Number(this.texasPolicy.sit_out_timeout_sec || 0);
      if (timeoutSec > 0) {
        seated.sitOutTimer = setTimeout(() => {
          const current = this.players.get(seatNumber);
          if (current?.sittingOut) {
            this.removePlayer(seatNumber);
            if (this.onSitOutTimeout) this.onSitOutTimeout(seatNumber, current);
          }
        }, timeoutSec * 1000);
      }
    }
    log(this.tableId, `➕ ${player.username} joined seat ${seatNumber} (chips: ${player.chips})${this.isPlaying ? ' [sitting out until next hand]' : ''}`);
  }

  requestStraddle(seatNumber, enabled = true) {
    if (this.isPlaying) return { error: 'Straddle can only be changed before the next hand' };
    const player = this.players.get(seatNumber);
    if (!player) return { error: 'Player not found' };
    if (player.sittingOut || player.disconnected === true) return { error: 'Player is not active' };
    if (enabled && this.texasPolicy.allow_straddle !== true) return { error: 'Straddle is disabled for this room' };
    const amount = Number(this.config.bigBlind) * 2;
    if (enabled && player.chips < amount) return { error: 'Insufficient chips for straddle' };
    player.straddleRequested = enabled === true;
    if (enabled) this.straddleSeat = seatNumber;
    else if (this.straddleSeat === seatNumber) this.straddleSeat = null;
    return { straddleSeat: this.straddleSeat, straddleRequested: player.straddleRequested };
  }

  removePlayer(seatNumber) {
    const p = this.players.get(seatNumber);
    if (p?.sitOutTimer) clearTimeout(p.sitOutTimer);
    if (this.straddleSeat === seatNumber) this.straddleSeat = null;
    log(this.tableId, `➖ ${p?.username || '?'} left seat ${seatNumber}`);
    this.players.delete(seatNumber);
    this._playerFirstPlayTime.delete(seatNumber);
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

  _sortedSeats() {
    return [...this.players.keys()].sort((a, b) => a - b);
  }

  _seatsAfter(startSeat) {
    const seats = this._sortedSeats();
    const idx = seats.indexOf(startSeat);
    if (idx === -1) return seats;
    return [...seats.slice(idx + 1), ...seats.slice(0, idx + 1)];
  }

  getActivePlayers() {
    return [...this.players.entries()]
      .filter(([_, p]) => !p.folded && !p.sittingOut)
      .map(([seat, p]) => ({ seat, ...p }));
  }

  _getActiveNonAllIn() {
    return [...this.players.entries()]
      .filter(([_, p]) => !p.folded && !p.allIn && !p.sittingOut)
      .map(([seat, p]) => ({ seat, ...p }));
  }

  startHand() {
    const eligiblePlayers = [...this.players.values()].filter(p => p.chips > 0 && p.disconnected !== true);
    if (this.players.size < 2 || eligiblePlayers.length < 2) return null;
    // Don't start a new hand if one is already in progress
    if (this.isPlaying) {
      log(this.tableId, `⚠️ startHand() called while game is in progress — ignoring`);
      return null;
    }
    if (this.texasPolicy.max_hands_per_room > 0 && this.handNumber >= this.texasPolicy.max_hands_per_room) {
      this.closedReason = 'max_hands_reached';
      throw new Error('Room hand limit reached');
    }
    if (this.texasPolicy.max_room_duration_hours > 0 &&
        Date.now() - this._roomCreatedAt >= this.texasPolicy.max_room_duration_hours * 3_600_000) {
      this.closedReason = 'max_room_duration_reached';
      throw new Error('Room duration limit reached');
    }
    this.handNumber++;
    this._raisesThisRound = 0;
    this.deck = newShuffledDeck();
    this.communityCards = [];
    this.runBoards = null;
    this.pot = 0;
    this.sidePots = [];
    this.actions = [];
    this.currentRound = 'preflop';
    this.isPlaying = true;
    this.lastAggressor = null;
    this.minRaise = this.config.bigBlind;

    for (const [_, p] of this.players) {
      if (p.sitOutTimer) { clearTimeout(p.sitOutTimer); p.sitOutTimer = null; }
      p.holeCards = []; p.folded = false; p.currentBet = 0; p.totalBetThisHand = 0; p.allIn = false; p.hasActed = false;
      p.timeBankRemaining = Number(this.texasPolicy.time_bank_sec || 0);
      p.hasStraddled = false;
      p.sittingOut = p.disconnected === true || p.chips <= 0; // Keep disconnected or broke players out of this hand
    }

    const seats = this._sortedSeats().filter(seat => {
      const player = this.players.get(seat);
      return player && player.chips > 0 && player.sittingOut !== true;
    });
    if (this.dealerSeat === null) {
      this.dealerSeat = seats[0];
    } else {
      const idx = seats.indexOf(this.dealerSeat);
      this.dealerSeat = seats[(idx + 1) % seats.length];
    }

    let sbSeat, bbSeat;
    if (seats.length === 2) {
      sbSeat = this.dealerSeat;
      bbSeat = seats.find(s => s !== this.dealerSeat);
    } else {
      const dIdx = seats.indexOf(this.dealerSeat);
      sbSeat = seats[(dIdx + 1) % seats.length];
      bbSeat = seats[(dIdx + 2) % seats.length];
    }

    // Store SB/BB seats as instance variables for getState()
    this.smallBlindSeat = sbSeat;
    this.bigBlindSeat = bbSeat;

    log(this.tableId, `\n${'='.repeat(50)}`);
    log(this.tableId, `🃏 HAND #${this.handNumber} START`);
    log(this.tableId, `  Dealer: seat ${this.dealerSeat}, SB: seat ${sbSeat}, BB: seat ${bbSeat}`);
    log(this.tableId, `  Players: ${seats.map(s => `seat${s}(${this.players.get(s).username}:${this.players.get(s).chips})`).join(', ')}`);

    const ante = Number(this.config.ante || 0);
    if (ante > 0) {
      for (const seat of seats) this._postForcedBet(seat, ante, 'ante');
    }
    this._postForcedBet(sbSeat, this.config.smallBlind, 'blind');
    this._postForcedBet(bbSeat, this.config.bigBlind, 'blind');

    const dealerIdx = seats.indexOf(this.dealerSeat);
    const dealOrder = [...seats.slice(dealerIdx + 1), ...seats.slice(0, dealerIdx + 1)];
    for (let round = 0; round < 2; round++) {
      for (const seat of dealOrder) {
        const p = this.players.get(seat);
        if (p) p.holeCards.push(this.deck.pop());
      }
    }

    for (const [seat, p] of this.players) {
      log(this.tableId, `  🂠 Seat ${seat} (${p.username}): ${p.holeCards.join(', ')}`);
    }

    // Mark first play time for time lock (only first time playing)
    for (const [seat] of this.players) {
      if (!this._playerFirstPlayTime.has(seat)) {
        this._playerFirstPlayTime.set(seat, Date.now());
        log(this.tableId, `  ⏱️ Seat ${seat} first hand — time lock starts now`);
      }
    }

    let straddledSeat = null;
    if (seats.length > 2) {
      const bbIdx = seats.indexOf(bbSeat);
      const utgSeat = this._findNextActive(bbIdx, seats);
      const requested = this.players.get(this.straddleSeat);
      if (utgSeat === this.straddleSeat && requested?.straddleRequested === true) {
        const straddleAmount = Math.min(Number(this.config.bigBlind) * 2, requested.chips);
        if (straddleAmount > 0) {
          requested.chips -= straddleAmount;
          requested.currentBet += straddleAmount;
          requested.totalBetThisHand += straddleAmount;
          this.pot += straddleAmount;
          if (requested.chips === 0) requested.allIn = true;
          requested.straddleRequested = false;
          requested.hasStraddled = true;
          this.actions.push({ seat: utgSeat, action: 'straddle', amount: straddleAmount, round: this.currentRound });
          straddledSeat = utgSeat;
          log(this.tableId, `  💰 Seat ${utgSeat} (${requested.username}) posts straddle ${straddleAmount} → chips: ${requested.chips}`);
        }
      }
    }

    if (seats.length === 2) {
      this.currentPlayerSeat = sbSeat;
    } else if (straddledSeat !== null) {
      const straddleIdx = seats.indexOf(straddledSeat);
      this.currentPlayerSeat = this._findNextActive(straddleIdx, seats);
    } else {
      const bbIdx = seats.indexOf(bbSeat);
      this.currentPlayerSeat = this._findNextActive(bbIdx, seats);
    }
    this.straddleSeat = straddledSeat;

    log(this.tableId, `  ▶ First to act: seat ${this.currentPlayerSeat} | Pot: ${this.pot}`);
    return this.getState();
  }

  _postForcedBet(seat, amount, action) {
    const p = this.players.get(seat);
    const actual = Math.min(amount, p.chips);
    p.chips -= actual;
    p.currentBet += actual;
    p.totalBetThisHand += actual;
    this.pot += actual;
    if (p.chips === 0) p.allIn = true;
    this.actions.push({ seat, action, amount: actual, round: this.currentRound });
    log(this.tableId, `  💰 Seat ${seat} (${p.username}) posts ${action} ${actual} → chips: ${p.chips}`);
  }

  _findNextActive(fromIdx, seats) {
    for (let i = 1; i <= seats.length; i++) {
      const idx = (fromIdx + i) % seats.length;
      const p = this.players.get(seats[idx]);
      if (p && !p.folded && !p.allIn && !p.sittingOut) return seats[idx];
    }
    return null;
  }

  handleAction(seat, action, amount = 0) {
    // Reject actions when no hand is in progress
    if (!this.isPlaying) {
      log(this.tableId, `❌ Seat ${seat} tried to act but no hand in progress`);
      return { error: 'No hand in progress' };
    }
    if (seat !== this.currentPlayerSeat) {
      log(this.tableId, `❌ Seat ${seat} tried to act but it's seat ${this.currentPlayerSeat}'s turn`);
      return { error: 'Not your turn' };
    }
    const p = this.players.get(seat);
    if (!p) return { error: 'Player not found' };
    if (p.folded) return { error: 'Player already folded' };
    if (p.sittingOut) return { error: 'Player is sitting out' };

    const maxBet = Math.max(...[...this.players.values()].map(x => x.currentBet));
    log(this.tableId, `\n  🎯 Seat ${seat} (${p.username}) → ${action}${amount ? ' ' + amount : ''} | round: ${this.currentRound} | maxBet: ${maxBet} | myBet: ${p.currentBet} | chips: ${p.chips}`);

    switch (action) {
      case 'fold':
        p.folded = true; p.hasActed = true;
        log(this.tableId, `    ❌ FOLD`);
        break;

      case 'call': {
        const toCall = Math.min(maxBet - p.currentBet, p.chips);
        p.chips -= toCall; p.currentBet += toCall; p.totalBetThisHand += toCall; this.pot += toCall;
        if (p.chips === 0) p.allIn = true;
        p.hasActed = true;
        log(this.tableId, `    📞 CALL ${toCall} → bet: ${p.currentBet}, chips: ${p.chips}, pot: ${this.pot}${p.allIn ? ' (ALL-IN)' : ''}`);
        break;
      }

      case 'raise': {
        const maxRaises = Number(this.texasPolicy.max_raises_per_round || 0);
        if (maxRaises > 0 && this._raisesThisRound >= maxRaises) {
          return { error: `Maximum raises per round reached (${maxRaises})` };
        }
        const toCall = maxBet - p.currentBet;
        const raiseOn = amount - toCall;
        if (raiseOn < this.minRaise && amount < p.chips) {
          log(this.tableId, `    ❌ RAISE rejected: raiseOn=${raiseOn} < minRaise=${this.minRaise}`);
          return { error: `Minimum raise is ${this.minRaise}` };
        }
        const totalBet = Math.min(amount, p.chips);
        p.chips -= totalBet; p.currentBet += totalBet; p.totalBetThisHand += totalBet; this.pot += totalBet;
        if (p.chips === 0) p.allIn = true;
        if (raiseOn > 0) {
          this.minRaise = raiseOn;
          this._raisesThisRound++;
        }
        this.lastAggressor = seat;
        p.hasActed = true;
        for (const [s, pl] of this.players) {
          if (s !== seat && !pl.folded && !pl.allIn) pl.hasActed = false;
        }
        log(this.tableId, `    📈 RAISE ${totalBet} (call:${toCall} + raise:${raiseOn}) → bet: ${p.currentBet}, chips: ${p.chips}, pot: ${this.pot}${p.allIn ? ' (ALL-IN)' : ''}`);
        break;
      }

      case 'check':
        if (p.currentBet < maxBet) {
          log(this.tableId, `    ❌ CHECK rejected: myBet ${p.currentBet} < maxBet ${maxBet}`);
          return { error: 'Cannot check, must call or raise' };
        }
        p.hasActed = true;
        log(this.tableId, `    ✅ CHECK`);
        break;

      case 'all_in': {
        const allInAmount = p.chips;
        const wouldRaise = p.currentBet + allInAmount > maxBet;
        const maxRaises = Number(this.texasPolicy.max_raises_per_round || 0);
        if (wouldRaise && maxRaises > 0 && this._raisesThisRound >= maxRaises) {
          return { error: `Maximum raises per round reached (${maxRaises})` };
        }
        this.pot += allInAmount; p.currentBet += allInAmount; p.totalBetThisHand += allInAmount; p.chips = 0; p.allIn = true; p.hasActed = true;
        if (p.currentBet > maxBet) {
          const raiseOn = p.currentBet - maxBet;
          if (raiseOn >= this.minRaise) {
            this.minRaise = raiseOn;
            this._raisesThisRound++;
          }
          this.lastAggressor = seat;
          for (const [s, pl] of this.players) {
            if (s !== seat && !pl.folded && !pl.allIn) pl.hasActed = false;
          }
        }
        log(this.tableId, `    🔥 ALL-IN ${allInAmount} → bet: ${p.currentBet}, pot: ${this.pot}`);
        break;
      }

      default: return { error: 'Invalid action' };
    }

    this.actions.push({ seat, action, amount, round: this.currentRound });

    // Check if only one non-folded player left
    const active = this.getActivePlayers();
    if (active.length === 1) {
      log(this.tableId, `  🏆 Only 1 player left → end hand`);
      return this._endHand([[active[0]]]);
    }

    // Log player states for debugging
    this._logPlayerStates();

    // Check if round is complete
    const roundDone = this._isRoundComplete();
    log(this.tableId, `  🔄 Round complete? ${roundDone}`);

    if (roundDone) return this._nextRound();

    // Move to next player
    this._moveToNextPlayer();
    log(this.tableId, `  ▶ Next to act: seat ${this.currentPlayerSeat}`);
    return this.getState();
  }

  _logPlayerStates() {
    for (const [seat, p] of this.players) {
      log(this.tableId, `    [Seat ${seat}] ${p.username}: chips=${p.chips} bet=${p.currentBet} folded=${p.folded} allIn=${p.allIn} hasActed=${p.hasActed}`);
    }
  }

  _moveToNextPlayer() {
    const seats = this._sortedSeats();
    const idx = seats.indexOf(this.currentPlayerSeat);
    this.currentPlayerSeat = this._findNextActive(idx, seats);
  }

  _isRoundComplete() {
    const active = this._getActiveNonAllIn();
    if (active.length === 0) {
      log(this.tableId, `    ✓ Round complete: all players folded or all-in`);
      return true;
    }
    const allActed = active.every(p => p.hasActed);
    const maxBet = Math.max(...active.map(p => p.currentBet));
    const allEqual = active.every(p => p.currentBet === maxBet);
    log(this.tableId, `    ⏳ RoundCheck: active=${active.length}, allActed=${allActed}, maxBet=${maxBet}, allEqual=${allEqual}`);
    if (!allActed) return false;
    return allEqual;
  }

  _nextRound() {
    for (const [_, p] of this.players) { p.currentBet = 0; p.hasActed = false; }
    // Note: totalBetThisHand is NOT reset here — it accumulates across all rounds for side pot calculation
    this.lastAggressor = null;
    this.minRaise = this.config.bigBlind;
    this._raisesThisRound = 0;

    this.deck.pop(); // burn

    const prevRound = this.currentRound;
    switch (this.currentRound) {
      case 'preflop':
        this.currentRound = 'flop';
        this.communityCards.push(this.deck.pop(), this.deck.pop(), this.deck.pop());
        break;
      case 'flop':
        this.currentRound = 'turn';
        this.communityCards.push(this.deck.pop());
        break;
      case 'turn':
        this.currentRound = 'river';
        this.communityCards.push(this.deck.pop());
        break;
      case 'river':
        log(this.tableId, `\n  🏁 SHOWDOWN after river`);
        return this._showdown();
    }

    log(this.tableId, `\n  📍 ${prevRound} → ${this.currentRound} | Community: [${this.communityCards.join(', ')}] | Pot: ${this.pot}`);

    const seats = this._sortedSeats();
    const dIdx = seats.indexOf(this.dealerSeat);
    const nextPlayer = this._findNextActive(dIdx, seats);

    if (!nextPlayer) {
      log(this.tableId, `  ⚡ All players all-in → deal remaining cards`);
      return this._dealRemainingAndShowdown();
    }

    this.currentPlayerSeat = nextPlayer;
    log(this.tableId, `  ▶ First to act: seat ${this.currentPlayerSeat}`);
    return this.getState();
  }

  _dealRemainingAndShowdown() {
    const active = this.getActivePlayers();
    const canRunTwice = this.texasPolicy.allow_run_twice === true &&
      active.length >= 2 && active.every(p => p.allIn === true);

    if (!canRunTwice) {
      while (this.communityCards.length < 5) {
        this.deck.pop(); // burn
        this.communityCards.push(this.deck.pop());
      }
      log(this.tableId, `  🃏 Final board: [${this.communityCards.join(', ')}]`);
      return this._showdown();
    }

    const firstBoard = [...this.communityCards];
    const secondBoard = [...this.communityCards];
    while (firstBoard.length < 5) {
      this.deck.pop(); // burn
      firstBoard.push(this.deck.pop());
    }
    while (secondBoard.length < 5) {
      this.deck.pop(); // burn
      secondBoard.push(this.deck.pop());
    }
    this.runBoards = [firstBoard, secondBoard];
    this.communityCards = firstBoard;
    log(this.tableId, `  🃏 Run-it-twice boards: [${firstBoard.join(', ')}] / [${secondBoard.join(', ')}]`);
    return this._showdown();
  }

  _showdown() {
    const active = this.getActivePlayers();
    log(this.tableId, `  👀 Showdown: ${active.map(p => `seat${p.seat}(${p.holeCards.join(',')})`).join(' vs ')}`);
    const boards = this.runBoards?.length ? this.runBoards : [this.communityCards];
    const winnersByRun = boards.map(board => findWinners(
      active.map(p => ({ id: p.id, seat: p.seat, holeCards: p.holeCards })),
      board
    ));
    winnersByRun.forEach((winners, index) => {
      log(this.tableId, `  🏆 Run ${index + 1} winners: ${winners.map(w => `seat${w.seat}(${this._handName(w.score?.hand)})`).join(', ')}`);
    });
    return this._endHand(winnersByRun);
  }

  calculateSidePots() {
    const activePlayers = [...this.players.entries()]
      .filter(([_, p]) => !p.folded)
      .map(([seat, p]) => ({ seat, totalBet: p.totalBetThisHand || 0, allIn: p.allIn }));

    // Include folded players' contributions
    const foldedPlayers = [...this.players.entries()]
      .filter(([_, p]) => p.folded)
      .map(([seat, p]) => ({ seat, totalBet: p.totalBetThisHand || 0, allIn: false }));

    const allContributors = [...activePlayers, ...foldedPlayers]
      .filter(p => p.totalBet > 0);

    if (allContributors.length === 0) return [];

    // Get unique all-in bet levels sorted ascending
    const allInLevels = [...new Set(
      activePlayers.filter(p => p.allIn).map(p => p.totalBet)
    )].sort((a, b) => a - b);

    const sidePots = [];
    let processedBet = 0;

    for (const level of allInLevels) {
      const contribution = level - processedBet;
      if (contribution <= 0) continue;

      // Everyone who bet at least this level contributes
      const contributors = allContributors.filter(p => p.totalBet > processedBet);
      const potAmount = contributors.reduce((sum, p) => {
        return sum + Math.min(p.totalBet - processedBet, contribution);
      }, 0);

      // Only active (non-folded) players who bet enough are eligible to win
      const eligibleSeats = activePlayers
        .filter(p => p.totalBet >= level)
        .map(p => p.seat);

      if (potAmount > 0) {
        sidePots.push({ amount: potAmount, eligibleSeats });
      }
      processedBet = level;
    }

    // Main pot: remaining bets above the highest all-in level
    const remainingContributors = allContributors.filter(p => p.totalBet > processedBet);
    if (remainingContributors.length > 0) {
      const mainPotAmount = remainingContributors.reduce((sum, p) => {
        return sum + (p.totalBet - processedBet);
      }, 0);

      const eligibleSeats = activePlayers
        .filter(p => p.totalBet > processedBet)
        .map(p => p.seat);

      if (mainPotAmount > 0) {
        sidePots.push({ amount: mainPotAmount, eligibleSeats });
      }
    }

    return sidePots;
  }

  _endHand(winnersByRun) {
    const runs = Array.isArray(winnersByRun?.[0]) ? winnersByRun : [winnersByRun];
    const runCount = Math.max(1, runs.length);
    const boards = this.runBoards?.length ? this.runBoards : [this.communityCards];
    const grossPots = this.calculateSidePots();
    const grossTotal = grossPots.reduce((sum, pot) => sum + pot.amount, 0);

    const rakePercent = this.config.rakePercent;
    const rakeCap = Number(this.config.rakeCap); // 0 = no cap
    const minimumRakePot = Number(this.texasPolicy.minimum_rake_pot || 0);
    const noFlopNoDrop = this.texasPolicy.no_flop_no_drop !== false;
    const reachedFlop = boards.some(board => board.length >= 3);
    let rakeAmount = 0;

    if (grossTotal > 0 && (!noFlopNoDrop || reachedFlop) && grossTotal >= minimumRakePot) {
      rakeAmount = Math.floor(grossTotal * rakePercent / 100);
      if (rakeCap > 0 && rakeAmount > rakeCap) rakeAmount = rakeCap;
      log(this.tableId, `  💸 RAKE: ${rakeAmount} (${rakePercent}% of pot, cap: ${rakeCap || 'none'}) → Net pot: ${grossTotal - rakeAmount}`);
    }
    this.rakeAmount = rakeAmount;

    const netTotal = Math.max(0, grossTotal - rakeAmount);
    let remainingNet = netTotal;
    const sidePots = grossPots.map((pot, index) => {
      const amount = index === grossPots.length - 1
        ? remainingNet
        : Math.floor(pot.amount * netTotal / grossTotal);
      remainingNet -= amount;
      return { ...pot, amount };
    });
    this.sidePots = sidePots;
    this.pot = netTotal;

    const distributions = new Map();
    const credit = (seat, amount) => {
      if (amount <= 0) return;
      const player = this.players.get(seat);
      if (!player) return;
      player.chips += amount;
      distributions.set(seat, (distributions.get(seat) || 0) + amount);
    };

    for (const pot of sidePots) {
      const amountPerRun = Math.floor(pot.amount / runCount);
      for (let runIndex = 0; runIndex < runCount; runIndex++) {
        const runAmount = amountPerRun + (runIndex === 0 ? pot.amount - amountPerRun * runCount : 0);
        const runWinners = runs[runIndex] || [];
        const eligibleWinners = runWinners.filter(w => pot.eligibleSeats.includes(w.seat));
        if (eligibleWinners.length === 0) {
          credit(pot.eligibleSeats[0], runAmount);
          continue;
        }
        const prizeEach = Math.floor(runAmount / eligibleWinners.length);
        const remainder = runAmount - prizeEach * eligibleWinners.length;
        eligibleWinners.forEach((winner, index) => {
          credit(winner.seat, prizeEach + (index === 0 ? remainder : 0));
        });
      }
    }

    const winnerSummaries = [...distributions.entries()].map(([seat, amount]) => {
      const player = this.players.get(seat);
      const winningRun = runs.findIndex(run => run.some(w => w.seat === seat));
      const winningScore = winningRun >= 0 ? runs[winningRun].find(w => w.seat === seat)?.score : null;
      return {
        seat,
        id: player?.id,
        username: player?.username,
        holeCards: player?.holeCards || [],
        handName: winningScore?.hand ? this._handName(winningScore.hand) : null,
        amount,
      };
    });
    const winnerSeats = new Set(winnerSummaries.map(w => w.seat));

    this.isPlaying = false;
    this.currentRound = 'result';

    log(this.tableId, `\n  💰 HAND #${this.handNumber} END | Pot: ${this.pot} | Runs: ${runCount}`);
    for (const winner of winnerSummaries) {
      log(this.tableId, `    🏆 Winner: seat ${winner.seat} (${winner.username}) → +${winner.amount} chips (total: ${this.players.get(winner.seat)?.chips})`);
    }
    log(this.tableId, `${'='.repeat(50)}\n`);

    this.lastResult = {
      winners: winnerSummaries.map(({ holeCards, ...winner }) => winner),
      losers: [...this.players.entries()]
        .filter(([seat]) => !winnerSeats.has(seat))
        .map(([seat, p]) => ({ seat, id: p.id, username: p.username, folded: p.folded, amount: p.totalBetThisHand || 0 })),
      pot: this.pot,
      handNumber: this.handNumber,
      rakeAmount,
      rakePercent,
      runCount,
      runBoards: boards.length > 1 ? boards : undefined,
      timestamp: new Date().toISOString(),
    };

    return {
      ...this.getState(),
      result: {
        winners: winnerSummaries,
        losers: [...this.players.entries()]
          .filter(([seat]) => !winnerSeats.has(seat))
          .map(([seat, p]) => ({
            seat, id: p.id, username: p.username,
            holeCards: p.holeCards || [], folded: p.folded,
            amount: p.totalBetThisHand || 0,
          })),
        communityCards: this.communityCards,
        runBoards: boards.length > 1 ? boards : undefined,
        pot: this.pot,
        runCount,
        rakeAmount,
        rakePercent,
      },
    };
  }

  _handName(rank) {
    const names = {
      9: 'Royal Flush', 8: 'Straight Flush', 7: 'Four of a Kind',
      6: 'Full House', 5: 'Flush', 4: 'Straight', 3: 'Three of a Kind',
      2: 'Two Pair', 1: 'One Pair', 0: 'High Card',
    };
    return names[rank] || 'Unknown';
  }

  getState(forSeat = null) {
    const players = {};
    for (const [seat, p] of this.players) {
      // Hole card privacy (Task 3.5):
      // - Owner always sees their own cards
      // - During "result" round, reveal cards of players who went to showdown (not folded)
      // - Folded players' cards remain hidden unless it's the owner viewing their own
      // - Otherwise mask as ["??", "??"]
      let holeCards;
      if (forSeat === seat) {
        holeCards = p.holeCards;
      } else if ((this.currentRound === 'result' || !this.isPlaying) && !p.folded) {
        holeCards = p.holeCards || ['??', '??'];
      } else {
        holeCards = ['??', '??'];
      }

      // Find last action for this player in current round
      const lastAct = [...this.actions].reverse().find(a => a.seat === seat && a.round === this.currentRound);

      players[seat] = {
        id: p.id, username: p.username, chips: p.chips,
        folded: p.folded, currentBet: p.currentBet, allIn: p.allIn,
        sittingOut: p.sittingOut || false,
        disconnected: p.disconnected === true,
        holeCards,
        lastAction: lastAct ? lastAct.action : null,
        // Position indicators (Task 3.3)
        isDealer: seat === this.dealerSeat,
        isSB: seat === this.smallBlindSeat,
        isBB: seat === this.bigBlindSeat,
        countryFlag: p.countryFlag || null,
        avatarUrl: p.avatarUrl || null,
        timeBankRemaining: p.timeBankRemaining || 0,
        straddleRequested: p.straddleRequested === true,
        hasStraddled: p.hasStraddled === true,
        seatNumber: seat,
      };
    }

    const playerBets = [...this.players.values()].map(p => p.currentBet);
    const maxBet = playerBets.length > 0 ? Math.max(...playerBets) : 0;

    return {
      tableId: this.tableId, handNumber: this.handNumber,
      closedReason: this.closedReason,
      isTournament: this.isTournament === true,
      communityCards: this.communityCards, pot: this.pot,
      currentRound: this.currentRound, currentPlayerSeat: this.currentPlayerSeat,
      dealerSeat: this.dealerSeat, isPlaying: this.isPlaying, players,
      smallBlindSeat: this.smallBlindSeat,
      bigBlindSeat: this.bigBlindSeat,
      straddleSeat: this.straddleSeat,
      minRaise: this.minRaise,
      maxBet,
      sidePots: this.sidePots || [],
      lastResult: this.lastResult || null,
      turnTotalSeconds: this._turnTotalSeconds,
      turnStartedAt: this._turnStartedAt,
      turnDeadlineAt: this._turnDeadlineAt,
      turnRemainingSeconds: this._turnDeadlineAt === null
        ? null
        : Math.max(0, Math.ceil((this._turnDeadlineAt - Date.now()) / 1000)),
      seatReservations: [...this.seatReservations.entries()].map(([seatNumber, reservation]) => ({ seatNumber, userId: reservation.userId, expiresAt: reservation.expiresAt })),
      minimumPlayMinutes: this.minPlayMinutes,
      features: {
        allowRebuy: this.texasPolicy.allow_rebuy !== false,
        allowStraddle: this.texasPolicy.allow_straddle === true,
        allowRunTwice: this.texasPolicy.allow_run_twice === true,
        maxRaisesPerRound: this.texasPolicy.max_raises_per_round ?? 0,
      },
      autoStartAt: this.config.autoStartAt,
      autoStartStartedAt: this._autoStartStartedAt,
      autoStartDeadlineAt: this._autoStartDeadlineAt,
      autoStartRemainingSeconds: this._autoStartDeadlineAt === null
        ? null
        : Math.max(0, Math.ceil((this._autoStartDeadlineAt - Date.now()) / 1000)),
    };
  }
}

module.exports = GameRoom;
