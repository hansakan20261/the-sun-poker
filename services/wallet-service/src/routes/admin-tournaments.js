const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { getConfig } = require('../config-service');

const router = express.Router();

// GET /admin/tournaments
router.get('/', authMiddleware, adminOnly, requireMenu('tournaments'), async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT t.*, gt.name as game_type_name, gt.name_th as game_type_name_th,
       (SELECT COUNT(*) FROM tournament_players tp WHERE tp.tournament_id = t.id) as player_count
       FROM tournaments t JOIN game_types gt ON gt.id = t.game_type_id ORDER BY t.created_at DESC`
    );
    res.json({ tournaments: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /admin/tournaments
router.post('/', authMiddleware, adminOnly, requireMenu('tournaments'), async (req, res) => {
  try {
    const { name, game_type_id, tournament_format, entry_fee, starting_chips,
            prize_pool, prize_structure, max_players, players_per_table,
            blind_structure, scheduled_at } = req.body;
    const policy = await getConfig(pool, 'tournament_policy');
    const result = await pool.query(
      `INSERT INTO tournaments (name, game_type_id, tournament_format, entry_fee,
       starting_chips, prize_pool, prize_structure, max_players, players_per_table,
       blind_structure, scheduled_at, created_by, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'draft') RETURNING *`,
      [name, game_type_id, tournament_format || policy.default_format, entry_fee ?? policy.default_entry_fee,
       starting_chips ?? policy.default_starting_chips, prize_pool || 0, JSON.stringify(prize_structure || {}),
       max_players ?? policy.default_max_players, players_per_table ?? policy.default_players_per_table,
       JSON.stringify(blind_structure || []), scheduled_at, req.user.id]
    );
    res.status(201).json({ tournament: result.rows[0] });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/tournaments/:id/status
router.put('/:id/status', authMiddleware, adminOnly, requireMenu('tournaments'), async (req, res) => {
  try {
    const { status } = req.body;
    const updates = { status };
    if (status === 'running') updates.started_at = new Date();
    if (status === 'finished') updates.finished_at = new Date();
    await pool.query(`UPDATE tournaments SET status = $1, started_at = COALESCE($2, started_at),
      finished_at = COALESCE($3, finished_at) WHERE id = $4`,
      [status, updates.started_at || null, updates.finished_at || null, req.params.id]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /admin/tournaments/:id/results — ดูรายละเอียด + ผู้เล่น
router.get('/:id/results', authMiddleware, adminOnly, requireMenu('tournaments'), async (req, res) => {
  try {
    const tournament = await pool.query(
      `SELECT t.*, gt.name as game_type_name, gt.name_th as game_type_name_th
       FROM tournaments t JOIN game_types gt ON gt.id = t.game_type_id WHERE t.id = $1`, [req.params.id]);
    if (tournament.rows.length === 0) return res.status(404).json({ error: 'Not found' });
    const players = await pool.query(
      `SELECT tp.*, u.username, u.display_name, u.avatar_url
       FROM tournament_players tp JOIN users u ON u.id = tp.user_id
       WHERE tp.tournament_id = $1
       ORDER BY COALESCE(tp.finish_position, 9999), tp.chip_count DESC`, [req.params.id]);
    res.json({ tournament: tournament.rows[0], players: players.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/tournaments/:id/players/:userId — ตั้งอันดับ + สถานะผู้เล่น
router.put('/:id/players/:userId', authMiddleware, adminOnly, requireMenu('tournaments'), async (req, res) => {
  try {
    const { finish_position, status, chip_count } = req.body;
    await pool.query(
      `UPDATE tournament_players SET
       finish_position = COALESCE($1, finish_position),
       status = COALESCE($2, status),
       chip_count = COALESCE($3, chip_count),
       eliminated_at = CASE WHEN $2 = 'eliminated' THEN NOW() ELSE eliminated_at END
       WHERE tournament_id = $4 AND user_id = $5`,
      [finish_position, status, chip_count, req.params.id, req.params.userId]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /admin/tournaments/:id/distribute-prizes — แจกเงินรางวัลอัตโนมัติ
router.post('/:id/distribute-prizes', authMiddleware, adminOnly, requireMenu('tournaments'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { prizes } = req.body; // [{ user_id, amount }]
    if (!prizes || !prizes.length) return res.status(400).json({ error: 'prizes array required' });

    await client.query('BEGIN');
    const distributed = [];
    for (const p of prizes) {
      if (!p.user_id || !p.amount || p.amount <= 0) continue;
      // อัปเดต prize_won ใน tournament_players
      await client.query(
        'UPDATE tournament_players SET prize_won = $1 WHERE tournament_id = $2 AND user_id = $3',
        [p.amount, req.params.id, p.user_id]);
      // เพิ่มเงินใน wallet
      await client.query('UPDATE wallets SET balance = balance + $1 WHERE user_id = $2', [p.amount, p.user_id]);
      // บันทึก transaction
      await client.query(
        `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id, description)
         VALUES ($1, 'tournament_prize', $2, (SELECT balance FROM wallets WHERE user_id = $1), $3, $4)`,
        [p.user_id, p.amount, req.params.id, `Tournament prize #${p.position || ''}`]);
      distributed.push({ user_id: p.user_id, amount: p.amount });
    }
    // Log
    await client.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'distribute_prizes', 'tournament', $2, $3)`,
      [req.user.id, req.params.id, JSON.stringify({ prizes: distributed })]);
    await client.query('COMMIT');
    res.json({ success: true, distributed });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Distribute prizes error:', err);
    res.status(500).json({ error: 'Internal server error' });
  } finally { client.release(); }
});

module.exports = router;
