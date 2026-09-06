const GameRoom = require('./game-room');

/**
 * TournamentRoom — wraps GameRoom with tournament-specific logic:
 * - Blind level escalation on timer
 * - Player elimination (chips = 0 → eliminated, no rebuy)
 * - Tracks remaining players for rebalance/finish
 */
class TournamentRoom extends GameRoom {
  constructor(tableId, config, tournamentConfig) {
    super(tableId, config);
    this.isTournament = true;
    this.isPractice = false;
    
    // Tournament-specific config
    this.tournamentId = tournamentConfig.tournamentId;
    this.blindLevels = tournamentConfig.blindLevels || [];
    this.currentBlindLevel = 0;
    this.blindLevelDurationMs = tournamentConfig.blindLevelMinutes * 60 * 1000;
    this.blindTimer = null;
    this.blindLevelStartTime = null;
    this.breakIntervalMs = (tournamentConfig.breakIntervalMinutes || 0) * 60 * 1000;
    this.breakDurationMs = (tournamentConfig.breakDurationMinutes || 0) * 60 * 1000;
    this.breakTimer = null;
    this.breakEndTimer = null;
    this.isOnBreak = false;
    this.currentBreakEndsAt = null;
    
    // Tournament state
    this.eliminatedPlayers = []; // [{id, username, seat, finishRank, eliminatedAt}]
    this.totalPlayersStarted = 0;
    this.tournamentStatus = 'waiting'; // waiting, running, finished
    
    // Callbacks
    this.onBlindUp = null; // (level) => {}
    this.onBreakStarted = null; // ({ endsAt }) => {}
    this.onBreakEnded = null; // () => {}
    this.onPlayerEliminated = null; // (player, rank) => {}
    this.onTournamentFinished = null; // (winner) => {}

  }

  /**
   * Start the tournament game loop
   */
  startTournament() {
    this.tournamentStatus = 'running';
    this.totalPlayersStarted = this.players.size;
    
    // Set initial blinds from level 0
    if (this.blindLevels.length > 0) {
      this._applyBlindLevel(0);
    }
    
    // Start blind timer
    this._startBlindTimer();
    this._startBreakTimer();
    
    console.log(`🏆 [TOURNAMENT] Started on table ${this.tableId} | ${this.players.size} players | Blinds: ${this.config.smallBlind}/${this.config.bigBlind}`);
    return this.startHand();
  }

  /**
   * Override handleAction to check for elimination after hand ends
   */
  handleAction(seat, action, amount = 0) {
    const result = super.handleAction(seat, action, amount);
    
    // If hand ended, check for eliminated players
    if (result && result.result) {
      this._checkEliminations();
    }
    
    return result;
  }

  /**
   * Check and eliminate players with 0 chips
   */
  _checkEliminations() {
    const busted = [];
    for (const [seat, p] of this.players) {
      if (p.chips <= 0 && !p.folded) {
        busted.push({ seat, ...p });
      }
    }

    for (const player of busted) {
      const remainingCount = this.players.size - busted.indexOf(player);
      const finishRank = this.totalPlayersStarted - this.eliminatedPlayers.length - busted.length + busted.indexOf(player) + 1;
      
      this.eliminatedPlayers.push({
        id: player.id,
        username: player.username,
        seat: player.seat,
        finishRank,
        eliminatedAt: new Date(),
      });
      
      this.removePlayer(player.seat);
      console.log(`💀 [TOURNAMENT] ${player.username} ELIMINATED (rank #${finishRank}) | ${this.players.size} remain`);
      
      if (this.onPlayerEliminated) {
        this.onPlayerEliminated(player, finishRank);
      }
    }

    // Check if tournament is over (1 player left)
    if (this.players.size <= 1) {
      this._finishTournament();
    }
  }

  /**
   * Start next hand after result delay (tournament auto-deals)
   */
  startNextHand() {
    if (this.tournamentStatus !== 'running' || this.isOnBreak) return null;
    if (this.players.size < 2) {
      this._finishTournament();
      return null;
    }
    return this.startHand();
  }

  /**
   * Finish tournament — declare winner
   */
  _finishTournament() {
    this.tournamentStatus = 'finished';
    this._stopBlindTimer();
    
    // The last remaining player is the winner
    const winner = this.players.size > 0 ? [...this.players.values()][0] : null;
    if (winner) {
      console.log(`🏆 [TOURNAMENT] FINISHED! Winner: ${winner.username} | ${this.eliminatedPlayers.length} eliminated`);
    }
    
    if (this.onTournamentFinished) {
      this.onTournamentFinished(winner, this.eliminatedPlayers);
    }
  }

  /**
   * Apply blind level
   */
  _applyBlindLevel(levelIndex) {
    if (levelIndex >= this.blindLevels.length) {
      // Beyond defined levels — keep doubling last level
      const lastLevel = this.blindLevels[this.blindLevels.length - 1];
      const multiplier = Math.pow(2, levelIndex - this.blindLevels.length + 1);
      this.config.smallBlind = lastLevel.small_blind * multiplier;
      this.config.bigBlind = lastLevel.big_blind * multiplier;
      this.config.ante = (lastLevel.ante || 0) * multiplier;
    } else {
      const level = this.blindLevels[levelIndex];
      this.config.smallBlind = level.small_blind;
      this.config.bigBlind = level.big_blind;
      this.config.ante = level.ante || 0;
    }
    this.currentBlindLevel = levelIndex;
    this.blindLevelStartTime = Date.now();
    
    console.log(`📈 [TOURNAMENT] Blind Level ${levelIndex + 1}: SB=${this.config.smallBlind} BB=${this.config.bigBlind} Ante=${this.config.ante || 0}`);
  }

  /**
   * Start blind escalation timer
   */
  _startBlindTimer() {
    this._stopBlindTimer();
    this.blindTimer = setInterval(() => {
      if (this.tournamentStatus !== 'running') {
        this._stopBlindTimer();
        return;
      }
      if (this.isOnBreak) return;
      this.currentBlindLevel++;
      this._applyBlindLevel(this.currentBlindLevel);
      
      if (this.onBlindUp) {
        this.onBlindUp({
          level: this.currentBlindLevel + 1,
          smallBlind: this.config.smallBlind,
          bigBlind: this.config.bigBlind,
          ante: this.config.ante || 0,
        });
      }
    }, this.blindLevelDurationMs);
  }

  _startBreakTimer() {
    if (this.breakIntervalMs <= 0 || this.breakDurationMs <= 0) return;
    this.breakTimer = setInterval(() => {
      if (this.tournamentStatus !== 'running') return;
      this.isOnBreak = true;
      this.currentBreakEndsAt = Date.now() + this.breakDurationMs;
      if (this.onBreakStarted) this.onBreakStarted({ endsAt: this.currentBreakEndsAt });
      clearTimeout(this.breakEndTimer);
      this.breakEndTimer = setTimeout(() => {
        this.isOnBreak = false;
        this.currentBreakEndsAt = null;
        if (this.onBreakEnded) this.onBreakEnded();
      }, this.breakDurationMs);
    }, this.breakIntervalMs);
  }

  _stopBreakTimer() {
    if (this.breakTimer) clearInterval(this.breakTimer);
    if (this.breakEndTimer) clearTimeout(this.breakEndTimer);
    this.breakTimer = null;
    this.breakEndTimer = null;
    this.isOnBreak = false;
    this.currentBreakEndsAt = null;
  }

  _stopBlindTimer() {
    if (this.blindTimer) {
      clearInterval(this.blindTimer);
      this.blindTimer = null;
    }
  }

  /**
   * Get tournament-specific state for clients
   */
  getTournamentState() {
    return {
      tournamentId: this.tournamentId,
      status: this.tournamentStatus,
      currentBlindLevel: this.currentBlindLevel + 1,
      smallBlind: this.config.smallBlind,
      bigBlind: this.config.bigBlind,
      ante: this.config.ante || 0,
      playersRemaining: this.players.size,
      totalPlayers: this.totalPlayersStarted,
      eliminatedCount: this.eliminatedPlayers.length,
      nextLevelIn: this.blindLevelStartTime
        ? Math.max(0, this.blindLevelDurationMs - (Date.now() - this.blindLevelStartTime))
        : 0,
      blindLevels: this.blindLevels,
      isOnBreak: this.isOnBreak,
      breakEndsAt: this.currentBreakEndsAt,
    };
  }

  /**
   * Override getState to include tournament info
   */
  getState(forSeat) {
    const baseState = super.getState(forSeat);
    return {
      ...baseState,
      tournament: this.getTournamentState(),
    };
  }

  /**
   * Override canLeave — tournament players cannot voluntarily leave
   */
  canLeave(seat) {
    if (this.tournamentStatus === 'running') {
      return { allowed: false, message: 'ไม่สามารถออกระหว่างแข่งทัวร์นาเมนต์ได้' };
    }
    return { allowed: true };
  }

  /**
   * Clean up
   */
  destroy() {
    this._stopBlindTimer();
    this._stopBreakTimer();
  }
}

module.exports = TournamentRoom;
