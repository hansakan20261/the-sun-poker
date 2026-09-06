const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');

const router = express.Router();

// GET /admin/reports/summary — สรุปภาพรวม
router.get('/summary', authMiddleware, adminOnly, requireMenu('reports'), async (req, res) => {
  try {
    const [users, agents, clubs, tables, coins] = await Promise.all([
      pool.query(`SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE role='player') as players,
                  COUNT(*) FILTER (WHERE is_suspended) as suspended FROM users`),
      pool.query('SELECT COUNT(*) as total FROM agents'),
      pool.query('SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE is_active) as active FROM clubs'),
      pool.query(`SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE status='playing') as playing FROM game_tables`),
      pool.query(`SELECT COALESCE(SUM(CASE WHEN type='credit' THEN coin_amount ELSE 0 END),0) as total_credit,
                  COALESCE(SUM(CASE WHEN type='debit' THEN coin_amount ELSE 0 END),0) as total_debit
                  FROM admin_coin_transactions`),
    ]);
    res.json({
      users: users.rows[0],
      agents: agents.rows[0],
      clubs: clubs.rows[0],
      tables: tables.rows[0],
      coins: coins.rows[0],
    });
  } catch (err) {
    console.error('Reports error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /admin/reports/daily-coins — เติม/ถอนรายวัน (30 วัน)
router.get('/daily-coins', authMiddleware, adminOnly, requireMenu('reports'), async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT DATE(created_at) as date,
             SUM(CASE WHEN type='credit' THEN coin_amount ELSE 0 END) as credit,
             SUM(CASE WHEN type='debit' THEN coin_amount ELSE 0 END) as debit,
             COUNT(*) as tx_count
      FROM admin_coin_transactions
      WHERE created_at >= NOW() - INTERVAL '30 days'
      GROUP BY DATE(created_at) ORDER BY date DESC
    `);
    res.json({ daily: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /admin/reports/top-players — ผู้เล่นเหรียญมากสุด
router.get('/top-players', authMiddleware, adminOnly, requireMenu('reports'), async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT u.username, u.display_name, w.balance, ps.total_games, ps.total_wins
      FROM wallets w JOIN users u ON u.id = w.user_id
      LEFT JOIN player_stats ps ON ps.user_id = u.id
      WHERE u.role = 'player' ORDER BY w.balance DESC LIMIT 20
    `);
    res.json({ players: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /admin/reports/rake — รายงาน Rake Revenue
router.get('/rake', authMiddleware, adminOnly, requireMenu('reports'), async (req, res) => {
  try {
    // Summary totals
    const summaryResult = await pool.query(`
      SELECT COUNT(*) as total_hands, COALESCE(SUM(rake_amount), 0) as total_rake
      FROM game_hands WHERE rake_amount > 0
    `);

    // NLH vs OFC breakdown (by game_type)
    const typeResult = await pool.query(`
      SELECT gty.slug as game_type,
             COUNT(*) as hands,
             COALESCE(SUM(gh.rake_amount), 0) as rake
      FROM game_hands gh
      JOIN game_tables gt ON gt.id = gh.table_id
      JOIN game_types gty ON gty.id = gt.game_type_id
      WHERE gh.rake_amount > 0
      GROUP BY gty.slug
    `);

    // By table
    const byTableResult = await pool.query(`
      SELECT gt.name as table_name, gty.name as game_type_name, gty.slug as game_type,
             COUNT(*) as hand_count, COALESCE(SUM(gh.rake_amount), 0) as total_rake
      FROM game_hands gh
      JOIN game_tables gt ON gt.id = gh.table_id
      JOIN game_types gty ON gty.id = gt.game_type_id
      WHERE gh.rake_amount > 0
      GROUP BY gt.name, gty.name, gty.slug
      ORDER BY total_rake DESC
    `);

    // Daily summary (last 30 days)
    const dailyResult = await pool.query(`
      SELECT * FROM rake_daily_summary LIMIT 30
    `);

    // Build summary object
    const summary = {
      total_hands: summaryResult.rows[0]?.total_hands || 0,
      total_rake: summaryResult.rows[0]?.total_rake || 0,
      nlh_hands: 0, nlh_rake: 0,
      ofc_hands: 0, ofc_rake: 0,
    };

    for (const row of typeResult.rows) {
      if (row.game_type === 'chinese_poker') {
        summary.ofc_hands = Number(row.hands);
        summary.ofc_rake = Number(row.rake);
      } else {
        summary.nlh_hands += Number(row.hands);
        summary.nlh_rake += Number(row.rake);
      }
    }

    res.json({
      summary,
      by_table: byTableResult.rows,
      daily: dailyResult.rows,
    });
  } catch (err) {
    console.error('Rake report error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
