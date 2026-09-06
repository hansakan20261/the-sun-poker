ALTER TABLE game_tables
  ADD COLUMN IF NOT EXISTS auto_start_delay_sec INT;

UPDATE game_tables
SET auto_start_delay_sec = COALESCE(
  auto_start_delay_sec,
  (SELECT (value->>'auto_start_delay_sec')::INT FROM system_config WHERE key = 'room_defaults'),
  2
);

ALTER TABLE game_tables
  ALTER COLUMN auto_start_delay_sec SET DEFAULT 2,
  ALTER COLUMN auto_start_delay_sec SET NOT NULL;

UPDATE system_config
SET value = value || '{"auto_start_delay_sec":2}'::JSONB,
    updated_at = NOW()
WHERE key = 'room_defaults' AND NOT (value ? 'auto_start_delay_sec');

INSERT INTO system_config (key, value)
VALUES ('room_creation_limits', '{"player_can_create":true,"max_rooms_per_player":3,"min_small_blind":5,"max_small_blind":1000,"min_players":2,"max_players":9,"min_turn_time_sec":10,"max_turn_time_sec":60,"min_auto_start_delay_sec":0,"max_auto_start_delay_sec":30}')
ON CONFLICT (key) DO UPDATE
SET value = system_config.value || EXCLUDED.value,
    updated_at = NOW();
