const test = require('node:test');
const assert = require('node:assert/strict');
const { CANDIDATE_SQL, executeCleanup, normalizeCleanupSettings } = require('./src/cleanup-service');

const settings = {
  enabled: true,
  delete_empty_after_minutes: 60,
  delete_all_player_rooms_after_hours: 24,
  only_player_created: true,
  allow_close_occupied_expired: false,
  allow_close_playing: false,
  cleanup_worker_interval_sec: 300,
  version: 2,
};

test('cleanup settings validate all policy fields', () => {
  assert.deepEqual(normalizeCleanupSettings(settings), settings);
  assert.throws(() => normalizeCleanupSettings({ ...settings, cleanup_worker_interval_sec: 10 }), /cleanup_worker_interval_sec/);
  assert.match(CANDIDATE_SQL, /\$4::boolean/);
  assert.match(CANDIDATE_SQL, /gt\.status != 'playing'/);
});

test('cleanup preview returns candidates without updating or auditing', async () => {
  const queries = [];
  const client = {
    query: async (text) => {
      queries.push(text);
      if (text.includes('WITH candidates')) return { rows: [{ id: 'room-1', name: 'Old', reason: 'empty' }] };
      return { rows: [] };
    },
    release: () => {},
  };
  const result = await executeCleanup({ connect: async () => client }, settings, { source: 'preview', dryRun: true });
  assert.equal(result.total_candidates, 1);
  assert.equal(result.total_deleted, 0);
  assert.equal(queries.some(query => query.includes('UPDATE game_tables SET')), false);
  assert.equal(queries.some(query => query.includes('admin_activity_log')), false);
});

test('cleanup closes candidates and writes config version to audit log', async () => {
  const queries = [];
  const client = {
    query: async (text, params) => {
      queries.push({ text, params });
      if (text.includes('WITH candidates')) return { rows: [{ id: '00000000-0000-0000-0000-000000000001', name: 'Old', reason: 'expired' }] };
      return { rows: [] };
    },
    release: () => {},
  };
  const result = await executeCleanup({ connect: async () => client }, settings, { source: 'scheduler' });
  assert.equal(result.total_deleted, 1);
  const audit = queries.find(query => query.text.includes('admin_activity_log'));
  assert.match(audit.params[1], /"config_version":2/);
});
