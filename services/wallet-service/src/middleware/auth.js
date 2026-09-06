const jwt = require('jsonwebtoken');
const { pool } = require('../db');

async function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: 'No token provided' });

  const token = authHeader.split(' ')[1];
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    if (!payload.sid) return res.status(401).json({ error: 'Session required' });
    const result = await pool.query(
      `SELECT u.id, u.username, u.role, u.is_suspended
       FROM users u
       JOIN user_sessions s ON s.user_id = u.id AND s.id = $2
       WHERE u.id = $1 AND s.revoked_at IS NULL AND s.expires_at > NOW()`,
      [payload.id, payload.sid],
    );
    const user = result.rows[0];
    if (!user || user.is_suspended) {
      return res.status(401).json({ error: 'Account unavailable' });
    }
    pool.query('UPDATE user_sessions SET last_seen_at = NOW() WHERE id = $1', [payload.sid]).catch(() => {});
    req.user = { ...payload, username: user.username, role: user.role };
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

function adminOnly(req, res, next) {
  if (!['admin', 'super_admin'].includes(req.user.role)) {
    return res.status(403).json({ error: 'Admin access required' });
  }
  next();
}

function superAdminOnly(req, res, next) {
  if (req.user.role !== 'super_admin') {
    return res.status(403).json({ error: 'Super admin access required' });
  }
  next();
}

module.exports = { authMiddleware, adminOnly, superAdminOnly };
