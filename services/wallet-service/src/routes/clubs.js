const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { sanitizeTable } = require('../room-security');
const { getConfig, normalizeRoomInput, resolveRoomConfig, roomSnapshotPayload } = require('../config-service');

const router = express.Router();

async function clubMemberOnly(req, res, next) {
  if (['admin', 'super_admin'].includes(req.user.role)) return next();
  try {
    const result = await pool.query(
      `SELECT role FROM club_members
       WHERE club_id = $1 AND user_id = $2 AND status = 'approved'`,
      [req.params.id, req.user.id],
    );
    if (result.rows.length === 0) return res.status(403).json({ error: 'Club membership required' });
    req.clubRole = result.rows[0].role;
    next();
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
}

async function clubStaffOnly(req, res, next) {
  await clubMemberOnly(req, res, () => {
    if (['admin', 'super_admin'].includes(req.user.role) || ['owner', 'admin'].includes(req.clubRole)) return next();
    res.status(403).json({ error: 'Club staff access required' });
  });
}

// GET /clubs — คลับทั้งหมด
router.get('/', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT c.*, u.username as owner_name,
       (SELECT COUNT(*) FROM club_members cm WHERE cm.club_id = c.id AND cm.status='approved') as member_count
       FROM clubs c JOIN users u ON u.id = c.owner_id WHERE c.is_active = TRUE ORDER BY c.created_at DESC`
    );
    res.json({ clubs: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /clubs/my — คลับที่ฉันเป็นสมาชิก
router.get('/my', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT c.*, cm.role, u.username as owner_name,
       (SELECT COUNT(*) FROM club_members cm2 WHERE cm2.club_id = c.id AND cm2.status='approved') as member_count
       FROM clubs c
       JOIN club_members cm ON cm.club_id = c.id AND cm.user_id = $1 AND cm.status = 'approved'
       JOIN users u ON u.id = c.owner_id
       WHERE c.is_active = TRUE ORDER BY cm.joined_at DESC`,
      [req.user.id]
    );
    res.json({ clubs: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /clubs — สร้างคลับ
router.post('/', authMiddleware, async (req, res) => {
  try {
    const { name, description, max_members } = req.body;
    if (!name || name.trim().length < 2) return res.status(400).json({ error: 'Club name required (min 2 chars)' });
    const limits = await getConfig(pool, 'room_creation_limits');
    const memberLimit = max_members ?? limits.club_max_members;
    if (memberLimit < 1 || memberLimit > limits.club_max_members) {
      return res.status(400).json({ error: `Club member limit must be between 1 and ${limits.club_max_members}` });
    }
    const result = await pool.query(
      `INSERT INTO clubs (name, description, owner_id, max_members) VALUES ($1,$2,$3,$4) RETURNING *`,
      [name.trim(), description || '', req.user.id, memberLimit]
    );
    await pool.query(
      `INSERT INTO club_members (club_id, user_id, role, status) VALUES ($1,$2,'owner','approved')`,
      [result.rows[0].id, req.user.id]
    );
    res.status(201).json({ club: result.rows[0] });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /clubs/:id/join — เข้าร่วมคลับ
router.post('/:id/join', authMiddleware, async (req, res) => {
  try {
    const club = await pool.query('SELECT * FROM clubs WHERE id = $1 AND is_active = TRUE', [req.params.id]);
    if (club.rows.length === 0) return res.status(404).json({ error: 'Club not found' });
    const memberCount = await pool.query(
      `SELECT COUNT(*) as cnt FROM club_members WHERE club_id = $1 AND status = 'approved'`, [req.params.id]);
    if (Number(memberCount.rows[0].cnt) >= club.rows[0].max_members) {
      return res.status(400).json({ error: 'Club is full' });
    }
    await pool.query(
      `INSERT INTO club_members (club_id, user_id, role, status) VALUES ($1,$2,'member','approved')
       ON CONFLICT (club_id, user_id) DO UPDATE SET status = 'approved'`,
      [req.params.id, req.user.id]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /clubs/:id/leave — ออกจากคลับ
router.post('/:id/leave', authMiddleware, async (req, res) => {
  try {
    // Owner can't leave
    const club = await pool.query('SELECT owner_id FROM clubs WHERE id = $1', [req.params.id]);
    if (club.rows.length > 0 && club.rows[0].owner_id === req.user.id) {
      return res.status(400).json({ error: 'Owner cannot leave. Transfer ownership or delete club.' });
    }
    await pool.query('DELETE FROM club_members WHERE club_id = $1 AND user_id = $2', [req.params.id, req.user.id]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /clubs/:id/members
router.get('/:id/members', authMiddleware, clubMemberOnly, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT cm.*, u.username, u.display_name, u.avatar_url FROM club_members cm
       JOIN users u ON u.id = cm.user_id WHERE cm.club_id = $1 AND cm.status = 'approved'
       ORDER BY cm.role = 'owner' DESC, cm.joined_at`, [req.params.id]
    );
    res.json({ members: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /clubs/:id/tables — ห้องเล่นในคลับ
router.get('/:id/tables', authMiddleware, clubMemberOnly, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT gt.*, gty.name as game_type_name, gty.slug as game_type_slug, gty.name_th,
       (SELECT COUNT(*) FROM table_players tp WHERE tp.table_id = gt.id) as player_count
       FROM game_tables gt
       JOIN game_types gty ON gty.id = gt.game_type_id
       WHERE gt.club_id = $1 AND gt.status != 'closed'
       ORDER BY gt.created_at DESC`,
      [req.params.id]
    );
    res.json({ tables: result.rows.map(sanitizeTable) });
  } catch (err) { console.error('GET club tables error:', err.message); res.status(500).json({ error: 'Internal server error' }); }
});

// POST /clubs/:id/tables — สร้างห้องในคลับ
router.post('/:id/tables', authMiddleware, clubStaffOnly, async (req, res) => {
  try {
    // Check membership
    const member = await pool.query(
      `SELECT role FROM club_members WHERE club_id = $1 AND user_id = $2 AND status = 'approved'`,
      [req.params.id, req.user.id]
    );
    if (member.rows.length === 0) return res.status(403).json({ error: 'Not a club member' });
    const role = member.rows[0].role;
    if (!['owner', 'admin'].includes(role)) return res.status(403).json({ error: 'Only owner/admin can create rooms' });

    const { game_type_id, name } = req.body;
    if (!game_type_id || !name) return res.status(400).json({ error: 'game_type_id and name required' });
    const [defaults, limits] = await Promise.all([
      getConfig(pool, 'room_defaults'),
      getConfig(pool, 'room_creation_limits'),
    ]);
    const activeRooms = await pool.query(
      "SELECT COUNT(*) AS total FROM game_tables WHERE club_id = $1 AND status != 'closed'",
      [req.params.id],
    );
    if (Number(activeRooms.rows[0].total) >= limits.max_rooms_per_club) {
      return res.status(400).json({ error: 'Club active room limit reached' });
    }
    const gameType = await pool.query('SELECT slug, is_active FROM game_types WHERE id = $1', [game_type_id]);
    if (!gameType.rows[0]?.is_active) return res.status(400).json({ error: 'Game type is not available' });
    if (!limits.allowed_game_type_slugs.includes(gameType.rows[0].slug)) {
      return res.status(400).json({ error: 'Game type is not allowed for room creation' });
    }
    const effective = await resolveRoomConfig(pool, {
      gameTypeId: game_type_id,
      templateId: req.body.room_template_id,
      overrides: req.body,
    });
    const roomInput = normalizeRoomInput({ ...effective.value, ...req.body, club_id: req.params.id }, defaults, limits);

    const result = await pool.query(
      `INSERT INTO game_tables (club_id, game_type_id, name, small_blind, big_blind, ante, min_buy_in, max_buy_in,
       max_players, turn_time_sec, auto_start_at, auto_start_delay_sec, minimum_play_minutes,
       rake_percent, rake_cap, room_template_id, config_snapshot, config_version, config_hash, status, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,'waiting',$20) RETURNING *`,
      [req.params.id, game_type_id, name, roomInput.small_blind, roomInput.big_blind, roomInput.ante,
       roomInput.min_buy_in, roomInput.max_buy_in, roomInput.max_players, roomInput.turn_time_sec,
       roomInput.auto_start_at, roomInput.auto_start_delay_sec, roomInput.minimum_play_minutes,
       roomInput.rake_percent, roomInput.rake_cap, req.body.room_template_id || null,
       JSON.stringify(roomSnapshotPayload(effective)),
       effective.revisions.room_defaults, effective.hash, req.user.id]
    );
    res.status(201).json({ table: result.rows[0], effective_config: effective });
  } catch (err) { console.error('POST club table error:', err.message); res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
