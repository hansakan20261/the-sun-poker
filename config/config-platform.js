const crypto = require('crypto');
const { CONFIG_DEFINITIONS } = require('./config-definitions');

function bootstrapValue(key) {
  const category = CONFIG_DEFINITIONS[key];
  if (!category) return undefined;
  return Object.fromEntries(
    Object.entries(category.fields).map(([field, definition]) => [field, definition.default]),
  );
}

function validateField(key, fieldName, value) {
  const definition = CONFIG_DEFINITIONS[key]?.fields?.[fieldName];
  if (!definition) throw new Error(`Unknown config field ${key}.${fieldName}`);
  if (value === null || value === undefined) {
    if (definition.required) throw new Error(`${key}.${fieldName} is required`);
    return value;
  }
  switch (definition.type) {
    case 'boolean':
      if (typeof value !== 'boolean') throw new Error(`${key}.${fieldName} must be a boolean`);
      break;
    case 'integer': {
      const number = Number(value);
      if (!Number.isInteger(number)) throw new Error(`${key}.${fieldName} must be an integer`);
      if (number < definition.min || number > definition.max) {
        throw new Error(`${key}.${fieldName} must be between ${definition.min} and ${definition.max}`);
      }
      return number;
    }
    case 'number': {
      const number = Number(value);
      if (!Number.isFinite(number)) throw new Error(`${key}.${fieldName} must be a number`);
      if (number < definition.min || number > definition.max) {
        throw new Error(`${key}.${fieldName} must be between ${definition.min} and ${definition.max}`);
      }
      return number;
    }
    case 'string':
      if (typeof value !== 'string') throw new Error(`${key}.${fieldName} must be a string`);
      if (definition.enum && !definition.enum.includes(value)) {
        throw new Error(`${key}.${fieldName} must be one of ${definition.enum.join(', ')}`);
      }
      break;
    case 'datetime':
      if (Number.isNaN(Date.parse(value))) throw new Error(`${key}.${fieldName} must be a valid datetime`);
      break;
    case 'semver':
      if (!/^\d+\.\d+\.\d+$/.test(value)) throw new Error(`${key}.${fieldName} must use semantic version format`);
      break;
    case 'array':
      if (!Array.isArray(value)) throw new Error(`${key}.${fieldName} must be an array`);
      if (definition.enum && !value.every(item => definition.enum.includes(item))) {
        throw new Error(`${key}.${fieldName} contains an unsupported value`);
      }
      break;
    case 'object':
      if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${key}.${fieldName} must be an object`);
      break;
    default:
      throw new Error(`${key}.${fieldName} has unsupported type ${definition.type}`);
  }
  return value;
}

function validateConfig(key, value, { partial = false } = {}) {
  const category = CONFIG_DEFINITIONS[key];
  if (!category) throw new Error(`Unknown config key ${key}`);
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${key} must be an object`);
  }
  const result = {};
  for (const fieldName of Object.keys(value)) validateField(key, fieldName, value[fieldName]);
  for (const [fieldName, definition] of Object.entries(category.fields)) {
    const hasValue = Object.prototype.hasOwnProperty.call(value, fieldName);
    if (!hasValue && !partial && definition.required) throw new Error(`${key}.${fieldName} is required`);
    if (hasValue) result[fieldName] = validateField(key, fieldName, value[fieldName]);
  }
  validateCrossFields(key, result, value);
  return result;
}

function validateCrossFields(key, normalized, original = normalized) {
  if (key === 'room_defaults') {
    if (normalized.big_blind < normalized.small_blind) throw new Error('room_defaults.big_blind must be greater than or equal to small_blind');
    if (normalized.max_buy_in < normalized.min_buy_in) throw new Error('room_defaults.max_buy_in must be greater than or equal to min_buy_in');
    if (normalized.auto_start_at > normalized.max_players) throw new Error('room_defaults.auto_start_at cannot exceed max_players');
  }
  if (key === 'room_creation_limits') {
    if (normalized.allowed_modes?.length === 0) throw new Error('room_creation_limits.allowed_modes cannot be empty');
    if (normalized.allowed_game_type_slugs?.length === 0) throw new Error('room_creation_limits.allowed_game_type_slugs cannot be empty');
    if (normalized.allowed_visibility?.length === 0) throw new Error('room_creation_limits.allowed_visibility cannot be empty');
    if (normalized.max_small_blind < normalized.min_small_blind) throw new Error('room_creation_limits.max_small_blind must be greater than or equal to min_small_blind');
    if (normalized.max_players < normalized.min_players) throw new Error('room_creation_limits.max_players must be greater than or equal to min_players');
    if (normalized.max_turn_time_sec < normalized.min_turn_time_sec) throw new Error('room_creation_limits.max_turn_time_sec must be greater than or equal to min_turn_time_sec');
    if (normalized.max_auto_start_delay_sec < normalized.min_auto_start_delay_sec) throw new Error('room_creation_limits.max_auto_start_delay_sec must be greater than or equal to min_auto_start_delay_sec');
    if (normalized.max_minimum_play_minutes < normalized.min_minimum_play_minutes) throw new Error('room_creation_limits.max_minimum_play_minutes must be greater than or equal to min_minimum_play_minutes');
  }
  if (key === 'wallet_economy_policy' && normalized.house_account_user_id &&
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(normalized.house_account_user_id)) {
    throw new Error('wallet_economy_policy.house_account_user_id must be a UUID');
  }
  if (key === 'practice_policy' && normalized.demo_bot_profiles) {
    for (const bot of normalized.demo_bot_profiles) {
      if (!bot || typeof bot !== 'object' || !/^[0-9a-f-]{36}$/i.test(String(bot.id)) ||
          typeof bot.username !== 'string' || !bot.username ||
          typeof bot.countryFlag !== 'string' || !bot.countryFlag) {
        throw new Error('practice_policy.demo_bot_profiles entries must include id, username and countryFlag');
      }
    }
  }
  if (key === 'chinese_poker_policy' &&
      normalized.auto_arrange_on_timeout === false &&
      normalized.force_foul_on_invalid === false) {
    throw new Error('chinese_poker_policy must enable auto-arrange or force-foul for timeout handling');
  }
  if (key === 'app_control' && normalized.maintenance_starts_at && normalized.maintenance_ends_at) {
    if (Date.parse(normalized.maintenance_ends_at) <= Date.parse(normalized.maintenance_starts_at)) {
      throw new Error('app_control.maintenance_ends_at must be after maintenance_starts_at');
    }
  }
  return original;
}

function configHash(value) {
  const canonical = JSON.stringify(sortObject(value));
  return crypto.createHash('sha256').update(canonical).digest('hex');
}

function sortObject(value) {
  if (Array.isArray(value)) return value.map(sortObject);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.keys(value).sort().map(key => [key, sortObject(value[key])]));
}

async function loadConfigRow(executor, key, { required = true } = {}) {
  const result = await executor.query('SELECT key, value, revision FROM system_config WHERE key = $1', [key]);
  if (result.rows.length === 0) {
    if (required) throw new Error(`${key} config is required`);
    return null;
  }
  const row = result.rows[0];
  const value = required
    ? validateConfig(key, row.value || {})
    : validateConfig(key, { ...bootstrapValue(key), ...(row.value || {}) });
  return { ...row, value };
}

async function resolveRoomConfig(executor, { gameTypeId, templateId, tableId, overrides = {}, snapshotOverrides = {} } = {}) {
  const [defaultsRow, limitsRow, texasPolicy, chinesePolicy, tournamentPolicy] = await Promise.all([
    loadConfigRow(executor, 'room_defaults'),
    loadConfigRow(executor, 'room_creation_limits'),
    loadConfigRow(executor, 'texas_holdem_policy'),
    loadConfigRow(executor, 'chinese_poker_policy'),
    loadConfigRow(executor, 'tournament_policy'),
  ]);
  let gameTypeConfig = {};
  if (gameTypeId) {
    const result = await executor.query('SELECT config FROM game_type_configs WHERE game_type_id = $1', [gameTypeId])
      .catch(error => {
        if (error.code !== '42P01') throw error;
        return { rows: [] };
      });
    if (result.rows.length === 0) {
      const legacy = await executor.query('SELECT config FROM game_types WHERE id = $1', [gameTypeId]);
      gameTypeConfig = legacy.rows[0]?.config || {};
    } else {
      gameTypeConfig = result.rows[0].config || {};
    }
  }
  let templateConfig = {};
  if (templateId) {
    const result = await executor.query(
      "SELECT config FROM room_templates WHERE id = $1 AND status = 'published'",
      [templateId],
    );
    if (result.rows.length === 0) throw new Error('Room template not found');
    templateConfig = result.rows[0].config || {};
  }
  let roomConfig = {};
  let table = null;
  if (tableId) {
    const result = await executor.query('SELECT * FROM game_tables WHERE id = $1', [tableId]);
    table = result.rows[0] || null;
    roomConfig = table?.config_snapshot?.room
      ? { room_defaults: table.config_snapshot.room, policies: table.config_snapshot.policies }
      : table?.config_snapshot || table || {};
  }
  let runtimeConfig = {};
  const runtimeResult = await executor.query(
    `SELECT key, value FROM runtime_overrides
     WHERE status = 'active' AND effective_at <= NOW()
       AND (expires_at IS NULL OR expires_at > NOW())
       AND ($1::uuid IS NULL OR apply_mode <> 'new_room')
       AND (($1::uuid IS NOT NULL AND table_id = $1)
         OR ($2::uuid IS NOT NULL AND game_type_id = $2))
     ORDER BY CASE WHEN table_id = $1 THEN 1 ELSE 0 END ASC, effective_at ASC, created_at ASC`,
    [tableId || null, gameTypeId || null],
  ).catch(error => {
    if (error.code === '42P01' || error.code === '42883') return { rows: [] };
    throw error;
  });
  for (const row of runtimeResult.rows) {
    if (typeof row.value === 'object' && row.value !== null && !Array.isArray(row.value)) {
      runtimeConfig = { ...runtimeConfig, ...row.value };
    } else {
      runtimeConfig[row.key] = row.value;
    }
  }
  const roomFieldNames = Object.keys(CONFIG_DEFINITIONS.room_defaults.fields);
  const policyCategories = {
    texas_holdem: 'texas_holdem_policy',
    chinese_poker: 'chinese_poker_policy',
    tournament: 'tournament_policy',
  };
  const pickFields = (source, fieldNames) => Object.fromEntries(
    fieldNames
      .filter(fieldName => source?.[fieldName] !== undefined && source[fieldName] !== null)
      .map(fieldName => [fieldName, source[fieldName]]),
  );
  const pickRoom = source => pickFields(source?.room_defaults || source, roomFieldNames);
  const pickPolicy = (source, policyKey, configKey) => {
    const nested = source?.policies?.[policyKey]
      || source?.[configKey]
      || source?.[policyKey]
      || {};
    return {
      ...pickFields(source, Object.keys(CONFIG_DEFINITIONS[configKey].fields)),
      ...pickFields(nested, Object.keys(CONFIG_DEFINITIONS[configKey].fields)),
    };
  };

  const layers = [gameTypeConfig, templateConfig, roomConfig, snapshotOverrides, runtimeConfig, overrides];
  const roomLayers = layers.map(pickRoom);
  const merged = { ...defaultsRow.value, ...Object.assign({}, ...roomLayers) };
  const value = validateConfig('room_defaults', merged);
  validateRoomAgainstLimits(value, limitsRow.value);
  const policies = {
    texas_holdem: validateConfig('texas_holdem_policy', {
      ...texasPolicy.value,
      ...Object.assign({}, ...layers.map(layer => pickPolicy(layer, 'texas_holdem', 'texas_holdem_policy'))),
    }),
    chinese_poker: validateConfig('chinese_poker_policy', {
      ...chinesePolicy.value,
      ...Object.assign({}, ...layers.map(layer => pickPolicy(layer, 'chinese_poker', 'chinese_poker_policy'))),
    }),
    tournament: validateConfig('tournament_policy', {
      ...tournamentPolicy.value,
      ...Object.assign({}, ...layers.map(layer => pickPolicy(layer, 'tournament', 'tournament_policy'))),
    }),
  };
  const [gameTypeRoom, templateRoom, roomSnapshot, appliedSnapshot, runtimeRoom, explicitRoom] = roomLayers;
  gameTypeConfig = gameTypeRoom;
  templateConfig = templateRoom;
  roomConfig = roomSnapshot;
  snapshotOverrides = appliedSnapshot;
  runtimeConfig = runtimeRoom;
  overrides = explicitRoom;
  return {
    value,
    policies,
    hash: configHash({ room: value, policies }),
    sources: Object.fromEntries(Object.keys(value).map(fieldName => [
      fieldName,
      overrides[fieldName] !== undefined ? 'runtime_override'
        : runtimeConfig[fieldName] !== undefined ? 'runtime_override'
        : snapshotOverrides[fieldName] !== undefined ? 'applied_snapshot'
        : roomConfig[fieldName] !== undefined ? 'room_snapshot'
        : templateConfig[fieldName] !== undefined ? 'room_template'
        : gameTypeConfig[fieldName] !== undefined ? 'game_type'
        : 'system_default',
    ])),
    revisions: {
      room_defaults: defaultsRow.revision ?? null,
      texas_holdem_policy: texasPolicy.revision ?? null,
      chinese_poker_policy: chinesePolicy.revision ?? null,
      tournament_policy: tournamentPolicy.revision ?? null,
    },
    table,
  };
}

function roomSnapshotPayload(effective) {
  return {
    room: effective.value,
    policies: effective.policies,
    revisions: effective.revisions,
    hash: effective.hash,
  };
}

function validateRoomAgainstLimits(room, limits) {
  if (room.max_players < limits.min_players || room.max_players > limits.max_players) throw new Error('max_players is outside configured bounds');
  if (room.small_blind < limits.min_small_blind || room.small_blind > limits.max_small_blind) throw new Error('small_blind is outside configured bounds');
  if (room.ante < limits.min_ante || room.ante > limits.max_ante) throw new Error('ante is outside configured bounds');
  if (room.turn_time_sec < limits.min_turn_time_sec || room.turn_time_sec > limits.max_turn_time_sec) throw new Error('turn_time_sec is outside configured bounds');
  if (room.auto_start_delay_sec < limits.min_auto_start_delay_sec || room.auto_start_delay_sec > limits.max_auto_start_delay_sec) throw new Error('auto_start_delay_sec is outside configured bounds');
  if (room.minimum_play_minutes < limits.min_minimum_play_minutes || room.minimum_play_minutes > limits.max_minimum_play_minutes) throw new Error('minimum_play_minutes is outside configured bounds');
  if (room.min_buy_in < limits.min_buy_in_chips || room.max_buy_in > limits.max_buy_in_chips) throw new Error('buy-in is outside configured bounds');
  if (room.rake_percent < limits.min_rake_percent || room.rake_percent > limits.max_rake_percent) throw new Error('rake_percent is outside configured bounds');
  if (room.rake_cap > limits.max_rake_cap) throw new Error('rake_cap is outside configured bounds');
  if (room.min_buy_in > room.max_buy_in) throw new Error('min_buy_in cannot exceed max_buy_in');
  if (room.auto_start_at > room.max_players) throw new Error('auto_start_at cannot exceed max_players');
}

async function syncConfigDefinitions(executor) {
  let count = 0;
  for (const category of Object.values(CONFIG_DEFINITIONS)) {
    for (const [fieldName, definition] of Object.entries(category.fields)) {
      await executor.query(
        `INSERT INTO config_definitions (key, field, definition, version, is_active)
         VALUES ($1, $2, $3, 1, TRUE)
         ON CONFLICT (key, field, version) DO UPDATE
         SET definition = EXCLUDED.definition, is_active = TRUE`,
        [category.key, fieldName, JSON.stringify(definition)],
      );
      count++;
    }
  }
  return count;
}

module.exports = {
  bootstrapValue,
  configHash,
  loadConfigRow,
  resolveRoomConfig,
  roomSnapshotPayload,
  syncConfigDefinitions,
  validateConfig,
  validateField,
  validateRoomAgainstLimits,
};
