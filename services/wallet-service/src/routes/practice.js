const express = require('express');
const crypto = require('crypto');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { getConfig, normalizeRoomInput } = require('../config-service');
const { resolveRoomConfig, roomSnapshotPayload } = require('../../../../config/config-platform');

const router = express.Router();

// POST /practice/create — สร้างห้องทดลองเล่น (ไม่หักเงินจริง)
router.post('/create', authMiddleware, async (req, res) => {
  try {
    const [policy, defaults, limits, runtime] = await Promise.all([
      getConfig(pool, 'practice_policy'),
      getConfig(pool, 'room_defaults'),
      getConfig(pool, 'room_creation_limits'),
      getConfig(pool, 'game_runtime'),
    ]);
    if (!policy.enabled || !limits.allowed_modes.includes('practice')) {
      return res.status(403).json({ error: 'Practice mode is disabled' });
    }

    const slug = req.body.game_type_slug || policy.default_game_type;
    if (!limits.allowed_game_type_slugs.includes(slug)) {
      return res.status(400).json({ error: 'Game type is not allowed for practice' });
    }
    const gtResult = await pool.query(
      'SELECT id FROM game_types WHERE slug = $1 AND is_active = TRUE', [slug]
    );
    if (gtResult.rows.length === 0) return res.status(400).json({ error: 'Invalid game type' });
    const gameTypeId = gtResult.rows[0].id;
    const isOFC = slug === 'chinese_poker';

    await pool.query(
      `UPDATE game_tables SET status = 'closed' WHERE created_by = $1 AND is_practice = TRUE AND status != 'closed'`,
      [req.user.id]
    );

    const roomCode = 'P' + crypto.randomBytes(3).toString('hex').toUpperCase();
    const roomInput = normalizeRoomInput({
      ...defaults,
      mode: 'practice',
      is_private: true,
      small_blind: req.body.small_blind ?? (isOFC ? policy.chinese_small_blind : defaults.small_blind),
      big_blind: req.body.big_blind ?? (isOFC ? policy.chinese_big_blind : defaults.big_blind),
      ante: isOFC ? req.body.ante ?? defaults.ante : defaults.ante,
      min_buy_in: req.body.min_buy_in ?? (isOFC ? policy.chinese_min_buy_in : defaults.min_buy_in),
      max_buy_in: req.body.max_buy_in ?? (isOFC ? policy.chinese_max_buy_in : defaults.max_buy_in),
      max_players: isOFC ? policy.chinese_max_players : policy.texas_max_players,
      turn_time_sec: isOFC ? policy.chinese_turn_time_sec : policy.texas_turn_time_sec,
      auto_start_delay_sec: policy.auto_start_delay_sec,
      minimum_play_minutes: runtime.practice_minimum_play_minutes,
    }, defaults, limits);
    const effective = await resolveRoomConfig(pool, { gameTypeId, overrides: roomInput });
    const name = isOFC ? 'ทดลองเล่น ไพ่สามกอง' : `ทดลองเล่น NLH ${roomInput.small_blind}/${roomInput.big_blind}`;

    const result = await pool.query(
      `INSERT INTO game_tables
        (game_type_id, name, mode, max_players, small_blind, big_blind, ante,
         min_buy_in, max_buy_in, turn_time_sec, auto_start_at, auto_start_delay_sec,
         minimum_play_minutes, room_code, is_private, hide_from_lobby, is_practice,
         config_snapshot, config_version, config_hash, status, created_by)
       VALUES ($1,$2,'practice',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,TRUE,TRUE,TRUE,$14,$15,$16,'waiting',$17)
       RETURNING *`,
      [
        gameTypeId, name, roomInput.max_players, roomInput.small_blind, roomInput.big_blind,
        roomInput.ante, roomInput.min_buy_in, roomInput.max_buy_in, roomInput.turn_time_sec,
        roomInput.auto_start_at, roomInput.auto_start_delay_sec, roomInput.minimum_play_minutes,
        roomCode, JSON.stringify(roomSnapshotPayload(effective)), effective.revisions.room_defaults,
        effective.hash, req.user.id,
      ]
    );

    const table = result.rows[0];
    table.practice_chips = policy.practice_chips;
    res.status(201).json({ table, effective_config: effective });
  } catch (err) {
    console.error('Create practice table error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /practice/status — ดูว่ามีห้องทดลองเล่นที่ยังเปิดอยู่ไหม
router.get('/status', authMiddleware, async (req, res) => {
  try {
    const [result, policy] = await Promise.all([
      pool.query(
        `SELECT * FROM game_tables
         WHERE created_by = $1 AND is_practice = TRUE AND status != 'closed'
         ORDER BY created_at DESC LIMIT 1`,
        [req.user.id]
      ),
      getConfig(pool, 'practice_policy'),
    ]);
    if (result.rows.length > 0) {
      result.rows[0].practice_chips = policy.practice_chips;
      res.json({ table: result.rows[0], exists: true });
    } else {
      res.json({ table: null, exists: false });
    }
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
