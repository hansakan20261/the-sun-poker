require('dotenv').config();
const { pool } = require('../services/wallet-service/src/db');
const { resolveRoomConfig, roomSnapshotPayload } = require('../config/config-platform');

const roomFields = [
  'max_players', 'small_blind', 'big_blind', 'ante', 'min_buy_in', 'max_buy_in',
  'turn_time_sec', 'auto_start_at', 'auto_start_delay_sec', 'minimum_play_minutes',
  'rake_percent', 'rake_cap',
];

async function main() {
  const client = await pool.connect();
  try {
    // Clear stale scalar snapshots and fix invalid small_blind before resolving
    await client.query('UPDATE game_tables SET config_snapshot = NULL');
    await client.query(
      `UPDATE game_tables
       SET small_blind = LEAST(1000, GREATEST(5, FLOOR(big_blind / 2)))
       WHERE small_blind IS NULL OR small_blind < 5 OR small_blind > 1000`,
    );

    const tables = await client.query(
      'SELECT id, game_type_id, room_template_id FROM game_tables ORDER BY created_at ASC',
    );
    let updated = 0;
    let mismatched = 0;
    for (const row of tables.rows) {
      const before = await client.query('SELECT * FROM game_tables WHERE id = $1', [row.id]);
      const beforeRow = before.rows[0];
      const beforeValues = Object.fromEntries(roomFields.map(f => [f, beforeRow[f]]));

      const effective = await resolveRoomConfig(client, {
        gameTypeId: row.game_type_id,
        templateId: row.room_template_id,
        tableId: row.id,
      });

      const payload = roomSnapshotPayload(effective);

      const beforeAndAfterEqual = roomFields.every(f => {
        const a = beforeValues[f];
        const b = effective.value[f];
        return a === b || (a == null && b == null);
      });

      if (!beforeAndAfterEqual) {
        mismatched++;
        console.warn(`[MISMATCH] table ${row.id}:`, { before: beforeValues, after: effective.value });
      }

      await client.query(
        `UPDATE game_tables
         SET config_snapshot = $1,
             config_version = $2,
             config_hash = $3
         WHERE id = $4`,
        [JSON.stringify(payload), effective.revisions.room_defaults, effective.hash, row.id],
      );

      await client.query(
        `UPDATE game_hands
         SET config_snapshot = $1,
             config_version = $2,
             config_hash = $3
         WHERE table_id = $4`,
        [JSON.stringify(payload), effective.revisions.room_defaults, effective.hash, row.id],
      );
      updated++;
    }
    console.log(`Backfilled ${updated} tables (and their hands), ${mismatched} potential mismatches`);
  } catch (err) {
    console.error('Backfill failed:', err);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
