const TournamentRoom = require('./tournament-room');

/**
 * TournamentManager — manages multiple tables for a single tournament.
 * Handles:
 * - Creating and tracking tournament tables (TournamentRoom instances)
 * - Table rebalancing when player counts become uneven
 * - Merging tables as players are eliminated
 * - Final Table transition
 * - Coordinating tournament finish with prize distribution
 */
class TournamentManager {
  constructor(tournamentId, config) {
    this.tournamentId = tournamentId;
    this.config = config; // {blindLevels, blindLevelMinutes, startingChips, playersPerTable, maxPlayers, prizePool}
    this.tables = new Map(); // tableId -> TournamentRoom
    this.playerTableMap = new Map(); // playerId -> tableId
    this.eliminatedPlayers = []; // ordered list of eliminated players (last eliminated = highest rank)
    this.totalPlayers = 0;
    this.status = 'waiting'; // waiting, running, final_table, finished
    this.isFinalTable = false;
    
    // Callbacks
    this.onTableRebalance = null; // (fromTableId, toTableId, player, newSeat) => {}
    this.onTableMerged = null; // (closedTableId, targetTableId) => {}
    this.onFinalTable = null; // (tableId) => {}
    this.onTournamentFinished = null; // (winner, rankings) => {}
    this.onPlayerEliminated = null; // (player, rank, tableId) => {}
    this.onBlindUp = null; // (levelInfo) => {}
  }

  /**
   * Create a tournament table and return its TournamentRoom
   */
  createTable(tableId, roomConfig = null) {
    const effectiveRoom = roomConfig?.effective?.value || {};
    const effectivePolicies = roomConfig?.effective?.policies || {};
    const texasPolicy = effectivePolicies.texas_holdem || {};
    const room = new TournamentRoom(tableId, {
      smallBlind: this.config.blindLevels[0]?.small_blind ?? effectiveRoom.small_blind ?? this.config.defaultSmallBlind,
      bigBlind: this.config.blindLevels[0]?.big_blind ?? effectiveRoom.big_blind ?? this.config.defaultBigBlind,
      ante: this.config.blindLevels[0]?.ante ?? effectiveRoom.ante ?? 0,
      maxSeats: this.config.playersPerTable,
      minBuyIn: this.config.startingChips,
      maxBuyIn: this.config.startingChips,
      minPlayMinutes: this.config.minimumPlayMinutes,
      turnTimeSec: this.config.turnTimeSec || this.config.actionTimeSec,
      autoStartAt: this.config.autoStartAt || this.config.minPlayersToStart,
      autoStartDelaySec: this.config.autoStartDelaySec || 0,
      rakePercent: this.config.rakePercent || 0,
      rakeCap: this.config.rakeCap || 0,
      texasPolicy: {
        ...texasPolicy,
        time_bank_sec: this.config.timeBankSec || 0,
        allow_rebuy: this.config.rebuyAllowed === true,
        max_raises_per_round: 0,
        no_flop_no_drop: false,
        minimum_rake_pot: 0,
        auto_timeout_action: texasPolicy.auto_timeout_action === 'fold' ? 'fold' : 'fold',
        sit_out_timeout_sec: this.config.disconnectTimeoutSec || 0,
        max_hands_per_room: 0,
        max_room_duration_hours: 0,
      },
    }, {
      tournamentId: this.tournamentId,
      blindLevels: this.config.blindLevels,
      blindLevelMinutes: this.config.blindLevelMinutes,
      breakIntervalMinutes: this.config.breakIntervalMinutes,
      breakDurationMinutes: this.config.breakDurationMinutes,
    });
    room.configVersion = roomConfig?.snapshot?.revisions?.room_defaults ?? null;
    room.configHash = roomConfig?.snapshot?.hash ?? null;
    room.effectiveConfig = roomConfig?.effective ?? null;

    // Wire up elimination callback
    room.onPlayerEliminated = (player, finishRank) => {
      // Calculate global rank (total players - eliminated so far)
      const globalRank = this.totalPlayers - this.eliminatedPlayers.length;
      this.eliminatedPlayers.push({
        ...player,
        finishRank: globalRank,
        tableId,
        eliminatedAt: new Date(),
      });
      this.playerTableMap.delete(player.id);
      
      if (this.onPlayerEliminated) {
        this.onPlayerEliminated(player, globalRank, tableId);
      }

      // Check if we need to rebalance or merge
      this._checkRebalance();
    };

    // Wire up blind escalation (sync across all tables)
    room.onBlindUp = (levelInfo) => {
      // Sync blinds to ALL tournament tables
      for (const [tid, tRoom] of this.tables) {
        if (tid !== tableId) {
          tRoom._applyBlindLevel(room.currentBlindLevel);
        }
      }
      if (this.onBlindUp) this.onBlindUp(levelInfo);
    };

    // Wire up tournament finish for single-table
    room.onTournamentFinished = (winner, eliminated) => {
      if (this.tables.size <= 1) {
        this._finishTournament(winner);
      }
    };

    this.tables.set(tableId, room);
    return room;
  }

  /**
   * Add a player to a specific table
   */
  addPlayer(tableId, seatNumber, playerData) {
    const room = this.tables.get(tableId);
    if (!room) return false;
    room.addPlayer(seatNumber, playerData);
    this.playerTableMap.set(playerData.id, tableId);
    this.totalPlayers++;
    return true;
  }

  /**
   * Rebuy a previously eliminated player into an available table.
   */
  rebuyPlayer(playerData) {
    if (this.status !== 'running' && this.status !== 'final_table') {
      return { error: 'Tournament is not running' };
    }
    if (this.config.rebuyAllowed !== true) return { error: 'Tournament rebuy is disabled' };
    if (this.playerTableMap.has(playerData.id)) return { error: 'Player is still seated' };
    const table = [...this.tables.entries()]
      .filter(([, room]) => room.tournamentStatus === 'running')
      .map(([tableId, room]) => ({ tableId, room }))
      .find(entry => entry.room.players.size < entry.room.maxSeats);
    if (!table) return { error: 'No tournament seat available' };
    const seat = this._findEmptySeat(table.room);
    if (seat === null) return { error: 'No tournament seat available' };
    table.room.addPlayer(seat, { ...playerData, disconnected: false });
    this.playerTableMap.set(playerData.id, table.tableId);
    this.totalPlayers++;
    return { tableId: table.tableId, seat, chips: Number(playerData.chips || 0) };
  }

  /**
   * Add configured chips to a seated player when add-on policy is enabled.
   */
  addonPlayer(playerId, chips) {
    if (this.config.addonAllowed !== true) return { error: 'Tournament add-on is disabled' };
    const tableId = this.playerTableMap.get(playerId);
    const room = tableId ? this.tables.get(tableId) : null;
    if (!room) return { error: 'Player is not seated in this tournament' };
    const player = [...room.players.values()].find(p => p.id === playerId);
    if (!player) return { error: 'Player is not seated in this tournament' };
    player.chips += Number(chips);
    return { tableId, chips: player.chips };
  }

  /**
   * Start tournament — start all tables simultaneously
   */
  start() {
    this.status = 'running';
    const results = [];
    for (const [tableId, room] of this.tables) {
      const state = room.startTournament();
      results.push({ tableId, state });
    }
    console.log(`🏆 [TM] Tournament ${this.tournamentId} STARTED | ${this.tables.size} tables | ${this.totalPlayers} players`);
    return results;
  }

  updateConfig(config) {
    this.config = { ...this.config, ...config };
    for (const room of this.tables.values()) {
      room.config.turnTimeSec = this.config.turnTimeSec || this.config.actionTimeSec;
      room.texasPolicy.time_bank_sec = this.config.timeBankSec || 0;
      room.texasPolicy.allow_rebuy = this.config.rebuyAllowed === true;
      room.texasPolicy.sit_out_timeout_sec = this.config.disconnectTimeoutSec || 0;
      room.config.texasPolicy = room.texasPolicy;
      room.disconnectTimeoutSec = this.config.disconnectTimeoutSec || 0;
      room.blindLevelDurationMs = (this.config.blindLevelMinutes || room.blindLevelDurationMs / 60000) * 60 * 1000;
    }
  }

  /**
   * Check if tables need rebalancing or merging
   */
  _checkRebalance() {
    if (this.status === 'finished') return;
    
    const activeTables = [...this.tables.entries()]
      .filter(([_, room]) => room.players.size > 0 && room.tournamentStatus === 'running');

    // If only 1 table with players left — it's the final table
    if (activeTables.length <= 1) {
      if (!this.isFinalTable && activeTables.length === 1) {
        this.isFinalTable = true;
        this.status = 'final_table';
        console.log(`🏆 [TM] FINAL TABLE reached! Table: ${activeTables[0][0]}`);
        if (this.onFinalTable) this.onFinalTable(activeTables[0][0]);
      }
      return;
    }

    // Find tables that need players and tables with too many
    const tableSizes = activeTables.map(([id, room]) => ({ id, size: room.players.size }));
    tableSizes.sort((a, b) => a.size - b.size);
    
    const smallest = tableSizes[0];
    const largest = tableSizes[tableSizes.length - 1];

    // Merge: if smallest table has <= 2 players and can fit in another table
    if (smallest.size <= 2 && smallest.size > 0) {
      const target = tableSizes.find(t => t.id !== smallest.id && (t.size + smallest.size) <= this.config.playersPerTable);
      if (target) {
        this._mergeTable(smallest.id, target.id);
        return;
      }
    }

    // Rebalance when the configured player-count difference is exceeded
    const maxDiff = Number(this.config.tableBalanceMaxDiff ?? 2);
    if (largest.size - smallest.size > maxDiff) {
      this._rebalancePlayer(largest.id, smallest.id);
    }
  }

  /**
   * Move all players from one table to another (merge)
   */
  _mergeTable(fromTableId, toTableId) {
    const fromRoom = this.tables.get(fromTableId);
    const toRoom = this.tables.get(toTableId);
    if (!fromRoom || !toRoom) return;

    console.log(`🔀 [TM] Merging table ${fromTableId} (${fromRoom.players.size} players) → ${toTableId}`);

    // Move each player
    const playersToMove = [...fromRoom.players.entries()];
    for (const [seat, player] of playersToMove) {
      // Find empty seat on target table
      const newSeat = this._findEmptySeat(toRoom);
      if (newSeat === null) break;

      fromRoom.removePlayer(seat);
      toRoom.addPlayer(newSeat, { ...player, sittingOut: false });
      this.playerTableMap.set(player.id, toTableId);

      if (this.onTableRebalance) {
        this.onTableRebalance(fromTableId, toTableId, player, newSeat);
      }
    }

    // Close the empty table
    fromRoom.tournamentStatus = 'finished';
    fromRoom.destroy();
    
    if (this.onTableMerged) {
      this.onTableMerged(fromTableId, toTableId);
    }

    // Check if this creates final table
    this._checkRebalance();
  }

  /**
   * Move one player from a larger table to a smaller one
   */
  _rebalancePlayer(fromTableId, toTableId) {
    const fromRoom = this.tables.get(fromTableId);
    const toRoom = this.tables.get(toTableId);
    if (!fromRoom || !toRoom) return;

    // Don't rebalance during a hand
    if (fromRoom.isPlaying) return;

    // Pick the player with the smallest stack (less disruptive)
    let minChips = Infinity;
    let moveCandidate = null;
    for (const [seat, player] of fromRoom.players) {
      if (player.chips < minChips) {
        minChips = player.chips;
        moveCandidate = { seat, player };
      }
    }

    if (!moveCandidate) return;

    const newSeat = this._findEmptySeat(toRoom);
    if (newSeat === null) return;

    console.log(`🔀 [TM] Rebalance: ${moveCandidate.player.username} from table ${fromTableId} → ${toTableId} seat ${newSeat}`);
    
    fromRoom.removePlayer(moveCandidate.seat);
    toRoom.addPlayer(newSeat, { ...moveCandidate.player, sittingOut: false });
    this.playerTableMap.set(moveCandidate.player.id, toTableId);

    if (this.onTableRebalance) {
      this.onTableRebalance(fromTableId, toTableId, moveCandidate.player, newSeat);
    }
  }

  /**
   * Find empty seat on a table
   */
  _findEmptySeat(room) {
    for (let s = 1; s <= room.maxSeats; s++) {
      if (!room.players.has(s)) return s;
    }
    return null;
  }

  /**
   * Finish tournament and determine final rankings
   */
  _finishTournament(winner) {
    this.status = 'finished';
    
    // Stop all blind timers
    for (const [_, room] of this.tables) {
      room.destroy();
    }

    // Build final rankings
    const rankings = [];
    if (winner) {
      rankings.push({ ...winner, finishRank: 1 });
    }
    // Add eliminated players in reverse order (last eliminated = rank 2, etc.)
    const reversed = [...this.eliminatedPlayers].reverse();
    for (let i = 0; i < reversed.length; i++) {
      rankings.push({ ...reversed[i], finishRank: i + 2 });
    }

    console.log(`🏆 [TM] Tournament ${this.tournamentId} FINISHED!`);
    console.log(`   Winner: ${winner?.username || 'N/A'}`);
    console.log(`   Rankings: ${rankings.slice(0, 5).map(r => `#${r.finishRank} ${r.username}`).join(', ')}`);

    if (this.onTournamentFinished) {
      this.onTournamentFinished(winner, rankings);
    }

    return rankings;
  }

  /**
   * Get remaining player count across all tables
   */
  getRemainingCount() {
    let count = 0;
    for (const [_, room] of this.tables) {
      count += room.players.size;
    }
    return count;
  }

  /**
   * Get global tournament state
   */
  getState() {
    const tableStates = [];
    for (const [tableId, room] of this.tables) {
      if (room.players.size > 0) {
        tableStates.push({
          tableId,
          playerCount: room.players.size,
          status: room.tournamentStatus,
        });
      }
    }

    return {
      tournamentId: this.tournamentId,
      status: this.status,
      totalPlayers: this.totalPlayers,
      remainingPlayers: this.getRemainingCount(),
      eliminatedCount: this.eliminatedPlayers.length,
      activeTables: tableStates,
      isFinalTable: this.isFinalTable,
    };
  }

  /**
   * Clean up all resources
   */
  destroy() {
    for (const [_, room] of this.tables) {
      room.destroy();
    }
    this.tables.clear();
    this.playerTableMap.clear();
  }
}

module.exports = TournamentManager;
