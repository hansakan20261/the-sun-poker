const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { createSession, loadSessionUser, revokeSession } = require('./src/session');
const { bootstrapValue } = require('../../config/config-platform');

const securityPolicy = bootstrapValue('security_policy');

test('created JWT is bound to a persisted session and configured expiry', async () => {
  process.env.JWT_SECRET = 'test-secret';
  const calls = [];
  const pool = {
    query: async (text, params) => {
      calls.push({ text, params });
      if (text.includes('FROM system_config')) return { rows: [{ value: securityPolicy }] };
      return { rows: [] };
    },
  };
  const token = await createSession(pool, { id: 'user-1', username: 'user', role: 'player' });
  const payload = jwt.verify(token, process.env.JWT_SECRET);
  assert.equal(payload.id, 'user-1');
  assert.equal(typeof payload.sid, 'string');
  assert.equal(payload.exp - payload.iat, securityPolicy.access_token_minutes * 60);
  assert.match(calls[1].text, /UPDATE user_sessions/);
  assert.match(calls[2].text, /INSERT INTO user_sessions/);
  assert.equal(calls[2].params[0], payload.sid);
  assert.equal(calls[2].params[4], securityPolicy.session_days);
});

test('revoked or missing sessions are rejected', async () => {
  const pool = { query: async () => ({ rows: [] }) };
  assert.equal(await loadSessionUser(pool, { id: 'user-1', sid: 'session-1' }), null);
  assert.equal(await revokeSession(pool, null, 'user-1'), false);
});
