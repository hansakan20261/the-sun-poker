const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');

const router = express.Router();

// GET /admin/permissions/:userId — ดูสิทธิ์ของผู้ใช้
router.get('/:userId', authMiddleware, adminOnly, requireMenu('users'), async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM user_permissions WHERE user_id = $1 ORDER BY permission_key', [req.params.userId]
    );
    res.json({ permissions: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/permissions/:userId/block — บล็อกสิทธิ์
router.put('/:userId/block', authMiddleware, adminOnly, requireMenu('users'), async (req, res) => {
  try {
    const { permission_key, reason, expires_at } = req.body;
    await pool.query(
      `INSERT INTO user_permissions (user_id, permission_key, is_allowed, blocked_by, blocked_reason, blocked_at, expires_at)
       VALUES ($1, $2, FALSE, $3, $4, NOW(), $5)
       ON CONFLICT (user_id, permission_key) DO UPDATE SET
       is_allowed = FALSE, blocked_by = $3, blocked_reason = $4, blocked_at = NOW(), expires_at = $5`,
      [req.params.userId, permission_key, req.user.id, reason, expires_at || null]
    );
    await pool.query(
      `INSERT INTO permission_audit_log (user_id, admin_id, action, permission_key, reason)
       VALUES ($1, $2, 'block', $3, $4)`,
      [req.params.userId, req.user.id, permission_key, reason]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/permissions/:userId/unblock — ปลดบล็อก
router.put('/:userId/unblock', authMiddleware, adminOnly, requireMenu('users'), async (req, res) => {
  try {
    const { permission_key } = req.body;
    await pool.query(
      'DELETE FROM user_permissions WHERE user_id = $1 AND permission_key = $2',
      [req.params.userId, permission_key]
    );
    await pool.query(
      `INSERT INTO permission_audit_log (user_id, admin_id, action, permission_key, reason)
       VALUES ($1, $2, 'unblock', $3, 'Admin unblock')`,
      [req.params.userId, req.user.id, permission_key]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
