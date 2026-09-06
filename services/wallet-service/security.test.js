const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const {
  hashRoomPassword,
  isHashedPassword,
  issueRoomAccessToken,
  sanitizeTable,
  verifyRoomPassword,
} = require('./src/room-security');
const { canGrantRole, canModifyRole } = require('./src/admin-security');
const { hasMenu } = require('./src/middleware/menu-permission');
const { normalizeGameRuntime, normalizeRoomInput } = require('./src/config-service');
const { bootstrapValue } = require('../../config/config-platform');

test('menu access is denied by default and supports explicit or all grants', () => {
  assert.equal(hasMenu({ menus: [] }, 'users'), false);
  assert.equal(hasMenu({ menus: ['users'] }, 'users'), true);
  assert.equal(hasMenu({ menus: ['all'] }, 'users'), true);
});

test('regular admin cannot grant or modify administrator roles', () => {
  assert.equal(canGrantRole('admin', 'admin'), false);
  assert.equal(canGrantRole('admin', 'super_admin'), false);
  assert.equal(canModifyRole('admin', 'super_admin'), false);
  assert.equal(canGrantRole('admin', 'player'), true);
});

test('super admin can manage administrator roles', () => {
  assert.equal(canGrantRole('super_admin', 'admin'), true);
  assert.equal(canGrantRole('super_admin', 'super_admin'), true);
  assert.equal(canModifyRole('super_admin', 'admin'), true);
});

test('sanitizeTable removes room password', () => {
  assert.deepEqual(
    sanitizeTable({ id: 'table-1', password: 'secret', name: 'Private' }),
    { id: 'table-1', name: 'Private', has_password: true },
  );
});

test('room passwords are hashed and verified', async () => {
  const hash = await hashRoomPassword('secret', 12);
  assert.equal(isHashedPassword(hash), true);
  assert.equal(await verifyRoomPassword('secret', hash), true);
  assert.equal(await verifyRoomPassword('wrong', hash), false);
});

test('legacy plaintext room passwords remain verifiable for migration', async () => {
  assert.equal(await verifyRoomPassword('legacy', 'legacy'), true);
  assert.equal(await verifyRoomPassword('wrong', 'legacy'), false);
});

test('game runtime rejects missing or out-of-range values', () => {
  const runtime = bootstrapValue('game_runtime');
  assert.deepEqual(normalizeGameRuntime(runtime), runtime);
  assert.throws(() => normalizeGameRuntime({ ...runtime, idle_timeout_sec: 1 }), /idle_timeout_sec/);
});

test('room config normalizes auto-start threshold and delay from configured bounds', () => {
  const defaults = {
    small_blind: 10, big_blind: 20, ante: 0, min_buy_in: 400, max_buy_in: 2000,
    max_players: 9, turn_time_sec: 30, auto_start_at: 2, auto_start_delay_sec: 2,
    minimum_play_minutes: 30, rake_percent: 5.5, rake_cap: 0,
  };
  const limits = {
    min_small_blind: 5, max_small_blind: 1000, min_players: 2, max_players: 9,
    min_turn_time_sec: 10, max_turn_time_sec: 60,
    min_auto_start_delay_sec: 0, max_auto_start_delay_sec: 30,
    min_minimum_play_minutes: 0, max_minimum_play_minutes: 1440,
    allowed_modes: ['cash', 'private'], allowed_visibility: ['public', 'private'],
    room_expiration_hours: 24, min_ante: 0, max_ante: 10000, private_room_enabled: true,
    room_name_min_length: 1, room_name_max_length: 100,
    room_password_min_length: 4, room_password_max_length: 100,
    min_buy_in_chips: 0, max_buy_in_chips: 1000000,
    min_rake_percent: 0, max_rake_percent: 20, max_rake_cap: 1000000,
  };
  assert.throws(
    () => normalizeRoomInput({ max_players: 4, auto_start_at: 8, auto_start_delay_sec: 90 }, defaults, limits),
    /auto_start_at cannot exceed max_players/,
  );
});

test('room access token is scoped to user and table', () => {
  process.env.JWT_SECRET = 'test-secret';
  const token = issueRoomAccessToken('table-1', 'user-1', 7);
  const payload = jwt.verify(token, process.env.JWT_SECRET);
  assert.equal(payload.purpose, 'room_access');
  assert.equal(payload.tableId, 'table-1');
  assert.equal(payload.userId, 'user-1');
  assert.equal(payload.exp - payload.iat, 7 * 60);
});
