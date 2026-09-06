const {
  bootstrapValue,
  configHash,
  loadConfigRow,
  resolveRoomConfig,
  roomSnapshotPayload,
  validateConfig,
  validateRoomAgainstLimits,
} = require('../../../config/config-platform');
const { CONFIG_DEFINITIONS } = require('../../../config/config-definitions');
const { notifyConfigChanged } = require('../../../config/config-events');

const DEFAULT_CONFIGS = Object.freeze(Object.fromEntries(
  Object.keys(CONFIG_DEFINITIONS).map(key => [key, Object.freeze(bootstrapValue(key))]),
));

const OPTIONAL_BOOTSTRAP_KEYS = new Set(['app_background', 'card_back_settings']);

async function getConfig(pool, key) {
  if (!CONFIG_DEFINITIONS[key]) {
    const result = await pool.query('SELECT value, revision FROM system_config WHERE key = $1', [key]);
    return result.rows[0]?.value || {};
  }
  const row = await loadConfigRow(pool, key, { required: !OPTIONAL_BOOTSTRAP_KEYS.has(key) });
  if (!row) return { ...DEFAULT_CONFIGS[key] };
  return row.value;
}

async function getOptionalConfig(pool, key) {
  const row = await loadConfigRow(pool, key, { required: false });
  return row ? row.value : null;
}

async function getRequiredConfig(pool, key) {
  return (await loadConfigRow(pool, key)).value;
}

async function setConfig(pool, key, value, userId, { expectedRevision, reason, correlationId } = {}) {
  const nextValue = validateConfig(key, value);
  const client = pool.connect ? await pool.connect() : pool;
  try {
    if (client.query.length !== undefined) await client.query('BEGIN');
    const current = await client.query('SELECT value, revision FROM system_config WHERE key = $1 FOR UPDATE', [key]);
    const currentRevision = Number(current.rows[0]?.revision || 0);
    if (expectedRevision !== undefined && Number(expectedRevision) !== currentRevision) {
      const error = new Error('Config revision conflict');
      error.status = 409;
      error.currentRevision = currentRevision;
      throw error;
    }
    const nextRevision = currentRevision + 1;
    const result = await client.query(
      `INSERT INTO system_config (key, value, revision, status, updated_by, updated_at, published_at, published_by, change_reason)
       VALUES ($1, $2, 1, 'published', $3, NOW(), NOW(), $3, $4)
       ON CONFLICT (key) DO UPDATE
       SET value = $2,
           revision = system_config.revision + 1,
           status = 'published',
           updated_by = $3,
           updated_at = NOW(),
           published_at = NOW(),
           published_by = $3,
           change_reason = $4
       RETURNING value, revision`,
      [key, JSON.stringify(nextValue), userId, reason || null],
    );
    await client.query(
      `INSERT INTO config_history
       (revision, key, scope, before_value, after_value, apply_mode, change_reason, correlation_id, updated_by)
       VALUES ($1, $2, 'system', $3, $4, $5, $6, $7, $8)`,
      [
        nextRevision,
        key,
        JSON.stringify(current.rows[0]?.value ?? null),
        JSON.stringify(nextValue),
        CONFIG_DEFINITIONS[key].applyMode,
        reason || null,
        correlationId || null,
        userId,
      ],
    );
    await notifyConfigChanged(client, {
      keys: [key],
      revision: nextRevision,
      actorId: userId,
      correlationId,
      applyMode: CONFIG_DEFINITIONS[key].applyMode,
    });
    if (client.query.length !== undefined) await client.query('COMMIT');
    return { ...result.rows[0], config_hash: configHash(nextValue) };
  } catch (error) {
    if (client.query.length !== undefined) await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    if (client.release) client.release();
  }
}

function clamp(value, min, max, fallback) {
  const number = Number(value ?? fallback);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, number));
}

function normalizeGameRuntime(input) {
  return validateConfig('game_runtime', input);
}

function normalizeRoomInput(input, defaults, limits) {
  const roomFieldNames = Object.keys(CONFIG_DEFINITIONS.room_defaults.fields);
  const roomOverrides = Object.fromEntries(
    roomFieldNames
      .filter(fieldName => input?.[fieldName] !== undefined)
      .map(fieldName => [fieldName, input[fieldName]]),
  );
  const normalized = validateConfig('room_defaults', { ...defaults, ...roomOverrides });
  validateRoomAgainstLimits(normalized, limits);
  if (input.name !== undefined) {
    const name = String(input.name || '');
    if (name.length < limits.room_name_min_length || name.length > limits.room_name_max_length) {
      throw new Error(`Room name must be between ${limits.room_name_min_length} and ${limits.room_name_max_length} characters`);
    }
  }
  if (input.mode !== undefined && !limits.allowed_modes.includes(input.mode)) {
    throw new Error(`Room mode ${input.mode} is not allowed`);
  }
  const visibility = input.club_id ? 'club' : (input.password || input.is_private) ? 'private' : 'public';
  if (!limits.allowed_visibility.includes(visibility)) {
    throw new Error(`Room visibility ${visibility} is not allowed`);
  }
  if (visibility === 'private' && limits.private_room_enabled === false) {
    throw new Error('Private rooms are disabled');
  }
  if (input.password !== undefined && input.password !== null && input.password !== '') {
    const password = String(input.password);
    if (password.length < limits.room_password_min_length || password.length > limits.room_password_max_length) {
      throw new Error(`Room password must be between ${limits.room_password_min_length} and ${limits.room_password_max_length} characters`);
    }
  }
  return { ...input, ...normalized };
}

module.exports = {
  DEFAULT_CONFIGS,
  getConfig,
  getOptionalConfig,
  getRequiredConfig,
  normalizeGameRuntime,
  normalizeRoomInput,
  resolveRoomConfig,
  roomSnapshotPayload,
  setConfig,
  validateConfig,
};
