const { loadConfigRow } = require('../../../config/config-platform');

async function loadSystemPolicy(pool, key) {
  const row = await loadConfigRow(pool, key);
  return row.value;
}

async function loadSecurityPolicy(pool) {
  return loadSystemPolicy(pool, 'security_policy');
}

module.exports = { loadSecurityPolicy, loadSystemPolicy };
