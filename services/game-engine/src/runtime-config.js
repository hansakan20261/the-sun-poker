const { CONFIG_DEFINITIONS } = require('../../../config/config-definitions');

const FIELDS = Object.freeze(Object.fromEntries(
  Object.entries(CONFIG_DEFINITIONS.game_runtime.fields)
    .map(([key, definition]) => [key, { min: definition.min, max: definition.max, type: definition.type }]),
));

function validateGameRuntime(value) {
  const result = {};
  for (const [key, bounds] of Object.entries(FIELDS)) {
    const number = Number(value?.[key]);
    const validNumber = bounds.type === 'integer' ? Number.isInteger(number) : Number.isFinite(number);
    if (!validNumber || number < bounds.min || number > bounds.max) {
      throw new Error(`${key} must be ${bounds.type === 'integer' ? 'an integer' : 'a number'} between ${bounds.min} and ${bounds.max}`);
    }
    result[key] = number;
  }
  return result;
}

async function loadGameRuntime(pool) {
  return loadSystemConfig(pool, 'game_runtime');
}

async function loadSystemConfig(pool, key) {
  const result = await pool.query('SELECT value FROM system_config WHERE key = $1', [key]);
  if (result.rows.length === 0) throw new Error(`${key} config is required`);
  return key === 'game_runtime'
    ? validateGameRuntime(result.rows[0].value)
    : require('../../../config/config-platform').validateConfig(key, result.rows[0].value);
}

module.exports = { FIELDS, loadGameRuntime, loadSystemConfig, validateGameRuntime };
