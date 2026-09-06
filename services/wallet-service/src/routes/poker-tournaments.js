const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { getConfig } = require('../config-service');

const router = express.Router();

// ═══════════════════════════════════════════════════════════════
// GET /poker/tournaments — list all tournaments
// ═══════════════════════════════════════════════════════════════
router.get('/', authMiddleware, async (req, res) => {
  try {
    const { status } = req.query;
    let query = `SELECT t.*, 
      (SELECT COUNT(*) FROM poker_tournament_players p WHERE p.tournament_id = t.id) as registered_count,
      u.username as creator_name
      FROM poker_tournaments t
      LEFT JOIN users u ON u.id = t.created_by`;
    const params = [];
    if (status) {
      query += ' WHERE t.status = $1';
      params.push(status);
    }
    query += ' ORDER BY t.created_at DESC LIMIT 50';
    const result = await pool.query(query, params);
    res.json({ tournaments: result.rows });
  } catch (err) {
    console.error('GET tournaments error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// GET /poker/tournaments/:id — tournament detail
// ═══════════════════════════════════════════════════════════════
router.get('/:id', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;
    const tournament = await pool.query(
      `SELECT t.*, 
       (SELECT COUNT(*) FROM poker_tournament_players p WHERE p.tournament_id = t.id) as registered_count
       FROM poker_tournaments t WHERE t.id = $1`, [id]
    );
    if (tournament.rows.length === 0) return res.status(404).json({ error: 'Tournament not found' });

    const players = await pool.query(
      `SELECT p.*, u.username, u.display_name, u.avatar_url
       FROM poker_tournament_players p JOIN users u ON u.id = p.user_id
       WHERE p.tournament_id = $1 ORDER BY p.finish_rank ASC NULLS LAST, p.registered_at ASC`, [id]
    );
    const blinds = await pool.query(
      `SELECT * FROM poker_blind_levels WHERE tournament_id = $1 ORDER BY level_no ASC`, [id]
    );

    const policy = await getConfig(pool, 'tournament_policy');
    res.json({
      tournament: tournament.rows[0],
      players: players.rows,
      blind_levels: blinds.rows,
      payout: policy.default_payout_structure,
    });
  } catch (err) {
    console.error('GET tournament detail error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// POST /poker/tournaments — create tournament (admin/super_admin)
// ═══════════════════════════════════════════════════════════════
router.post('/', authMiddleware, async (req, res) => {
  try {
    const { role } = req.user;
    if (!['admin', 'super_admin'].includes(role)) {
      return res.status(403).json({ error: 'Only admin can create tournaments' });
    }

    const policy = await getConfig(pool, 'tournament_policy');
    const {
      name, type = policy.default_tournament_type, game = policy.default_game_slug,
      buy_in = policy.default_entry_fee, entry_fee = 0, max_players = policy.default_max_players,
      players_per_table = policy.default_players_per_table, starting_chips = policy.default_starting_chips,
      blind_level_minutes = policy.default_blind_level_minutes, start_time, description,
    } = req.body;

    if (!name) return res.status(400).json({ error: 'Tournament name required' });

    const result = await pool.query(
      `INSERT INTO poker_tournaments 
       (name, type, game, buy_in, entry_fee, max_players, players_per_table, starting_chips, blind_level_minutes, start_time, description, created_by, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'registration') RETURNING *`,
      [name, type, game, buy_in, entry_fee, max_players, players_per_table, starting_chips, blind_level_minutes, start_time || null, description || null, req.user.id]
    );

    const tournamentId = result.rows[0].id;

    // Create configured blind levels
    for (const bl of policy.default_blind_structure) {
      await pool.query(
        `INSERT INTO poker_blind_levels (tournament_id, level_no, small_blind, big_blind, ante, duration_seconds)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [tournamentId, bl.level_no, bl.small_blind, bl.big_blind, bl.ante, blind_level_minutes * 60]
      );
    }

    res.status(201).json({ tournament: result.rows[0] });
  } catch (err) {
    console.error('POST tournament error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// POST /poker/tournaments/:id/register — player registers
// ═══════════════════════════════════════════════════════════════
router.post('/:id/register', authMiddleware, async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const userId = req.user.id;

    await client.query('BEGIN');

    // Check tournament exists and is open
    const t = await client.query('SELECT * FROM poker_tournaments WHERE id = $1', [id]);
    if (t.rows.length === 0) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Tournament not found' }); }
    const tournament = t.rows[0];
    const policy = await getConfig(client, 'tournament_policy');
    const now = Date.now();
    if (tournament.status === 'registration') {
      const createdAt = Date.parse(tournament.created_at || '');
      if (Number.isFinite(createdAt) && policy.registration_window_minutes > 0 &&
          now > createdAt + policy.registration_window_minutes * 60_000) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Registration window has closed' });
      }
    } else if (tournament.status === 'running') {
      const startedAt = Date.parse(tournament.start_time || tournament.started_at || '');
      const canLateRegister = policy.late_registration_minutes > 0 &&
        Number.isFinite(startedAt) &&
        now <= startedAt + policy.late_registration_minutes * 60_000;
      if (!canLateRegister) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Registration closed' });
      }
    } else {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Registration closed' });
    }

    // Check not already registered
    const existing = await client.query(
      'SELECT id FROM poker_tournament_players WHERE tournament_id = $1 AND user_id = $2', [id, userId]
    );
    if (existing.rows.length > 0) { await client.query('ROLLBACK'); return res.status(400).json({ error: 'Already registered' }); }

    // Check max players
    const count = await client.query(
      'SELECT COUNT(*) as cnt FROM poker_tournament_players WHERE tournament_id = $1', [id]
    );
    if (parseInt(count.rows[0].cnt) >= tournament.max_players) {
      await client.query('ROLLBACK'); return res.status(400).json({ error: 'Tournament full' });
    }

    // Deduct buy-in + entry fee from player balance
    const totalCost = Number(tournament.buy_in) + Number(tournament.entry_fee);
    const wallet = await client.query('SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE', [userId]);
    if (wallet.rows.length === 0) { await client.query('ROLLBACK'); return res.status(400).json({ error: 'Wallet not found' }); }
    const balance = Number(wallet.rows[0].balance);
    if (balance < totalCost) { await client.query('ROLLBACK'); return res.status(400).json({ error: 'Insufficient balance' }); }

    // Deduct balance
    const newBalance = balance - totalCost;
    await client.query('UPDATE wallets SET balance = $1 WHERE user_id = $2', [newBalance, userId]);

    // Record transaction
    await client.query(
      `INSERT INTO transactions (user_id, type, amount, balance_after, description)
       VALUES ($1, 'tournament_buy_in', $2, $3, $4)`,
      [userId, -totalCost, newBalance, `Tournament: ${tournament.name}`]
    );

    // Register player
    await client.query(
      `INSERT INTO poker_tournament_players (tournament_id, user_id, chips, status)
       VALUES ($1, $2, $3, 'registered')`,
      [id, userId, tournament.starting_chips]
    );

    // Update prize pool
    await client.query(
      'UPDATE poker_tournaments SET prize_pool = prize_pool + $1 WHERE id = $2',
      [Number(tournament.buy_in), id]
    );

    await client.query('COMMIT');

    const newCount = parseInt(count.rows[0].cnt) + 1;
    res.json({
      success: true,
      message: 'Registered successfully',
      balance_after: newBalance,
      registered_count: newCount,
      starting_chips: tournament.starting_chips,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Tournament register error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// ═══════════════════════════════════════════════════════════════
// GET /poker/tournaments/:id/leaderboard
// ═══════════════════════════════════════════════════════════════
router.get('/:id/leaderboard', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `SELECT p.*, u.username, u.display_name, u.avatar_url
       FROM poker_tournament_players p JOIN users u ON u.id = p.user_id
       WHERE p.tournament_id = $1
       ORDER BY 
         CASE WHEN p.status = 'eliminated' THEN 1 ELSE 0 END ASC,
         p.chips DESC, p.finish_rank ASC NULLS LAST`,
      [id]
    );
    res.json({ leaderboard: result.rows });
  } catch (err) {
    console.error('Tournament leaderboard error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// POST /poker/tournaments/:id/start — admin starts tournament
// ═══════════════════════════════════════════════════════════════
router.post('/:id/start', authMiddleware, async (req, res) => {
  try {
    if (!['admin', 'super_admin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Only admin can start tournaments' });
    }

    const { id } = req.params;
    const t = await pool.query('SELECT * FROM poker_tournaments WHERE id = $1', [id]);
    if (t.rows.length === 0) return res.status(404).json({ error: 'Tournament not found' });
    if (t.rows[0].status !== 'registration') return res.status(400).json({ error: 'Tournament not in registration phase' });

    const players = await pool.query(
      'SELECT * FROM poker_tournament_players WHERE tournament_id = $1 ORDER BY registered_at', [id]
    );
    const policy = await getConfig(pool, 'tournament_policy');
    const playerCount = players.rows.length;
    if (playerCount < policy.min_players_to_start) {
      return res.status(400).json({ error: `Need at least ${policy.min_players_to_start} players` });
    }

    const playersPerTable = t.rows[0].players_per_table;
    const tableCount = Math.ceil(playerCount / playersPerTable);

    // Create tables
    const tableIds = [];
    for (let i = 1; i <= tableCount; i++) {
      const tr = await pool.query(
        `INSERT INTO poker_tournament_tables (tournament_id, table_no, status) VALUES ($1, $2, 'active') RETURNING id`,
        [id, i]
      );
      tableIds.push(tr.rows[0].id);
    }

    // Seat players round-robin
    for (let i = 0; i < players.rows.length; i++) {
      const tableIdx = i % tableCount;
      const seatNo = Math.floor(i / tableCount) + 1;
      await pool.query(
        `UPDATE poker_tournament_players SET table_id = $1, seat_no = $2, status = 'seated'
         WHERE id = $3`,
        [tableIds[tableIdx], seatNo, players.rows[i].id]
      );
    }

    // Update tournament status
    await pool.query(
      `UPDATE poker_tournaments SET status = 'running', start_time = NOW(), updated_at = NOW() WHERE id = $1`,
      [id]
    );

    res.json({ success: true, tables_created: tableCount, players_seated: playerCount });
  } catch (err) {
    console.error('Tournament start error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// POST /poker/tournaments/:id/cancel — admin cancels tournament
// ═══════════════════════════════════════════════════════════════
router.post('/:id/cancel', authMiddleware, async (req, res) => {
  const client = await pool.connect();
  try {
    if (!['admin', 'super_admin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Only admin can cancel tournaments' });
    }
    const { id } = req.params;
    const reason = String(req.body?.reason || 'Tournament cancelled by admin');
    await client.query('BEGIN');
    const tournamentResult = await client.query(
      'SELECT * FROM poker_tournaments WHERE id = $1 FOR UPDATE',
      [id],
    );
    const tournament = tournamentResult.rows[0];
    if (!tournament) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Tournament not found' });
    }
    if (['finished', 'cancelled'].includes(tournament.status)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: `Tournament is already ${tournament.status}` });
    }

    const policy = await getConfig(client, 'tournament_policy');
    const playersResult = await client.query(
      `SELECT p.*, u.username FROM poker_tournament_players p
       JOIN users u ON u.id = p.user_id
       WHERE p.tournament_id = $1
       FOR UPDATE`,
      [id],
    );
    const players = playersResult.rows;
    const cancellationPolicy = policy.cancellation_policy;
    const paidActions = [];

    if (cancellationPolicy === 'refund') {
      for (const player of players) {
        const refund = Number(tournament.buy_in) + Number(tournament.entry_fee);
        if (refund <= 0) continue;
        const wallet = await client.query(
          'UPDATE wallets SET balance = balance + $1, updated_at = NOW() WHERE user_id = $2 RETURNING balance',
          [refund, player.user_id],
        );
        if (wallet.rows.length === 0) throw new Error('Player wallet not found');
        await client.query(
          `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id, description)
           VALUES ($1, 'tournament_refund', $2, $3, $4, $5)`,
          [player.user_id, refund, wallet.rows[0].balance, id, `Tournament refund: ${tournament.name}`],
        );
        paidActions.push({ user_id: player.user_id, amount: refund, type: 'refund' });
      }
    } else if (cancellationPolicy === 'prize_pool_split' && players.length > 0) {
      const share = Math.floor(Number(tournament.prize_pool) / players.length);
      for (const player of players) {
        if (share <= 0) break;
        const wallet = await client.query(
          'UPDATE wallets SET balance = balance + $1, updated_at = NOW() WHERE user_id = $2 RETURNING balance',
          [share, player.user_id],
        );
        if (wallet.rows.length === 0) throw new Error('Player wallet not found');
        await client.query(
          `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id, description)
           VALUES ($1, 'tournament_prize', $2, $3, $4, $5)`,
          [player.user_id, share, wallet.rows[0].balance, id, `Cancelled tournament split: ${tournament.name}`],
        );
        await client.query(
          'UPDATE poker_tournament_players SET prize = $1 WHERE id = $2',
          [share, player.id],
        );
        paidActions.push({ user_id: player.user_id, amount: share, type: 'prize_pool_split' });
      }
    }

    await client.query(
      `UPDATE poker_tournament_players
       SET status = 'cancelled', chips = 0
       WHERE tournament_id = $1`,
      [id],
    );
    await client.query(
      `UPDATE poker_tournaments
       SET status = 'cancelled', updated_at = NOW(), cancelled_at = NOW(),
           cancel_reason = $2, cancellation_policy = $3
       WHERE id = $1`,
      [id, reason, cancellationPolicy],
    );
    await client.query('COMMIT');
    res.json({ success: true, policy: cancellationPolicy, paid_actions: paidActions });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Tournament cancel error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// ═══════════════════════════════════════════════════════════════
// POST /poker/tournaments/:id/finish — admin finishes tournament
// ═══════════════════════════════════════════════════════════════
router.post('/:id/finish', authMiddleware, async (req, res) => {
  const client = await pool.connect();
  try {
    if (!['admin', 'super_admin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Only admin can finish tournaments' });
    }

    const { id } = req.params;
    await client.query('BEGIN');

    const t = await client.query('SELECT * FROM poker_tournaments WHERE id = $1 FOR UPDATE', [id]);
    if (t.rows.length === 0) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Not found' }); }
    if (t.rows[0].status === 'finished') {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Tournament already finished' });
    }

    const prizePool = Number(t.rows[0].prize_pool);

    // Get players ordered by chips (alive first, then by finish_rank)
    const players = await client.query(
      `SELECT * FROM poker_tournament_players WHERE tournament_id = $1
       ORDER BY 
         CASE WHEN status != 'eliminated' THEN 0 ELSE 1 END ASC,
         chips DESC, finish_rank ASC NULLS LAST`,
      [id]
    );

    const policy = await getConfig(client, 'tournament_policy');
    // Assign ranks and prizes
    for (let i = 0; i < players.rows.length; i++) {
      const rank = i + 1;
      const payout = policy.prize_distribution_policy === 'winner_take_all'
        ? { percent: rank === 1 ? 100 : 0 }
        : policy.prize_distribution_policy === 'final_table_split'
          ? { percent: rank <= Math.min(9, players.rows.length) ? 100 / Math.min(9, players.rows.length) : 0 }
          : policy.default_payout_structure.find(p => p.rank === rank);
      const prize = payout ? Math.floor(prizePool * payout.percent / 100) : 0;
      const status = i === 0 ? 'winner' : 'eliminated';

      await client.query(
        `UPDATE poker_tournament_players SET finish_rank = $1, prize = $2, status = $3 WHERE id = $4`,
        [rank, prize, status, players.rows[i].id]
      );

      // Credit prize to wallet
      if (prize > 0) {
        const wallet = await client.query('SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE', [players.rows[i].user_id]);
        const newBal = Number(wallet.rows[0]?.balance || 0) + prize;
        await client.query('UPDATE wallets SET balance = $1 WHERE user_id = $2', [newBal, players.rows[i].user_id]);
        await client.query(
          `INSERT INTO transactions (user_id, type, amount, balance_after, description)
           VALUES ($1, 'tournament_prize', $2, $3, $4)`,
          [players.rows[i].user_id, prize, newBal, `Tournament prize: Rank #${rank}`]
        );
      }
    }

    await client.query(
      `UPDATE poker_tournaments SET status = 'finished', updated_at = NOW() WHERE id = $1`, [id]
    );

    await client.query('COMMIT');
    res.json({ success: true, message: 'Tournament finished', prize_pool: prizePool });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Tournament finish error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

module.exports = router;
