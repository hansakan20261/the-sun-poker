const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();

// GET /leaderboard/global — อันดับทั้งระบบ (เหรียญมากสุด)
router.get('/global', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.display_name, u.avatar_url, u.vip_level,
              w.balance, ps.total_games, ps.total_wins, ps.win_rate
       FROM wallets w JOIN users u ON u.id = w.user_id
       LEFT JOIN player_stats ps ON ps.user_id = u.id
       WHERE u.role = 'player' ORDER BY w.balance DESC LIMIT 50`
    );
    res.json({ leaderboard: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /leaderboard/wins — อันดับชนะมากสุด
router.get('/wins', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.display_name, u.avatar_url,
              ps.total_games, ps.total_wins, ps.win_rate, ps.biggest_pot_won
       FROM player_stats ps JOIN users u ON u.id = ps.user_id
       WHERE u.role = 'player' AND ps.total_wins > 0
       ORDER BY ps.total_wins DESC LIMIT 50`
    );
    res.json({ leaderboard: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /leaderboard/club/:clubId — อันดับในคลับ
router.get('/club/:clubId', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.display_name, w.balance, ps.total_wins, ps.win_rate
       FROM club_members cm JOIN users u ON u.id = cm.user_id
       LEFT JOIN wallets w ON w.user_id = u.id
       LEFT JOIN player_stats ps ON ps.user_id = u.id
       WHERE cm.club_id = $1 AND cm.status = 'approved'
       ORDER BY w.balance DESC LIMIT 50`, [req.params.clubId]
    );
    res.json({ leaderboard: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
