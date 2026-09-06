const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { sanitizeTable } = require('../room-security');

const router = express.Router();

// GET /admin/clubs — ดูคลับทั้งหมด
router.get('/', authMiddleware, adminOnly, requireMenu('clubs'), async (req, res) => {
  try {
    const { search, limit = 20, offset = 0 } = req.query;
    let query = `SELECT c.*, u.username as owner_username, u.display_name as owner_name,
                   (SELECT COUNT(*) FROM club_members cm WHERE cm.club_id = c.id AND cm.status = 'approved') as member_count
                 FROM clubs c JOIN users u ON u.id = c.owner_id WHERE 1=1`;
    const params = [];

    if (search) {
      params.push(`%${search}%`);
      query += ` AND (c.name ILIKE $${params.length} OR u.username ILIKE $${params.length})`;
    }

    const countParams = [...params];
    const countQuery = `SELECT COUNT(*) as total FROM clubs c JOIN users u ON u.id = c.owner_id WHERE 1=1` +
      query.split('WHERE 1=1')[1].split('ORDER BY')[0];
    const countResult = await pool.query(countQuery, countParams);

    params.push(Number(limit));
    query += ` ORDER BY c.created_at DESC LIMIT $${params.length}`;
    params.push(Number(offset));
    query += ` OFFSET $${params.length}`;

    const result = await pool.query(query, params);
    res.json({ clubs: result.rows, total: Number(countResult.rows[0].total) });
  } catch (err) {
    console.error('List clubs error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /admin/clubs/:id — รายละเอียดคลับ
router.get('/:id', authMiddleware, adminOnly, requireMenu('clubs'), async (req, res) => {
  try {
    const club = await pool.query(
      `SELECT c.*, u.username as owner_username, u.display_name as owner_name
       FROM clubs c JOIN users u ON u.id = c.owner_id WHERE c.id = $1`, [req.params.id]
    );
    if (club.rows.length === 0) return res.status(404).json({ error: 'Club not found' });

    const members = await pool.query(
      `SELECT cm.*, u.username, u.display_name FROM club_members cm
       JOIN users u ON u.id = cm.user_id WHERE cm.club_id = $1
       ORDER BY cm.joined_at DESC`, [req.params.id]
    );
    // ห้องเล่น (cash game) ของคลับ
    const tables = await pool.query(
      `SELECT gt.*, gty.name as game_type_name, gty.name_th,
       (SELECT COUNT(*) FROM table_players tp WHERE tp.table_id = gt.id AND tp.is_active) as player_count
       FROM game_tables gt JOIN game_types gty ON gty.id = gt.game_type_id
       WHERE gt.club_id = $1 ORDER BY gt.created_at DESC`, [req.params.id]
    );
    // ทัวร์นาเมนต์ของคลับ
    const tournaments = await pool.query(
      `SELECT t.*, gty.name as game_type_name, gty.name_th,
       (SELECT COUNT(*) FROM tournament_players tp WHERE tp.tournament_id = t.id) as player_count
       FROM tournaments t JOIN game_types gty ON gty.id = t.game_type_id
       WHERE t.club_id = $1 ORDER BY t.created_at DESC`, [req.params.id]
    );
    res.json({ club: club.rows[0], members: members.rows, tables: tables.rows.map(sanitizeTable), tournaments: tournaments.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/clubs/:id/toggle — เปิด/ปิดคลับ
router.put('/:id/toggle', authMiddleware, adminOnly, requireMenu('clubs'), async (req, res) => {
  try {
    await pool.query('UPDATE clubs SET is_active = NOT is_active WHERE id = $1', [req.params.id]);
    await pool.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'toggle_club', 'club', $2, '{}')`, [req.user.id, req.params.id]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// DELETE /admin/clubs/:id/members/:userId — ลบสมาชิกออกจากคลับ
router.delete('/:id/members/:userId', authMiddleware, adminOnly, requireMenu('clubs'), async (req, res) => {
  try {
    await pool.query('DELETE FROM club_members WHERE club_id = $1 AND user_id = $2',
      [req.params.id, req.params.userId]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
