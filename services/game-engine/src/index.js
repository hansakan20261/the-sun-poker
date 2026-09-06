require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const { createChineseRoom, createTexasRoom } = require('./poker/room-factory');
const { setupTournamentHandlers } = require('./poker/tournament-socket-handler');
const { canAccessRoom, isAdminRole } = require('./security');
const { addToBuyIn, cashOut, deductBuyIn } = require('./game-wallet');
const { clearRoomTurnTimer, getRoomTurnTimeSec, scheduleRoomTurnTimer } = require('./poker/turn-timer');
const { clearRoomAutoStart, scheduleRoomAutoStart } = require('./poker/auto-start');
const { loadRoomSnapshot, reloadRoomFromSnapshot, reloadRoomRuntimeConfig, resolveMinimumPlayMinutes, resolveRoomAutoStart, resolveRoomTurnTimeSec } = require('./config-registry');
const { loadGameRuntime, loadSystemConfig } = require('./runtime-config');
const { roomSnapshotPayload } = require('../../../config/config-platform');
const { ConfigRevisionTracker, startConfigListener } = require('../../../config/config-events');
const { corsOriginConfig } = require('../../../config/cors');
const { databaseConfigFromEnv } = require('../../../config/database-env');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: corsOriginConfig() } });
const pool = new Pool(databaseConfigFromEnv());

const PORT = process.env.PORT || 3003;
const configTracker = new ConfigRevisionTracker('game-engine', [
  'game_runtime',
  'room_defaults',
  'room_creation_limits',
  'texas_holdem_policy',
  'chinese_poker_policy',
  'tournament_policy',
  'practice_policy',
  'wallet_economy_policy',
]);
let configListener = null;
const rooms = new Map(); // tableId -> GameRoom
const chineseRooms = new Map(); // tableId -> ChinesePokerRoom
let configuredDemoTableIds = new Set();
let configuredDemoBots = [];

function isDemoTable(tableId) { return configuredDemoTableIds.has(tableId); }
function demoBots(room = null) { return room?.practicePolicy?.demo_bot_profiles ?? configuredDemoBots; }
function isDemoBotId(playerId, room = null) { return demoBots(room).some(bot => bot.id === playerId); }

async function refreshPracticePolicy() {
  const policy = await loadSystemConfig(pool, 'practice_policy');
  configuredDemoTableIds = new Set(policy.demo_table_ids);
  configuredDemoBots = policy.demo_bot_profiles;
  for (const [tableId, room] of [...rooms.entries(), ...chineseRooms.entries()]) {
    if (room.isPractice || isDemoTable(tableId)) room.practicePolicy = policy;
  }
  return policy;
}

async function setTablePlayerActive(tableId, seatNumber, player, active) {
  if (!player || isDemoBotId(player.id)) return;
  if (active) {
    await pool.query(
      `INSERT INTO table_players (table_id, user_id, seat_number, chip_count, is_active)
       VALUES ($1,$2,$3,$4,TRUE)
       ON CONFLICT (table_id, seat_number) DO UPDATE
       SET user_id = EXCLUDED.user_id, chip_count = EXCLUDED.chip_count, is_active = TRUE, joined_at = NOW()`,
      [tableId, player.id, seatNumber, player.chips],
    );
  } else {
    await pool.query('UPDATE table_players SET is_active = FALSE, chip_count = $1 WHERE table_id = $2 AND user_id = $3', [player.chips, tableId, player.id]);
  }
}

async function setTableStatus(tableId, status) {
  await pool.query('UPDATE game_tables SET status = $1 WHERE id = $2', [status, tableId]);
}

function addDemoBotsToRoom(room, tableId, maxBots, botChips = room.config.minBuyIn) {
  const occupiedSeats = [...room.players.keys()];
  const maxSeats = room.maxSeats;
  let added = 0;
  for (const bot of demoBots(room)) {
    if (added >= maxBots) break;
    // Skip if bot already in room
    if ([...room.players.values()].some(p => p.id === bot.id)) continue;
    // Find empty seat
    for (let s = 1; s <= maxSeats; s++) {
      if (!room.players.has(s)) {
        const buyIn = Number(botChips);
        room.addPlayer(s, { id: bot.id, username: bot.username, chips: buyIn, countryFlag: bot.countryFlag });
        console.log(`🤖 Demo bot ${bot.username} joined seat ${s} on table ${tableId}`);
        added++;
        break;
      }
    }
  }
  return added;
}

// Helper: ส่ง personalized state ให้แต่ละ player เห็นไพ่ตัวเอง + spectators
function broadcastState(ioServer, tableId, room) {
  const allSockets = [...ioServer.sockets.sockets.values()].filter(s => s.tableId === tableId);
  for (const s of allSockets) {
    if (s.seatNumber && room.players.has(s.seatNumber)) {
      // Seated player: see own hole cards
      const state = room.getState(s.seatNumber);
      const myCards = state.players?.[s.seatNumber]?.holeCards;
      if (myCards && myCards[0] === '??' && room.isPlaying) {
        console.log(`⚠️ [BROADCAST] seat ${s.seatNumber} (${s.user?.username}) got masked cards! forSeat type: ${typeof s.seatNumber}`);
      }
      s.emit('game:state', state);
    } else {
      // Spectator: no hole cards visible
      s.emit('game:state', room.getState());
    }
  }
}

async function persistGameHand(tableId, room, handNumber, communityCards, potTotal, winnerIds) {
  const snapshot = room.effectiveConfig
    ? roomSnapshotPayload(room.effectiveConfig)
    : { room: room.config, hash: room.configHash || null };
  await pool.query(
    `INSERT INTO game_hands (
      table_id, hand_number, community_cards, pot_total, winner_ids,
      config_snapshot, config_version, config_hash
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
    [
      tableId, handNumber, JSON.stringify(communityCards), potTotal, winnerIds,
      JSON.stringify(snapshot), room.configVersion || snapshot.revisions?.room_defaults || null,
      room.configHash || snapshot.hash,
    ]
  );
}

async function recordRakeToHouse(tableId, result) {
  const rakeAmount = Number(result?.rakeAmount || 0);
  if (rakeAmount <= 0) return 0;
  const economyPolicy = await loadSystemConfig(pool, 'wallet_economy_policy');
  const houseUserId = economyPolicy.house_account_user_id;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const wallet = await client.query(
      'UPDATE wallets SET balance = balance + $1 WHERE user_id = $2 RETURNING balance',
      [rakeAmount, houseUserId],
    );
    if (wallet.rows.length === 0) throw new Error('Configured house wallet is missing');
    await client.query(
      `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id)
       VALUES ($1, 'rake', $2, $3, $4)`,
      [houseUserId, rakeAmount, wallet.rows[0].balance, tableId],
    );
    await client.query('COMMIT');
    return rakeAmount;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

// Helper: Save NLH hand result to database
async function _saveNLHHand(tableId, room, result) {
  try {
    const { winners, pot } = result;
    const prizePerWinner = result.prizePerWinner || 0;
    const playerHands = {};
    for (const [seat, p] of room.players) {
      const isWinner = winners.some(w => w.seat === seat);
      const isFolded = p.folded === true;
      // Calculate net amount: winners get prize, others lose their total bet
      let amount = 0;
      if (isWinner) {
        amount = prizePerWinner;
      } else if (!isFolded) {
        // Lost at showdown — estimate loss from total pot contribution
        amount = -(p.totalBet || 0);
      } else {
        // Folded — lost their bet
        amount = -(p.totalBet || 0);
      }
      const handName = isWinner ? (winners.find(w => w.seat === seat)?.handName || '') : '';
      playerHands[seat] = {
        id: p.id, username: p.username, holeCards: p.holeCards, folded: p.folded,
        amount, handName,
        countryFlag: p.countryFlag || null,
      };
    }
    await persistGameHand(tableId, room, room.handNumber, {
      community: room.communityCards,
      players: playerHands,
      actions: room.actions,
    }, pot, winners.filter(w => !isDemoBotId(w.id, room)).map(w => w.id));
    console.log(`💾 [NLH] Saved hand #${room.handNumber} to DB (pot=${pot})`);
  } catch (err) { console.error('Save NLH hand error:', err.message); }
}

// Helper: Bot auto-play (รอ delay แล้วเล่น)
function botAutoPlay(ioServer, tableId, room) {
  if (!room.isPlaying) return;
  const currentSeat = room.currentPlayerSeat;
  const currentPlayer = room.players.get(currentSeat);
  const isBotPlayer = currentPlayer && isDemoBotId(currentPlayer.id, room);
  if (!isBotPlayer) return;

  // Prevent duplicate bot timers: use a generation counter
  // Each new call increments the generation; only the latest generation executes
  if (!room._botGeneration) room._botGeneration = 0;
  room._botGeneration++;
  const myGeneration = room._botGeneration;

  const policy = room.practicePolicy;
  if (!policy) return;
  const delay = policy.bot_action_min_ms + Math.floor(Math.random() * (policy.bot_action_jitter_ms + 1));
  setTimeout(() => {
    // Skip if a newer botAutoPlay call was made (prevents duplicates)
    if (room._botGeneration !== myGeneration) return;
    if (!room.isPlaying) return;

    // Re-read current player inside timeout (state may have changed)
    const botSeat = room.currentPlayerSeat;
    const botPlayer = room.players.get(botSeat);
    const isStillBot = botPlayer && isDemoBotId(botPlayer.id, room);
    if (!isStillBot) return; // Human's turn now — don't interfere

    const maxBet = Math.max(...[...room.players.values()].map(p => p.currentBet));
    // Smart bot: fold/call/raise based on situation
    // Limit raise wars: cap raises per round and check pot size
    const bb = Number(room.config.bigBlind);
    const potTooBig = room.pot > bb * policy.bot_pot_limit_big_blinds;
    
    // Count how many raises happened this round (prevent infinite re-raise loops)
    const raisesThisRound = room.actions.filter(a => a.round === room.currentRound && (a.action === 'raise' || a.action === 'all_in')).length;
    const maxRaises = room.effectiveConfig?.policies?.texas_holdem?.max_raises_per_round;
    if (!Number.isInteger(maxRaises)) return;
    const tooManyRaises = raisesThisRound >= maxRaises;
    
    let action;
    const rand = Math.random();
    if (botPlayer.currentBet < maxBet) {
      // Need to call or fold
      const callAmount = maxBet - botPlayer.currentBet;
      if (callAmount > botPlayer.chips * 0.5) {
        // Call is expensive — fold more often
        if (rand < 0.55) action = 'fold';
        else action = 'call';
      } else if (potTooBig || tooManyRaises) {
        // Pot already big or too many raises — just call or fold, no more raising
        if (rand < 0.3) action = 'fold';
        else action = 'call';
      } else {
        if (rand < 0.2) action = 'fold';
        else if (rand < 0.95) action = 'call';
        else action = 'raise';
      }
    } else {
      // Can check or raise
      if (potTooBig || tooManyRaises) {
        action = 'check'; // Don't raise when pot is already big or too many raises
      } else {
        if (rand < 0.92) action = 'check';
        else action = 'raise';
      }
    }
    let amount = 0;
    if (action === 'raise') {
      const minRaise = room.minRaise || room.config.bigBlind;
      // Small raise: just min raise or slightly above
      amount = (maxBet - botPlayer.currentBet) + minRaise + Math.floor(Math.random() * minRaise);
      amount = Math.min(amount, botPlayer.chips);
    }
    console.log(`🤖 [BOT] ${botPlayer.username} seat ${botSeat}: ${action}${amount ? ' ' + amount : ''}`);
    const result = room.handleAction(botSeat, action, amount);
    if (result.error) {
      console.log(`🤖 [BOT ERROR] ${result.error} — retrying botAutoPlay`);
      // Retry with fresh state after a short delay
      setTimeout(() => botAutoPlay(ioServer, tableId, room), policy.bot_error_retry_ms);
      return;
    }
    if (result.result) {
      clearRoomTurnTimer(room);
      console.log(`🤖 [BOT] Hand ended → emitting result, auto-deal in 5s`);
      ioServer.to(tableId).emit('game:result', result.result);
      _saveNLHHand(tableId, room, result.result);
      scheduleAutoDeal(ioServer, tableId, room);
    } else {
      botAutoPlay(ioServer, tableId, room);
      startTurnTimer(ioServer, tableId, room); // Timer for next human player
    }
    broadcastState(ioServer, tableId, room);
  }, delay);
}

// Server-side turn timer — auto-fold/check when human player runs out of time
function startTurnTimer(ioServer, tableId, room) {
  // Clear any existing timer
  clearRoomTurnTimer(room);
  if (!room.isPlaying) return;
  
  const currentSeat = room.currentPlayerSeat;
  const currentPlayer = room.players.get(currentSeat);
  if (!currentPlayer) return;
  
  // Don't set timer for bots (they have their own delay)
  const isBotPlayer = isDemoBotId(currentPlayer.id, room);
  if (isBotPlayer) return;
  let turnTimeSec;
  try {
    turnTimeSec = getRoomTurnTimeSec(room);
  } catch (err) {
    console.error(`Invalid turn timer config for table ${tableId}:`, err.message);
    ioServer.to(tableId).emit('error', { message: 'Invalid room turn time configuration' });
    return;
  }
  
  const handleTurnTimeout = () => {
    if (!room.isPlaying) return;
    if (room.currentPlayerSeat !== currentSeat) return; // Player already acted

    const timeBankSec = Math.max(0, Number(currentPlayer.timeBankRemaining || 0));
    if (timeBankSec > 0) {
      currentPlayer.timeBankRemaining = 0;
      room._turnTotalSeconds = timeBankSec;
      room._turnStartedAt = Date.now();
      room._turnDeadlineAt = room._turnStartedAt + timeBankSec * 1000;
      ioServer.to(tableId).emit('game:time_bank', { seat: currentSeat, seconds: timeBankSec });
      broadcastState(ioServer, tableId, room);
      room._turnTimer = setTimeout(handleTurnTimeout, timeBankSec * 1000);
      return;
    }

    // Auto-check if possible, otherwise auto-fold
    const maxBet = Math.max(...[...room.players.values()].filter(p => !p.folded).map(p => p.currentBet));
    const canCheck = currentPlayer.currentBet >= maxBet;
    const policy = room.config.texasPolicy || {};
    const action = policy.auto_timeout_action === 'fold' ? 'fold' : (canCheck ? 'check' : 'fold');

    console.log(`⏰ [TIMEOUT] ${currentPlayer.username} seat ${currentSeat}: auto-${action} (${turnTimeSec}s expired)`);
    const result = room.handleAction(currentSeat, action, 0);
    if (result && !result.error) {
      if (result.result) {
        clearRoomTurnTimer(room);
        ioServer.to(tableId).emit('game:result', result.result);
        _saveNLHHand(tableId, room, result.result);
        scheduleAutoDeal(ioServer, tableId, room);
      } else {
        // Continue: bot plays next or start timer for next human
        if (room.isPractice || isDemoTable(tableId)) {
          botAutoPlay(ioServer, tableId, room);
        }
        startTurnTimer(ioServer, tableId, room);
      }
      broadcastState(ioServer, tableId, room);
    }
  };
  scheduleRoomTurnTimer(room, handleTurnTimeout);
}

// Handle Chinese Poker arrange timeout — force foul for human players, valid arrange for bots
function _chineseArrangeTimeout(ioServer, tableId, room) {
  if (!room || room.phase !== 'arranging') return;
  // Auto-arrange for every player who hasn't arranged yet
  const unarranged = [...room.players.entries()].filter(([_, p]) => !p.arranged && !p.sittingOut && p.hand.length === 13);
  let lastResult = null;
  for (const [seat, p] of unarranged) {
    const policy = room.policy || {};
    const isBot = isDemoBotId(p.id, room);
    const result = (policy.auto_arrange_on_timeout || isBot)
      ? room.autoArrangeForSeat(seat)
      : room.forceFoulForSeat(seat);
    if (result && result.result) lastResult = result;
  }
  // If scoring happened, broadcast result
  if (lastResult && lastResult.result) {
    ioServer.to(tableId).emit('chinese:result', lastResult.result);
    ioServer.to(tableId).emit('chinese:state', lastResult);

    // Save to DB — record hand history
    (async () => {
      try {
        const winnerIds = lastResult.result.results
          .filter(r => r.coinChange > 0 && !isDemoBotId(r.id, room))
          .map(r => r.id);
        const potTotal = lastResult.result.results
          .filter(r => r.coinChange > 0)
          .reduce((sum, r) => sum + r.coinChange, 0);
        const handNumber = room ? room.handNumber : 1;

        const detailedResults = lastResult.result.results.map(r => ({
          id: r.id, seat: r.seat, username: r.username,
          front: r.front || [], middle: r.middle || [], back: r.back || [],
          frontName: r.frontName || '', middleName: r.middleName || '', backName: r.backName || '',
          coinChange: r.coinChange || 0, points: r.points || 0, royalties: r.royalties || 0,
          isFoul: r.isFoul || false, qualifiesFantasyland: r.qualifiesFantasyland || false,
        }));

        if (!room.isPractice && !isDemoTable(tableId)) {
          await recordRakeToHouse(tableId, lastResult.result);
        }
        await persistGameHand(tableId, room, handNumber, { results: detailedResults, game_type: 'chinese' }, potTotal, winnerIds);
        console.log(`💾 [Chinese] Saved hand #${handNumber} to DB (timeout path)`);
      } catch (err) { console.error('Save chinese timeout result error:', err); }
    })();

    // Auto-deal next hand after the configured result display period
    scheduleRuntimeTimeout('result_display_sec', async () => {
      const r = chineseRooms.get(tableId);
      if (!r || r.phase !== 'result') return;
      for (const [seat, p] of r.players) {
        if (p.chips <= 0 && !isDemoBotId(p.id, r)) r.removePlayer(seat);
      }
      for (const [_, p] of r.players) p.sittingOut = false;
      if (r.players.size >= r.config.autoStartAt) {
        try {
          await reloadRoomRuntimeConfig(pool, r, tableId);
        } catch (err) {
          ioServer.to(tableId).emit('error', { message: 'Invalid room runtime configuration' });
          return;
        }
        const newState = r.startHand();
        if (newState) {
          _startChineseArrangeTimer(ioServer, tableId, r);
          for (const [seat] of r.players) {
            const sockets = [...ioServer.sockets.sockets.values()].filter(s => s.tableId === tableId && s.seatNumber === seat);
            sockets.forEach(s => s.emit('chinese:state', r.getState(seat)));
          }
          const spectators = [...ioServer.sockets.sockets.values()].filter(s => s.tableId === tableId && !s.seatNumber);
          spectators.forEach(s => s.emit('chinese:state', r.getState()));
          if (r.isPractice) _chineseBotAutoArrange(ioServer, tableId, r);
        }
      }
    });
  } else {
    // Broadcast updated state
    for (const [seat] of room.players) {
      const sockets = [...ioServer.sockets.sockets.values()].filter(s => s.tableId === tableId && s.seatNumber === seat);
      sockets.forEach(s => s.emit('chinese:state', room.getState(seat)));
    }
  }
}

// Start arrange timer for Chinese Poker room
function _startChineseArrangeTimer(ioServer, tableId, room) {
  room.startArrangeTimer(() => _chineseArrangeTimeout(ioServer, tableId, room));
}

// Bot auto-arrange for Chinese Poker
async function _chineseBotAutoArrange(ioServer, tableId, room) {
  let policy;
  try {
    policy = await loadSystemConfig(pool, 'practice_policy');
    room.practicePolicy = policy;
  } catch (err) {
    console.error(`Practice policy unavailable for table ${tableId}:`, err.message);
    return;
  }
  if (!policy.enabled || !policy.bots_enabled) return;

  // Prevent duplicate triggers
  if (!room._chineseBotGeneration) room._chineseBotGeneration = 0;
  room._chineseBotGeneration++;
  const myGen = room._chineseBotGeneration;

  // Track bot seats that need to arrange
  const botSeats = [];
  for (const [seat, p] of room.players) {
    if (!isDemoBotId(p.id, room)) continue;
    if (p.arranged) continue;
    botSeats.push(seat);
    if (botSeats.length >= policy.max_bots) break;
  }

  if (botSeats.length === 0) return;

  // Strategy: Bots arrange AFTER human confirms, with staggered delays
  // First bot: waits until human is ready + configured delay
  // Subsequent bots: use configured minimum delay plus jitter
  // This ensures the "waiting for others" screen is visible
  
  const maxChecks = Math.ceil(policy.bot_max_wait_ms / policy.bot_ready_poll_ms);
  let checkCount = 0;
  
  const checkHumanReady = () => {
    if (room._chineseBotGeneration !== myGen) return;
    if (!room || room.phase !== 'arranging') return;
    checkCount++;
    
    // Check if human player has arranged
    const humanArranged = [...room.players.entries()]
      .filter(([_, p]) => !isDemoBotId(p.id, room))
      .every(([_, p]) => p.arranged || p.sittingOut);
    
    if (humanArranged || checkCount >= maxChecks) {
      // Human is ready (or timeout) — start staggered bot arrangement
      let delay = policy.bot_action_min_ms + policy.bot_ready_poll_ms + Math.floor(Math.random() * (policy.bot_action_jitter_ms + 1));
      for (const seat of botSeats) {
        setTimeout(() => {
          if (room._chineseBotGeneration !== myGen) return;
          if (!room || room.phase !== 'arranging') return;
          const p = room.players.get(seat);
          if (!p || p.arranged) return;
          const hand = p.hand || [];
          if (hand.length !== 13) return;
          console.log(`🤖 [BOT] ${p.username} auto-arranging Chinese Poker (${delay/1000}s after human)`);
          const result = room.autoArrangeForSeat(seat);
          if (result && result.error) { console.log(`🤖 [BOT ERROR] ${result.error}`); return; }
          if (result && result.result) {
            ioServer.to(tableId).emit('chinese:result', result.result);
            ioServer.to(tableId).emit('chinese:state', room.getState());
            // Save hand history to DB
            (async () => {
              try {
                const winnerIds = result.result.results
                  .filter(r => r.coinChange > 0 && !isDemoBotId(r.id, room))
                  .map(r => r.id);
                const potTotal = result.result.results
                  .filter(r => r.coinChange > 0)
                  .reduce((sum, r) => sum + r.coinChange, 0);
                const handNumber = room ? room.handNumber : 1;
                const detailedResults = result.result.results.map(r => ({
                  id: r.id, seat: r.seat, username: r.username,
                  front: r.front || [], middle: r.middle || [], back: r.back || [],
                  frontName: r.frontName || '', middleName: r.middleName || '', backName: r.backName || '',
                  coinChange: r.coinChange || 0, points: r.points || 0, royalties: r.royalties || 0,
                  isFoul: r.isFoul || false, qualifiesFantasyland: r.qualifiesFantasyland || false,
                }));
                if (!room.isPractice && !isDemoTable(tableId)) {
                  await recordRakeToHouse(tableId, result.result);
                }
                await persistGameHand(tableId, room, handNumber, { results: detailedResults, game_type: 'chinese' }, potTotal, winnerIds);
                console.log(`💾 [Chinese] Saved hand #${handNumber} to DB (bot-trigger path)`);
              } catch (err) { console.error('Save chinese bot result error:', err); }
            })();
            // Wait for the configured result display period before starting the next round
            scheduleRuntimeTimeout('result_display_sec', async () => {
              if (!room || room.phase !== 'result') return;
              for (const [s, pl] of room.players) { if (pl.chips <= 0) room.removePlayer(s); }
              for (const [_, pl] of room.players) pl.sittingOut = false;
              if (room.players.size >= room.config.autoStartAt) {
                try {
                  await reloadRoomRuntimeConfig(pool, room, tableId);
                } catch (err) {
                  ioServer.to(tableId).emit('error', { message: 'Invalid room runtime configuration' });
                  return;
                }
                const state = room.startHand();
                if (state) {
                  _startChineseArrangeTimer(ioServer, tableId, room);
                  for (const [s] of room.players) {
                    const sockets = [...ioServer.sockets.sockets.values()].filter(ss => ss.tableId === tableId && ss.seatNumber === s);
                    sockets.forEach(ss => ss.emit('chinese:state', room.getState(s)));
                  }
                  const spectators = [...ioServer.sockets.sockets.values()].filter(ss => ss.tableId === tableId && (!ss.seatNumber || !room.players.has(ss.seatNumber)));
                  spectators.forEach(ss => ss.emit('chinese:state', room.getState()));
                  _chineseBotAutoArrange(ioServer, tableId, room);
                }
              }
            });
          } else {
            // Broadcast updated state (show who is ready)
            for (const [s] of room.players) {
              const sockets = [...ioServer.sockets.sockets.values()].filter(ss => ss.tableId === tableId && ss.seatNumber === s);
              sockets.forEach(ss => ss.emit('chinese:state', room.getState(s)));
            }
            const spectators = [...ioServer.sockets.sockets.values()].filter(ss => ss.tableId === tableId && (!ss.seatNumber || !room.players.has(ss.seatNumber)));
            spectators.forEach(ss => ss.emit('chinese:state', room.getState()));
          }
        }, delay);
        delay += policy.bot_action_min_ms + Math.floor(Math.random() * (policy.bot_action_jitter_ms + 1));
      }
    } else {
      // Human not ready yet — check again after the configured polling interval
      setTimeout(checkHumanReady, policy.bot_ready_poll_ms);
    }
  };
  
  // Start checking after the configured initial wait
  setTimeout(checkHumanReady, policy.bot_initial_wait_ms);
}

async function startNLHHand(ioServer, tableId, room, requireAutoStartThreshold = false) {
  if (room.isPlaying || room._startingHand) return null;
  room._startingHand = true;
  clearPendingAutoDeal(room);
  try {
    await reloadRoomRuntimeConfig(pool, room, tableId);
    if (requireAutoStartThreshold && room.players.size < room.config.autoStartAt) return null;
    const state = room.startHand();
    if (state) await setTableStatus(tableId, 'playing');
    return state;
  } catch (err) {
    console.error(`Unable to start hand on table ${tableId}:`, err.message);
    if (room.closedReason) {
      room.phase = 'closed';
      await setTableStatus(tableId, 'closed').catch(() => {});
      ioServer.to(tableId).emit('room:closed', { reason: room.closedReason });
      broadcastState(ioServer, tableId, room);
    } else {
      ioServer.to(tableId).emit('error', { message: 'Invalid room runtime configuration' });
    }
    return null;
  } finally {
    room._startingHand = false;
  }
}

function scheduleNLHAutoStart(ioServer, tableId, room) {
  try {
    scheduleRoomAutoStart(room, async () => {
      const state = await startNLHHand(ioServer, tableId, room, true);
      if (!state) return;
      botAutoPlay(ioServer, tableId, room);
      startTurnTimer(ioServer, tableId, room);
      broadcastState(ioServer, tableId, room);
    });
    broadcastState(ioServer, tableId, room);
  } catch (err) {
    console.error(`Unable to schedule auto-start on table ${tableId}:`, err.message);
    ioServer.to(tableId).emit('error', { message: 'Invalid room auto-start configuration' });
  }
}

function broadcastChineseState(ioServer, tableId, room) {
  const sockets = [...ioServer.sockets.sockets.values()].filter(s => s.tableId === tableId);
  for (const socket of sockets) {
    socket.emit('chinese:state', room.getState(socket.seatNumber || null));
  }
}

function scheduleChineseAutoStart(ioServer, tableId, room) {
  try {
    scheduleRoomAutoStart(room, async () => {
      try {
        await reloadRoomRuntimeConfig(pool, room, tableId);
      } catch (err) {
        ioServer.to(tableId).emit('error', { message: 'Invalid room runtime configuration' });
        return;
      }
      const state = room.startHand();
      if (!state) return;
      await setTableStatus(tableId, 'playing');
      _startChineseArrangeTimer(ioServer, tableId, room);
      broadcastChineseState(ioServer, tableId, room);
      _chineseBotAutoArrange(ioServer, tableId, room);
    });
    broadcastChineseState(ioServer, tableId, room);
  } catch (err) {
    console.error(`Unable to schedule Chinese auto-start on table ${tableId}:`, err.message);
    ioServer.to(tableId).emit('error', { message: 'Invalid room auto-start configuration' });
  }
}

async function scheduleRuntimeTimeout(key, callback) {
  try {
    const runtime = await loadGameRuntime(pool);
    return setTimeout(callback, runtime[key] * 1000);
  } catch (err) {
    console.error(`Unable to schedule ${key}:`, err.message);
    return null;
  }
}

function clearPendingAutoDeal(room) {
  if (room._autoDealTimer) clearTimeout(room._autoDealTimer);
  room._autoDealTimer = null;
  room._autoDealScheduled = false;
}

async function scheduleAutoDeal(ioServer, tableId, room) {
  // Prevent duplicate auto-deal timers
  if (room._autoDealScheduled) return;
  clearRoomAutoStart(room);
  room._autoDealScheduled = true;
  let runtime;
  try {
    runtime = await loadGameRuntime(pool);
  } catch (err) {
    room._autoDealScheduled = false;
    console.error(`Unable to schedule auto-deal on table ${tableId}:`, err.message);
    return;
  }

  room._autoDealTimer = setTimeout(async () => {
    room._autoDealTimer = null;
    room._autoDealScheduled = false;
    if (!room || room.isPlaying) return;
    if (room._pendingConfigUpdate) {
      try {
        await reloadRoomRuntimeConfig(pool, room, tableId);
        delete room._pendingConfigUpdate;
        io.to(tableId).emit('room:config', { tableId, configVersion: room.configVersion, configHash: room.configHash });
      } catch (err) { console.error(`Next-hand config reload failed for room ${tableId}:`, err.message); }
    }
    // Reset bot generation for fresh hand
    room._botGeneration = 0;
    // Remove broke players
    for (const [seat, p] of room.players) {
      if (p.chips <= 0) room.removePlayer(seat);
    }
    if (isDemoTable(tableId) || room.isPractice) {
      try {
        const policy = await loadSystemConfig(pool, 'practice_policy');
        const configuredDemoBots = policy.demo_table_bot_counts?.[tableId];
        const maxBots = isDemoTable(tableId)
          ? configuredDemoBots ?? policy.max_bots
          : Math.min(policy.max_bots, Math.max(room.maxSeats - room.players.size, 0));
        addDemoBotsToRoom(room, tableId, maxBots, room.isPractice ? policy.practice_chips : room.config.minBuyIn);
      } catch (err) {
        console.error(`Practice/demo policy unavailable on table ${tableId}:`, err.message);
      }
    }
    if (room.players.size > 0) {
      console.log(`\n🔄 Auto-deal hand #${room.handNumber + 1} on table ${tableId}`);
      const newState = await startNLHHand(ioServer, tableId, room, true);
      if (newState) {
        if (isDemoTable(tableId) || room.isPractice) botAutoPlay(ioServer, tableId, room);
        startTurnTimer(ioServer, tableId, room);
        broadcastState(ioServer, tableId, room);
      }
    } else {
      broadcastState(ioServer, tableId, room);
    }
  }, runtime.auto_deal_delay_sec * 1000);
}

async function getActiveUser(token) {
  const payload = jwt.verify(token, process.env.JWT_SECRET);
  if (!payload.sid) throw new Error('Session required');
  const result = await pool.query(
    `SELECT u.id, u.username, u.role, u.is_suspended
     FROM users u
     JOIN user_sessions s ON s.user_id = u.id AND s.id = $2
     WHERE u.id = $1 AND s.revoked_at IS NULL AND s.expires_at > NOW()`,
    [payload.id, payload.sid],
  );
  const user = result.rows[0];
  if (!user || user.is_suspended) throw new Error('Account unavailable');
  pool.query('UPDATE user_sessions SET last_seen_at = NOW() WHERE id = $1', [payload.sid]).catch(() => {});
  return { ...payload, username: user.username, role: user.role };
}

async function requireAdmin(req, res, next) {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'No token' });
  try {
    req.user = await getActiveUser(token);
    if (!isAdminRole(req.user.role)) {
      return res.status(403).json({ error: 'Admin only' });
    }
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or inactive token' });
  }
}

// Auth middleware for Socket.IO
io.use(async (socket, next) => {
  const token = socket.handshake.auth.token;
  if (!token) return next(new Error('No token'));
  try {
    socket.user = await getActiveUser(token);
    next();
  } catch { next(new Error('Invalid or inactive token')); }
});

io.on('connection', (socket) => {
  console.log(`🎮 Player connected: ${socket.user.username}`);
  let idleTimer;
  let idleTimeoutMs;
  const resetIdleTimer = () => {
    if (!idleTimeoutMs) return;
    clearTimeout(idleTimer);
    idleTimer = setTimeout(() => {
      socket.emit('error', { message: 'Disconnected due to inactivity' });
      socket.disconnect(true);
    }, idleTimeoutMs);
  };
  loadGameRuntime(pool).then(runtime => {
    idleTimeoutMs = runtime.idle_timeout_sec * 1000;
    resetIdleTimer();
  }).catch(err => console.error('Idle timeout config error:', err.message));
  socket.use((_, next) => {
    resetIdleTimer();
    next();
  });

  socket.on('seat:reserve', async ({ tableId, seatNumber }) => {
    const room = rooms.get(tableId) || chineseRooms.get(tableId);
    if (!room || room.players.has(seatNumber)) return socket.emit('error', { message: 'Seat unavailable' });
    const existing = room.seatReservations.get(seatNumber);
    if (existing && existing.userId !== socket.user.id && existing.expiresAt > Date.now()) {
      return socket.emit('error', { message: 'Seat is reserved' });
    }
    const runtime = await loadGameRuntime(pool);
    if (existing?.timer) clearTimeout(existing.timer);
    const expiresAt = Date.now() + runtime.seat_reservation_ttl_sec * 1000;
    const timer = setTimeout(() => {
      room.seatReservations.delete(seatNumber);
      if (rooms.has(tableId)) broadcastState(io, tableId, room);
      else broadcastChineseState(io, tableId, room);
    }, runtime.seat_reservation_ttl_sec * 1000);
    room.seatReservations.set(seatNumber, { userId: socket.user.id, expiresAt, timer });
    if (rooms.has(tableId)) broadcastState(io, tableId, room);
    else broadcastChineseState(io, tableId, room);
  });

  socket.on('seat:cancel', ({ tableId, seatNumber }) => {
    const room = rooms.get(tableId) || chineseRooms.get(tableId);
    const reservation = room?.seatReservations.get(seatNumber);
    if (!reservation || reservation.userId !== socket.user.id) return;
    clearTimeout(reservation.timer);
    room.seatReservations.delete(seatNumber);
    if (rooms.has(tableId)) broadcastState(io, tableId, room);
    else broadcastChineseState(io, tableId, room);
  });

  // Spectate: join room to receive game state without sitting down
  socket.on('game:spectate', async ({ tableId, accessToken }) => {
    try {
      if (!rooms.has(tableId)) {
        const table = await pool.query('SELECT * FROM game_tables WHERE id = $1', [tableId]);
        if (table.rows.length === 0) return socket.emit('error', { message: 'Table not found' });
        const t = table.rows[0];
        const roomConfig = await loadRoomSnapshot(pool, t);
        const room = createTexasRoom(t, roomConfig);
        room.onSitOutTimeout = (seat, player) => {
          setTablePlayerActive(tableId, seat, player, false).catch(() => {});
          broadcastState(io, tableId, room);
        };
        rooms.set(tableId, room);
      }
      const room = rooms.get(tableId);
      if (!canAccessRoom(room, socket, accessToken)) {
        return socket.emit('error', { message: 'Private room access required' });
      }
      socket.join(tableId);
      socket.tableId = tableId;
      socket.isSpectator = true;
      // Send current state (no hole cards visible)
      socket.emit('game:state', room.getState());
      console.log(`👁️ ${socket.user.username} spectating table ${tableId}`);

      // Practice tables: auto-add bots so spectator can watch
      if (room.isPractice && room.players.size === 0) {
        const practicePolicy = await loadSystemConfig(pool, 'practice_policy');
        room.practicePolicy = practicePolicy;
        addDemoBotsToRoom(room, tableId, Math.min(practicePolicy.max_bots, room.maxSeats), practicePolicy.practice_chips);
        // Send updated state with bots
        socket.emit('game:state', room.getState());
        // Auto-start bots playing immediately
        scheduleNLHAutoStart(io, tableId, room);
      } else if (room.players.size > 0) {
        // Room already has players — send fresh state
        socket.emit('game:state', room.getState());
        // Safety net: ensure bot chain is running for practice tables
        if (room.isPractice && room.isPlaying) {
          botAutoPlay(io, tableId, room);
        }
        // Safety net: if game ended but no auto-deal scheduled, restart
        if (room.isPractice && !room.isPlaying && room.players.size >= room.config.autoStartAt) {
          scheduleAutoDeal(io, tableId, room);
        }
      }
    } catch (err) { socket.emit('error', { message: err.message }); }
  });

  socket.on('game:join', async ({ tableId, seatNumber, buyIn, accessToken }) => {
    try {
      // Get or create room
      if (!rooms.has(tableId)) {
        // Check regular game_tables first
        let table = await pool.query('SELECT * FROM game_tables WHERE id = $1', [tableId]);
        
        // If not found, check if it's a tournament table
        if (table.rows.length === 0) {
          const tournTable = await pool.query('SELECT * FROM poker_tournament_tables WHERE id = $1', [tableId]);
          if (tournTable.rows.length > 0) {
            return socket.emit('error', { message: 'Use tournament:join for tournament tables' });
          } else {
            return socket.emit('error', { message: 'Table not found' });
          }
        } else {
          const t = table.rows[0];
          const roomConfig = await loadRoomSnapshot(pool, t);
          const room = createTexasRoom(t, roomConfig);
          room.onSitOutTimeout = (seat, player) => {
            setTablePlayerActive(tableId, seat, player, false).catch(() => {});
            broadcastState(io, tableId, room);
          };
          rooms.set(tableId, room);
        }
      }

      const room = rooms.get(tableId);
      if (!canAccessRoom(room, socket, accessToken)) {
        return socket.emit('error', { message: 'Private room access required' });
      }
      const maxSeats = room.maxSeats;
      const reservation = room.seatReservations.get(seatNumber);
      if (reservation && reservation.userId !== socket.user.id && reservation.expiresAt > Date.now()) {
        return socket.emit('error', { message: 'Seat is reserved' });
      }
      if (reservation) {
        clearTimeout(reservation.timer);
        room.seatReservations.delete(seatNumber);
      }

      // Tournament reconnect: if player is already seated in this room, just rejoin socket
      for (const [existingSeat, existingPlayer] of room.players) {
        if (existingPlayer.id === socket.user.id) {
          console.log(`🔄 [REJOIN] ${socket.user.username} reconnecting to seat ${existingSeat} on ${tableId}`);
          existingPlayer.socketId = socket.id;
          socket.tableId = tableId;
          socket.seatNumber = existingSeat;
          socket.join(tableId);
          socket.emit('game:state', room.getState(existingSeat));
          return;
        }
      }

      // Task 3.1: Seat range validation
      if (seatNumber < 1 || seatNumber > maxSeats) {
        return socket.emit('error', { message: 'Invalid seat' });
      }

      // Task 3.1: Occupied seat check
      if (room.players.has(seatNumber)) {
        return socket.emit('error', { message: 'Seat is already taken' });
      }

      // Task 3.1: Duplicate player check
      for (const [, player] of room.players) {
        if (player.id === socket.user.id) {
          return socket.emit('error', { message: 'You are already seated' });
        }
      }

      // Practice mode: use free chips, skip wallet
      if (room.isPractice) {
        const practicePolicy = await loadSystemConfig(pool, 'practice_policy');
        room.practicePolicy = practicePolicy;
        const practiceChips = buyIn ?? practicePolicy.practice_chips;
        room.addPlayer(seatNumber, {
          id: socket.user.id, username: socket.user.username, chips: practiceChips,
          countryFlag: socket.user.country_flag || null,
          avatarUrl: socket.user.avatar_url || null,
          socketId: socket.id,
        });
        socket.join(tableId);
        socket.tableId = tableId;
        socket.seatNumber = seatNumber;
        await setTablePlayerActive(tableId, seatNumber, room.players.get(seatNumber), true);

        // Add bots for practice
        const maxBots = Math.min(practicePolicy.max_bots, maxSeats);
        addDemoBotsToRoom(room, tableId, maxBots, practicePolicy.practice_chips);
        broadcastState(io, tableId, room);
        socket.emit('game:state', room.getState(seatNumber));
        console.log(`🎯 [PRACTICE] ${socket.user.username} joined practice table ${tableId} seat ${seatNumber} with ${practiceChips} chips`);

        // Auto-start after configured delay
        if (room.isPlaying) {
          // Game already in progress — ensure bot chain is still running
          botAutoPlay(io, tableId, room);
          startTurnTimer(io, tableId, room);
        } else {
          scheduleNLHAutoStart(io, tableId, room);
        }
        return;
      }

      // Task 3.2: Buy-in range validation
      const minBuyIn = Number(room.config.minBuyIn);
      const maxBuyIn = Number(room.config.maxBuyIn);
      if (minBuyIn > 0 && buyIn < minBuyIn) {
        return socket.emit('error', { message: `Buy-in must be at least ${minBuyIn}` });
      }
      if (maxBuyIn < Infinity && buyIn > maxBuyIn) {
        return socket.emit('error', { message: `Buy-in must be at most ${maxBuyIn}` });
      }

      // Deduct buy-in from wallet
      let walletSession;
      try {
        walletSession = await deductBuyIn(pool, {
          userId: socket.user.id,
          tableId,
          amount: buyIn,
        });
      } catch (err) {
        return socket.emit('error', { message: err.message === 'Insufficient balance' ? err.message : 'Failed to deduct buy-in' });
      }

      try {
        room.addPlayer(seatNumber, {
          id: socket.user.id, username: socket.user.username, chips: buyIn,
          countryFlag: socket.user.country_flag || null,
          avatarUrl: socket.user.avatar_url || null,
          walletSessionId: walletSession.sessionId,
          socketId: socket.id,
        });
      } catch (err) {
        await cashOut(pool, {
          sessionId: walletSession.sessionId,
          userId: socket.user.id,
          tableId,
          amount: buyIn,
        });
        throw err;
      }
      socket.join(tableId);
      socket.tableId = tableId;
      socket.seatNumber = seatNumber;
      await setTablePlayerActive(tableId, seatNumber, room.players.get(seatNumber), true);

      // Broadcast updated seat map to all players in room (Task 3.1)
      broadcastState(io, tableId, room);
      socket.emit('game:state', room.getState(seatNumber));
      console.log(`${socket.user.username} joined table ${tableId} seat ${seatNumber}`);

      // Demo tables: auto-add bots and auto-start
      if (isDemoTable(tableId)) {
        const policy = await loadSystemConfig(pool, 'practice_policy');
        const maxBots = policy.demo_table_bot_counts?.[tableId] ?? policy.max_bots;
        addDemoBotsToRoom(room, tableId, maxBots);
      }
      scheduleNLHAutoStart(io, tableId, room);
    } catch (err) { socket.emit('error', { message: err.message }); }
  });

  socket.on('game:start', async () => {
    const room = rooms.get(socket.tableId);
    if (!room) return;
    if (room.isTournament) return socket.emit('error', { message: 'Use tournament controls for this table' });
    if (!socket.seatNumber || !room.players.has(socket.seatNumber)) return socket.emit('error', { message: 'Only a seated player can start the game' });
    // Don't start a new hand if one is already in progress
    if (room.isPlaying) {
      return socket.emit('error', { message: 'Game already in progress' });
    }
    console.log(`\n🎮 [START] ${socket.user.username} started game on table ${socket.tableId}`);
    clearRoomAutoStart(room);
    const state = await startNLHHand(io, socket.tableId, room);
    if (!state) return socket.emit('error', { message: 'Need at least 2 players' });
    botAutoPlay(io, socket.tableId, room);
    startTurnTimer(io, socket.tableId, room);
    broadcastState(io, socket.tableId, room);
  });

  socket.on('game:straddle', ({ enabled } = {}) => {
    const room = rooms.get(socket.tableId);
    if (!room || room.isTournament === true) return socket.emit('error', { message: 'Not in a cash game' });
    const result = room.requestStraddle(socket.seatNumber, enabled !== false);
    if (result?.error) return socket.emit('error', { message: result.error });
    broadcastState(io, socket.tableId, room);
  });

  socket.on('game:action', async ({ action, amount }) => {
    const room = rooms.get(socket.tableId);
    if (!room) return;
    if (room.isTournament) return socket.emit('error', { message: 'Use tournament:action for this table' });
    console.log(`🎯 [ACTION] ${socket.user.username} seat ${socket.seatNumber}: ${action}${amount ? ' ' + amount : ''}`);
    const result = room.handleAction(socket.seatNumber, action, amount);
    if (result.error) {
      console.log(`❌ [ERROR] ${result.error}`);
      return socket.emit('error', { message: result.error });
    }
    // Demo/practice tables: trigger bot to play next if it's bot's turn
    if (!result.result) {
      if (isDemoTable(socket.tableId) || room.isPractice) {
        botAutoPlay(io, socket.tableId, room);
      }
      startTurnTimer(io, socket.tableId, room); // Start timer for human player
    } else {
      clearRoomTurnTimer(room);
      console.log(`🏆 [RESULT] Winners: ${result.result.winners.map(w => `seat${w.seat}`).join(',')} | Prize: ${result.result.prizePerWinner}`);
      io.to(socket.tableId).emit('game:result', result.result);
    }
    broadcastState(io, socket.tableId, room);

    // Save to DB when hand ends
    if (result.result) {
      const { winners, pot } = result.result;
      const tableId = socket.tableId;
      try {
        // บันทึก game_hands พร้อม hole cards (ทั้ง practice และ real)
        const playerHands = {};
        for (const [seat, p] of room.players) {
          playerHands[seat] = { id: p.id, username: p.username, holeCards: p.holeCards, folded: p.folded };
        }
        await persistGameHand(tableId, room, room.handNumber, {
          community: room.communityCards,
          players: playerHands,
          actions: room.actions,
        }, pot, winners.filter(w => !isDemoBotId(w.id, room)).map(w => w.id));
        // บันทึก hand_actions
        for (const act of room.actions) {
          const player = room.players.get(act.seat);
          if (!player || isDemoBotId(player.id, room)) continue;
          await pool.query(
            `INSERT INTO hand_actions (hand_id, user_id, action_type, amount, round, hole_cards)
             VALUES ((SELECT id FROM game_hands WHERE table_id = $1 AND hand_number = $2 LIMIT 1), $3, $4, $5, $6, $7)`,
            [tableId, room.handNumber, player.id, act.action, act.amount || 0, act.round, JSON.stringify(player.holeCards)]
          );
        }
        // Transactions only for real tables (skip practice)
        if (!room.isPractice) {
        for (const w of winners) {
          if (isDemoBotId(w.id, room)) continue;
          const prize = result.result.prizePerWinner;
          // ไม่ต้อง update wallet ตรงนี้ — chips จะถูกคืนตอน cashout (disconnect)
          // แค่บันทึก transaction เป็นประวัติ
          await pool.query(
            `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id)
             VALUES ($1, 'game_win', $2, (SELECT balance FROM wallets WHERE user_id = $1), $3)`,
            [w.id, prize, tableId]
          );
        }
        // บันทึก game_loss สำหรับคนแพ้
        for (const [seat, p] of room.players) {
          if (isDemoBotId(p.id, room)) continue;
          const isWinner = winners.some(w => w.seat === seat);
          if (!isWinner) {
            // คำนวณเงินที่เสียจาก actions ในมือนี้
            const lostAmount = room.actions
              .filter(a => a.seat === seat && (a.action === 'blind' || a.action === 'call' || a.action === 'raise' || a.action === 'all_in'))
              .reduce((sum, a) => sum + (a.amount || 0), 0);
            if (lostAmount > 0) {
              await pool.query(
                `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id)
                 VALUES ($1, 'game_loss', $2, (SELECT balance FROM wallets WHERE user_id = $1), $3)`,
                [p.id, -lostAmount, tableId]
              );
            }
          }
        }
        } // end if (!room.isPractice) — transactions

        // ═══ RAKE RECORDING — เก็บค่าธรรมเนียมโต๊ะสำหรับเจ้าของเว็บ ═══
        const recordedRake = await recordRakeToHouse(tableId, result.result);
        if (recordedRake > 0) {
          console.log(`💸 [RAKE] Table ${tableId}: ฿${recordedRake} (${result.result.rakePercent}%) → House`);
        }

        for (const [seat, p] of room.players) {
          if (isDemoBotId(p.id, room)) continue;
          const isWinner = winners.some(w => w.seat === seat);
          await pool.query(
            `UPDATE player_stats SET total_games = total_games + 1,
             total_wins = total_wins + $1, hands_played = hands_played + 1,
             updated_at = NOW() WHERE user_id = $2`,
            [isWinner ? 1 : 0, p.id]
          );
        }
      } catch (err) { console.error('Save game result error:', err); }

      // ผู้เล่นต้องกด start เอง — ไม่ auto-deal
      // Auto-deal มือถัดไปหลังจบ
      scheduleAutoDeal(io, socket.tableId, room);
    }
  });

  // Chat in room
  socket.on('chat:message', ({ message, receiverId }) => {
    if (!socket.tableId) return;
    const data = { sender: socket.user.username, senderId: socket.user.id, message, receiverId, timestamp: new Date() };
    if (receiverId) {
      const target = [...io.sockets.sockets.values()].find(s => s.user?.id === receiverId && s.tableId === socket.tableId);
      if (target) target.emit('chat:message', data);
      socket.emit('chat:message', data);
    } else {
      io.to(socket.tableId).emit('chat:message', data);
    }
  });

  // ===== Chinese Poker (ไพ่สามกอง) =====

  // Spectate Chinese Poker table
  socket.on('chinese:spectate', async ({ tableId, accessToken }) => {
    try {
      if (!chineseRooms.has(tableId)) {
        const table = await pool.query('SELECT * FROM game_tables WHERE id = $1', [tableId]);
        if (table.rows.length === 0) return socket.emit('error', { message: 'Table not found' });
        const t = table.rows[0];
        const roomConfig = await loadRoomSnapshot(pool, t);
        const room = createChineseRoom(t, roomConfig);
        chineseRooms.set(tableId, room);
      }
      const room = chineseRooms.get(tableId);
      if (!canAccessRoom(room, socket, accessToken)) {
        return socket.emit('error', { message: 'Private room access required' });
      }
      socket.join(tableId);
      socket.tableId = tableId;
      socket.isSpectator = true;
      socket.gameType = 'chinese';
      socket.emit('chinese:state', room.getState());
      console.log(`👁️ ${socket.user.username} spectating Chinese Poker table ${tableId}`);

      // Practice: add bots and auto-start
      if (room.isPractice && room.players.size === 0) {
        const practicePolicy = await loadSystemConfig(pool, 'practice_policy');
        room.practicePolicy = practicePolicy;
        for (let i = 0; i < practicePolicy.max_bots && i < practicePolicy.demo_bot_profiles.length; i++) {
          const bot = practicePolicy.demo_bot_profiles[i];
          room.addPlayer(i + 1, { id: bot.id, username: bot.username, chips: practicePolicy.practice_chips, countryFlag: bot.countryFlag });
        }
        io.to(tableId).emit('chinese:state', room.getState());
        // Auto-start after configured delay
        scheduleChineseAutoStart(io, tableId, room);
      }
    } catch (err) { socket.emit('error', { message: err.message }); }
  });

  socket.on('chinese:join', async ({ tableId, seatNumber, buyIn, accessToken }) => {
    try {
      if (!chineseRooms.has(tableId)) {
        const table = await pool.query('SELECT * FROM game_tables WHERE id = $1', [tableId]);
        if (table.rows.length === 0) return socket.emit('error', { message: 'Table not found' });
        const t = table.rows[0];
        const roomConfig = await loadRoomSnapshot(pool, t);
        const room = createChineseRoom(t, roomConfig);
        chineseRooms.set(tableId, room);
      }
      const room = chineseRooms.get(tableId);
      if (!canAccessRoom(room, socket, accessToken)) {
        return socket.emit('error', { message: 'Private room access required' });
      }
      const reservation = room.seatReservations.get(seatNumber);
      if (reservation && reservation.userId !== socket.user.id && reservation.expiresAt > Date.now()) {
        return socket.emit('error', { message: 'Seat is reserved' });
      }
      if (reservation) {
        clearTimeout(reservation.timer);
        room.seatReservations.delete(seatNumber);
      }
      for (const [existingSeat, existingPlayer] of room.players) {
        if (existingPlayer.id === socket.user.id) {
          existingPlayer.socketId = socket.id;
          socket.join(tableId);
          socket.tableId = tableId;
          socket.seatNumber = existingSeat;
          socket.gameType = 'chinese';
          socket.emit('chinese:state', room.getState(existingSeat));
          return;
        }
      }
      if (seatNumber < 1 || seatNumber > 4) {
        return socket.emit('error', { message: 'Invalid seat' });
      }
      if (room.players.has(seatNumber)) {
        return socket.emit('error', { message: 'Seat is already taken' });
      }

      // Practice mode: skip wallet deduction
      if (room.isPractice) {
        const practicePolicy = await loadSystemConfig(pool, 'practice_policy');
        room.practicePolicy = practicePolicy;
        const practiceChips = buyIn ?? practicePolicy.practice_chips;
        room.addPlayer(seatNumber, { id: socket.user.id, username: socket.user.username, chips: practiceChips, socketId: socket.id });
        socket.join(tableId);
        socket.tableId = tableId;
        socket.seatNumber = seatNumber;
        socket.gameType = 'chinese';
        await setTablePlayerActive(tableId, seatNumber, room.players.get(seatNumber), true);
        // Add bots
        for (let i = 0; i < practicePolicy.max_bots && i < practicePolicy.demo_bot_profiles.length; i++) {
          const bot = practicePolicy.demo_bot_profiles[i];
          if ([...room.players.values()].some(p => p.id === bot.id)) continue;
          for (let s = 1; s <= room.maxSeats; s++) {
            if (!room.players.has(s)) { room.addPlayer(s, { id: bot.id, username: bot.username, chips: practicePolicy.practice_chips, countryFlag: bot.countryFlag }); break; }
          }
        }
        io.to(tableId).emit('chinese:state', room.getState());
        console.log(`🎯 [PRACTICE] ${socket.user.username} joined Chinese Poker practice table ${tableId}`);
        // Auto-start
        scheduleChineseAutoStart(io, tableId, room);
        return;
      }

      const minBuyIn = Number(room.config.minBuyIn);
      const maxBuyIn = Number(room.config.maxBuyIn);
      if (minBuyIn > 0 && buyIn < minBuyIn) {
        return socket.emit('error', { message: `Buy-in must be at least ${minBuyIn}` });
      }
      if (maxBuyIn < Infinity && buyIn > maxBuyIn) {
        return socket.emit('error', { message: `Buy-in must be at most ${maxBuyIn}` });
      }

      // Real mode: deduct buy-in
      let walletSession;
      try {
        walletSession = await deductBuyIn(pool, {
          userId: socket.user.id,
          tableId,
          amount: buyIn,
        });
      } catch (err) {
        return socket.emit('error', { message: err.message === 'Insufficient balance' ? err.message : 'Failed to deduct buy-in' });
      }

      try {
        room.addPlayer(seatNumber, {
          id: socket.user.id,
          username: socket.user.username,
          chips: buyIn,
          walletSessionId: walletSession.sessionId,
          socketId: socket.id,
        });
      } catch (err) {
        await cashOut(pool, {
          sessionId: walletSession.sessionId,
          userId: socket.user.id,
          tableId,
          amount: buyIn,
        });
        throw err;
      }
      socket.join(tableId);
      socket.tableId = tableId;
      socket.seatNumber = seatNumber;
      socket.gameType = 'chinese';
      await setTablePlayerActive(tableId, seatNumber, room.players.get(seatNumber), true);

      io.to(tableId).emit('chinese:state', room.getState());
      scheduleChineseAutoStart(io, tableId, room);
      console.log(`${socket.user.username} joined Chinese Poker table ${tableId} seat ${seatNumber}`);
    } catch (err) { socket.emit('error', { message: err.message }); }
  });

  socket.on('chinese:start', async () => {
    const room = chineseRooms.get(socket.tableId);
    if (!room) return;
    if (!socket.seatNumber || !room.players.has(socket.seatNumber)) return socket.emit('error', { message: 'Only a seated player can start the game' });
    console.log(`\n🀄 [START] ${socket.user.username} started Chinese Poker on table ${socket.tableId}`);
    clearRoomAutoStart(room);
    try {
      await reloadRoomRuntimeConfig(pool, room, socket.tableId);
    } catch (err) {
      return socket.emit('error', { message: 'Invalid room runtime configuration' });
    }
    const state = room.startHand();
    if (!state) return socket.emit('error', { message: 'Need 2-4 players' });
    await setTableStatus(socket.tableId, 'playing');
    _startChineseArrangeTimer(io, socket.tableId, room);
    // ส่งไพ่ให้แต่ละคนเห็นเฉพาะของตัวเอง
    for (const [seat] of room.players) {
      const sockets = [...io.sockets.sockets.values()].filter(s => s.tableId === socket.tableId && s.seatNumber === seat);
      sockets.forEach(s => s.emit('chinese:state', room.getState(seat)));
    }
  });

  socket.on('chinese:arrange', ({ front, middle, back }) => {
    const room = chineseRooms.get(socket.tableId);
    if (!room) return;
    console.log(`🀄 [ARRANGE] ${socket.user.username} seat ${socket.seatNumber} arranging cards`);
    const result = room.arrangeCards(socket.seatNumber, front, middle, back);
    if (result.error) {
      console.log(`❌ [ERROR] ${result.error}`);
      return socket.emit('error', { message: result.error });
    }

    // ถ้ามี result = ทุกคนจัดเสร็จ → ส่งผลให้ทุกคน
    if (result.result) {
      const tableId = socket.tableId;
      io.to(tableId).emit('chinese:result', result.result);
      io.to(tableId).emit('chinese:state', result);
      // Save to DB — record hand history + transactions
      // (wallet is updated on disconnect via cashout with final chips)
      (async () => {
        try {
          const room = chineseRooms.get(tableId);
          const isPractice = room && room.isPractice;

          // Save game_hands with card data (save for all tables including practice)
          {
            const winnerIds = result.result.results
              .filter(r => r.coinChange > 0 && !isDemoBotId(r.id, room))
              .map(r => r.id);
            const potTotal = result.result.results
              .filter(r => r.coinChange > 0)
              .reduce((sum, r) => sum + r.coinChange, 0);
            const handNumber = room ? room.handNumber : 1;

            // Build detailed results for community_cards JSON
            const detailedResults = result.result.results.map(r => ({
              id: r.id,
              seat: r.seat,
              username: r.username,
              front: r.front || [],
              middle: r.middle || [],
              back: r.back || [],
              frontName: r.frontName || '',
              middleName: r.middleName || '',
              backName: r.backName || '',
              coinChange: r.coinChange || 0,
              points: r.points || 0,
              royalties: r.royalties || 0,
              isFoul: r.isFoul || false,
              qualifiesFantasyland: r.qualifiesFantasyland || false,
            }));

            if (!isPractice && !isDemoTable(tableId)) {
              await recordRakeToHouse(tableId, result.result);
            }
            await persistGameHand(tableId, room, handNumber, { results: detailedResults, game_type: 'chinese' }, potTotal, winnerIds);
            console.log(`💾 [Chinese] Saved hand #${handNumber} to DB (arrange path)`);
          }

          for (const r of result.result.results) {
            if (isDemoBotId(r.id, room)) continue;
            if (r.coinChange !== 0) {
              await pool.query(
                `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id)
                 VALUES ($1, $2, $3, (SELECT balance FROM wallets WHERE user_id = $1), $4)`,
                [r.id, r.coinChange > 0 ? 'game_win' : 'game_loss', r.coinChange, tableId]
              );
            }
            await pool.query(
              `UPDATE player_stats SET total_games = total_games + 1,
               total_wins = total_wins + $1, hands_played = hands_played + 1,
               updated_at = NOW() WHERE user_id = $2`,
              [r.coinChange > 0 ? 1 : 0, r.id]
            );
          }
        } catch (err) { console.error('Save chinese poker result error:', err); }
      })();

      // Auto-deal the next hand after the configured result display period
      scheduleRuntimeTimeout('result_display_sec', async () => {
        const r = chineseRooms.get(tableId);
        if (!r || r.phase !== 'result') return;
        for (const [seat, p] of r.players) {
          if (p.chips <= 0 && !isDemoBotId(p.id, r)) r.removePlayer(seat);
        }
        // Clear sittingOut for all players — everyone plays next hand
        for (const [_, p] of r.players) p.sittingOut = false;
        if (r.players.size >= r.config.autoStartAt) {
          try {
            await reloadRoomRuntimeConfig(pool, r, tableId);
          } catch (err) {
            io.to(tableId).emit('error', { message: 'Invalid room runtime configuration' });
            return;
          }
          const newState = r.startHand();
          if (newState) {
            _startChineseArrangeTimer(io, tableId, r);
            // Send personalized state to seated players
            for (const [seat] of r.players) {
              const sockets = [...io.sockets.sockets.values()].filter(s => s.tableId === tableId && s.seatNumber === seat);
              sockets.forEach(s => s.emit('chinese:state', r.getState(seat)));
            }
            // Send state to spectators
            const spectators = [...io.sockets.sockets.values()].filter(s => s.tableId === tableId && !s.seatNumber);
            spectators.forEach(s => s.emit('chinese:state', r.getState()));
            console.log(`🔄 Chinese Poker auto-deal hand #${r.handNumber} on table ${tableId}`);
            // Bot auto-arrange
            if (r.isPractice) _chineseBotAutoArrange(io, tableId, r);
          }
        }
      });
    } else {
      // ส่ง state อัปเดตให้ทุกคน (เห็นว่าใครจัดเสร็จแล้ว)
      for (const [seat] of room.players) {
        const sockets = [...io.sockets.sockets.values()].filter(s => s.tableId === socket.tableId && s.seatNumber === seat);
        sockets.forEach(s => s.emit('chinese:state', room.getState(seat)));
      }
    }
  });

  socket.on('game:rebuy', async ({ amount }) => {
    try {
      const room = rooms.get(socket.tableId);
      if (!room || !socket.seatNumber) return socket.emit('error', { message: 'Not seated in a poker room' });
      if (room.isTournament) return socket.emit('error', { message: 'Use tournament rebuy for this table' });
      if (room.isPlaying) return socket.emit('error', { message: 'Rebuy is available between hands only' });
      const player = room.players.get(socket.seatNumber);
      if (!player) return socket.emit('error', { message: 'Player not found' });
      if (room.texasPolicy.allow_rebuy === false) {
        return socket.emit('error', { message: 'Rebuy is disabled for this room' });
      }
      const rebuyAmount = Number(amount);
      if (!Number.isInteger(rebuyAmount) || rebuyAmount <= 0) {
        return socket.emit('error', { message: 'Rebuy amount must be a positive integer' });
      }
      const maxStack = Number(room.config.maxBuyIn);
      if (player.chips + rebuyAmount > maxStack) {
        return socket.emit('error', { message: `Rebuy cannot exceed maximum stack ${maxStack}` });
      }
      const walletSession = room.isPractice
        ? { sessionId: player.walletSessionId, balance: null }
        : await addToBuyIn(pool, {
            sessionId: player.walletSessionId,
            userId: player.id,
            tableId: socket.tableId,
            amount: rebuyAmount,
          });
      player.walletSessionId = walletSession.sessionId;
      player.chips += rebuyAmount;
      socket.emit('game:rebuy:ok', { chips: player.chips, balance: walletSession.balance });
      broadcastState(io, socket.tableId, room);
    } catch (err) {
      socket.emit('error', { message: err.message || 'Rebuy failed' });
    }
  });

  // NLH Poker: Leave room (with minimum play time check)
  socket.on('game:leave', () => {
    const room = rooms.get(socket.tableId);
    if (!room) return socket.emit('game:leave:ok', {});
    
    const canLeave = room.canLeave(socket.seatNumber);
    if (canLeave.allowed === false) {
      return socket.emit('game:leave:denied', {
        message: canLeave.message,
        remainingMinutes: canLeave.remainingMinutes,
      });
    }
    socket.emit('game:leave:ok', {});
  });

  // Chinese Poker: Leave room (with minimum play time check)
  socket.on('chinese:leave', () => {
    const room = chineseRooms.get(socket.tableId);
    if (!room) return socket.emit('chinese:leave:ok', {});
    
    const canLeave = room.canLeave(socket.seatNumber);
    if (canLeave.allowed === false) {
      return socket.emit('chinese:leave:denied', {
        message: canLeave.message,
        remainingMinutes: canLeave.remainingMinutes,
      });
    }
    socket.emit('chinese:leave:ok', {});
  });

  socket.on('disconnect', async () => {
    clearTimeout(idleTimer);
    try {
      const runtime = await loadGameRuntime(pool);
      if (runtime.disconnect_grace_sec > 0) {
        await new Promise(resolve => setTimeout(resolve, runtime.disconnect_grace_sec * 1000));
      }
    } catch (err) {
      console.error('Disconnect grace config error:', err.message);
      return;
    }
    // Handle Chinese Poker disconnect
    if (socket.tableId && socket.gameType === 'chinese' && chineseRooms.has(socket.tableId)) {
      const room = chineseRooms.get(socket.tableId);
      const player = room.players.get(socket.seatNumber);
      if (player?.socketId && player.socketId !== socket.id) return;
      if (player && !room.isPractice) {
        try {
          await cashOut(pool, {
            sessionId: player.walletSessionId,
            userId: player.id,
            tableId: socket.tableId,
            amount: Math.max(0, player.chips),
          });
        } catch (err) {
          console.error('Chinese poker cashout error:', err);
          return;
        }
      }
      await setTablePlayerActive(socket.tableId, socket.seatNumber, player, false);
      room.removePlayer(socket.seatNumber);
      scheduleChineseAutoStart(io, socket.tableId, room);
      io.to(socket.tableId).emit('chinese:state', room.getState());
      if (room.players.size === 0) chineseRooms.delete(socket.tableId);
    }
    // Handle Texas Hold'em disconnect (existing code)
    if (socket.tableId && rooms.has(socket.tableId)) {
      const room = rooms.get(socket.tableId);
      const player = room.players.get(socket.seatNumber);
      if (player?.socketId && player.socketId !== socket.id) return;

      // Task 3.7: Auto-fold if player is in an active hand
      if (player && room.isPlaying && !player.folded && !player.allIn) {
        console.log(`🔌 [DISCONNECT] Auto-folding ${player.username} (seat ${socket.seatNumber}) during active hand`);
        // If it's their turn, handle the fold action
        if (room.currentPlayerSeat === socket.seatNumber) {
          const result = room.handleAction(socket.seatNumber, 'fold', 0);
          if (result && !result.error) {
            if (result.result) {
              clearRoomTurnTimer(room);
              io.to(socket.tableId).emit('game:result', result.result);
              scheduleAutoDeal(io, socket.tableId, room);
            } else {
              if (room.isPractice || isDemoTable(socket.tableId)) botAutoPlay(io, socket.tableId, room);
              startTurnTimer(io, socket.tableId, room);
            }
            broadcastState(io, socket.tableId, room);
          }
        } else {
          // Not their turn yet — just mark as folded so they auto-skip
          player.folded = true;
        }
      }

      // Return remaining chips to wallet (skip for practice tables)
      if (player && !room.isPractice) {
        try {
          await cashOut(pool, {
            sessionId: player.walletSessionId,
            userId: player.id,
            tableId: socket.tableId,
            amount: Math.max(0, player.chips),
          });
        } catch (err) {
          console.error('Cashout error:', err);
          return;
        }
      }
      await setTablePlayerActive(socket.tableId, socket.seatNumber, player, false);
      room.removePlayer(socket.seatNumber);
      scheduleNLHAutoStart(io, socket.tableId, room);
      io.to(socket.tableId).emit('game:state', room.getState());
      if (room.players.size === 0) rooms.delete(socket.tableId);
    }
    console.log(`Player disconnected: ${socket.user?.username}`);
  });
});

app.get('/health', (_, res) => res.json({ status: 'ok', service: 'game-engine', rooms: rooms.size, config: configTracker.status() }));

app.get('/ready', async (_, res) => {
  try {
    const config = await configTracker.reconcile(pool);
    await loadGameRuntime(pool);
    await refreshPracticePolicy();
    res.json({ status: 'ready', service: 'game-engine', config });
  } catch (err) {
    res.status(503).json({ status: 'not_ready', service: 'game-engine', error: err.message, config: configTracker.status() });
  }
});

// Admin API: ดูห้องที่กำลังเล่น + ไพ่ในมือทุกคน
app.get('/admin/rooms', requireAdmin, (req, res) => {
  const roomList = [];
  for (const [tableId, room] of rooms) {
    const state = room.getState();
    // Admin เห็นไพ่ทุกคน
    const players = {};
    for (const [seat, p] of room.players) {
      players[seat] = { id: p.id, username: p.username, chips: p.chips, holeCards: p.holeCards, folded: p.folded, currentBet: p.currentBet, allIn: p.allIn };
    }
    roomList.push({ tableId, ...state, players, actions: room.actions?.slice(-10) || [] });
  }
  res.json({ rooms: roomList });
});

app.get('/admin/rooms/:tableId', requireAdmin, (req, res) => {
  const room = rooms.get(req.params.tableId);
  if (!room) return res.status(404).json({ error: 'Room not found' });
  const players = {};
  for (const [seat, p] of room.players) {
    players[seat] = { id: p.id, username: p.username, chips: p.chips, holeCards: p.holeCards, folded: p.folded, currentBet: p.currentBet, allIn: p.allIn };
  }
  res.json({ tableId: req.params.tableId, ...room.getState(), players, actions: room.actions?.slice(-20) || [] });
});

// Setup tournament WebSocket handlers
const tournamentHandler = setupTournamentHandlers(io, pool);

// REST endpoint to trigger tournament start from admin/wallet-service
app.post('/tournament/start', express.json(), requireAdmin, async (req, res) => {
  const { tournamentId } = req.body;
  if (!tournamentId) return res.status(400).json({ error: 'tournamentId required' });
  const result = await tournamentHandler.startTournament(tournamentId);
  if (result.error) return res.status(400).json(result);
  res.json(result);
});

app.get('/tournament/active', requireAdmin, (req, res) => {
  const active = [];
  for (const [id, mgr] of tournamentHandler.activeTournaments) {
    active.push({ tournamentId: id, ...mgr.getState() });
  }
  res.json({ tournaments: active });
});

server.listen(PORT, () => {
  console.log(`🎮 Game Engine running on port ${PORT}`);
  tournamentHandler.startTournamentScheduler();
  configTracker.reconcile(pool)
    .then(async () => {
      await refreshPracticePolicy();
      configListener = startConfigListener({
        tracker: configTracker,
        onEvent: event => {
          configTracker.reconcile(pool).catch(error => {
            configTracker.lastError = error.message;
          });
          io.emit('config:revision', {
            keys: event.keys,
            revisions: event.revisions,
            apply_mode: event.apply_mode,
            apply_modes: event.apply_modes,
            emitted_at: event.emitted_at,
          });
          const roomPolicyKeys = ['room_defaults', 'room_creation_limits', 'texas_holdem_policy', 'chinese_poker_policy'];
          if (event.keys?.some(key => roomPolicyKeys.includes(key))) {
            const allModes = [event.apply_mode, ...(event.apply_modes ? event.keys.map(key => event.apply_modes[key]) : [])];
            for (const [tableId, room] of [...rooms.entries(), ...chineseRooms.entries()]) {
              if (allModes.includes('immediate')) {
                reloadRoomFromSnapshot(pool, room, tableId).catch(error => {
                  console.error(`Immediate config reload failed for room ${tableId}:`, error.message);
                });
                io.to(tableId).emit('room:config', { tableId, configVersion: room.configVersion, configHash: room.configHash });
              } else if (allModes.some(mode => ['next_hand', 'next_turn'].includes(mode))) {
                room._pendingConfigUpdate = { tableId, at: Date.now(), modes: allModes };
                io.to(tableId).emit('room:pending_config', { tableId, applyMode: allModes.includes('next_turn') ? 'next_turn' : 'next_hand' });
              }
            }
          }
          if (event.keys?.includes('tournament_policy')) {
            tournamentHandler.reloadPolicy().catch(error => console.error('Unable to reload tournament policy:', error.message));
          }
          if (event.keys?.includes('practice_policy')) {
            refreshPracticePolicy().catch(error => console.error('Unable to reload practice policy:', error.message));
          }
        },
      });
    })
    .catch(error => {
      configTracker.listenerState = 'not_ready';
      configTracker.lastError = error.message;
      console.error('Config readiness failed:', error.message);
    });
});
