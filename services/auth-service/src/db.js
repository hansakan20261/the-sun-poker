const { Pool } = require('pg');
const { databaseConfigFromEnv } = require('../../../config/database-env');

const pool = new Pool(databaseConfigFromEnv());

pool.on('connect', () => {
  console.log('📦 Connected to PostgreSQL');
});

module.exports = { pool };
