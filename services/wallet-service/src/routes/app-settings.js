const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { getConfig, normalizeGameRuntime, setConfig } = require('../config-service');
const { configHash } = require('../../../config/config-platform');

function compareSemver(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const na = Number.isFinite(pa[i]) ? pa[i] : 0;
    const nb = Number.isFinite(pb[i]) ? pb[i] : 0;
    if (na < nb) return -1;
    if (na > nb) return 1;
  }
  return 0;
}

const router = express.Router();

router.get('/app-control', async (req, res) => {
  try {
    res.json(await getConfig(pool, 'app_control'));
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/feature-flags', async (req, res) => {
  try {
    const result = await pool.query('SELECT feature_key, is_enabled, config FROM feature_flags');
    res.json({ flags: Object.fromEntries(result.rows.map((row) => [row.feature_key, { enabled: row.is_enabled, config: row.config }])) });
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/room-defaults', async (req, res) => {
  try {
    res.json(await getConfig(pool, 'room_defaults'));
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/game-runtime', async (req, res) => {
  try {
    const [runtime, notifications] = await Promise.all([
      getConfig(pool, 'game_runtime'),
      getConfig(pool, 'notification_policy'),
    ]);
    res.json({ ...normalizeGameRuntime(runtime), ...notifications });
  } catch {
    res.status(500).json({ error: 'Invalid game runtime configuration' });
  }
});

router.get('/public-config', async (req, res) => {
  try {
    const clientSchemaVersion = Number(req.query.schemaVersion || 1);
    if (clientSchemaVersion !== 1) {
      return res.status(426).json({
        error: 'Config schema is not supported by this client',
        supported_schema_version: 1,
        min_supported_schema_version: 1,
      });
    }
    const clientAppVersion = req.query.appVersion;
    const keys = ['app_control', 'game_runtime', 'notification_policy', 'app_background', 'room_defaults'];
    const rows = await pool.query('SELECT key, value, revision FROM system_config WHERE key = ANY($1)', [keys]);
    const values = Object.fromEntries(rows.rows.map(row => [row.key, row.value]));
    const revisions = Object.fromEntries(rows.rows.map(row => [row.key, Number(row.revision)]));
    const runtime = await getConfig(pool, 'game_runtime');
    const minSupportedVersion = values.app_control?.min_supported_version;
    if (clientAppVersion && minSupportedVersion && /^\d+\.\d+\.\d+/.test(clientAppVersion) && /^\d+\.\d+\.\d+/.test(minSupportedVersion)) {
      if (compareSemver(clientAppVersion, minSupportedVersion) < 0) {
        return res.status(426).json({
          error: 'App version is below the minimum supported version',
          min_supported_version: minSupportedVersion,
        });
      }
    }
    const cacheTtlSec = Number(runtime.public_config_cache_ttl_sec);
    const payload = {
      schema_version: 1,
      min_supported_schema_version: 1,
      config_revision: revisions,
      cache_ttl_sec: cacheTtlSec,
      server_time: new Date().toISOString(),
      values: {
        app_control: values.app_control || {},
        game_runtime: values.game_runtime || {},
        notification_policy: values.notification_policy || {},
        app_background: values.app_background || {},
        room_defaults: values.room_defaults || {},
      },
    };
    const etag = `W/"${configHash(payload.values)}-${payload.schema_version}"`;
    res.set('ETag', etag);
    res.set('Cache-Control', `public, max-age=${cacheTtlSec}`);
    if (req.headers['if-none-match'] === etag) return res.status(304).end();
    res.json({ ...payload, etag });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/admin/game-runtime', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    const value = normalizeGameRuntime(req.body);
    res.json({ config: await setConfig(pool, 'game_runtime', value, req.user.id) });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

router.get('/card-back-settings', async (req, res) => {
  try {
    res.json(await getConfig(pool, 'card_back_settings'));
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/admin/app-control', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    const value = {
      maintenance_enabled: Boolean(req.body.maintenance_enabled),
      maintenance_message: String(req.body.maintenance_message || ''),
      maintenance_starts_at: req.body.maintenance_starts_at || null,
      maintenance_ends_at: req.body.maintenance_ends_at || null,
      min_supported_version: String(req.body.min_supported_version || '1.0.0'),
      force_update_message: String(req.body.force_update_message || ''),
      announcement: req.body.announcement || null,
    };
    if (!/^\d+\.\d+\.\d+$/.test(value.min_supported_version)) {
      return res.status(400).json({ error: 'min_supported_version must use semantic version format' });
    }
    res.json({ config: await setConfig(pool, 'app_control', value, req.user.id) });
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Public endpoint — mobile app reads this ──

// GET /settings/app-config — ดึง config สาธารณะ (background_url, overlay_opacity)
router.get('/app-config', async (req, res) => {
  try {
    res.json(await getConfig(pool, 'app_background'));
  } catch (err) {
    console.error('app-config error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Admin endpoints — only admin can change background ──

// GET /settings/admin/background — ดูค่า background ปัจจุบัน
router.get('/admin/background', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT value FROM system_config WHERE key = 'app_background'"
    );
    if (result.rows.length === 0) {
      return res.json({ background_url: null, overlay_opacity: 0.55 });
    }
    res.json(result.rows[0].value);
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /settings/admin/background — admin เปลี่ยน background URL และ overlay opacity
router.put('/admin/background', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    const { background_url, overlay_opacity } = req.body;

    // Validate
    if (overlay_opacity !== undefined) {
      const op = parseFloat(overlay_opacity);
      if (isNaN(op) || op < 0 || op > 1) {
        return res.status(400).json({ error: 'overlay_opacity must be between 0 and 1' });
      }
    }

    const newConfig = {
      background_url: background_url || null,
      overlay_opacity: overlay_opacity !== undefined ? parseFloat(overlay_opacity) : 0.55,
    };

    const result = await setConfig(pool, 'app_background', newConfig, req.user.id);
    res.json({ success: true, config: result.value, revision: result.revision });
  } catch (err) {
    console.error('update background error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /settings/admin/background — รีเซ็ตกลับเป็น default (local asset)
router.delete('/admin/background', authMiddleware, adminOnly, requireMenu('settings'), async (req, res) => {
  try {
    const result = await setConfig(pool, 'app_background', { background_url: null, overlay_opacity: 0.55 }, req.user.id);
    res.json({ success: true, message: 'Background reset to default', revision: result.revision });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
