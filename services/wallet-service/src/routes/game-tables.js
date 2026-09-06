const express = require('express');
const crypto = require('crypto');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');
const {
  hashRoomPassword,
  isHashedPassword,
  issueRoomAccessToken,
  sanitizeTable,
  verifyRoomPassword,
} = require('../room-security');
const { getConfig, normalizeRoomInput, resolveRoomConfig, roomSnapshotPayload } = require('../config-service');

const router = express.Router();
const PLAYER_ROOM_OVERRIDE_FIELDS = new Set([
  'small_blind',
  'big_blind',
  'ante',
  'min_buy_in',
  'max_buy_in',
  'max_players',
  'turn_time_sec',
  'auto_start_at',
  'auto_start_delay_sec',
  'minimum_play_minutes',
]);

function playerRoomOverrides(input = {}) {
  return Object.fromEntries(
    [...PLAYER_ROOM_OVERRIDE_FIELDS]
      .filter(field => input[field] !== undefined)
      .map(field => [field, input[field]]),
  );
}

// GET /tables — ดูห้องเล่นที่เปิดอยู่
router.get('/', authMiddleware, async (req, res) => {
  try {
    const { game_type_id } = req.query;
    let query = `SELECT gt.*, gty.name as game_type_name, gty.name_th,
                  (SELECT COUNT(*) FROM table_players tp WHERE tp.table_id = gt.id AND tp.is_active) as player_count
                 FROM game_tables gt JOIN game_types gty ON gty.id = gt.game_type_id
                 WHERE gt.status != 'closed' AND gt.hide_from_lobby = FALSE`;
    const params = [];
    if (game_type_id) { params.push(game_type_id); query += ` AND gt.game_type_id = $${params.length}`; }
    query += ' ORDER BY gt.is_featured DESC, gt.created_at DESC';
    const result = await pool.query(query, params);
    res.json({ tables: result.rows.map(sanitizeTable) });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /tables — ผู้เล่นสร้างห้อง
router.post('/', authMiddleware, async (req, res) => {
  try {
    const feature = await pool.query("SELECT is_enabled FROM feature_flags WHERE feature_key = 'feature_room_creation'");
    if (feature.rows[0]?.is_enabled === false) {
      return res.status(403).json({ error: 'Room creation is disabled' });
    }
    const [defaults, limits, securityPolicy] = await Promise.all([
      getConfig(pool, 'room_defaults'),
      getConfig(pool, 'room_creation_limits'),
      getConfig(pool, 'security_policy'),
    ]);
    if (limits.player_can_create === false) {
      return res.status(403).json({ error: 'Player room creation is disabled' });
    }
    const activeRooms = await pool.query(
      `SELECT COUNT(*) AS total FROM game_tables
       WHERE created_by = $1 AND status != 'closed'`,
      [req.user.id],
    );
    const activeRoomLimit = req.user.role === 'agent' ? limits.max_rooms_per_agent : limits.max_rooms_per_player;
    if (Number(activeRooms.rows[0].total) >= Number(activeRoomLimit)) {
      return res.status(400).json({ error: 'Active room limit reached' });
    }
    const game_type_id = req.body.game_type_id;
    if (!game_type_id) return res.status(400).json({ error: 'game_type_id is required' });
    const gameType = await pool.query('SELECT slug, is_active FROM game_types WHERE id = $1', [game_type_id]);
    if (!gameType.rows[0]?.is_active) return res.status(400).json({ error: 'Game type is not available' });
    if (!limits.allowed_game_type_slugs.includes(gameType.rows[0].slug)) {
      return res.status(400).json({ error: 'Game type is not allowed for room creation' });
    }
    const roomOverrides = playerRoomOverrides(req.body);
    const effective = await resolveRoomConfig(pool, {
      gameTypeId: game_type_id,
      templateId: req.body.room_template_id,
      overrides: roomOverrides,
    });
    const roomInput = normalizeRoomInput({ ...effective.value, ...roomOverrides }, defaults, limits);
    const { name, max_players, small_blind, big_blind, ante,
            min_buy_in, max_buy_in, turn_time_sec, auto_start_at, auto_start_delay_sec,
            minimum_play_minutes, rake_percent, rake_cap, password, club_id } = { ...req.body, ...roomInput };
    const roomCode = crypto.randomBytes(3).toString('hex').toUpperCase();
    const passwordHash = await hashRoomPassword(password, securityPolicy.password_hash_rounds);
    const result = await pool.query(
      `INSERT INTO game_tables (game_type_id, name, mode, max_players, small_blind, big_blind, ante,
       min_buy_in, max_buy_in, turn_time_sec, auto_start_at, auto_start_delay_sec, minimum_play_minutes,
       rake_percent, rake_cap, password, room_code, is_private, club_id, room_template_id, config_snapshot,
       config_version, config_hash, status, created_by)
       VALUES ($1,$2,'private',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,'waiting',$23) RETURNING *`,
      [game_type_id, name, max_players, small_blind, big_blind, ante, min_buy_in, max_buy_in,
       turn_time_sec, auto_start_at, auto_start_delay_sec, minimum_play_minutes, rake_percent, rake_cap,
       passwordHash, roomCode, Boolean(password), club_id||null, req.body.room_template_id || null,
       JSON.stringify(roomSnapshotPayload(effective)),
       effective.revisions.room_defaults, effective.hash, req.user.id]
    );
    res.status(201).json({ table: sanitizeTable(result.rows[0]), effective_config: effective });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /tables/config-effective — public effective room defaults for a game type
router.get('/config-effective', authMiddleware, async (req, res) => {
  try {
    const { game_type_id } = req.query;
    if (!game_type_id) return res.status(400).json({ error: 'game_type_id is required' });
    const effective = await resolveRoomConfig(pool, {
      gameTypeId: game_type_id,
      templateId: req.query.room_template_id,
    });
    res.json({ effective_config: effective });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// POST /tables/join-by-code — เข้าห้องด้วยรหัสห้อง (ต้องอยู่ก่อน /:id/join)
router.post('/join-by-code', authMiddleware, async (req, res) => {
  try {
    const { room_code, password } = req.body;
    if (!room_code) return res.status(400).json({ error: 'กรุณากรอกรหัสห้อง' });

    const result = await pool.query(
      `SELECT gt.*, gty.slug as game_type_slug, gty.name_th as game_type_name_th
       FROM game_tables gt
       JOIN game_types gty ON gty.id = gt.game_type_id
       WHERE gt.room_code = $1 AND gt.status != 'closed'`,
      [room_code.toUpperCase()]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'ไม่พบห้องที่มีรหัสนี้' });
    }

    const table = result.rows[0];
    const securityPolicy = await getConfig(pool, 'security_policy');
    if (!await verifyRoomPassword(password, table.password)) {
      return res.status(403).json({ error: 'รหัสผ่านไม่ถูกต้อง' });
    }
    if (table.password && !isHashedPassword(table.password)) {
      table.password = await hashRoomPassword(password, securityPolicy.password_hash_rounds);
      await pool.query('UPDATE game_tables SET password = $1 WHERE id = $2', [table.password, table.id]);
    }

    const playerCount = await pool.query(
      'SELECT COUNT(*) as count FROM table_players WHERE table_id = $1 AND is_active = TRUE',
      [table.id]
    );
    if (Number(playerCount.rows[0].count) >= table.max_players) {
      return res.status(400).json({ error: 'ห้องเต็มแล้ว' });
    }

    const runtime = await getConfig(pool, 'game_runtime');
    res.json({
      table: sanitizeTable(table),
      room_access_token: issueRoomAccessToken(table.id, req.user.id, runtime.room_access_token_minutes),
    });
  } catch (err) {
    console.error('Join by code error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /tables/:id/join — เข้าร่วมห้องผ่าน Game Socket เท่านั้น
router.post('/:id/join', authMiddleware, (req, res) => {
  res.status(410).json({ error: 'Use the authenticated game socket to join a table' });
});

// GET /tables/game-types — ดูประเภทเกมที่เปิด
router.get('/game-types', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM game_types WHERE is_active = TRUE ORDER BY sort_order');
    res.json({ game_types: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /tables/hand-history — ประวัติมือของผู้เล่น
router.get('/hand-history', authMiddleware, async (req, res) => {
  try {
    const { limit = 20, offset = 0, table_id } = req.query;
    let query;
    let params;

    if (table_id) {
      // Filter by specific table
      query = `SELECT gh.*, gt.name as table_name, gty.name as game_type_name, gty.name_th
       FROM game_hands gh
       JOIN game_tables gt ON gt.id = gh.table_id
       JOIN game_types gty ON gty.id = gt.game_type_id
       WHERE gh.table_id = $1
       ORDER BY gh.started_at DESC LIMIT $2 OFFSET $3`;
      params = [table_id, Number(limit), Number(offset)];
    } else {
      // All hands for this user
      query = `SELECT gh.*, gt.name as table_name, gty.name as game_type_name, gty.name_th
       FROM game_hands gh
       JOIN game_tables gt ON gt.id = gh.table_id
       JOIN game_types gty ON gty.id = gt.game_type_id
       WHERE $1 = ANY(gh.winner_ids)
          OR gh.id IN (SELECT hand_id FROM hand_actions WHERE user_id = $1)
       ORDER BY gh.started_at DESC LIMIT $2 OFFSET $3`;
      params = [req.user.id, Number(limit), Number(offset)];
    }

    const result = await pool.query(query, params);
    res.json({ hands: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /tables/hand-history/:handId — รายละเอียดมือ
router.get('/hand-history/:handId', authMiddleware, async (req, res) => {
  try {
    const hand = await pool.query(
      `SELECT gh.*, gt.name as table_name FROM game_hands gh
       JOIN game_tables gt ON gt.id = gh.table_id WHERE gh.id = $1`, [req.params.handId]);
    if (hand.rows.length === 0) return res.status(404).json({ error: 'Hand not found' });
    const actions = await pool.query(
      `SELECT ha.*, u.username FROM hand_actions ha
       JOIN users u ON u.id = ha.user_id WHERE ha.hand_id = $1
       ORDER BY ha.created_at`, [req.params.handId]);
    res.json({ hand: hand.rows[0], actions: actions.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// DELETE /tables/:id — ลบห้อง (admin หรือเจ้าของห้อง)
router.delete('/:id', authMiddleware, async (req, res) => {
  try {
    const table = await pool.query('SELECT * FROM game_tables WHERE id = $1', [req.params.id]);
    if (table.rows.length === 0) return res.status(404).json({ error: 'Table not found' });
    const t = table.rows[0];
    if (t.created_by !== req.user.id && req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Not authorized' });
    }
    await pool.query('DELETE FROM table_players WHERE table_id = $1', [req.params.id]);
    await pool.query('DELETE FROM game_tables WHERE id = $1', [req.params.id]);
    res.json({ success: true, message: 'Table deleted' });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /tables/:id — อัพเดทห้อง (admin หรือเจ้าของห้อง)
router.put('/:id', authMiddleware, async (req, res) => {
  try {
    const table = await pool.query('SELECT * FROM game_tables WHERE id = $1', [req.params.id]);
    if (table.rows.length === 0) return res.status(404).json({ error: 'Table not found' });
    const t = table.rows[0];
    if (t.created_by !== req.user.id && req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Not authorized' });
    }
    const gameplayFields = ['small_blind', 'big_blind', 'ante', 'min_buy_in', 'max_buy_in',
      'max_players', 'turn_time_sec', 'auto_start_at', 'auto_start_delay_sec',
      'minimum_play_minutes', 'rake_percent', 'rake_cap', 'room_template_id'];
    const requestedGameplay = gameplayFields.filter(f => req.body[f] !== undefined);
    if (t.status === 'playing' && requestedGameplay.length > 0) {
      return res.status(409).json({ error: 'Cannot change room config while the room is playing' });
    }
    const [defaults, limits] = await Promise.all([
      getConfig(pool, 'room_defaults'),
      getConfig(pool, 'room_creation_limits'),
    ]);
    const normalized = normalizeRoomInput({ ...t, ...req.body }, defaults, limits);
    const effective = await resolveRoomConfig(pool, {
      gameTypeId: t.game_type_id,
      templateId: req.body.room_template_id || t.room_template_id,
      tableId: req.params.id,
      overrides: normalized,
    });
    const { name, small_blind, big_blind, ante, min_buy_in, max_buy_in, max_players,
            turn_time_sec, auto_start_at, auto_start_delay_sec, minimum_play_minutes,
            rake_percent, rake_cap, status, hide_from_lobby } = normalized;
    const result = await pool.query(
      `UPDATE game_tables SET
        name = COALESCE($1, name), small_blind = COALESCE($2, small_blind),
        big_blind = COALESCE($3, big_blind), ante = COALESCE($4, ante),
        min_buy_in = COALESCE($5, min_buy_in), max_buy_in = COALESCE($6, max_buy_in),
        max_players = COALESCE($7, max_players), turn_time_sec = COALESCE($8, turn_time_sec),
        auto_start_at = COALESCE($9, auto_start_at), auto_start_delay_sec = COALESCE($10, auto_start_delay_sec),
        minimum_play_minutes = COALESCE($11, minimum_play_minutes),
        rake_percent = COALESCE($12, rake_percent), rake_cap = COALESCE($13, rake_cap),
        status = COALESCE($14, status), hide_from_lobby = COALESCE($15, hide_from_lobby),
        config_snapshot = $17, config_version = $18, config_hash = $19,
        room_template_id = COALESCE($20, room_template_id)
       WHERE id = $16 RETURNING *`,
      [name, small_blind, big_blind, ante, min_buy_in, max_buy_in, max_players, turn_time_sec,
       auto_start_at, auto_start_delay_sec, minimum_play_minutes,
       rake_percent, rake_cap, status, hide_from_lobby, req.params.id,
       JSON.stringify(roomSnapshotPayload(effective)), effective.revisions.room_defaults, effective.hash,
       req.body.room_template_id || t.room_template_id]
    );
    res.json({ table: sanitizeTable(result.rows[0]) });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// DELETE /tables/game-types/:id — ลบ/ปิด game type (admin only)
router.delete('/game-types/:id', authMiddleware, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).json({ error: 'Admin only' });
    await pool.query('UPDATE game_types SET is_active = FALSE WHERE id = $1', [req.params.id]);
    res.json({ success: true, message: 'Game type deactivated' });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
