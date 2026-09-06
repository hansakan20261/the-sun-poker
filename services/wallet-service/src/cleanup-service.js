const { getConfig, setConfig, validateConfig } = require('./config-service');

function normalizeCleanupSettings(input) {
  return validateConfig('room_auto_cleanup', input);
}

async function loadCleanupSettings(pool) {
  const [settings, limits] = await Promise.all([
    getConfig(pool, 'room_auto_cleanup'),
    getConfig(pool, 'room_creation_limits'),
  ]);
  return normalizeCleanupSettings({
    ...settings,
    delete_all_player_rooms_after_hours: limits.room_expiration_hours,
  });
}

async function saveCleanupSettings(pool, input, userId) {
  const current = await loadCleanupSettings(pool);
  const next = normalizeCleanupSettings({
    ...current,
    ...input,
    delete_all_player_rooms_after_hours: current.delete_all_player_rooms_after_hours,
    version: current.version + 1,
  });
  await setConfig(pool, 'room_auto_cleanup', next, userId);
  return next;
}

const CANDIDATE_SQL = `
WITH candidates AS (
  SELECT gt.id, gt.name,
    CASE WHEN gt.created_at < NOW() - INTERVAL '1 hour' * $2 THEN 'expired' ELSE 'empty' END AS reason
  FROM game_tables gt
  LEFT JOIN users u ON u.id = gt.created_by
  WHERE gt.status != 'closed'
    AND ($3::boolean = FALSE OR u.role = 'player')
    AND ($5::boolean = TRUE OR gt.status != 'playing')
    AND (
      (gt.created_at < NOW() - INTERVAL '1 minute' * $1
       AND NOT EXISTS (SELECT 1 FROM table_players tp WHERE tp.table_id = gt.id AND tp.is_active))
      OR
      (gt.created_at < NOW() - INTERVAL '1 hour' * $2
       AND ($4::boolean = TRUE OR NOT EXISTS (SELECT 1 FROM table_players tp WHERE tp.table_id = gt.id AND tp.is_active)))
    )
)
SELECT id, name, reason FROM candidates ORDER BY reason, name`;

async function executeCleanup(pool, settings, { actorId = null, source, dryRun = false } = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(CANDIDATE_SQL, [
      settings.delete_empty_after_minutes,
      settings.delete_all_player_rooms_after_hours,
      settings.only_player_created,
      settings.allow_close_occupied_expired,
      settings.allow_close_playing,
    ]);
    const rooms = result.rows;
    if (!dryRun && rooms.length > 0) {
      await client.query("UPDATE game_tables SET status = 'closed', hide_from_lobby = TRUE WHERE id = ANY($1::uuid[])", [rooms.map(room => room.id)]);
      await client.query(
        `INSERT INTO admin_activity_log (admin_id, action, target_type, details)
         VALUES ($1, 'room_cleanup', 'game_tables', $2)`,
        [actorId, JSON.stringify({ source, config_version: settings.version, config: settings, rooms })],
      );
    }
    await client.query('COMMIT');
    return {
      dry_run: dryRun,
      total_deleted: dryRun ? 0 : rooms.length,
      total_candidates: rooms.length,
      deleted_empty: dryRun ? 0 : rooms.filter(room => room.reason === 'empty').length,
      deleted_expired: dryRun ? 0 : rooms.filter(room => room.reason === 'expired').length,
      rooms,
    };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { CANDIDATE_SQL, executeCleanup, loadCleanupSettings, normalizeCleanupSettings, saveCleanupSettings };
