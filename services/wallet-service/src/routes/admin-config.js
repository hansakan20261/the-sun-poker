const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly, superAdminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { getConfig, resolveRoomConfig, roomSnapshotPayload, setConfig, validateConfig } = require('../config-service');
const { APPLY_MODES, CONFIG_DEFINITIONS } = require('../../../../config/config-definitions');
const { notifyConfigChanged, ConfigRevisionTracker } = require('../../../../config/config-events');
const { syncConfigDefinitions } = require('../../../../config/config-platform');

const router = express.Router();
const PUBLIC_SCOPE_KEYS = new Set(Object.keys(CONFIG_DEFINITIONS));
const writeRateLimit = new Map();
const adminTracker = new ConfigRevisionTracker('wallet-service-admin', Object.keys(CONFIG_DEFINITIONS));
const PROTECTED_CATEGORIES = new Set(['wallet_economy_policy', 'security_policy', 'coin_settings']);

function canWriteConfig(user, key) {
  const category = CONFIG_DEFINITIONS[key];
  if (!category) return false;
  if (['security_invariant', 'protocol_invariant'].includes(category.classification)) return false;
  if (PROTECTED_CATEGORIES.has(key)) return user.role === 'super_admin';
  return ['admin', 'super_admin'].includes(user.role);
}
const HIERARCHY_POLICIES = Object.freeze({
  texas_holdem: 'texas_holdem_policy',
  chinese_poker: 'chinese_poker_policy',
  tournament: 'tournament_policy',
});

function pickScopedFields(configKey, source, scope) {
  const category = CONFIG_DEFINITIONS[configKey];
  return Object.fromEntries(Object.entries(category.fields)
    .filter(([fieldName, field]) => field.scopes?.includes(scope) && source?.[fieldName] !== undefined)
    .map(([fieldName]) => [fieldName, source[fieldName]]));
}

function normalizeHierarchicalConfig(input, scope) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    const error = new Error('config must be an object');
    error.status = 400;
    throw error;
  }
  const roomInput = input.room_defaults && typeof input.room_defaults === 'object'
    ? input.room_defaults
    : pickScopedFields('room_defaults', input, scope);
  const normalized = {
    room_defaults: validateConfig('room_defaults', roomInput, { partial: true }),
    policies: {},
  };
  for (const [policyKey, configKey] of Object.entries(HIERARCHY_POLICIES)) {
    const nested = input.policies?.[policyKey] || input.policies?.[configKey] || input[configKey] || {};
    const flat = pickScopedFields(configKey, input, scope);
    normalized.policies[policyKey] = validateConfig(configKey, { ...flat, ...nested }, { partial: true });
  }
  return normalized;
}

async function requireConfigWrite(req, res, next) {
  try {
    const policy = await getConfig(pool, 'security_policy');
    const authenticatedAt = Number(req.user.iat || 0) * 1000;
    if (!authenticatedAt || Date.now() - authenticatedAt > policy.admin_reauth_minutes * 60_000) {
      return res.status(401).json({ error: 'Recent admin authentication required' });
    }
    const now = Date.now();
    const windowStart = now - policy.admin_config_write_window_sec * 1000;
    const entries = (writeRateLimit.get(req.user.id) || []).filter(time => time > windowStart);
    if (entries.length >= policy.admin_config_write_max_requests) {
      return res.status(429).json({ error: 'Too many config write requests' });
    }
    entries.push(now);
    writeRateLimit.set(req.user.id, entries);
    next();
  } catch (err) {
    res.status(503).json({ error: 'Security policy unavailable' });
  }
}

async function auditConfig(req, action, details) {
  await pool.query(
    `INSERT INTO admin_activity_log (admin_id, action, target_type, details, ip_address)
     VALUES ($1, $2, 'config', $3, $4)`,
    [req.user.id, action, JSON.stringify(details), req.ip || null],
  ).catch(() => {});
}

router.use(authMiddleware, adminOnly, requireMenu('settings'));

router.get('/definitions', (req, res) => {
  const definitions = Object.values(CONFIG_DEFINITIONS).map(category => ({
    key: category.key,
    owner: category.owner,
    classification: category.classification,
    applyMode: category.applyMode,
    fields: Object.fromEntries(Object.entries(category.fields)
      .filter(([, field]) => !field.sensitive)
      .map(([name, field]) => [name, field])),
  }));
  res.json({ definitions });
});

router.post('/definitions/sync', superAdminOnly, requireConfigWrite, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const count = await syncConfigDefinitions(client);
    await client.query('COMMIT');
    await auditConfig(req, 'config_definitions_sync', { fields: count });
    res.json({ success: true, fields: count });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

router.get('/values', async (req, res) => {
  try {
    const scope = req.query.scope || 'system';
    const scopeId = req.query.scope_id;
    if (scope === 'system') {
      const result = await pool.query(
        'SELECT key, value, revision, status, updated_by, updated_at, change_reason FROM system_config WHERE key = ANY($1::varchar[]) ORDER BY key',
        [Object.keys(CONFIG_DEFINITIONS)],
      );
      return res.json({ values: result.rows.filter(row => PUBLIC_SCOPE_KEYS.has(row.key)) });
    }
    if (scope === 'game_type') {
      if (!scopeId) return res.status(400).json({ error: 'scope_id (game_type_id) is required' });
      const result = await pool.query(
        'SELECT game_type_id AS scope_id, config AS value, revision, status, updated_by, updated_at FROM game_type_configs WHERE game_type_id = $1',
        [scopeId],
      );
      return res.json({ values: result.rows });
    }
    if (scope === 'template') {
      if (!scopeId) return res.status(400).json({ error: 'scope_id (template_id) is required' });
      const result = await pool.query(
        'SELECT id AS scope_id, config AS value, revision, status, created_by AS updated_by, created_at AS updated_at FROM room_templates WHERE id = $1',
        [scopeId],
      );
      return res.json({ values: result.rows });
    }
    if (scope === 'room') {
      if (!scopeId) return res.status(400).json({ error: 'scope_id (table_id) is required' });
      const result = await pool.query(
        'SELECT id AS scope_id, config_snapshot AS value, config_version AS revision, status, created_by AS updated_by, created_at AS updated_at FROM game_tables WHERE id = $1',
        [scopeId],
      );
      return res.json({ values: result.rows });
    }
    res.status(400).json({ error: 'Unsupported scope' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/propagation', async (req, res) => {
  try {
    const status = await adminTracker.reconcile(pool);
    res.json({ propagation: status });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load propagation status' });
  }
});

router.get('/effective', async (req, res) => {
  try {
    const { gameTypeId, templateId, tableId } = req.query;
    const effective = await resolveRoomConfig(pool, { gameTypeId, templateId, tableId });
    res.json(effective);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

router.post('/validate', async (req, res) => {
  try {
    const { key, value, gameTypeId, tableId } = req.body || {};
    if (!key) return res.status(400).json({ error: 'key is required' });
    const normalized = validateConfig(key, value);
    if (key === 'room_defaults') {
      const effective = await resolveRoomConfig(pool, { gameTypeId, tableId, overrides: normalized });
      return res.json({ valid: true, normalized, effective });
    }
    res.json({ valid: true, normalized });
  } catch (err) {
    res.status(400).json({ valid: false, error: err.message });
  }
});

const SENSITIVE_CONFIG_KEYS = ['wallet_economy_policy', 'security_policy', 'coin_settings'];

router.put('/values/:key', requireConfigWrite, async (req, res) => {
  try {
    const key = req.params.key;
    if (!PUBLIC_SCOPE_KEYS.has(key)) return res.status(404).json({ error: 'Config not found' });
    if (!canWriteConfig(req.user, key)) {
      return res.status(403).json({ error: 'Not authorized to modify this config category' });
    }
    const { value, expected_revision, reason, correlation_id } = req.body || {};
    const result = await setConfig(pool, key, value, req.user.id, {
      expectedRevision: expected_revision,
      reason,
      correlationId: correlation_id,
    });
    await auditConfig(req, 'config_update', { key, revision: result.revision, reason });
    res.json({ success: true, ...result });
  } catch (err) {
    res.status(err.status || 400).json({ error: err.message, currentRevision: err.currentRevision });
  }
});

router.post('/publish', superAdminOnly, requireConfigWrite, async (req, res) => {
  const client = await pool.connect();
  try {
    const { values, expected_revisions = {}, reason, correlation_id } = req.body || {};
    if (!values || typeof values !== 'object' || Array.isArray(values)) {
      return res.status(400).json({ error: 'values must be an object' });
    }
    const keys = Object.keys(values);
    if (keys.length === 0) return res.status(400).json({ error: 'No config values provided' });
    for (const key of keys) {
      if (!canWriteConfig(req.user, key)) {
        return res.status(403).json({ error: `Not authorized to publish: ${key}` });
      }
    }
    const normalized = Object.fromEntries(keys.map(key => [key, validateConfig(key, values[key])]));
    await client.query('BEGIN');
    const current = await client.query(
      'SELECT key, revision, value FROM system_config WHERE key = ANY($1::varchar[]) FOR UPDATE',
      [keys],
    );
    const byKey = Object.fromEntries(current.rows.map(row => [row.key, row]));
    for (const key of keys) {
      const expected = expected_revisions[key];
      if (expected !== undefined && Number(byKey[key]?.revision || 0) !== Number(expected)) {
        const error = new Error(`${key} revision conflict`);
        error.status = 409;
        error.currentRevision = Number(byKey[key]?.revision || 0);
        throw error;
      }
    }
    const results = {};
    for (const key of keys) {
      const nextRevision = Number(byKey[key]?.revision || 0) + 1;
      const updated = await client.query(
        `INSERT INTO system_config (key, value, revision, status, updated_by, updated_at, published_at, published_by, change_reason)
         VALUES ($1, $2, 1, 'published', $3, NOW(), NOW(), $3, $4)
         ON CONFLICT (key) DO UPDATE
         SET value = $2, revision = system_config.revision + 1, status = 'published',
             updated_by = $3, updated_at = NOW(), published_at = NOW(), published_by = $3, change_reason = $4
         RETURNING value, revision`,
        [key, JSON.stringify(normalized[key]), req.user.id, reason || null],
      );
      await client.query(
        `INSERT INTO config_history
         (revision, key, scope, before_value, after_value, apply_mode, change_reason, correlation_id, updated_by)
         VALUES ($1, $2, 'system', $3, $4, $5, $6, $7, $8)`,
        [nextRevision, key, JSON.stringify(byKey[key]?.value ?? null), JSON.stringify(normalized[key]),
         CONFIG_DEFINITIONS[key].applyMode, reason || null, correlation_id || null, req.user.id],
      );
      results[key] = updated.rows[0];
    }
    await notifyConfigChanged(client, {
      keys,
      revisions: Object.fromEntries(Object.entries(results).map(([key, row]) => [key, row.revision])),
      applyModes: Object.fromEntries(keys.map(key => [key, CONFIG_DEFINITIONS[key].applyMode])),
      actorId: req.user.id,
      correlationId: correlation_id,
    });
    await client.query('COMMIT');
    await auditConfig(req, 'config_publish', { keys, reason });
    res.json({ success: true, values: results });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    res.status(err.status || 400).json({ error: err.message, currentRevision: err.currentRevision });
  } finally {
    client.release();
  }
});

router.get('/overrides', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT ro.*, u.username AS created_by_name, a.username AS approved_by_name
       FROM runtime_overrides ro
       LEFT JOIN users u ON u.id = ro.created_by
       LEFT JOIN users a ON a.id = ro.approved_by
       ORDER BY ro.created_at DESC LIMIT 500`,
    );
    res.json({ overrides: result.rows });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/overrides', adminOnly, requireConfigWrite, async (req, res) => {
  try {
    const { table_id, game_type_id, category = 'room_defaults', key, value, apply_mode = 'immediate', effective_at, expires_at, reason } = req.body || {};
    if ((!table_id && !game_type_id) || (table_id && game_type_id) || !category || !key || value === undefined) {
      return res.status(400).json({ error: 'Exactly one of table_id or game_type_id, plus category, key and value are required' });
    }
    if (!CONFIG_DEFINITIONS[category]) {
      return res.status(400).json({ error: 'Unknown config category' });
    }
    if (!canWriteConfig(req.user, category)) {
      return res.status(403).json({ error: 'Not authorized to override this category' });
    }
    if (!CONFIG_DEFINITIONS[category].fields[key]) {
      return res.status(400).json({ error: 'Override key must be a valid field in the selected category' });
    }
    if (!APPLY_MODES.includes(apply_mode)) {
      return res.status(400).json({ error: 'Invalid apply mode' });
    }
    if (table_id) {
      const room = await pool.query('SELECT id, status FROM game_tables WHERE id = $1', [table_id]);
      if (room.rows.length === 0) return res.status(404).json({ error: 'Room not found' });
      if (room.rows[0].status === 'playing' && (apply_mode === 'immediate' || apply_mode === 'next_turn')) {
        return res.status(409).json({ error: 'Cannot apply immediate or next-turn override to a room that is playing' });
      }
    }
    if (game_type_id) {
      const gameType = await pool.query('SELECT id FROM game_types WHERE id = $1 AND is_active = TRUE', [game_type_id]);
      if (gameType.rows.length === 0) return res.status(404).json({ error: 'Game type not found' });
    }
    if (effective_at && expires_at && Date.parse(expires_at) <= Date.parse(effective_at)) {
      return res.status(400).json({ error: 'expires_at must be after effective_at' });
    }
    validateConfig(category, { [key]: value }, { partial: true });
    const result = await pool.query(
      `INSERT INTO runtime_overrides
       (table_id, game_type_id, key, value, apply_mode, effective_at, expires_at, status, created_by, approved_by)
       VALUES ($1,$2,$3,$4,$5,COALESCE($6, NOW()),$7,'active',$8,$8) RETURNING *`,
      [
        table_id || null,
        game_type_id || null,
        key,
        JSON.stringify({ [key]: value }),
        apply_mode,
        effective_at || null,
        expires_at || null,
        req.user.id,
      ],
    );
    await notifyConfigChanged(pool, {
      keys: [category],
      actorId: req.user.id,
      correlationId: req.body?.correlation_id,
      applyMode: apply_mode,
    });
    await auditConfig(req, 'runtime_override_create', { id: result.rows[0].id, category, key, apply_mode, reason });
    res.status(201).json({ override: result.rows[0] });
  } catch (err) {
    res.status(err.status || 400).json({ error: err.message });
  }
});

router.delete('/overrides/:id', superAdminOnly, requireConfigWrite, async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE runtime_overrides SET status = 'cancelled', approved_by = $2 WHERE id = $1 AND status = 'active' RETURNING *`,
      [req.params.id, req.user.id],
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Active runtime override not found' });
    await notifyConfigChanged(pool, { keys: ['room_defaults'], actorId: req.user.id, applyMode: 'immediate' });
    await auditConfig(req, 'runtime_override_cancel', { id: req.params.id });
    res.json({ success: true, override: result.rows[0] });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/history', async (req, res) => {
  try {
    const { key, scope, scope_id, admin, game_type_id, table_id, limit = 50, offset = 0 } = req.query;
    const params = [];
    const conditions = [];
    let query = `SELECT ch.*, u.username AS updated_by_name
                 FROM config_history ch LEFT JOIN users u ON u.id = ch.updated_by`;
    if (key) {
      params.push(key);
      conditions.push(`ch.key = $${params.length}`);
    }
    if (scope) {
      params.push(scope);
      conditions.push(`ch.scope = $${params.length}`);
    }
    if (scope_id) {
      params.push(scope_id);
      conditions.push(`ch.scope_id = $${params.length}`);
    }
    if (admin) {
      params.push(admin);
      conditions.push(`ch.updated_by = $${params.length}`);
    }
    if (game_type_id) {
      params.push(game_type_id);
      conditions.push(`ch.after_value->>'game_type_id' = $${params.length}`);
    }
    if (table_id) {
      params.push(table_id);
      conditions.push(`ch.scope_id = $${params.length}`);
    }
    if (conditions.length) {
      query += ' WHERE ' + conditions.join(' AND ');
    }
    params.push(Math.min(Number(limit) || 50, 200));
    query += ` ORDER BY ch.created_at DESC LIMIT $${params.length}`;
    params.push(Number(offset) || 0);
    query += ` OFFSET $${params.length}`;
    const result = await pool.query(query, params);
    res.json({ history: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/rollback/:revision', superAdminOnly, requireConfigWrite, async (req, res) => {
  try {
    const revision = Number(req.params.revision);
    const key = req.body?.key;
    if (!key || !PUBLIC_SCOPE_KEYS.has(key)) return res.status(400).json({ error: 'Config key is required' });
    const history = await pool.query(
      'SELECT * FROM config_history WHERE key = $1 AND revision = $2 ORDER BY created_at DESC LIMIT 1',
      [key, revision],
    );
    if (history.rows.length === 0) return res.status(404).json({ error: 'Config revision not found' });
    const target = history.rows[0].before_value;
    if (target === null) return res.status(400).json({ error: 'Cannot rollback to a missing config' });
    const result = await setConfig(pool, key, target, req.user.id, {
      reason: req.body?.reason || `Rollback to revision ${revision}`,
      correlationId: req.body?.correlation_id,
    });
    await auditConfig(req, 'config_rollback', { key, target_revision: revision, new_revision: result.revision });
    res.json({ success: true, ...result });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

router.get('/game-types/:gameTypeId/config', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT gtc.*, gt.slug, gt.name, gt.name_th
       FROM game_type_configs gtc
       JOIN game_types gt ON gt.id = gtc.game_type_id
       WHERE gtc.game_type_id = $1`,
      [req.params.gameTypeId],
    );
    res.json({ config: result.rows[0] || null });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/game-types/:gameTypeId/config', requireConfigWrite, async (req, res) => {
  const client = await pool.connect();
  try {
    const { config, expected_revision, reason, correlation_id } = req.body || {};
    const normalized = normalizeHierarchicalConfig(config || {}, 'game_type');
    await resolveRoomConfig(client, {
      gameTypeId: req.params.gameTypeId,
      overrides: normalized,
    });
    await client.query('BEGIN');
    const current = await client.query(
      'SELECT * FROM game_type_configs WHERE game_type_id = $1 FOR UPDATE',
      [req.params.gameTypeId],
    );
    const currentRow = current.rows[0];
    if (expected_revision !== undefined && Number(currentRow?.revision || 0) !== Number(expected_revision)) {
      const error = new Error('game type config revision conflict');
      error.status = 409;
      error.currentRevision = Number(currentRow?.revision || 0);
      throw error;
    }
    const nextRevision = Number(currentRow?.revision || 0) + 1;
    const result = await client.query(
      `INSERT INTO game_type_configs (game_type_id, revision, config, status, updated_by, updated_at)
       VALUES ($1, 1, $2, 'published', $3, NOW())
       ON CONFLICT (game_type_id) DO UPDATE
       SET config = $2, revision = game_type_configs.revision + 1,
           status = 'published', updated_by = $3, updated_at = NOW()
       RETURNING *`,
      [req.params.gameTypeId, JSON.stringify(normalized), req.user.id],
    );
    await client.query(
      `INSERT INTO config_history
       (revision, key, scope, scope_id, before_value, after_value, apply_mode, change_reason, correlation_id, updated_by)
       VALUES ($1, 'room_defaults', 'game_type', $2, $3, $4, 'new_room', $5, $6, $7)`,
      [nextRevision, req.params.gameTypeId, JSON.stringify(currentRow?.config ?? null), JSON.stringify(normalized), reason || null, correlation_id || null, req.user.id],
    );
    await notifyConfigChanged(client, {
      keys: ['room_defaults'],
      applyMode: 'new_room',
      actorId: req.user.id,
      correlationId: correlation_id,
    });
    await client.query('COMMIT');
    await auditConfig(req, 'game_type_config_update', { game_type_id: req.params.gameTypeId, revision: nextRevision, reason });
    res.json({ success: true, config: result.rows[0] });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    res.status(err.status || 400).json({ error: err.message, currentRevision: err.currentRevision });
  } finally {
    client.release();
  }
});

router.get('/templates', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT rt.*, gt.slug AS game_type_slug, gt.name AS game_type_name, gt.name_th AS game_type_name_th,
              u.username AS created_by_name,
              COUNT(t.id)::int AS active_room_count
       FROM room_templates rt
       JOIN game_types gt ON gt.id = rt.game_type_id
       LEFT JOIN users u ON u.id = rt.created_by
       LEFT JOIN game_tables t ON t.room_template_id = rt.id AND t.status != 'closed'
       GROUP BY rt.id, gt.slug, gt.name, gt.name_th, u.username
       ORDER BY rt.updated_at DESC`,
    );
    res.json({ templates: result.rows });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/templates', requireConfigWrite, async (req, res) => {
  try {
    const { game_type_id, name, mode = 'cash', config = {}, reason } = req.body || {};
    if (!game_type_id || !name) return res.status(400).json({ error: 'game_type_id and name are required' });
    if (!['cash', 'private', 'practice', 'tournament'].includes(mode)) {
      return res.status(400).json({ error: 'Invalid template mode' });
    }
    const normalized = normalizeHierarchicalConfig(config, 'template');
    const result = await pool.query(
      `INSERT INTO room_templates (game_type_id, name, mode, config, status, created_by)
       VALUES ($1, $2, $3, $4, 'published', $5) RETURNING *`,
      [game_type_id, name, mode, JSON.stringify(normalized), req.user.id],
    );
    await auditConfig(req, 'room_template_create', { id: result.rows[0].id, name, mode, reason });
    res.status(201).json({ template: result.rows[0] });
  } catch (err) {
    res.status(err.status || 400).json({ error: err.message });
  }
});

router.get('/templates/:id', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT rt.*, gt.slug AS game_type_slug, gt.name AS game_type_name, gt.name_th AS game_type_name_th,
              u.username AS created_by_name
       FROM room_templates rt
       JOIN game_types gt ON gt.id = rt.game_type_id
       LEFT JOIN users u ON u.id = rt.created_by
       WHERE rt.id = $1`,
      [req.params.id],
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Template not found' });
    const usage = await pool.query(
      `SELECT id, name, status, created_at FROM game_tables
       WHERE room_template_id = $1 ORDER BY created_at DESC LIMIT 100`,
      [req.params.id],
    );
    res.json({ template: result.rows[0], rooms: usage.rows });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/templates/:id', requireConfigWrite, async (req, res) => {
  const client = await pool.connect();
  try {
    const { name, mode, config, expected_revision, reason, correlation_id } = req.body || {};
    await client.query('BEGIN');
    const current = await client.query('SELECT * FROM room_templates WHERE id = $1 FOR UPDATE', [req.params.id]);
    if (current.rows.length === 0) {
      const error = new Error('Template not found');
      error.status = 404;
      throw error;
    }
    const existing = current.rows[0];
    if (config !== undefined) {
      const usage = await client.query(
        `SELECT COUNT(*)::int AS count FROM game_tables
         WHERE room_template_id = $1 AND status != 'closed'`,
        [req.params.id],
      );
      if (Number(usage.rows[0]?.count || 0) > 0) {
        const error = new Error('Template revision is used by active rooms; clone the template to create a new revision');
        error.status = 409;
        error.currentRevision = Number(existing.revision);
        throw error;
      }
    }
    if (expected_revision !== undefined && Number(existing.revision) !== Number(expected_revision)) {
      const error = new Error('template revision conflict');
      error.status = 409;
      error.currentRevision = Number(existing.revision);
      throw error;
    }
    const nextMode = mode === undefined ? existing.mode : mode;
    if (!['cash', 'private', 'practice', 'tournament'].includes(nextMode)) {
      const error = new Error('Invalid template mode');
      error.status = 400;
      throw error;
    }
    const normalized = config === undefined
      ? existing.config
      : normalizeHierarchicalConfig(config, 'template');
    await resolveRoomConfig(client, {
      gameTypeId: existing.game_type_id,
      templateId: req.params.id,
      overrides: normalized,
    });
    const nextRevision = Number(existing.revision) + 1;
    const result = await client.query(
      `UPDATE room_templates
       SET name = $2, mode = $3, config = $4, revision = $5, updated_at = NOW()
       WHERE id = $1 RETURNING *`,
      [req.params.id, name ?? existing.name, nextMode, JSON.stringify(normalized), nextRevision],
    );
    await client.query(
      `INSERT INTO config_history
       (revision, key, scope, scope_id, before_value, after_value, apply_mode, change_reason, correlation_id, updated_by)
       VALUES ($1, 'room_defaults', 'template', $2, $3, $4, 'new_room', $5, $6, $7)`,
      [nextRevision, req.params.id, JSON.stringify(existing.config), JSON.stringify(normalized), reason || null, correlation_id || null, req.user.id],
    );
    await client.query('COMMIT');
    await auditConfig(req, 'room_template_update', { id: req.params.id, revision: nextRevision, reason });
    res.json({ success: true, template: result.rows[0] });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    res.status(err.status || 400).json({ error: err.message, currentRevision: err.currentRevision });
  } finally {
    client.release();
  }
});

router.post('/templates/:id/clone', requireConfigWrite, async (req, res) => {
  try {
    const current = await pool.query('SELECT * FROM room_templates WHERE id = $1', [req.params.id]);
    if (current.rows.length === 0) return res.status(404).json({ error: 'Template not found' });
    const template = current.rows[0];
    const name = req.body?.name || `${template.name} Copy`;
    const result = await pool.query(
      `INSERT INTO room_templates (game_type_id, name, mode, config, status, created_by)
       VALUES ($1, $2, $3, $4, 'published', $5) RETURNING *`,
      [template.game_type_id, name, template.mode, JSON.stringify(template.config || {}), req.user.id],
    );
    await auditConfig(req, 'room_template_clone', { source_id: req.params.id, id: result.rows[0].id });
    res.status(201).json({ template: result.rows[0] });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/templates/:id/archive', requireConfigWrite, async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE room_templates SET status = 'archived', updated_at = NOW()
       WHERE id = $1 AND status != 'archived' RETURNING *`,
      [req.params.id],
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Template not found' });
    await auditConfig(req, 'room_template_archive', { id: req.params.id });
    res.json({ success: true, template: result.rows[0] });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/apply-existing', superAdminOnly, requireConfigWrite, async (req, res) => {
  try {
    const { key, dry_run = true, reason, apply_mode = 'immediate' } = req.body || {};
    if (key !== 'room_defaults') return res.status(400).json({ error: 'Only room_defaults can be applied to existing rooms' });
    if (!APPLY_MODES.includes(apply_mode)) return res.status(400).json({ error: 'Invalid apply mode' });
    const preview = await pool.query(
      `SELECT id, name, status, config_version, small_blind, big_blind, ante, min_buy_in, max_buy_in,
              max_players, turn_time_sec, auto_start_at, auto_start_delay_sec,
              minimum_play_minutes, rake_percent, rake_cap
       FROM game_tables
       WHERE status = 'waiting' AND config_snapshot IS NOT NULL
       ORDER BY created_at DESC LIMIT 500`,
    );
    const roomFields = Object.keys(CONFIG_DEFINITIONS.room_defaults.fields);
    const latestRoomDefaults = await getConfig(pool, 'room_defaults');
    const withDiff = [];
    for (const room of preview.rows) {
      const effective = await resolveRoomConfig(pool, {
        tableId: room.id,
        snapshotOverrides: latestRoomDefaults,
      });
      const diff = Object.fromEntries(roomFields
        .filter(f => effective.value[f] !== room[f])
        .map(f => [f, { before: room[f], after: effective.value[f] }]));
      withDiff.push({ room_id: room.id, name: room.name, status: room.status, diff });
    }
    if (dry_run) {
      return res.json({ dry_run: true, apply_mode, affected_rooms: withDiff.length, rooms: withDiff });
    }
    if (apply_mode !== 'immediate') {
      return res.status(501).json({ error: `Apply mode '${apply_mode}' is not yet supported by apply-existing` });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const latestRoomDefaults = await getConfig(client, 'room_defaults');
      for (const room of preview.rows) {
        const effective = await resolveRoomConfig(client, {
          tableId: room.id,
          snapshotOverrides: latestRoomDefaults,
        });
        await client.query(
          `UPDATE game_tables
           SET small_blind = $1, big_blind = $2, ante = $3, min_buy_in = $4,
               max_buy_in = $5, max_players = $6, turn_time_sec = $7,
               auto_start_at = $8, auto_start_delay_sec = $9,
               minimum_play_minutes = $10, rake_percent = $11, rake_cap = $12,
               config_snapshot = $13, config_version = $14, config_hash = $15
           WHERE id = $16`,
          [
            effective.value.small_blind, effective.value.big_blind, effective.value.ante,
            effective.value.min_buy_in, effective.value.max_buy_in, effective.value.max_players,
            effective.value.turn_time_sec, effective.value.auto_start_at,
            effective.value.auto_start_delay_sec, effective.value.minimum_play_minutes,
            effective.value.rake_percent, effective.value.rake_cap,
            JSON.stringify(roomSnapshotPayload(effective)),
            effective.revisions.room_defaults,
            effective.hash,
            room.id,
          ],
        );
      }
      await notifyConfigChanged(client, {
        keys: ['room_defaults'],
        applyMode: 'immediate',
        actorId: req.user.id,
        reason: reason || 'Apply room defaults to existing rooms',
      });
      await client.query('COMMIT');
      await auditConfig(req, 'config_apply_existing', { key, affected_rooms: preview.rows.length, reason });
      res.json({ success: true, dry_run: false, affected_rooms: preview.rows.length });
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
