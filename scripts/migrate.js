#!/usr/bin/env node
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { pool } = require('../services/wallet-service/src/db');

const MIGRATIONS_DIR = path.resolve(__dirname, '../database/migrations');

async function runMigrations() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename VARCHAR(255) PRIMARY KEY,
        executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    const files = fs.readdirSync(MIGRATIONS_DIR)
      .filter(f => f.endsWith('.sql'))
      .sort();

    for (const file of files) {
      const existing = await client.query('SELECT 1 FROM schema_migrations WHERE filename = $1', [file]);
      if (existing.rows.length > 0) {
        console.log(`[SKIP] ${file}`);
        continue;
      }
      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
      console.log(`[RUN] ${file}`);
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [file]);
    }

    await client.query('COMMIT');
    console.log('Migrations complete');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

function runBackfill() {
  console.log('Running room snapshot backfill...');
  const result = spawnSync('node', ['backfill-room-snapshots.js'], {
    cwd: __dirname,
    stdio: 'inherit',
  });
  if (result.status !== 0) {
    throw new Error('Backfill script failed');
  }
}

runMigrations()
  .then(() => runBackfill())
  .catch(err => {
    console.error('Migration failed:', err);
    process.exitCode = 1;
  });
