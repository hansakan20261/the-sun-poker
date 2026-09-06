const { pool } = require('../db');

const BACKOFFICE_ROLES = new Set(['super_admin', 'admin', 'club_owner', 'club_admin', 'agent']);

async function resolvePermissions(user) {
  const override = await pool.query(
    `SELECT menus, data_scope, club_scope
     FROM user_menu_permissions WHERE user_id = $1`,
    [user.id],
  );
  if (override.rows.length > 0) return { ...override.rows[0], source: 'user' };

  const template = await pool.query(
    `SELECT menus, data_scope, NULL::uuid AS club_scope
     FROM role_permission_templates WHERE role = $1`,
    [user.role],
  );
  if (template.rows.length > 0) return { ...template.rows[0], source: 'role' };
  return { menus: [], data_scope: 'read_only', club_scope: null, source: 'none' };
}

function hasMenu(permissions, menuId) {
  const menus = Array.isArray(permissions?.menus) ? permissions.menus : [];
  return menus.includes('all') || menus.includes(menuId);
}

function backofficeOnly(req, res, next) {
  if (!BACKOFFICE_ROLES.has(req.user.role)) {
    return res.status(403).json({ error: 'Backoffice access required' });
  }
  next();
}

function requireMenu(menuId, { write } = {}) {
  return async (req, res, next) => {
    try {
      const permissions = await resolvePermissions(req.user);
      if (!hasMenu(permissions, menuId)) {
        return res.status(403).json({ error: 'Menu permission required', menu: menuId });
      }
      if (permissions.data_scope === 'own_club' && ['admin', 'super_admin'].includes(req.user.role)) {
        return res.status(403).json({ error: 'This route does not support club-scoped platform access' });
      }
      const writeRequest = write ?? !['GET', 'HEAD', 'OPTIONS'].includes(req.method);
      if (writeRequest && permissions.data_scope === 'read_only') {
        return res.status(403).json({ error: 'Read-only access' });
      }
      req.permissions = permissions;
      next();
    } catch {
      res.status(500).json({ error: 'Unable to resolve permissions' });
    }
  };
}

module.exports = { backofficeOnly, hasMenu, requireMenu, resolvePermissions };
