const ADMIN_ROLES = new Set(['admin', 'super_admin']);

function canGrantRole(actorRole, role) {
  return !ADMIN_ROLES.has(role) || actorRole === 'super_admin';
}

function canModifyRole(actorRole, targetRole) {
  return !ADMIN_ROLES.has(targetRole) || actorRole === 'super_admin';
}

module.exports = { canGrantRole, canModifyRole };
