const { Pool, types } = require('pg');

// Override DATE type (OID 1082) to return raw string instead of JS Date
// This prevents timezone conversion issues (e.g. '2026-05-06' becoming '2026-05-05' in UTC+7)
types.setTypeParser(1082, (val) => val); // return date string as-is

const { databaseConfigFromEnv } = require('../../../config/database-env');

const pool = new Pool(databaseConfigFromEnv());

module.exports = { pool };
