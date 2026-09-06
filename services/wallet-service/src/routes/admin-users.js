const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { canGrantRole, canModifyRole } = require('../admin-security');
const { getConfig } = require('../config-service');

const router = express.Router();

async function protectPrivilegedTarget(req, res, next) {
  try {
    const result = await pool.query('SELECT role FROM users WHERE id = $1', [req.params.id]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'User not found' });
    if (!canModifyRole(req.user.role, result.rows[0].role)) {
      return res.status(403).json({ error: 'Only super admin can modify administrator accounts' });
    }
    next();
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
}

// GET /admin/users — ดูรายชื่อผู้ใช้ทั้งหมด
router.get('/', authMiddleware, adminOnly, requireMenu('users'), async (req, res) => {
  try {
    const { search, role, status, limit = 20, offset = 0 } = req.query;
    let query = `SELECT u.id, u.username, u.email, u.phone, u.display_name,
                        u.role, u.is_suspended, u.is_verified, u.vip_level,
                        u.last_login_at, u.created_at, w.balance
                 FROM users u LEFT JOIN wallets w ON w.user_id = u.id WHERE 1=1`;
    const params = [];

    if (search) {
      params.push(`%${search}%`);
      query += ` AND (u.username ILIKE $${params.length} OR u.email ILIKE $${params.length} OR u.phone ILIKE $${params.length} OR u.display_name ILIKE $${params.length})`;
    }
    if (role) { params.push(role); query += ` AND u.role = $${params.length}`; }
    if (status === 'suspended') query += ' AND u.is_suspended = TRUE';
    if (status === 'active') query += ' AND u.is_suspended = FALSE';

    // Count total
    const countParams = [...params];
    const countQuery = `SELECT COUNT(*) as total FROM users u WHERE 1=1` +
      query.split('WHERE 1=1')[1].split('ORDER BY')[0];
    const countResult = await pool.query(countQuery, countParams);

    params.push(Number(limit));
    query += ` ORDER BY u.created_at DESC LIMIT $${params.length}`;
    params.push(Number(offset));
    query += ` OFFSET $${params.length}`;

    const result = await pool.query(query, params);
    res.json({
      users: result.rows,
      total: Number(countResult.rows[0].total),
      limit: Number(limit),
      offset: Number(offset),
    });
  } catch (err) {
    console.error('List users error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /admin/users — Admin สร้างบัญชีผู้ใช้ใหม่
router.post('/', authMiddleware, adminOnly, requireMenu('users'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { username, password, email, phone, display_name, role, initial_balance } = req.body;
    const [securityPolicy, policy] = await Promise.all([
      getConfig(pool, 'security_policy'),
      getConfig(pool, 'wallet_economy_policy'),
    ]);
    if (!username || !password) return res.status(400).json({ error: 'username and password required' });
    if (password.length < securityPolicy.password_min_length) {
      return res.status(400).json({ error: `password must be at least ${securityPolicy.password_min_length} characters` });
    }
    if (!canGrantRole(req.user.role, role)) {
      return res.status(403).json({ error: 'Only super admin can create administrator accounts' });
    }
    
    await client.query('BEGIN');
    
    const passwordHash = await bcrypt.hash(password, securityPolicy.password_hash_rounds);
    const userRole = role && ['player', 'agent', 'club_owner', 'club_admin', 'admin', 'super_admin'].includes(role) ? role : securityPolicy.default_user_role;
    
    const userResult = await client.query(
      `INSERT INTO users (username, password_hash, email, phone, display_name, role, is_verified)
       VALUES ($1, $2, $3, $4, $5, $6, TRUE) RETURNING id, username, email, phone, display_name, role, created_at`,
      [username, passwordHash, email || null, phone || null, display_name || username, userRole]
    );
    const user = userResult.rows[0];
    
    // Create wallet with optional initial balance
    const balance = initial_balance === undefined ? policy.initial_wallet_balance : Number(initial_balance);
    if (!Number.isInteger(balance) || balance < 0 || balance > policy.max_balance) {
      await client.query('ROLLBACK').catch(() => {});
      return res.status(400).json({ error: `Initial balance must be between 0 and ${policy.max_balance}` });
    }
    await client.query('INSERT INTO wallets (user_id, balance) VALUES ($1, $2)', [user.id, balance]);
    
    // Create player_stats
    await client.query('INSERT INTO player_stats (user_id) VALUES ($1)', [user.id]);
    
    // Log activity
    await client.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'create_user', 'user', $2, $3)`,
      [req.user.id, user.id, JSON.stringify({ username, role: userRole, initial_balance: balance })]
    );
    
    await client.query('COMMIT');
    res.status(201).json({ user: { ...user, balance }, success: true });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') return res.status(409).json({ error: 'Username already exists' });
    console.error('Create user error:', err);
    res.status(500).json({ error: 'Internal server error' });
  } finally { client.release(); }
});

// GET /admin/users/:id — ดูรายละเอียดผู้ใช้
router.get('/:id', authMiddleware, adminOnly, requireMenu('users'), async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.*, w.balance,
              ps.total_games, ps.total_wins, ps.win_rate, ps.hands_played,
              ar.referred_at,
              ag.agent_code, ag.display_name as agent_name,
              ac.channel_name, ac.referral_code
       FROM users u
       LEFT JOIN wallets w ON w.user_id = u.id
       LEFT JOIN player_stats ps ON ps.user_id = u.id
       LEFT JOIN agent_referrals ar ON ar.user_id = u.id
       LEFT JOIN agents ag ON ag.id = ar.agent_id
       LEFT JOIN agent_channels ac ON ac.id = ar.channel_id
       WHERE u.id = $1`, [req.params.id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'User not found' });
    const { password_hash, two_fa_secret, ...user } = result.rows[0];
    res.json({ user });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /admin/users/:id/suspend — ระงับบัญชี
router.put('/:id/suspend', authMiddleware, adminOnly, requireMenu('users'), protectPrivilegedTarget, async (req, res) => {
  try {
    const { reason } = req.body;
    await pool.query('UPDATE users SET is_suspended = TRUE, updated_at = NOW() WHERE id = $1', [req.params.id]);
    await pool.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'suspend_user', 'user', $2, $3)`,
      [req.user.id, req.params.id, JSON.stringify({ reason })]
    );
    res.json({ success: true, message: 'User suspended' });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /admin/users/:id/unsuspend — ปลดระงับ
router.put('/:id/unsuspend', authMiddleware, adminOnly, requireMenu('users'), protectPrivilegedTarget, async (req, res) => {
  try {
    await pool.query('UPDATE users SET is_suspended = FALSE, updated_at = NOW() WHERE id = $1', [req.params.id]);
    await pool.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'unsuspend_user', 'user', $2, '{}')`,
      [req.user.id, req.params.id]
    );
    res.json({ success: true, message: 'User unsuspended' });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /admin/users/:id/reset-password — รีเซ็ตรหัสผ่าน
router.put('/:id/reset-password', authMiddleware, adminOnly, requireMenu('users'), protectPrivilegedTarget, async (req, res) => {
  try {
    const securityPolicy = await getConfig(pool, 'security_policy');
    const newPassword = `Sun${crypto.randomBytes(6).toString('base64url')}!`;
    const hash = await bcrypt.hash(newPassword, securityPolicy.password_hash_rounds);
    await pool.query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2', [hash, req.params.id]);
    await pool.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'reset_password', 'user', $2, '{}')`,
      [req.user.id, req.params.id]
    );
    res.json({ success: true, new_password: newPassword });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /admin/users/:id/set-password — ตั้งรหัสผ่านใหม่ (admin กำหนดเอง)
router.put('/:id/set-password', authMiddleware, adminOnly, requireMenu('users'), protectPrivilegedTarget, async (req, res) => {
  try {
    const { new_password } = req.body;
    const securityPolicy = await getConfig(pool, 'security_policy');
    if (!new_password || new_password.length < securityPolicy.password_min_length) {
      return res.status(400).json({ error: `รหัสผ่านต้องมีอย่างน้อย ${securityPolicy.password_min_length} ตัวอักษร` });
    }
    const hash = await bcrypt.hash(new_password, securityPolicy.password_hash_rounds);
    await pool.query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2', [hash, req.params.id]);
    await pool.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'set_password', 'user', $2, '{}')`,
      [req.user.id, req.params.id]
    );
    res.json({ success: true, message: 'ตั้งรหัสผ่านใหม่สำเร็จ' });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /admin/users/:id/role — เปลี่ยน role
router.put('/:id/role', authMiddleware, adminOnly, requireMenu('users'), protectPrivilegedTarget, async (req, res) => {
  try {
    const { role } = req.body;
    if (!['player', 'agent', 'club_owner', 'club_admin', 'admin', 'super_admin'].includes(role)) {
      return res.status(400).json({ error: 'Invalid role' });
    }
    if (!canGrantRole(req.user.role, role)) {
      return res.status(403).json({ error: 'Only super admin can grant administrator roles' });
    }
    if (req.params.id === req.user.id && role !== 'super_admin') {
      return res.status(400).json({ error: 'Super admin cannot demote the active account' });
    }
    await pool.query('UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2', [role, req.params.id]);
    await pool.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'change_role', 'user', $2, $3)`,
      [req.user.id, req.params.id, JSON.stringify({ role })]
    );
    res.json({ success: true, role });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /admin/users/:id/transactions — ประวัติธุรกรรมของผู้ใช้
router.get('/:id/transactions', authMiddleware, adminOnly, requireMenu('users'), async (req, res) => {
  try {
    const { limit = 20, offset = 0 } = req.query;
    const result = await pool.query(
      `SELECT * FROM transactions WHERE user_id = $1
       ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
      [req.params.id, Number(limit), Number(offset)]
    );
    res.json({ transactions: result.rows });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
