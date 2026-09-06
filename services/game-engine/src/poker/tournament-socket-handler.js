const TournamentManager = require('./tournament-manager');
const { Pool } = require('pg');
const { loadGameRuntime, loadSystemConfig } = require('../runtime-config');
const { resolveRoomConfig, roomSnapshotPayload } = require('../../../../config/config-platform');

/**
 * Tournament Socket Handler — integrates TournamentManager with Socket.IO
 * Emits WebSocket events for tournament-specific actions:
 * - tournament:blind_up
 * - tournament:player_eliminated  
 * - tournament:table_merged
 * - tournament:rebalance
 * - tournament:final_table
 * - tournament:finished
 * - tournament:state
 */

// Active tournament managers
const activeTournaments = new Map(); // tournamentId -> TournamentManager

function setupTournamentHandlers(io, pool) {
  const policyConfig = (policy, runtime) => ({
    minimumPlayMinutes: runtime.tournament_minimum_play_minutes,
    actionTimeSec: policy.action_time_sec,
    turnTimeSec: policy.action_time_sec,
    timeBankSec: policy.time_bank_sec,
    minPlayersToStart: policy.min_players_to_start,
    defaultSmallBlind: policy.default_small_blind,
    defaultBigBlind: policy.default_big_blind,
    autoStartDelaySec: 0,
    autoStartAt: policy.min_players_to_start,
    autoStartEnabled: policy.auto_start_enabled,
    autoStartIntervalSec: policy.auto_start_interval_sec,
    rakePercent: 0,
    rakeCap: 0,
    breakIntervalMinutes: policy.break_interval_minutes,
    breakDurationMinutes: policy.break_duration_minutes,
    rebuyAllowed: policy.rebuy_allowed,
    addonAllowed: policy.addon_allowed,
    rebuyChipAmount: policy.rebuy_chip_amount,
    addonChipAmount: policy.addon_chip_amount,
    tableBalanceMaxDiff: policy.table_balance_max_diff,
    disconnectTimeoutSec: policy.disconnect_timeout_sec,
    prizeDistributionPolicy: policy.prize_distribution_policy,
  });

  async function chargeTournamentEntry(tournamentId, userId, transactionType) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const tournamentResult = await client.query(
        'SELECT * FROM poker_tournaments WHERE id = $1 FOR UPDATE',
        [tournamentId],
      );
      const tournament = tournamentResult.rows[0];
      if (!tournament || tournament.status !== 'running') {
        throw new Error('Tournament is not running');
      }
      const cost = Number(tournament.buy_in) + Number(tournament.entry_fee);
      if (cost > 0) {
        const wallet = await client.query(
          'SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE',
          [userId],
        );
        if (wallet.rows.length === 0) throw new Error('Wallet not found');
        if (Number(wallet.rows[0].balance) < cost) throw new Error('Insufficient balance');
        await client.query(
          'UPDATE wallets SET balance = balance - $1, updated_at = NOW() WHERE user_id = $2',
          [cost, userId],
        );
      }
      const balance = await client.query('SELECT balance FROM wallets WHERE user_id = $1', [userId]);
      await client.query(
        `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id, description)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [userId, transactionType, -cost, balance.rows[0]?.balance ?? 0, tournamentId, `Tournament ${transactionType}`],
      );
      await client.query(
        'UPDATE poker_tournaments SET prize_pool = prize_pool + $1, updated_at = NOW() WHERE id = $2',
        [Number(tournament.buy_in), tournamentId],
      );
      await client.query('COMMIT');
      return { cost, balance: Number(balance.rows[0]?.balance ?? 0) };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Start a tournament (called from REST API or admin action)
   */
  async function startTournament(tournamentId) {
    try {
      // Load tournament data from DB
      const tResult = await pool.query('SELECT * FROM poker_tournaments WHERE id = $1', [tournamentId]);
      if (tResult.rows.length === 0) throw new Error('Tournament not found');
      const tournament = tResult.rows[0];

      // Load blind levels
      const blindsResult = await pool.query(
        'SELECT * FROM poker_blind_levels WHERE tournament_id = $1 ORDER BY level_no ASC', [tournamentId]
      );
      const blindLevels = blindsResult.rows;

      if (['finished', 'cancelled'].includes(tournament.status)) {
        throw new Error(`Tournament is already ${tournament.status}`);
      }

      const policy = await loadSystemConfig(pool, 'tournament_policy');
      let players = [];
      let tables = [];
      const seatClient = await pool.connect();
      try {
        await seatClient.query('BEGIN');
        const playersResult = await seatClient.query(
          `SELECT p.*, u.username, u.display_name, u.avatar_url
           FROM poker_tournament_players p JOIN users u ON u.id = p.user_id
           WHERE p.tournament_id = $1 AND p.status IN ('registered', 'seated')
           ORDER BY p.registered_at
           FOR UPDATE OF p`,
          [tournamentId],
        );
        const playersToSeat = playersResult.rows;
        if (playersToSeat.length < policy.min_players_to_start) {
          throw new Error(`Tournament not properly set up (minimum ${policy.min_players_to_start} players required)`);
        }
        let tablesResult = await seatClient.query(
          `SELECT * FROM poker_tournament_tables WHERE tournament_id = $1 AND status = 'active' ORDER BY table_no FOR UPDATE`,
          [tournamentId],
        );
        const playersPerTable = tournament.players_per_table ?? policy.default_players_per_table;
        const requiredTables = Math.ceil(playersToSeat.length / playersPerTable);
        while (tablesResult.rows.length < requiredTables) {
          const created = await seatClient.query(
            `INSERT INTO poker_tournament_tables (tournament_id, table_no, status)
             VALUES ($1, $2, 'active') RETURNING *`,
            [tournamentId, tablesResult.rows.length + 1],
          );
          tablesResult.rows.push(created.rows[0]);
        }
        const needsSeating = playersToSeat.some(player => !player.table_id || !player.seat_no);
        if (needsSeating) {
          await seatClient.query(
            `UPDATE poker_tournament_players SET table_id = NULL, seat_no = NULL WHERE tournament_id = $1`,
            [tournamentId],
          );
          const seatCounts = new Map(tablesResult.rows.map(table => [table.id, 0]));
          for (const player of playersToSeat) {
            const table = tablesResult.rows.find(candidate => (seatCounts.get(candidate.id) || 0) < playersPerTable);
            if (!table) throw new Error('Unable to allocate tournament table seat');
            const seatNo = seatCounts.get(table.id) + 1;
            seatCounts.set(table.id, seatNo);
            await seatClient.query(
              `UPDATE poker_tournament_players
               SET table_id = $1, seat_no = $2, status = 'seated', chips = $3
               WHERE id = $4`,
              [table.id, seatNo, tournament.starting_chips, player.id],
            );
            Object.assign(player, { table_id: table.id, seat_no: seatNo, status: 'seated', chips: tournament.starting_chips });
          }
        } else {
          for (const player of playersToSeat) {
            await seatClient.query(
              `UPDATE poker_tournament_players SET status = 'seated' WHERE id = $1`,
              [player.id],
            );
            player.status = 'seated';
          }
        }
        await seatClient.query(
          `UPDATE poker_tournaments
           SET status = 'running', started_at = COALESCE(started_at, NOW()),
               start_time = COALESCE(start_time, NOW()), updated_at = NOW()
           WHERE id = $1`,
          [tournamentId],
        );
        await seatClient.query('COMMIT');
        players = playersToSeat;
        tables = tablesResult.rows;
      } catch (error) {
        await seatClient.query('ROLLBACK').catch(() => {});
        throw error;
      } finally {
        seatClient.release();
      }

      // Create TournamentManager
      const runtime = await loadGameRuntime(pool);
      const manager = new TournamentManager(tournamentId, {
        blindLevels,
        blindLevelMinutes: tournament.blind_level_minutes ?? policy.default_blind_level_minutes,
        startingChips: tournament.starting_chips,
        playersPerTable: tournament.players_per_table ?? policy.default_players_per_table,
        maxPlayers: tournament.max_players,
        prizePool: Number(tournament.prize_pool),
        ...policyConfig(policy, runtime),
      });

      const gameType = await pool.query(
        'SELECT id FROM game_types WHERE slug = $1 AND is_active = true',
        [tournament.game || policy.default_game_slug],
      );
      const gameTypeId = gameType.rows[0]?.id || null;

      // Create tables in manager with an effective config snapshot per tournament table.
      for (const table of tables) {
        const effective = await resolveRoomConfig(pool, { gameTypeId, tableId: table.id });
        const room = manager.createTable(table.id, {
          snapshot: roomSnapshotPayload(effective),
          effective,
        });
        room.onBreakStarted = ({ endsAt }) => {
          io.to(`tournament:${tournamentId}`).emit('tournament:break_started', { tournamentId, endsAt });
        };
        room.onBreakEnded = () => {
          io.to(`tournament:${tournamentId}`).emit('tournament:break_ended', { tournamentId });
          if (room._tournamentAutoDealCheck) room._tournamentAutoDealCheck();
        };
      }

      // Seat players
      for (const player of players) {
        if (!player.table_id) continue;
        manager.addPlayer(player.table_id, player.seat_no, {
          id: player.user_id,
          username: player.display_name || player.username,
          chips: player.chips || tournament.starting_chips,
          avatarUrl: player.avatar_url,
        });
      }

      // Wire up WebSocket event callbacks
      manager.onBlindUp = (levelInfo) => {
        // Broadcast to all tournament players
        for (const [tableId] of manager.tables) {
          io.to(`tournament:${tournamentId}`).emit('tournament:blind_up', {
            tournamentId,
            ...levelInfo,
          });
        }
        console.log(`📡 [WS] tournament:blind_up — Level ${levelInfo.level} (${levelInfo.smallBlind}/${levelInfo.bigBlind})`);
      };

      manager.onPlayerEliminated = async (player, rank, tableId) => {
        io.to(`tournament:${tournamentId}`).emit('tournament:player_eliminated', {
          tournamentId,
          playerId: player.id,
          username: player.username,
          rank,
          tableId,
          remaining: manager.getRemainingCount(),
        });

        // Update DB
        try {
          await pool.query(
            `UPDATE poker_tournament_players SET status = 'eliminated', finish_rank = $1, chips = 0
             WHERE tournament_id = $2 AND user_id = $3`,
            [rank, tournamentId, player.id]
          );
        } catch (err) { console.error('Update eliminated player DB error:', err.message); }

        console.log(`📡 [WS] tournament:player_eliminated — ${player.username} rank #${rank}`);
      };

      manager.onTableMerged = (closedTableId, targetTableId) => {
        io.to(`tournament:${tournamentId}`).emit('tournament:table_merged', {
          tournamentId,
          closedTableId,
          targetTableId,
          remaining: manager.getRemainingCount(),
        });

        // Update DB
        pool.query(
          `UPDATE poker_tournament_tables SET status = 'broken' WHERE id = $1`, [closedTableId]
        ).catch(err => console.error('Update merged table DB error:', err.message));

        console.log(`📡 [WS] tournament:table_merged — ${closedTableId} → ${targetTableId}`);
      };

      manager.onTableRebalance = (fromTableId, toTableId, player, newSeat) => {
        // Notify the moved player specifically
        const playerSockets = [...io.sockets.sockets.values()]
          .filter(s => s.user?.id === player.id);
        for (const s of playerSockets) {
          s.emit('tournament:rebalance', {
            tournamentId,
            fromTableId,
            toTableId,
            newSeat,
            message: `คุณถูกย้ายไปโต๊ะใหม่`,
          });
        }

        // Update DB
        pool.query(
          `UPDATE poker_tournament_players SET table_id = $1, seat_no = $2 WHERE tournament_id = $3 AND user_id = $4`,
          [toTableId, newSeat, tournamentId, player.id]
        ).catch(err => console.error('Update rebalance DB error:', err.message));

        console.log(`📡 [WS] tournament:rebalance — ${player.username} → table ${toTableId} seat ${newSeat}`);
      };

      manager.onFinalTable = (tableId) => {
        io.to(`tournament:${tournamentId}`).emit('tournament:final_table', {
          tournamentId,
          tableId,
          remaining: manager.getRemainingCount(),
        });
        console.log(`📡 [WS] tournament:final_table — ${tableId}`);
      };

      manager.onTournamentFinished = async (winner, rankings) => {
        io.to(`tournament:${tournamentId}`).emit('tournament:finished', {
          tournamentId,
          winner: winner ? { id: winner.id, username: winner.username } : null,
          rankings: rankings.slice(0, 10).map(r => ({
            rank: r.finishRank, id: r.id, username: r.username,
          })),
        });

        // Update tournament status in DB
        try {
          await pool.query(
            `UPDATE poker_tournaments SET status = 'finished', updated_at = NOW() WHERE id = $1`,
            [tournamentId]
          );
          // Prize distribution handled by REST API /poker/tournaments/:id/finish
        } catch (err) { console.error('Update tournament finished DB error:', err.message); }

        // Cleanup
        setTimeout(() => {
          activeTournaments.delete(tournamentId);
          manager.destroy();
        }, 60000); // Keep alive for 1 min for late joiners to see result

        console.log(`📡 [WS] tournament:finished — Winner: ${winner?.username}`);
      };

      // Store manager
      activeTournaments.set(tournamentId, manager);

      // Start all tables
      const results = manager.start();

      // Broadcast initial state to each table
      for (const [tableId, room] of manager.tables) {
        broadcastTournamentState(io, tableId, room);
      }

      // Setup auto-deal for each table after hand ends
      for (const [tableId, room] of manager.tables) {
        setupTournamentAutoDeal(io, tableId, room, manager);
      }

      console.log(`🏆 [TOURNAMENT] ${tournament.name} started! ${players.length} players on ${tables.length} tables`);
      return { success: true, tables: tables.length, players: players.length };
    } catch (err) {
      console.error('startTournament error:', err.message);
      return { error: err.message };
    }
  }

  /**
   * Broadcast personalized state to all sockets on a tournament table
   */
  function broadcastTournamentState(ioServer, tableId, room) {
    const allSockets = [...ioServer.sockets.sockets.values()].filter(s => s.tableId === tableId);
    for (const s of allSockets) {
      if (s.seatNumber && room.players.has(s.seatNumber)) {
        s.emit('game:state', room.getState(s.seatNumber));
      } else {
        s.emit('game:state', room.getState());
      }
    }
  }

  async function persistTournamentHand(tournamentId, tableId, room, result) {
    const playerData = Object.fromEntries(
      [...room.players].map(([seat, player]) => [seat, {
        id: player.id,
        username: player.username,
        chips: player.chips,
        holeCards: player.holeCards || [],
        folded: player.folded === true,
        allIn: player.allIn === true,
      }]),
    );
    await pool.query(
      `INSERT INTO tournament_hands
       (tournament_id, tournament_table_id, hand_number, community_cards, player_data,
        actions, pot_total, rake_amount, winner_ids, config_revision, config_hash)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       ON CONFLICT (tournament_table_id, hand_number) DO NOTHING`,
      [
        tournamentId,
        tableId,
        room.handNumber,
        JSON.stringify(room.communityCards || []),
        JSON.stringify(playerData),
        JSON.stringify(room.actions || []),
        Number(result?.pot || 0),
        Number(result?.rakeAmount || 0),
        (result?.winners || []).map(winner => winner.id).filter(Boolean),
        room.configVersion,
        room.configHash,
      ],
    );
  }

  /**
   * Auto-deal next hand in tournament after delay
   */
  function setupTournamentAutoDeal(ioServer, tableId, room, manager) {
    // Override the existing result handler to auto-start next hand
    const originalOnFinished = room.onTournamentFinished;
    
    // Check after each hand if we should auto-deal
    room._tournamentAutoDealCheck = async () => {
      if (room.tournamentStatus !== 'running') return;
      if (room.players.size < manager.config.minPlayersToStart) return;
      const runtime = await loadGameRuntime(pool);
      
      setTimeout(() => {
        if (room.tournamentStatus !== 'running') return;
        if (room.players.size < manager.config.minPlayersToStart) return;
        
        const state = room.startNextHand();
        if (state) {
          broadcastTournamentState(ioServer, tableId, room);
          // Start bot/timer logic if needed
          startTournamentTurnTimer(ioServer, tableId, room, manager);
        }
      }, runtime.auto_deal_delay_sec * 1000);
    };
  }

  /**
   * Turn timer for tournament — auto-fold after timeout
   */
  function startTournamentTurnTimer(ioServer, tableId, room, manager) {
    if (room._turnTimer) { clearTimeout(room._turnTimer); room._turnTimer = null; }
    if (!room.isPlaying) return;

    const currentSeat = room.currentPlayerSeat;
    const currentPlayer = room.players.get(currentSeat);
    if (!currentPlayer) return;

    const turnTimeSec = manager.config.actionTimeSec;

    const handleTimeout = () => {
      room._turnTimer = null;
      if (!room.isPlaying) return;
      if (room.currentPlayerSeat !== currentSeat) return;

      const timeBankSec = Math.max(0, Number(currentPlayer.timeBankRemaining || 0));
      if (timeBankSec > 0) {
        currentPlayer.timeBankRemaining = 0;
        ioServer.to(tableId).emit('tournament:time_bank', { seat: currentSeat, seconds: timeBankSec });
        room._turnTimer = setTimeout(handleTimeout, timeBankSec * 1000);
        return;
      }

      // Auto-check or auto-fold
      const maxBet = Math.max(...[...room.players.values()].filter(p => !p.folded).map(p => p.currentBet));
      const canCheck = currentPlayer.currentBet >= maxBet;
      const action = canCheck ? 'check' : 'fold';

      console.log(`⏰ [TOURNAMENT] ${currentPlayer.username} auto-${action} (timeout)`);
      const result = room.handleAction(currentSeat, action, 0);
      
      if (result && !result.error) {
        broadcastTournamentState(ioServer, tableId, room);
        if (result.result) {
          persistTournamentHand(room.tournamentId, tableId, room, result.result)
            .catch(error => console.error('Tournament hand persistence error:', error.message));
          ioServer.to(tableId).emit('game:result', result.result);
          // Trigger auto-deal for next hand
          if (room._tournamentAutoDealCheck) room._tournamentAutoDealCheck();
        } else {
          startTournamentTurnTimer(ioServer, tableId, room, manager);
        }
      }
    };
    room._turnTimer = setTimeout(handleTimeout, turnTimeSec * 1000);
  }

  // ═══════════════════════════════════════════════════════════════
  // Socket event: tournament:join — player joins tournament room
  // ═══════════════════════════════════════════════════════════════
  io.on('connection', (socket) => {
    socket.on('tournament:join', async ({ tournamentId }) => {
      if (!socket.user) return socket.emit('error', { message: 'Not authenticated' });
      
      // Join the tournament broadcast room
      socket.join(`tournament:${tournamentId}`);
      
      // Find which table this player is on
      const manager = activeTournaments.get(tournamentId);
      if (!manager) {
        return socket.emit('tournament:state', { status: 'not_started', tournamentId });
      }

      const tableId = manager.playerTableMap.get(socket.user.id);
      if (tableId) {
        const room = manager.tables.get(tableId);
        if (room) {
          socket.tableId = tableId;
          socket.join(tableId);
          // Find player's seat
          for (const [seat, p] of room.players) {
            if (p.id === socket.user.id) {
              socket.seatNumber = seat;
              p.socketId = socket.id;
              p.disconnected = false;
              p.sittingOut = false;
              break;
            }
          }
          socket.emit('game:state', room.getState(socket.seatNumber));
        }
      }

      // Send global tournament state
      socket.emit('tournament:state', manager.getState());
    });

    socket.on('tournament:rebuy', async ({ tournamentId }) => {
      try {
        if (!socket.user) return socket.emit('error', { message: 'Not authenticated' });
        const manager = activeTournaments.get(tournamentId);
        if (!manager || manager.config.rebuyAllowed !== true) {
          return socket.emit('error', { message: 'Tournament rebuy is not available' });
        }
        const entry = await pool.query(
          `SELECT p.*, u.username, u.display_name, u.avatar_url
           FROM poker_tournament_players p JOIN users u ON u.id = p.user_id
           WHERE p.tournament_id = $1 AND p.user_id = $2`,
          [tournamentId, socket.user.id],
        );
        const registration = entry.rows[0];
        if (!registration || registration.status !== 'eliminated') {
          return socket.emit('error', { message: 'Only eliminated players can rebuy' });
        }
        const chips = Number(manager.config.rebuyChipAmount || 0);
        if (chips <= 0) return socket.emit('error', { message: 'Invalid tournament rebuy configuration' });
        const seatResult = manager.rebuyPlayer({
          id: socket.user.id,
          username: registration.display_name || registration.username,
          avatarUrl: registration.avatar_url,
          chips,
        });
        if (seatResult.error) return socket.emit('error', { message: seatResult.error });
        try {
          const charge = await chargeTournamentEntry(tournamentId, socket.user.id, 'tournament_rebuy');
          await pool.query(
            `UPDATE poker_tournament_players
             SET status = 'seated', table_id = $1, seat_no = $2, chips = $3,
                 finish_rank = NULL, rebuy_count = COALESCE(rebuy_count, 0) + 1
             WHERE tournament_id = $4 AND user_id = $5`,
            [seatResult.tableId, seatResult.seat, chips, tournamentId, socket.user.id],
          );
          socket.tableId = seatResult.tableId;
          socket.seatNumber = seatResult.seat;
          socket.join(seatResult.tableId);
          socket.emit('tournament:rebuy:ok', { ...seatResult, balance: charge.balance });
          const room = manager.tables.get(seatResult.tableId);
          if (room) broadcastTournamentState(io, seatResult.tableId, room);
        } catch (error) {
          const room = manager.tables.get(seatResult.tableId);
          if (room) room.removePlayer(seatResult.seat);
          manager.playerTableMap.delete(socket.user.id);
          manager.totalPlayers--;
          throw error;
        }
      } catch (error) {
        socket.emit('error', { message: error.message || 'Tournament rebuy failed' });
      }
    });

    socket.on('tournament:addon', async ({ tournamentId }) => {
      try {
        if (!socket.user) return socket.emit('error', { message: 'Not authenticated' });
        const manager = activeTournaments.get(tournamentId);
        if (!manager || manager.config.addonAllowed !== true) {
          return socket.emit('error', { message: 'Tournament add-on is not available' });
        }
        const entry = await pool.query(
          `SELECT status, addon_count FROM poker_tournament_players
           WHERE tournament_id = $1 AND user_id = $2`,
          [tournamentId, socket.user.id],
        );
        const registration = entry.rows[0];
        if (!registration || registration.status !== 'seated') {
          return socket.emit('error', { message: 'Only seated players can add-on' });
        }
        if (Number(registration.addon_count || 0) > 0) {
          return socket.emit('error', { message: 'Add-on has already been used' });
        }
        const chips = Number(manager.config.addonChipAmount || 0);
        if (chips <= 0) return socket.emit('error', { message: 'Invalid tournament add-on configuration' });
        const preview = manager.addonPlayer(socket.user.id, 0);
        if (preview.error) return socket.emit('error', { message: preview.error });
        const charge = await chargeTournamentEntry(tournamentId, socket.user.id, 'tournament_addon');
        const applied = manager.addonPlayer(socket.user.id, chips);
        await pool.query(
          `UPDATE poker_tournament_players
           SET chips = chips + $1, addon_count = COALESCE(addon_count, 0) + 1
           WHERE tournament_id = $2 AND user_id = $3`,
          [chips, tournamentId, socket.user.id],
        );
        socket.emit('tournament:addon:ok', { chips: applied.chips, balance: charge.balance });
        const room = manager.tables.get(applied.tableId);
        if (room) broadcastTournamentState(io, applied.tableId, room);
      } catch (error) {
        socket.emit('error', { message: error.message || 'Tournament add-on failed' });
      }
    });

    socket.on('disconnect', () => {
      if (!socket.user) return;
      for (const manager of activeTournaments.values()) {
        const tableId = manager.playerTableMap.get(socket.user.id);
        const room = tableId ? manager.tables.get(tableId) : null;
        if (!room) continue;
        const player = [...room.players.values()].find(p => p.id === socket.user.id);
        if (!player || (player.socketId && player.socketId !== socket.id)) return;
        player.disconnected = true;
        const timeoutSec = Math.max(0, Number(manager.config.disconnectTimeoutSec || 0));
        if (timeoutSec === 0) {
          player.sittingOut = true;
          broadcastTournamentState(io, tableId, room);
          continue;
        }
        setTimeout(() => {
          const current = [...room.players.values()].find(p => p.id === socket.user.id);
          if (!current || current.disconnected !== true) return;
          const seat = [...room.players.entries()].find(([, p]) => p.id === socket.user.id)?.[0];
          if (room.isPlaying && room.currentPlayerSeat === seat) {
            room.handleAction(room.currentPlayerSeat, 'fold', 0);
          }
          current.sittingOut = true;
          broadcastTournamentState(io, tableId, room);
        }, timeoutSec * 1000);
      }
    });

    // Handle tournament player actions (reuse existing game:action)
    socket.on('tournament:action', ({ action, amount }) => {
      if (!socket.tableId || !socket.seatNumber) return;
      
      // Find the tournament room
      let tournamentRoom = null;
      for (const [_, manager] of activeTournaments) {
        const room = manager.tables.get(socket.tableId);
        if (room) { tournamentRoom = room; break; }
      }
      
      if (!tournamentRoom) return socket.emit('error', { message: 'Tournament table not found' });

      const result = tournamentRoom.handleAction(socket.seatNumber, action, amount);
      if (result.error) return socket.emit('error', { message: result.error });

      broadcastTournamentState(io, socket.tableId, tournamentRoom);

      if (result.result) {
        persistTournamentHand(tournamentRoom.tournamentId, socket.tableId, tournamentRoom, result.result)
          .catch(error => console.error('Tournament hand persistence error:', error.message));
        io.to(socket.tableId).emit('game:result', result.result);
        // Auto-deal next hand
        if (tournamentRoom._tournamentAutoDealCheck) {
          tournamentRoom._tournamentAutoDealCheck();
        }
      } else {
        // Start turn timer for next player
        const manager = [...activeTournaments.values()].find(m => m.tables.has(socket.tableId));
        if (manager) startTournamentTurnTimer(io, socket.tableId, tournamentRoom, manager);
      }
    });
  });

  async function reloadPolicy() {
    const [policy, runtime] = await Promise.all([
      loadSystemConfig(pool, 'tournament_policy'),
      loadGameRuntime(pool),
    ]);
    for (const manager of activeTournaments.values()) {
      manager.updateConfig(policyConfig(policy, runtime));
    }
    return { updated: activeTournaments.size };
  }

  async function seatLateRegistrations(tournamentId, policy) {
    const manager = activeTournaments.get(tournamentId);
    if (!manager || manager.status === 'finished') return { seated: 0 };
    const players = await pool.query(
      `SELECT p.*, u.username, u.display_name, u.avatar_url
       FROM poker_tournament_players p
       JOIN users u ON u.id = p.user_id
       WHERE p.tournament_id = $1 AND p.status = 'registered'
       ORDER BY p.registered_at ASC`,
      [tournamentId],
    );
    let seated = 0;
    for (const player of players.rows) {
      const table = [...manager.tables.entries()].find(([, room]) =>
        room.tournamentStatus === 'running' && room.players.size < room.maxSeats,
      );
      if (!table) break;
      const [tableId, room] = table;
      const seat = manager._findEmptySeat(room);
      if (seat === null) continue;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const updated = await client.query(
          `UPDATE poker_tournament_players
           SET status = 'seated', table_id = $1, seat_no = $2, chips = $3
           WHERE id = $4 AND status = 'registered'
           RETURNING id`,
          [tableId, seat, player.chips, player.id],
        );
        if (updated.rows.length === 0) {
          await client.query('ROLLBACK');
          continue;
        }
        await client.query('COMMIT');
        manager.addPlayer(tableId, seat, {
          id: player.user_id,
          username: player.display_name || player.username,
          chips: player.chips,
          avatarUrl: player.avatar_url,
        });
        seated++;
        broadcastTournamentState(io, tableId, room);
      } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        throw error;
      } finally {
        client.release();
      }
    }
    return { seated };
  }

  async function scanScheduledTournaments() {
    const lock = await pool.query('SELECT pg_try_advisory_lock(731905) AS acquired');
    if (!lock.rows[0]?.acquired) return { started: 0, locked: true };
    try {
      const policy = await loadSystemConfig(pool, 'tournament_policy');
      const candidates = await pool.query(
        `SELECT t.*,
          (SELECT COUNT(*)::int FROM poker_tournament_players p
           WHERE p.tournament_id = t.id AND p.status IN ('registered', 'seated')) AS registered_count
         FROM poker_tournaments t
         WHERE (
           t.status = 'running'
           OR (
             t.status = 'registration'
             AND $1::boolean = TRUE
             AND (
               (t.start_time IS NOT NULL AND t.start_time <= NOW())
               OR (SELECT COUNT(*) FROM poker_tournament_players p
                    WHERE p.tournament_id = t.id AND p.status IN ('registered', 'seated')) >= t.max_players
             )
           )
         )
         ORDER BY t.created_at ASC`,
        [policy.auto_start_enabled === true],
      );
      let started = 0;
      for (const tournament of candidates.rows) {
        if (activeTournaments.has(tournament.id)) {
          await seatLateRegistrations(tournament.id, policy);
          continue;
        }
        const result = await startTournament(tournament.id);
        if (!result.error) started++;
      }
      return { started };
    } finally {
      await pool.query('SELECT pg_advisory_unlock(731905)').catch(() => {});
    }
  }

  function startTournamentScheduler() {
    let stopped = false;
    let timer = null;
    let intervalSec = null;
    const scheduleNext = async () => {
      if (stopped) return;
      try {
        const policy = await loadSystemConfig(pool, 'tournament_policy');
        intervalSec = Math.max(5, Number(policy.auto_start_interval_sec));
        await scanScheduledTournaments();
      } catch (error) {
        console.error('Tournament scheduler error:', error.message);
        if (intervalSec === null) return;
      }
      if (!stopped) timer = setTimeout(scheduleNext, intervalSec * 1000);
    };
    scheduleNext();
    return {
      stop() {
        stopped = true;
        if (timer) clearTimeout(timer);
      },
    };
  }

  return { startTournament, activeTournaments, reloadPolicy, scanScheduledTournaments, startTournamentScheduler };
}

module.exports = { setupTournamentHandlers };
