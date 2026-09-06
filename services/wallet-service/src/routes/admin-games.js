const express = require('express');
const crypto = require('crypto');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { hashRoomPassword, sanitizeTable } = require('../room-security');
const { getConfig, normalizeRoomInput, resolveRoomConfig, roomSnapshotPayload } = require('../config-service');
const { executeCleanup, loadCleanupSettings, saveCleanupSettings } = require('../cleanup-service');
const { notifyConfigChanged } = require('../../../../config/config-events');

const router = express.Router();

// ============ GAME TYPES ============

// GET /admin/games/types — ดูประเภทเกมทั้งหมด
router.get('/types', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM game_types ORDER BY sort_order');
    res.json({ game_types: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /admin/games/types — เพิ่มเกมใหม่
router.post('/types', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const { slug, name, name_th, min_players, max_players, description } = req.body;
    const limits = await getConfig(pool, 'room_creation_limits');
    const minPlayers = min_players ?? limits.min_players;
    const maxPlayers = max_players ?? limits.max_players;
    if (minPlayers < limits.min_players || maxPlayers > limits.max_players || minPlayers > maxPlayers) {
      return res.status(400).json({ error: 'Player count is outside configured bounds' });
    }
    const maxSort = await pool.query('SELECT COALESCE(MAX(sort_order),0)+1 as next FROM game_types');
    const result = await pool.query(
      `INSERT INTO game_types (slug, name, name_th, min_players, max_players, description, sort_order, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
      [slug, name, name_th, minPlayers, maxPlayers, description, maxSort.rows[0].next, req.user.id]
    );
    res.status(201).json({ game_type: result.rows[0] });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Slug already exists' });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /admin/games/types/:id — แก้ไขเกม
router.put('/types/:id', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const { name, name_th, min_players, max_players, is_active, sort_order } = req.body;
    await pool.query(
      `UPDATE game_types SET name=COALESCE($1,name), name_th=COALESCE($2,name_th),
       min_players=COALESCE($3,min_players), max_players=COALESCE($4,max_players),
       is_active=COALESCE($5,is_active), sort_order=COALESCE($6,sort_order), updated_at=NOW()
       WHERE id=$7`,
      [name, name_th, min_players, max_players, is_active, sort_order, req.params.id]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/games/types/:id/toggle — เปิด/ปิดเกม
router.put('/types/:id/toggle', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    await pool.query('UPDATE game_types SET is_active = NOT is_active, updated_at = NOW() WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// DELETE /admin/games/types/:id — ลบเกม
router.delete('/types/:id', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const tables = await pool.query('SELECT COUNT(*) as c FROM game_tables WHERE game_type_id = $1 AND status != $2', [req.params.id, 'closed']);
    if (Number(tables.rows[0].c) > 0) return res.status(400).json({ error: 'Cannot delete: has active tables' });
    await pool.query('DELETE FROM game_types WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// ============ GAME TABLES (ห้องเล่น) ============

// GET /admin/games/tables — ดูห้องเล่นทั้งหมด (+ filter ห้องว่าง/กำลังเล่น)
router.get('/tables', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const { status, game_type_id, occupancy, created_by_type, limit = 20, offset = 0 } = req.query;
    let query = `SELECT gt.*, gty.name as game_type_name, gty.name_th as game_type_name_th,
                   u.username as created_by_name, u.role as created_by_role,
                   (SELECT COUNT(*) FROM table_players tp WHERE tp.table_id = gt.id AND tp.is_active) as player_count
                 FROM game_tables gt
                 JOIN game_types gty ON gty.id = gt.game_type_id
                 LEFT JOIN users u ON u.id = gt.created_by WHERE 1=1`;
    const params = [];

    if (status) { params.push(status); query += ` AND gt.status = $${params.length}`; }
    if (game_type_id) { params.push(game_type_id); query += ` AND gt.game_type_id = $${params.length}`; }

    // Filter: occupancy = 'playing' (มีคนเล่นอยู่) | 'empty' (ห้องว่าง)
    if (occupancy === 'playing') {
      query += ` AND (SELECT COUNT(*) FROM table_players tp WHERE tp.table_id = gt.id AND tp.is_active) > 0`;
    } else if (occupancy === 'empty') {
      query += ` AND (SELECT COUNT(*) FROM table_players tp WHERE tp.table_id = gt.id AND tp.is_active) = 0`;
    }

    // Filter: created_by_type = 'player' (ผู้เล่นสร้าง) | 'admin' (admin สร้าง)
    if (created_by_type === 'player') {
      query += ` AND u.role = 'player'`;
    } else if (created_by_type === 'admin') {
      query += ` AND (u.role = 'admin' OR u.role = 'super_admin')`;
    }

    params.push(Number(limit));
    query += ` ORDER BY gt.created_at DESC LIMIT $${params.length}`;
    params.push(Number(offset));
    query += ` OFFSET $${params.length}`;

    const result = await pool.query(query, params);

    // Count with same filters (for pagination)
    let countQuery = `SELECT COUNT(*) as total FROM game_tables gt
                      JOIN game_types gty ON gty.id = gt.game_type_id
                      LEFT JOIN users u ON u.id = gt.created_by WHERE 1=1`;
    const countParams = [];
    if (status) { countParams.push(status); countQuery += ` AND gt.status = $${countParams.length}`; }
    if (game_type_id) { countParams.push(game_type_id); countQuery += ` AND gt.game_type_id = $${countParams.length}`; }
    if (occupancy === 'playing') countQuery += ` AND (SELECT COUNT(*) FROM table_players tp WHERE tp.table_id = gt.id AND tp.is_active) > 0`;
    if (occupancy === 'empty') countQuery += ` AND (SELECT COUNT(*) FROM table_players tp WHERE tp.table_id = gt.id AND tp.is_active) = 0`;
    if (created_by_type === 'player') countQuery += ` AND u.role = 'player'`;
    if (created_by_type === 'admin') countQuery += ` AND (u.role = 'admin' OR u.role = 'super_admin')`;

    const countResult = await pool.query(countQuery, countParams);
    res.json({ tables: result.rows.map(sanitizeTable), total: Number(countResult.rows[0].total) });
  } catch (err) {
    console.error('List tables error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/room-config', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const [defaults, limits] = await Promise.all([
      getConfig(pool, 'room_defaults'),
      getConfig(pool, 'room_creation_limits'),
    ]);
    res.json({ defaults, limits });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /admin/games/tables — Admin สร้างห้องเล่น
router.post('/tables', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const [defaults, limits, securityPolicy] = await Promise.all([
      getConfig(pool, 'room_defaults'),
      getConfig(pool, 'room_creation_limits'),
      getConfig(pool, 'security_policy'),
    ]);
    if (!req.body.game_type_id) return res.status(400).json({ error: 'game_type_id is required' });
    const gameType = await pool.query('SELECT slug, is_active FROM game_types WHERE id = $1', [req.body.game_type_id]);
    if (!gameType.rows[0]?.is_active) return res.status(400).json({ error: 'Game type is not available' });
    if (!limits.allowed_game_type_slugs.includes(gameType.rows[0].slug)) {
      return res.status(400).json({ error: 'Game type is not allowed for room creation' });
    }
    const mode = req.body.mode ?? limits.allowed_modes[0];
    if (!mode || !limits.allowed_modes.includes(mode)) return res.status(400).json({ error: 'Room mode is not allowed' });
    const effective = await resolveRoomConfig(pool, {
      gameTypeId: req.body.game_type_id,
      templateId: req.body.room_template_id,
      overrides: req.body,
    });
    const roomInput = normalizeRoomInput({ ...effective.value, ...req.body, mode }, defaults, limits);
    const { name, is_private, password, is_featured, game_type_id, room_template_id } = req.body;
    const { max_players, small_blind, big_blind,
            min_buy_in, max_buy_in, ante, turn_time_sec, auto_start_at,
            auto_start_delay_sec, minimum_play_minutes, rake_percent, rake_cap } = roomInput;

    const roomCode = crypto.randomBytes(3).toString('hex').toUpperCase();
    const passwordHash = await hashRoomPassword(password, securityPolicy.password_hash_rounds);
    const result = await pool.query(
      `INSERT INTO game_tables (game_type_id, name, mode, max_players, small_blind, big_blind,
       min_buy_in, max_buy_in, ante, turn_time_sec, auto_start_at, auto_start_delay_sec,
       minimum_play_minutes, is_private, password, room_code, rake_percent, rake_cap, is_featured,
       room_template_id, config_snapshot, config_version, config_hash, status, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,'waiting',$24) RETURNING *`,
      [game_type_id, name, mode, max_players, small_blind, big_blind,
       min_buy_in, max_buy_in, ante, turn_time_sec, auto_start_at, auto_start_delay_sec,
       minimum_play_minutes, Boolean(is_private || password), passwordHash, roomCode,
       rake_percent ?? null, rake_cap ?? null, is_featured||false, room_template_id || null,
       JSON.stringify(roomSnapshotPayload(effective)),
       effective.revisions.room_defaults, effective.hash, req.user.id]
    );
    res.status(201).json({ table: sanitizeTable(result.rows[0]), effective_config: effective });
  } catch (err) {
    console.error('Create table error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /admin/games/tables/:id — แก้ไขห้องพร้อมอัปเดต config snapshot
router.put('/tables/:id', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  const client = await pool.connect();
  try {
    const applyMode = req.body.apply_mode || 'next_hand';
    if (!['immediate', 'next_hand', 'new_room'].includes(applyMode)) {
      return res.status(400).json({ error: 'Invalid apply mode' });
    }
    await client.query('BEGIN');
    const current = await client.query('SELECT * FROM game_tables WHERE id = $1 FOR UPDATE', [req.params.id]);
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Table not found' });
    }
    const table = current.rows[0];
    if (table.status === 'playing' && (applyMode === 'immediate' || applyMode === 'next_turn')) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Cannot apply immediate or next-turn config changes while the room is playing' });
    }
    const roomFields = [
      'max_players', 'small_blind', 'big_blind', 'ante', 'min_buy_in', 'max_buy_in',
      'turn_time_sec', 'auto_start_at', 'auto_start_delay_sec', 'minimum_play_minutes',
      'rake_percent', 'rake_cap',
    ];
    const overrides = Object.fromEntries(roomFields
      .filter(field => req.body[field] !== undefined && req.body[field] !== null)
      .map(field => [field, req.body[field]]));

    if (applyMode === 'new_room') {
      for (const field of Object.keys(overrides)) {
        await client.query(
          `INSERT INTO runtime_overrides
           (game_type_id, key, value, apply_mode, effective_at, status, created_by, approved_by)
           VALUES ($1, $2, $3, 'new_room', NOW(), 'active', $4, $4)`,
          [table.game_type_id, field, JSON.stringify({ [field]: overrides[field] }), req.user.id],
        );
      }
      await notifyConfigChanged(client, {
        keys: ['room_defaults'],
        applyMode: 'new_room',
        actorId: req.user.id,
        correlationId: req.body?.correlation_id,
      });
      await client.query('COMMIT');
      return res.json({ success: true, applied: 'new_room', overrides_created: Object.keys(overrides).length });
    }

    const effective = await resolveRoomConfig(client, {
      gameTypeId: req.body.game_type_id || table.game_type_id,
      templateId: req.body.room_template_id === undefined ? table.room_template_id : req.body.room_template_id,
      tableId: req.params.id,
      overrides,
    });
    const roomInput = normalizeRoomInput({ ...effective.value, ...req.body, mode: req.body.mode ?? table.mode },
      await getConfig(client, 'room_defaults'), await getConfig(client, 'room_creation_limits'));
    const securityPolicy = await getConfig(client, 'security_policy');
    const passwordHash = req.body.password !== undefined
      ? await hashRoomPassword(req.body.password, securityPolicy.password_hash_rounds)
      : table.password;
    const result = await client.query(
      `UPDATE game_tables
       SET game_type_id = $2, name = $3, mode = $4, max_players = $5,
           small_blind = $6, big_blind = $7, ante = $8,
           min_buy_in = $9, max_buy_in = $10, turn_time_sec = $11,
           auto_start_at = $12, auto_start_delay_sec = $13,
           minimum_play_minutes = $14, rake_percent = $15, rake_cap = $16,
           is_private = $17, password = $18, is_featured = $19,
           room_template_id = $20, config_snapshot = $21,
           config_version = $22, config_hash = $23
       WHERE id = $1 RETURNING *`,
      [
        req.params.id,
        req.body.game_type_id || table.game_type_id,
        req.body.name ?? table.name,
        req.body.mode ?? table.mode,
        roomInput.max_players, roomInput.small_blind, roomInput.big_blind, roomInput.ante,
        roomInput.min_buy_in, roomInput.max_buy_in, roomInput.turn_time_sec,
        roomInput.auto_start_at, roomInput.auto_start_delay_sec, roomInput.minimum_play_minutes,
        roomInput.rake_percent, roomInput.rake_cap,
        req.body.is_private === undefined ? table.is_private : Boolean(req.body.is_private || req.body.password),
        passwordHash,
        req.body.is_featured === undefined ? table.is_featured : Boolean(req.body.is_featured),
        req.body.room_template_id === undefined ? table.room_template_id : req.body.room_template_id,
        JSON.stringify(roomSnapshotPayload(effective)),
        effective.revisions.room_defaults,
        effective.hash,
      ],
    );
    await client.query(
      `INSERT INTO config_history
       (revision, key, scope, scope_id, before_value, after_value, apply_mode, change_reason, correlation_id, updated_by)
       VALUES ($1, 'room_defaults', 'room', $2, $3, $4, $5, $6, $7, $8)`,
      [
        effective.revisions.room_defaults,
        req.params.id,
        JSON.stringify(table.config_snapshot || null),
        JSON.stringify(roomSnapshotPayload(effective)),
        applyMode,
        req.body?.reason || null,
        req.body?.correlation_id || null,
        req.user.id,
      ],
    );
    await notifyConfigChanged(client, {
      keys: ['room_defaults'],
      applyMode,
      actorId: req.user.id,
      correlationId: req.body?.correlation_id,
    });
    await client.query('COMMIT');
    res.json({ success: true, table: sanitizeTable(result.rows[0]), effective_config: effective });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    res.status(400).json({ error: err.message });
  } finally {
    client.release();
  }
});

// PUT /admin/games/tables/:id/status — เปลี่ยนสถานะห้อง
router.put('/tables/:id/status', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const { status } = req.body; // waiting, playing, closed
    await pool.query('UPDATE game_tables SET status = $1 WHERE id = $2', [status, req.params.id]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// DELETE /admin/games/tables/:id — ลบห้อง
router.delete('/tables/:id', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    await pool.query('DELETE FROM game_tables WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// ============ AUTO-CLEANUP: ลบห้องที่ผู้เล่นสร้าง ============

// GET /admin/games/cleanup-settings — ดูการตั้งค่า auto-cleanup
router.get('/cleanup-settings', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    res.json(await loadCleanupSettings(pool));
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /admin/games/cleanup-settings — ตั้งค่า auto-cleanup
router.put('/cleanup-settings', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    res.json({ success: true, ...(await saveCleanupSettings(pool, req.body, req.user.id)) });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

router.post('/cleanup-preview', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const settings = await loadCleanupSettings(pool);
    res.json(await executeCleanup(pool, settings, { actorId: req.user.id, source: 'manual_preview', dryRun: true }));
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// POST /admin/games/cleanup-now — ลบห้องที่ผู้เล่นสร้างทันที (ห้องว่างที่หมดเวลา)
router.post('/cleanup-now', authMiddleware, adminOnly, requireMenu('games'), async (req, res) => {
  try {
    const settings = await loadCleanupSettings(pool);
    res.json({ success: true, ...(await executeCleanup(pool, settings, { actorId: req.user.id, source: 'manual' })) });
  } catch (err) {
    console.error('Cleanup error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
