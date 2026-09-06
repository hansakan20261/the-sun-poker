const test = require('node:test');
const assert = require('node:assert/strict');
const {
  reloadRoomRuntimeConfig,
  resolveRoomTurnTimeSec,
  validateMinimumPlayMinutes,
  validateRoomAutoStart,
  validateRoomTurnTimeSec,
} = require('./src/config-registry');
const { bootstrapValue } = require('../../config/config-platform');

const limits = { ...bootstrapValue('room_creation_limits'), min_turn_time_sec: 10, max_turn_time_sec: 60 };

function createPool(responses) {
  const queries = [];
  return {
    queries,
    query: async (text, params) => {
      queries.push({ text, params });
      return responses.shift() || { rows: [] };
    },
  };
}

test('turn time registry validates configured bounds without fallback values', () => {
  assert.equal(validateRoomTurnTimeSec(10, limits), 10);
  assert.equal(validateRoomTurnTimeSec('30', limits), 30);
  assert.equal(validateRoomTurnTimeSec(60, limits), 60);
  assert.throws(() => validateRoomTurnTimeSec(9, limits), /between 10 and 60/);
  assert.throws(() => validateRoomTurnTimeSec(61, limits), /between 10 and 60/);
  assert.throws(() => validateRoomTurnTimeSec(30.5, limits), /integer/);
  assert.throws(() => validateRoomTurnTimeSec(30, {}), /bounds/);
});

test('minimum play registry accepts 0, 1, and configured maximum', () => {
  const playLimits = { min_minimum_play_minutes: 0, max_minimum_play_minutes: 1440 };
  assert.equal(validateMinimumPlayMinutes(0, playLimits), 0);
  assert.equal(validateMinimumPlayMinutes(1, playLimits), 1);
  assert.equal(validateMinimumPlayMinutes(1440, playLimits), 1440);
  assert.throws(() => validateMinimumPlayMinutes(1441, playLimits), /between 0 and 1440/);
});

test('auto-start registry validates threshold, delay, and room capacity', () => {
  const autoLimits = { ...limits, min_players: 2, max_players: 9, min_auto_start_delay_sec: 0, max_auto_start_delay_sec: 30 };
  assert.deepEqual(validateRoomAutoStart(4, 3, 6, autoLimits), { autoStartAt: 4, autoStartDelaySec: 3 });
  assert.throws(() => validateRoomAutoStart(7, 3, 6, autoLimits), /cannot exceed max_players/);
  assert.throws(() => validateRoomAutoStart(4, 31, 6, autoLimits), /between 0 and 30/);
});

test('room runtime config reload applies the effective hierarchy atomically', async () => {
  const table = {
    id: '11111111-1111-1111-1111-111111111111',
    game_type_id: '22222222-2222-2222-2222-222222222222',
    config_snapshot: { minimum_play_minutes: 20 },
  };
  const configs = {
    room_defaults: bootstrapValue('room_defaults'),
    room_creation_limits: limits,
    texas_holdem_policy: bootstrapValue('texas_holdem_policy'),
    chinese_poker_policy: bootstrapValue('chinese_poker_policy'),
    tournament_policy: bootstrapValue('tournament_policy'),
  };
  const pool = {
    query: async (text, params = []) => {
      if (text.includes('FROM system_config')) return { rows: [{ value: configs[params[0]], revision: 2 }] };
      if (text.includes('FROM game_type_configs')) return { rows: [{ config: { auto_start_at: 3, auto_start_delay_sec: 3 } }] };
      if (text.includes('FROM game_tables')) return { rows: [table] };
      if (text.includes('FROM runtime_overrides')) return { rows: [{ key: 'room_defaults', value: { turn_time_sec: 50, auto_start_at: 4 } }] };
      return { rows: [] };
    },
  };
  const room = { config: { turnTimeSec: 30, autoStartAt: 2, autoStartDelaySec: 2 } };
  assert.deepEqual(await reloadRoomRuntimeConfig(pool, room, table.id), {
    turnTimeSec: 50,
    autoStartAt: 4,
    autoStartDelaySec: 3,
    minimumPlayMinutes: 20,
    minPlayMinutes: 20,
    rakePercent: configs.room_defaults.rake_percent,
    rakeCap: configs.room_defaults.rake_cap,
  });
  assert.equal(room.config.turnTimeSec, 50);
  assert.equal(room.config.autoStartAt, 4);
  assert.equal(room.config.minimumPlayMinutes, 20);
  assert.equal(room.minPlayMinutes, 20);
});

test('turn time registry resolves limits from system_config', async () => {
  const pool = createPool([{ rows: [{ value: limits }] }]);
  assert.equal(await resolveRoomTurnTimeSec(pool, 45), 45);
  assert.match(pool.queries[0].text, /system_config/);
  assert.deepEqual(pool.queries[0].params, ['room_creation_limits']);
});

