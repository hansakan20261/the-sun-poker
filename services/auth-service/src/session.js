const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { loadSecurityPolicy } = require('./security-policy');

async function createSession(pool, user, metadata = {}) {
  const policy = await loadSecurityPolicy(pool);
  const sessionId = crypto.randomUUID();
  const token = jwt.sign(
    { id: user.id, username: user.username, role: user.role, sid: sessionId },
    process.env.JWT_SECRET,
    { expiresIn: policy.access_token_minutes * 60 },
  );

  await pool.query(
    `UPDATE user_sessions SET revoked_at = NOW()
     WHERE id IN (
       SELECT id FROM user_sessions
       WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > NOW()
       ORDER BY last_seen_at ASC NULLS FIRST, created_at ASC
       OFFSET $2
     )`,
    [user.id, Math.max(policy.max_sessions_per_user - 1, 0)],
  );

  await pool.query(
    `INSERT INTO user_sessions (id, user_id, device_info, ip_address, expires_at)
     VALUES ($1, $2, $3, $4, NOW() + INTERVAL '1 day' * $5)`,
    [
      sessionId,
      user.id,
      JSON.stringify(metadata.deviceInfo || {}),
      metadata.ipAddress || null,
      policy.session_days,
    ],
  );
  return token;
}

async function revokeSession(pool, sessionId, userId) {
  if (!sessionId) return false;
  const result = await pool.query(
    `UPDATE user_sessions SET revoked_at = NOW()
     WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL
     RETURNING id`,
    [sessionId, userId],
  );
  return result.rows.length > 0;
}

async function loadSessionUser(pool, payload) {
  if (!payload.sid) return null;
  const result = await pool.query(
    `SELECT u.id, u.username, u.email, u.phone, u.display_name,
            u.first_name, u.last_name, u.avatar_url, u.role,
            u.vip_level, u.locale, u.created_at, w.balance
     FROM users u
     JOIN user_sessions s ON s.user_id = u.id AND s.id = $2
     LEFT JOIN wallets w ON w.user_id = u.id
     WHERE u.id = $1 AND u.is_suspended = FALSE
       AND s.revoked_at IS NULL AND s.expires_at > NOW()`,
    [payload.id, payload.sid],
  );
  if (result.rows.length === 0) return null;
  await pool.query('UPDATE user_sessions SET last_seen_at = NOW() WHERE id = $1', [payload.sid]);
  return result.rows[0];
}

module.exports = { createSession, loadSessionUser, revokeSession };
