const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly, superAdminOnly } = require('../middleware/auth');
const { backofficeOnly, requireMenu, resolvePermissions } = require('../middleware/menu-permission');
const { canModifyRole } = require('../admin-security');

const router = express.Router();

router.get('/my', authMiddleware, backofficeOnly, async (req, res) => {
  try {
    const permissions = await resolvePermissions(req.user);
    res.json({ role: req.user.role, ...permissions });
  } catch {
    res.status(500).json({ error: 'Unable to resolve permissions' });
  }
});

router.get('/templates', authMiddleware, adminOnly, requireMenu('menu-permissions'), async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM role_permission_templates ORDER BY role');
    res.json({ templates: result.rows });
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/templates/:role', authMiddleware, superAdminOnly, requireMenu('menu-permissions'), async (req, res) => {
  try {
    const { menus, data_scope } = req.body;
    if (!Array.isArray(menus)) return res.status(400).json({ error: 'menus must be an array' });
    if (!['all', 'own_club', 'read_only'].includes(data_scope)) {
      return res.status(400).json({ error: 'Invalid data_scope' });
    }
    const result = await pool.query(
      `INSERT INTO role_permission_templates (role, menus, data_scope, updated_by, updated_at)
       VALUES ($1, $2, $3, $4, NOW())
       ON CONFLICT (role) DO UPDATE SET menus = $2, data_scope = $3, updated_by = $4, updated_at = NOW()
       RETURNING *`,
      [req.params.role, JSON.stringify(menus), data_scope, req.user.id],
    );
    res.json({ template: result.rows[0] });
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/users/:userId', authMiddleware, adminOnly, requireMenu('menu-permissions'), async (req, res) => {
  try {
    const user = await pool.query('SELECT id, username, role FROM users WHERE id = $1', [req.params.userId]);
    if (user.rows.length === 0) return res.status(404).json({ error: 'User not found' });
    const permissions = await resolvePermissions(user.rows[0]);
    res.json({ user: user.rows[0], permissions });
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/users/:userId', authMiddleware, adminOnly, requireMenu('menu-permissions'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { menus, data_scope, club_scope } = req.body;
    if (!Array.isArray(menus)) return res.status(400).json({ error: 'menus must be an array' });
    if (!['all', 'own_club', 'read_only'].includes(data_scope)) {
      return res.status(400).json({ error: 'Invalid data_scope' });
    }
    const target = await client.query('SELECT role FROM users WHERE id = $1', [req.params.userId]);
    if (target.rows.length === 0) return res.status(404).json({ error: 'User not found' });
    if (!canModifyRole(req.user.role, target.rows[0].role)) {
      return res.status(403).json({ error: 'Only super admin can modify administrator permissions' });
    }
    await client.query('BEGIN');
    const before = await client.query('SELECT * FROM user_menu_permissions WHERE user_id = $1', [req.params.userId]);
    const result = await client.query(
      `INSERT INTO user_menu_permissions (user_id, menus, data_scope, club_scope, updated_by, updated_at)
       VALUES ($1, $2, $3, $4, $5, NOW())
       ON CONFLICT (user_id) DO UPDATE SET menus = $2, data_scope = $3, club_scope = $4, updated_by = $5, updated_at = NOW()
       RETURNING *`,
      [req.params.userId, JSON.stringify(menus), data_scope, club_scope || null, req.user.id],
    );
    await client.query(
      `INSERT INTO menu_permission_audit_log (user_id, admin_id, before_value, after_value)
       VALUES ($1, $2, $3, $4)`,
      [req.params.userId, req.user.id, JSON.stringify(before.rows[0] || null), JSON.stringify(result.rows[0])],
    );
    await client.query('COMMIT');
    res.json({ permissions: result.rows[0] });
  } catch {
    await client.query('ROLLBACK');
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

router.delete('/users/:userId', authMiddleware, adminOnly, requireMenu('menu-permissions'), async (req, res) => {
  try {
    const target = await pool.query('SELECT role FROM users WHERE id = $1', [req.params.userId]);
    if (target.rows.length === 0) return res.status(404).json({ error: 'User not found' });
    if (!canModifyRole(req.user.role, target.rows[0].role)) {
      return res.status(403).json({ error: 'Only super admin can modify administrator permissions' });
    }
    await pool.query('DELETE FROM user_menu_permissions WHERE user_id = $1', [req.params.userId]);
    res.json({ success: true });
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
