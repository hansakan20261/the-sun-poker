const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { canAccessRoom, isAdminRole, verifyRoomAccessToken } = require('./src/security');
const { cashOut, deductBuyIn } = require('./src/game-wallet');

function createPool(responses) {
  const queries = [];
  const client = {
    query: async (text, params) => {
      queries.push({ text, params });
      return responses.shift() || { rows: [] };
    },
    release: () => {},
  };
  return { pool: { connect: async () => client }, queries };
}

test('buy-in locks wallet and records a wallet session atomically', async () => {
  const { pool, queries } = createPool([
    { rows: [] },
    { rows: [{ balance: 1000 }] },
    { rows: [{ balance: 600 }] },
    { rows: [] },
    { rows: [] },
    { rows: [] },
  ]);
  const result = await deductBuyIn(pool, { userId: 'user-1', tableId: 'table-1', amount: 400 });
  assert.equal(result.balance, 600);
  assert.match(queries[1].text, /FOR UPDATE/);
  assert.match(queries[3].text, /game_wallet_sessions/);
  assert.equal(queries.at(-1).text, 'COMMIT');
});

test('duplicate cashout does not credit wallet twice', async () => {
  const { pool, queries } = createPool([
    { rows: [] },
    { rows: [] },
    { rows: [] },
  ]);
  const settled = await cashOut(pool, {
    sessionId: 'session-1', userId: 'user-1', tableId: 'table-1', amount: 400,
  });
  assert.equal(settled, false);
  assert.equal(queries.some(({ text }) => text.startsWith('UPDATE wallets')), false);
});

test('tournament controls accept only administrator roles', () => {
  assert.equal(isAdminRole('super_admin'), true);
  assert.equal(isAdminRole('admin'), true);
  assert.equal(isAdminRole('agent'), false);
  assert.equal(isAdminRole('player'), false);
});

test('private room access requires a user and table scoped token', () => {
  process.env.JWT_SECRET = 'test-secret';
  const token = jwt.sign(
    { purpose: 'room_access', tableId: 'table-1', userId: 'user-1' },
    process.env.JWT_SECRET,
    { expiresIn: '5m' },
  );
  assert.equal(verifyRoomAccessToken(token, 'table-1', 'user-1'), true);
  assert.equal(verifyRoomAccessToken(token, 'table-2', 'user-1'), false);
  assert.equal(verifyRoomAccessToken(token, 'table-1', 'user-2'), false);
});

test('existing player can reconnect to a private room', () => {
  const room = {
    tableId: 'table-1',
    isPrivate: true,
    players: new Map([[1, { id: 'user-1' }]]),
  };
  const socket = { user: { id: 'user-1' } };
  assert.equal(canAccessRoom(room, socket), true);
});

test('public room does not require an access token', () => {
  const room = { tableId: 'table-1', isPrivate: false, players: new Map() };
  assert.equal(canAccessRoom(room, { user: { id: 'user-1' } }), true);
});
