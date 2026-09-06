ALTER TABLE game_tables
  ADD COLUMN IF NOT EXISTS minimum_play_minutes INT;

ALTER TABLE admin_activity_log
  ALTER COLUMN admin_id DROP NOT NULL;

INSERT INTO system_config (key, value)
VALUES
  ('game_runtime', '{"auto_deal_delay_sec":5,"result_display_sec":12,"socket_reconnect_delay_sec":3,"socket_reconnect_attempts":10,"room_access_token_minutes":5,"seat_reservation_ttl_sec":30,"disconnect_grace_sec":15,"idle_timeout_sec":300,"tournament_minimum_play_minutes":0,"practice_minimum_play_minutes":0}'),
  ('room_auto_cleanup', '{"enabled":false,"delete_empty_after_minutes":60,"delete_all_player_rooms_after_hours":24,"only_player_created":true,"allow_close_occupied_expired":false,"allow_close_playing":false,"cleanup_worker_interval_sec":300,"version":1}')
ON CONFLICT (key) DO UPDATE
SET value = system_config.value || EXCLUDED.value,
    updated_at = NOW();

UPDATE system_config
SET value = value || '{"minimum_play_minutes":30}'::JSONB,
    updated_at = NOW()
WHERE key = 'room_defaults' AND NOT (value ? 'minimum_play_minutes');

UPDATE system_config
SET value = value || '{"min_minimum_play_minutes":0,"max_minimum_play_minutes":1440}'::JSONB,
    updated_at = NOW()
WHERE key = 'room_creation_limits';
