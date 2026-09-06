const test = require('node:test');
const assert = require('node:assert/strict');
const { CONFIG_DEFINITIONS } = require('../../config/config-definitions');
const {
  bootstrapValue,
  configHash,
  resolveRoomConfig,
  validateConfig,
} = require('../../config/config-platform');
const { DEFAULT_CONFIGS, setConfig } = require('./src/config-service');

function configPool({ defaults, limits, gameConfig = {}, templateConfig = null, table = null, runtimeOverrides = [] }) {
  return {
    query: async (text, params) => {
      if (text.includes('FROM system_config')) {
        const key = params[0];
        const value = key === 'room_defaults' ? defaults
          : key === 'room_creation_limits' ? limits
          : bootstrapValue(key);
        return { rows: value ? [{ key, value, revision: 7 }] : [] };
      }
      if (text.includes('FROM game_type_configs')) return { rows: [{ config: gameConfig }] };
      if (text.includes('FROM room_templates')) return { rows: templateConfig ? [{ config: templateConfig }] : [] };
      if (text.includes('FROM game_tables')) return { rows: table ? [table] : [] };
      if (text.includes('FROM runtime_overrides')) return { rows: runtimeOverrides };
      return { rows: [] };
    },
  };
}

test('registry covers all P1 domain categories', () => {
  for (const key of [
    'texas_holdem_policy',
    'chinese_poker_policy',
    'tournament_policy',
    'practice_policy',
    'wallet_economy_policy',
    'security_policy',
    'notification_policy',
    'coin_settings',
  ]) {
    assert.ok(CONFIG_DEFINITIONS[key], `${key} must be defined`);
    assert.ok(validateConfig(key, bootstrapValue(key)));
  }
});

test('registry defaults are versioned bootstrap data, not silent code defaults', () => {
  assert.equal(DEFAULT_CONFIGS.room_defaults.turn_time_sec, 30);
  assert.equal(bootstrapValue('game_runtime').room_access_token_minutes, 5);
  assert.equal(CONFIG_DEFINITIONS.game_runtime.fields.room_access_token_minutes.applyMode, 'immediate');
});

test('typed config validation rejects unknown, invalid and conflicting fields', () => {
  const runtime = bootstrapValue('game_runtime');
  assert.deepEqual(validateConfig('game_runtime', runtime), runtime);
  assert.throws(() => validateConfig('game_runtime', { ...runtime, unknown: 1 }), /Unknown config field/);
  assert.throws(() => validateConfig('game_runtime', { ...runtime, idle_timeout_sec: 1 }), /idle_timeout_sec/);
  assert.throws(
    () => validateConfig('room_defaults', { ...bootstrapValue('room_defaults'), max_buy_in: 1 }),
    /max_buy_in/,
  );
});

test('room config resolver returns value, source and deterministic hash', async () => {
  const defaults = bootstrapValue('room_defaults');
  const limits = bootstrapValue('room_creation_limits');
  const pool = configPool({
    defaults,
    limits,
    gameConfig: { turn_time_sec: 45, ignored: 'field' },
    templateConfig: { turn_time_sec: 35 },
    table: { ...defaults, config_snapshot: { minimum_play_minutes: 10 } },
  });
  const result = await resolveRoomConfig(pool, { gameTypeId: 'game-1', templateId: 'template-1', tableId: 'table-1' });
  assert.equal(result.value.turn_time_sec, 35);
  assert.equal(result.value.minimum_play_minutes, 10);
  assert.equal(result.sources.turn_time_sec, 'room_template');
  assert.equal(result.sources.minimum_play_minutes, 'room_snapshot');
  assert.equal(result.hash, configHash({ room: result.value, policies: result.policies }));
});

test('runtime overrides take precedence over room template and snapshot values', async () => {
  const pool = configPool({
    defaults: bootstrapValue('room_defaults'),
    limits: bootstrapValue('room_creation_limits'),
    gameConfig: { turn_time_sec: 45 },
    templateConfig: { turn_time_sec: 35 },
    table: { config_snapshot: { turn_time_sec: 40 } },
    runtimeOverrides: [{ key: 'room_defaults', value: { turn_time_sec: 50 } }],
  });
  const result = await resolveRoomConfig(pool, {
    gameTypeId: 'game-1',
    templateId: 'template-1',
    tableId: '11111111-1111-1111-1111-111111111111',
  });
  assert.equal(result.value.turn_time_sec, 50);
  assert.equal(result.sources.turn_time_sec, 'runtime_override');
});

test('new-room runtime overrides are excluded when resolving an existing room', async () => {
  const queries = [];
  const pool = {
    query: async (text, params) => {
      queries.push({ text, params });
      if (text.includes('FROM system_config')) return { rows: [{ key: params[0], value: bootstrapValue(params[0]), revision: 7 }] };
      if (text.includes('FROM game_tables')) return { rows: [{ id: params[0], game_type_id: 'game-1', config_snapshot: {} }] };
      return { rows: [] };
    },
  };
  await resolveRoomConfig(pool, { tableId: '11111111-1111-1111-1111-111111111111' });
  const overrideQuery = queries.find(query => query.text.includes('FROM runtime_overrides'));
  assert.match(overrideQuery.text, /apply_mode <> 'new_room'/);
});

test('applied snapshots override room values while runtime overrides remain authoritative', async () => {
  const base = {
    defaults: bootstrapValue('room_defaults'),
    limits: bootstrapValue('room_creation_limits'),
    table: { config_snapshot: { turn_time_sec: 40 } },
  };
  const withoutRuntime = await resolveRoomConfig(configPool(base), {
    tableId: '11111111-1111-1111-1111-111111111111',
    snapshotOverrides: { turn_time_sec: 45 },
  });
  assert.equal(withoutRuntime.value.turn_time_sec, 45);
  assert.equal(withoutRuntime.sources.turn_time_sec, 'applied_snapshot');

  const withRuntime = await resolveRoomConfig(configPool({
    ...base,
    runtimeOverrides: [{ key: 'room_defaults', value: { turn_time_sec: 50 } }],
  }), {
    tableId: '11111111-1111-1111-1111-111111111111',
    snapshotOverrides: { turn_time_sec: 45 },
  });
  assert.equal(withRuntime.value.turn_time_sec, 50);
  assert.equal(withRuntime.sources.turn_time_sec, 'runtime_override');
});

test('config update enforces optimistic locking and appends history', async () => {
  const queries = [];
  const client = {
    query: async (text, params) => {
      queries.push({ text, params });
      if (text.includes('FOR UPDATE')) return { rows: [{ value: bootstrapValue('app_control'), revision: 2 }] };
      if (text.includes('INSERT INTO system_config')) return { rows: [{ value: bootstrapValue('app_control'), revision: 3 }] };
      return { rows: [] };
    },
    release: () => {},
  };
  const pool = { connect: async () => client };
  await assert.rejects(
    setConfig(pool, 'app_control', bootstrapValue('app_control'), 'admin-1', { expectedRevision: 1 }),
    error => error.status === 409 && error.currentRevision === 2,
  );
  assert.equal(queries.some(query => query.text.includes('INSERT INTO config_history')), false);
});

test('config update writes history with correlation and reason', async () => {
  const queries = [];
  const client = {
    query: async (text, params) => {
      queries.push({ text, params });
      if (text.includes('FOR UPDATE')) return { rows: [{ value: bootstrapValue('app_control'), revision: 2 }] };
      if (text.includes('INSERT INTO system_config')) return { rows: [{ value: bootstrapValue('app_control'), revision: 3 }] };
      return { rows: [] };
    },
    release: () => {},
  };
  const result = await setConfig(
    { connect: async () => client },
    'app_control',
    bootstrapValue('app_control'),
    'admin-1',
    { expectedRevision: 2, reason: 'scheduled maintenance', correlationId: '11111111-1111-1111-1111-111111111111' },
  );
  assert.equal(result.revision, 3);
  const history = queries.find(query => query.text.includes('INSERT INTO config_history'));
  assert.equal(history.params[5], 'scheduled maintenance');
});
