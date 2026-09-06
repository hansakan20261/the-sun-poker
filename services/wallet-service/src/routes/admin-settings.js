const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { getConfig, setConfig, validateRoomAgainstLimits } = require('../config-service');
const { notifyConfigChanged } = require('../../../../config/config-events');

const router = express.Router();

// GET /admin/settings — ดูตั้งค่าทั้งหมด
router.get('/', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    const configs = await pool.query('SELECT * FROM system_config ORDER BY key');
    const features = await pool.query('SELECT * FROM feature_flags ORDER BY feature_key');
    res.json({ configs: configs.rows, features: features.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/settings/config/:key — อัปเดตค่า config
router.put('/config/:key', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    const { value, expected_revision, reason } = req.body;
    const result = await setConfig(pool, req.params.key, value, req.user.id, { expectedRevision: expected_revision, reason });
    res.json({ success: true, ...result });
  } catch (err) { res.status(err.status || 400).json({ error: err.message, currentRevision: err.currentRevision }); }
});

// PUT /admin/settings/features/:key/toggle — เปิด/ปิด feature flag
router.put('/features/:key/toggle', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    await pool.query(
      'UPDATE feature_flags SET is_enabled = NOT is_enabled, updated_by = $1, updated_at = NOW() WHERE feature_key = $2',
      [req.user.id, req.params.key]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/settings/rake — อัปเดตค่าคอมมิสชั่น (rake) ทั้งระบบ
// Body: { rake_percent: number, rake_cap: number, apply_to_existing: boolean }
router.put('/rake', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    const { rake_percent, rake_cap, apply_to_existing } = req.body;
    const [current, limits] = await Promise.all([
      getConfig(pool, 'rake_settings'),
      getConfig(pool, 'room_creation_limits'),
    ]);
    const next = {
      default_rake_percent: Number(rake_percent),
      default_rake_cap: Number(rake_cap ?? current.default_rake_cap),
    };
    if (!Number.isFinite(next.default_rake_percent) || !Number.isInteger(next.default_rake_cap)) {
      return res.status(400).json({ error: 'Invalid rake settings' });
    }
    validateRoomAgainstLimits(
      { ...await getConfig(pool, 'room_defaults'), rake_percent: next.default_rake_percent, rake_cap: next.default_rake_cap },
      limits,
    );
    await setConfig(pool, 'rake_settings', next, req.user.id, { reason: 'Update global rake settings' });

    let updatedTables = 0;
    if (apply_to_existing) {
      const result = await pool.query(
        `INSERT INTO runtime_overrides (table_id, key, value, apply_mode, created_by)
         SELECT id, 'room_defaults', jsonb_build_object('rake_percent', $1, 'rake_cap', $2), 'immediate', $3
         FROM game_tables WHERE status != 'closed'`,
        [next.default_rake_percent, next.default_rake_cap, req.user.id],
      );
      updatedTables = result.rowCount;
      await notifyConfigChanged(pool, {
        keys: ['room_defaults'],
        applyMode: 'immediate',
        actorId: req.user.id,
        reason: 'Apply rake settings to existing rooms',
      });
    }

    res.json({ success: true, updatedTables, rake_percent: next.default_rake_percent, rake_cap: next.default_rake_cap });
  } catch (err) {
    console.error('Update rake error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /admin/settings/rake — ดูค่าคอมมิสชั่นปัจจุบัน
router.get('/rake', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    res.json(await getConfig(pool, 'rake_settings'));
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
