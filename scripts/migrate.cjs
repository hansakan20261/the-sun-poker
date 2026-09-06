#!/usr/bin/env node
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { pool } = require('../services/wallet-service/src/db');

const MIGRATIONS_DIR = path.resolve(__dirname, '../database/migrations');
const INIT_DIR = path.resolve(__dirname, '../database/init');

async function applySqlFiles(client, dir, files) {
  for (const file of files) {
    const existing = await client.query('SELECT 1 FROM schema_migrations WHERE filename = $1', [file]);
    if (existing.rows.length > 0) {
      console.log(`[SKIP] ${file}`);
      continue;
    }
    const sql = fs.readFileSync(path.join(dir, file), 'utf8');
    console.log(`[RUN] ${file}`);
    await client.query(sql);
    await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [file]);
  }
}

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

    const applied = await client.query('SELECT COUNT(*)::int AS count FROM schema_migrations');
    const isFresh = applied.rows[0].count === 0;

    const files = fs.readdirSync(MIGRATIONS_DIR)
      .filter(f => f.endsWith('.sql'))
      .sort();

    if (isFresh && fs.existsSync(INIT_DIR) && !process.env.SKIP_INIT) {
      const initFiles = fs.readdirSync(INIT_DIR)
        .filter(f => f.endsWith('.sql'))
        .sort();
      await applySqlFiles(client, INIT_DIR, initFiles);
    }

    if (isFresh && process.env.SKIP_INIT) {
      for (const file of files) {
        if (fs.existsSync(path.join(INIT_DIR, file))) {
          await client.query(
            'INSERT INTO schema_migrations (filename) VALUES ($1) ON CONFLICT DO NOTHING',
            [file]
          );
        }
      }
    }

    await applySqlFiles(client, MIGRATIONS_DIR, files);

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
  const result = spawnSync('node', ['backfill-room-snapshots.cjs'], {
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
