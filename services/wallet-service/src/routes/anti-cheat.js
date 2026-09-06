const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');

const router = express.Router();

// GET /admin/anti-cheat/suspicious — ดูพฤติกรรมน่าสงสัย
router.get('/suspicious', authMiddleware, adminOnly, async (req, res) => {
  try {
    // ตรวจจับ: ผู้เล่นที่ชนะบ่อยผิดปกติ (win rate > 80% && games > 20)
    const highWinRate = await pool.query(
      `SELECT u.id, u.username, u.display_name, ps.total_games, ps.total_wins, ps.win_rate
       FROM player_stats ps JOIN users u ON u.id = ps.user_id
       WHERE ps.win_rate > 80 AND ps.total_games > 20
       ORDER BY ps.win_rate DESC LIMIT 20`
    );

    // ตรวจจับ: ผู้เล่นที่เล่นด้วยกันบ่อย (potential collusion)
    const frequentPairs = await pool.query(
      `SELECT tp1.user_id as player1, tp2.user_id as player2,
              u1.username as p1_name, u2.username as p2_name,
              COUNT(*) as games_together
       FROM table_players tp1
       JOIN table_players tp2 ON tp1.table_id = tp2.table_id AND tp1.user_id < tp2.user_id
       JOIN users u1 ON u1.id = tp1.user_id
       JOIN users u2 ON u2.id = tp2.user_id
       GROUP BY tp1.user_id, tp2.user_id, u1.username, u2.username
       HAVING COUNT(*) > 10
       ORDER BY games_together DESC LIMIT 20`
    );

    // ตรวจจับ: ธุรกรรมผิดปกติ (โอนเหรียญจำนวนมากระหว่างผู้เล่น)
    const suspiciousTransfers = await pool.query(
      `SELECT t.*, u.username FROM transactions t
       JOIN users u ON u.id = t.user_id
       WHERE t.type IN ('transfer_in', 'transfer_out') AND ABS(t.amount) > 10000
       ORDER BY t.created_at DESC LIMIT 20`
    );

    res.json({
      high_win_rate: highWinRate.rows,
      frequent_pairs: frequentPairs.rows,
      suspicious_transfers: suspiciousTransfers.rows,
      checked_at: new Date(),
    });
  } catch (err) {
    console.error('Anti-cheat error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /admin/anti-cheat/flag/:userId — แจ้งผู้เล่นน่าสงสัย
router.post('/flag/:userId', authMiddleware, adminOnly, async (req, res) => {
  try {
    const { reason } = req.body;
    await pool.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'flag_suspicious', 'user', $2, $3)`,
      [req.user.id, req.params.userId, JSON.stringify({ reason })]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
