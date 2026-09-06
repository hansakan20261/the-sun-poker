const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { body, validationResult } = require('express-validator');
const { pool } = require('../db');
const { createSession, loadSessionUser, revokeSession } = require('../session');
const { loadSecurityPolicy, loadSystemPolicy } = require('../security-policy');

const router = express.Router();

// POST /auth/register
router.post('/register', [
  body('username').isLength({ min: 3, max: 50 }).trim(),
  body('password').isLength({ min: 1 }),
  body('email').optional().isEmail(),
  body('phone').optional().isMobilePhone(),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { username, password, email, phone, display_name } = req.body;
    const [securityPolicy, economyPolicy] = await Promise.all([
      loadSecurityPolicy(pool),
      loadSystemPolicy(pool, 'wallet_economy_policy'),
    ]);
    if (password.length < securityPolicy.password_min_length) {
      return res.status(400).json({ error: `Password must be at least ${securityPolicy.password_min_length} characters` });
    }

    // Check if username exists
    const existing = await pool.query(
      'SELECT id FROM users WHERE username = $1', [username]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Username already exists' });
    }

    // Hash password
    const password_hash = await bcrypt.hash(password, securityPolicy.password_hash_rounds);

    // Create user
    const result = await pool.query(
      `INSERT INTO users (username, password_hash, email, phone, display_name)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, username, email, phone, display_name, role, created_at`,
      [username, password_hash, email, phone, display_name || username]
    );

    const user = result.rows[0];

    // Create wallet
    await pool.query(
      'INSERT INTO wallets (user_id, balance) VALUES ($1, $2)', [user.id, economyPolicy.initial_wallet_balance]
    );

    // Create player_stats
    await pool.query(
      'INSERT INTO player_stats (user_id) VALUES ($1)', [user.id]
    );

    // Generate JWT
    const token = await createSession(pool, user, {
      deviceInfo: req.body.device_info,
      ipAddress: req.ip,
    });

    res.status(201).json({ user, token });
  } catch (err) {
    console.error('Register error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /auth/login
router.post('/login', [
  body('username').notEmpty(),
  body('password').notEmpty(),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { username, password } = req.body;
    const securityPolicy = await loadSecurityPolicy(pool);

    // Find user
    const result = await pool.query(
      `SELECT id, username, email, phone, display_name, password_hash,
              role, is_suspended, avatar_url, failed_login_attempts, locked_until
       FROM users WHERE username = $1 OR email = $1`,
      [username]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];

    if (user.is_suspended) {
      return res.status(403).json({ error: 'Account suspended' });
    }
    if (user.locked_until && new Date(user.locked_until) > new Date()) {
      return res.status(423).json({ error: 'Account temporarily locked', locked_until: user.locked_until });
    }

    // Verify password
    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      await pool.query(
        `UPDATE users
         SET failed_login_attempts = COALESCE(failed_login_attempts, 0) + 1,
             locked_until = CASE
               WHEN COALESCE(failed_login_attempts, 0) + 1 >= $2
               THEN NOW() + INTERVAL '1 minute' * $3
               ELSE NULL
             END,
             updated_at = NOW()
         WHERE id = $1`,
        [user.id, securityPolicy.login_max_attempts, securityPolicy.login_lockout_minutes],
      );
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Update last login
    await pool.query(
      `UPDATE users SET last_login_at = NOW(), login_count = login_count + 1,
       failed_login_attempts = 0, locked_until = NULL
       WHERE id = $1`, [user.id]
    );

    // Get wallet balance
    const wallet = await pool.query(
      'SELECT balance FROM wallets WHERE user_id = $1', [user.id]
    );
    if (wallet.rows.length === 0) throw new Error('Wallet is required');

    // Generate JWT
    const token = await createSession(pool, user, {
      deviceInfo: req.body.device_info,
      ipAddress: req.ip,
    });

    const { password_hash, ...userWithoutPassword } = user;

    res.json({
      user: {
        ...userWithoutPassword,
        balance: Number(wallet.rows[0].balance),
      },
      token,
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /auth/me (ต้องมี token)
router.get('/me', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      return res.status(401).json({ error: 'No token provided' });
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user = await loadSessionUser(pool, decoded);

    if (!user) {
      return res.status(401).json({ error: 'Session unavailable' });
    }

    res.json({ user });
  } catch (err) {
    if (err.name === 'JsonWebTokenError') {
      return res.status(401).json({ error: 'Invalid token' });
    }
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/logout', async (req, res) => {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'No token provided' });
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    await revokeSession(pool, payload.sid, payload.id);
    res.json({ success: true });
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
});

module.exports = router;

// POST /auth/forgot-password — User รีเซ็ตรหัสผ่านเอง (ใช้ username + email ยืนยัน)
router.post('/forgot-password', [
  body('username').notEmpty(),
  body('email').isEmail(),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { username, email, new_password } = req.body;

    // ตรวจสอบว่า username + email ตรงกัน
    const result = await pool.query(
      'SELECT id FROM users WHERE username = $1 AND email = $2', [username, email]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'ไม่พบบัญชีที่ตรงกับ username และ email นี้' });
    }

    const securityPolicy = await loadSecurityPolicy(pool);
    if (!new_password || new_password.length < securityPolicy.password_min_length) {
      return res.status(400).json({ error: `รหัสผ่านใหม่ต้องมีอย่างน้อย ${securityPolicy.password_min_length} ตัวอักษร` });
    }

    const hash = await bcrypt.hash(new_password, securityPolicy.password_hash_rounds);
    await pool.query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2',
      [hash, result.rows[0].id]);

    res.json({ success: true, message: 'เปลี่ยนรหัสผ่านสำเร็จ' });
  } catch (err) {
    console.error('Forgot password error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});
