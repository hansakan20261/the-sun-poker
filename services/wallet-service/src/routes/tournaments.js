const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();

// GET /tournaments — ดูรายการแข่งทั้งหมด
router.get('/', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT t.*, gt.name as game_type_name, gt.name_th,
       (SELECT COUNT(*) FROM tournament_players tp WHERE tp.tournament_id = t.id) as player_count
       FROM tournaments t JOIN game_types gt ON gt.id = t.game_type_id
       WHERE t.is_visible = TRUE AND t.status != 'cancelled'
       ORDER BY t.scheduled_at ASC NULLS LAST`
    );
    res.json({ tournaments: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /tournaments/my/history — ประวัติรายการที่เคยเข้าร่วม (ต้องอยู่ก่อน /:id)
router.get('/my/history', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT tp.*, t.name, t.status, t.entry_fee, t.prize_pool,
              gt.name as game_type_name, gt.name_th
       FROM tournament_players tp
       JOIN tournaments t ON t.id = tp.tournament_id
       JOIN game_types gt ON gt.id = t.game_type_id
       WHERE tp.user_id = $1 ORDER BY tp.registered_at DESC`, [req.user.id]);
    res.json({ history: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /tournaments/:id/results — ดูผลการแข่งขัน
router.get('/:id/results', authMiddleware, async (req, res) => {
  try {
    const tournament = await pool.query(
      `SELECT t.*, gt.name as game_type_name, gt.name_th FROM tournaments t
       JOIN game_types gt ON gt.id = t.game_type_id WHERE t.id = $1`, [req.params.id]);
    if (tournament.rows.length === 0) return res.status(404).json({ error: 'Not found' });
    const players = await pool.query(
      `SELECT tp.*, u.username, u.display_name, u.avatar_url
       FROM tournament_players tp JOIN users u ON u.id = tp.user_id
       WHERE tp.tournament_id = $1
       ORDER BY COALESCE(tp.finish_position, 9999), tp.chip_count DESC`, [req.params.id]);
    res.json({ tournament: tournament.rows[0], players: players.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /tournaments/:id/register — สมัครแข่ง
router.post('/:id/register', authMiddleware, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const t = await client.query('SELECT * FROM tournaments WHERE id = $1', [req.params.id]);
    if (t.rows.length === 0) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Not found' }); }
    const tournament = t.rows[0];
    if (!['draft', 'registration'].includes(tournament.status)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Registration closed' });
    }
    if (Number(tournament.entry_fee) > 0) {
      const wallet = await client.query('SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE', [req.user.id]);
      if (Number(wallet.rows[0].balance) < Number(tournament.entry_fee)) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Insufficient balance' });
      }
      await client.query('UPDATE wallets SET balance = balance - $1 WHERE user_id = $2', [tournament.entry_fee, req.user.id]);
      await client.query(
        `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id)
         VALUES ($1, 'tournament_entry', $2, (SELECT balance FROM wallets WHERE user_id=$1), $3)`,
        [req.user.id, -Number(tournament.entry_fee), req.params.id]);
    }
    await client.query(
      `INSERT INTO tournament_players (tournament_id, user_id, chip_count) VALUES ($1, $2, $3)`,
      [req.params.id, req.user.id, tournament.starting_chips]);
    await client.query('COMMIT');
    res.json({ success: true });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') return res.status(409).json({ error: 'Already registered' });
    res.status(500).json({ error: 'Internal server error' });
  } finally { client.release(); }
});

module.exports = router;
