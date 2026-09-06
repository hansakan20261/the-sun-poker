const test = require('node:test');
const assert = require('node:assert/strict');
const { loadGameRuntime, validateGameRuntime } = require('./src/runtime-config');
const { bootstrapValue } = require('../../config/config-platform');

const runtime = bootstrapValue('game_runtime');

test('game runtime validates every required field', () => {
  assert.deepEqual(validateGameRuntime(runtime), runtime);
  assert.throws(() => validateGameRuntime({ ...runtime, auto_deal_delay_sec: -1 }), /auto_deal_delay_sec/);
  assert.throws(() => validateGameRuntime({ ...runtime, socket_reconnect_attempts: undefined }), /socket_reconnect_attempts/);
});

test('game runtime loads from system_config', async () => {
  const queries = [];
  const pool = { query: async (text, params) => { queries.push({ text, params }); return { rows: [{ value: runtime }] }; } };
  assert.deepEqual(await loadGameRuntime(pool), runtime);
  assert.match(queries[0].text, /system_config/);
  assert.deepEqual(queries[0].params, ['game_runtime']);
});
