CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS failed_login_attempts INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;

ALTER TABLE system_config
  ADD COLUMN IF NOT EXISTS revision BIGINT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'published',
  ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS published_by UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS change_reason TEXT;

CREATE TABLE IF NOT EXISTS config_definitions (
  key          VARCHAR(100) NOT NULL,
  field        VARCHAR(100) NOT NULL,
  definition   JSONB NOT NULL,
  version      INT NOT NULL DEFAULT 1,
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (key, field, version)
);

CREATE TABLE IF NOT EXISTS config_history (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  revision       BIGINT NOT NULL,
  key            VARCHAR(100) NOT NULL,
  scope          VARCHAR(30) NOT NULL DEFAULT 'system',
  scope_id       UUID,
  before_value   JSONB,
  after_value    JSONB NOT NULL,
  status         VARCHAR(20) NOT NULL DEFAULT 'published',
  apply_mode     VARCHAR(30) NOT NULL,
  change_reason  TEXT,
  correlation_id UUID,
  updated_by     UUID REFERENCES users(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_config_history_key ON config_history(key, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_config_history_revision ON config_history(revision DESC);
CREATE INDEX IF NOT EXISTS idx_config_history_scope ON config_history(scope, scope_id);

CREATE OR REPLACE FUNCTION prevent_config_history_mutation()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'config_history is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS config_history_no_update ON config_history;
CREATE TRIGGER config_history_no_update
  BEFORE UPDATE OR DELETE ON config_history
  FOR EACH ROW EXECUTE FUNCTION prevent_config_history_mutation();

CREATE TABLE IF NOT EXISTS game_type_configs (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_type_id UUID NOT NULL REFERENCES game_types(id),
  revision     BIGINT NOT NULL DEFAULT 1,
  config       JSONB NOT NULL DEFAULT '{}',
  status       VARCHAR(20) NOT NULL DEFAULT 'published',
  updated_by   UUID REFERENCES users(id),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(game_type_id)
);

CREATE TABLE IF NOT EXISTS room_templates (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_type_id UUID NOT NULL REFERENCES game_types(id),
  name         VARCHAR(100) NOT NULL,
  mode         VARCHAR(20) NOT NULL DEFAULT 'cash',
  revision     BIGINT NOT NULL DEFAULT 1,
  config       JSONB NOT NULL DEFAULT '{}',
  status       VARCHAR(20) NOT NULL DEFAULT 'published',
  created_by   UUID REFERENCES users(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_room_templates_game_type ON room_templates(game_type_id, status);

CREATE TABLE IF NOT EXISTS runtime_overrides (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id     UUID REFERENCES game_tables(id) ON DELETE CASCADE,
  game_type_id UUID REFERENCES game_types(id) ON DELETE CASCADE,
  key          VARCHAR(100) NOT NULL,
  value        JSONB NOT NULL,
  apply_mode   VARCHAR(30) NOT NULL,
  effective_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at   TIMESTAMPTZ,
  status       VARCHAR(20) NOT NULL DEFAULT 'active',
  approved_by  UUID REFERENCES users(id),
  created_by   UUID REFERENCES users(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (table_id IS NOT NULL OR game_type_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_runtime_overrides_active ON runtime_overrides(status, effective_at, expires_at);

ALTER TABLE game_tables
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS room_template_id UUID REFERENCES room_templates(id),
  ADD COLUMN IF NOT EXISTS config_snapshot JSONB,
  ADD COLUMN IF NOT EXISTS config_version BIGINT,
  ADD COLUMN IF NOT EXISTS config_hash VARCHAR(64);

ALTER TABLE game_hands
  ADD COLUMN IF NOT EXISTS config_snapshot JSONB,
  ADD COLUMN IF NOT EXISTS config_version BIGINT,
  ADD COLUMN IF NOT EXISTS config_hash VARCHAR(64);

UPDATE system_config
SET value = value || '{"ante":0}'::JSONB,
    updated_at = NOW()
WHERE key = 'room_defaults';

UPDATE system_config
SET value = value || '{"background_url":null,"overlay_opacity":0.55}'::JSONB,
    updated_at = NOW()
WHERE key = 'app_background';

INSERT INTO users (id, username, password_hash, display_name, role, is_verified, is_suspended)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  '__house__',
  crypt(gen_random_uuid()::text, gen_salt('bf')),
  'House Account',
  'system',
  TRUE,
  TRUE
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO wallets (user_id, balance)
VALUES ('00000000-0000-0000-0000-000000000000', 0)
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO system_config (key, value) VALUES
('app_background', '{"background_url":null,"overlay_opacity":0.55}'),
('app_control', '{"maintenance_enabled":false,"maintenance_message":"กำลังปรับปรุงระบบ กรุณาลองใหม่ภายหลัง","maintenance_starts_at":null,"maintenance_ends_at":null,"min_supported_version":"1.0.0","force_update_message":"กรุณาอัปเดตแอปเป็นเวอร์ชันล่าสุด","announcement":null,"announcement_enabled":false,"announcement_severity":"info"}'),
('texas_holdem_policy', '{"time_bank_sec":0,"allow_straddle":false,"allow_rebuy":true,"allow_run_twice":false,"max_raises_per_round":3,"no_flop_no_drop":true,"minimum_rake_pot":0,"auto_timeout_action":"check_or_fold","sit_out_timeout_sec":300,"max_hands_per_room":0,"max_room_duration_hours":0}'),
('chinese_poker_policy', '{"auto_arrange_on_timeout":true,"force_foul_on_invalid":true,"fantasyland_enabled":true,"royalty_table_version":"v1","scoop_bonus_points":3,"foul_penalty_points":6}'),
('tournament_policy', '{"registration_window_minutes":60,"late_registration_minutes":0,"min_players_to_start":2,"action_time_sec":30,"time_bank_sec":0,"break_interval_minutes":60,"break_duration_minutes":5,"rebuy_allowed":false,"addon_allowed":false,"rebuy_chip_amount":10000,"addon_chip_amount":10000,"cancellation_policy":"refund","default_small_blind":25,"default_big_blind":50,"default_players_per_table":8,"default_format":"freezeout","default_tournament_type":"sit_and_go","default_game_slug":"texas_holdem","default_max_players":50,"default_starting_chips":10000,"default_entry_fee":0,"default_blind_level_minutes":5,"default_blind_structure":[{"level_no":1,"small_blind":25,"big_blind":50,"ante":0},{"level_no":2,"small_blind":50,"big_blind":100,"ante":0},{"level_no":3,"small_blind":100,"big_blind":200,"ante":25},{"level_no":4,"small_blind":200,"big_blind":400,"ante":50},{"level_no":5,"small_blind":400,"big_blind":800,"ante":100},{"level_no":6,"small_blind":600,"big_blind":1200,"ante":150},{"level_no":7,"small_blind":1000,"big_blind":2000,"ante":200},{"level_no":8,"small_blind":1500,"big_blind":3000,"ante":300},{"level_no":9,"small_blind":2000,"big_blind":4000,"ante":400},{"level_no":10,"small_blind":3000,"big_blind":6000,"ante":500}],"default_payout_structure":[{"rank":1,"percent":40},{"rank":2,"percent":25},{"rank":3,"percent":15},{"rank":4,"percent":10},{"rank":5,"percent":5},{"rank":6,"percent":3},{"rank":7,"percent":1},{"rank":8,"percent":1}],"auto_start_enabled":true,"auto_start_interval_sec":15,"table_balance_max_diff":1,"disconnect_timeout_sec":300,"prize_distribution_policy":"configured"}'),
('practice_policy', '{"enabled":true,"bots_enabled":true,"max_bots":3,"bot_ready_poll_ms":1000,"bot_initial_wait_ms":5000,"bot_max_wait_ms":25000,"bot_action_min_ms":2000,"bot_action_jitter_ms":2000,"bot_pot_limit_big_blinds":20,"bot_error_retry_ms":500,"practice_chips":10000,"auto_start_delay_sec":2,"default_game_type":"texas_holdem","texas_max_players":6,"chinese_max_players":4,"texas_turn_time_sec":30,"chinese_turn_time_sec":60,"chinese_small_blind":0,"chinese_big_blind":0,"chinese_min_buy_in":100,"chinese_max_buy_in":500,"strategy_profile":"simple","demo_table_ids":["d0000000-0000-0000-0000-000000000001","d0000000-0000-0000-0000-000000000002","d0000000-0000-0000-0000-000000000003"],"demo_table_bot_counts":{"d0000000-0000-0000-0000-000000000001":4,"d0000000-0000-0000-0000-000000000002":4,"d0000000-0000-0000-0000-000000000003":2},"demo_bot_profiles":[{"id":"b0000000-0000-0000-0000-000000000001","username":"Alex 🇺🇸","countryFlag":"🇺🇸"},{"id":"b0000000-0000-0000-0000-000000000002","username":"Yuki 🇯🇵","countryFlag":"🇯🇵"},{"id":"b0000000-0000-0000-0000-000000000003","username":"Somchai 🇹🇭","countryFlag":"🇹🇭"},{"id":"b0000000-0000-0000-0000-000000000004","username":"Maria 🇵🇭","countryFlag":"🇵🇭"}]}'),
('wallet_economy_policy', '{"min_transfer_amount":1,"max_transfer_amount":1000000,"daily_transfer_limit":5000000,"admin_adjustment_requires_reason":true,"daily_bonus_enabled":true,"agent_withdrawal_approval_threshold":100000,"daily_bonus_base":100,"daily_bonus_reward_schedule":[100,200,300,500,800,1000,1500,2000,3000,5000],"daily_bonus_streak_step":50,"daily_bonus_max_streak_days":7,"max_shop_item_price":1000000,"max_shop_items_per_day":10,"shop_default_quantity":1,"initial_wallet_balance":0,"house_account_user_id":"00000000-0000-0000-0000-000000000000","agent_default_commission_percent":10,"agent_default_channel_name":"Default","agent_commission_max_percent":50}'),
('security_policy', '{"access_token_minutes":60,"session_days":7,"login_max_attempts":5,"login_lockout_minutes":15,"password_min_length":8,"password_policy_version":1,"password_hash_rounds":12,"default_user_role":"player","max_sessions_per_user":5,"admin_reauth_minutes":15,"admin_config_write_window_sec":60,"admin_config_write_max_requests":30,"audit_retention_days":365}'),
('notification_policy', '{"push_enabled":false,"in_app_enabled":true,"notification_poll_interval_sec":30,"lobby_poll_interval_sec":15,"api_retry_attempts":2}')
ON CONFLICT (key) DO UPDATE
SET value = system_config.value || EXCLUDED.value,
    updated_at = NOW();

UPDATE system_config
SET value = value || '{
  "http_timeout_sec":30,
  "health_check_timeout_sec":5,
  "public_config_cache_ttl_sec":30,
  "balance_poll_interval_sec":12,
  "promotion_banner_interval_sec":4,
  "admin_live_poll_interval_sec":1,
  "socket_reconnect_max_delay_sec":15,
  "socket_reconnect_randomization":0.5,
  "showdown_ready_delay_sec":5
}'::JSONB,
    updated_at = NOW()
WHERE key = 'game_runtime';

UPDATE system_config
SET value = value || '{
  "player_can_create":true,
  "max_rooms_per_player":3,
  "club_max_members":200,
  "max_rooms_per_agent":20,
  "max_rooms_per_club":50,
  "allowed_modes":["cash","private"],
  "allowed_game_type_slugs":["texas_holdem","chinese_poker"],
  "allowed_visibility":["public","private"],
  "room_expiration_hours":24,
  "min_ante":0,
  "max_ante":10000,
  "private_room_enabled":true,
  "room_name_min_length":1,
  "room_name_max_length":100,
  "room_password_min_length":4,
  "room_password_max_length":100,
  "min_buy_in_chips":0,
  "max_buy_in_chips":1000000,
  "min_rake_percent":0,
  "max_rake_percent":20,
  "max_rake_cap":1000000
}'::JSONB,
    updated_at = NOW()
WHERE key = 'room_creation_limits';

UPDATE game_tables
SET config_snapshot = jsonb_build_object(
  'small_blind', small_blind,
  'big_blind', big_blind,
  'ante', ante,
  'min_buy_in', min_buy_in,
  'max_buy_in', max_buy_in,
  'max_players', max_players,
  'turn_time_sec', turn_time_sec,
  'auto_start_at', auto_start_at,
  'auto_start_delay_sec', auto_start_delay_sec,
  'minimum_play_minutes', minimum_play_minutes,
  'rake_percent', rake_percent,
  'rake_cap', rake_cap
),
config_version = COALESCE(config_version, 1),
config_hash = COALESCE(config_hash, encode(digest(jsonb_build_object(
  'small_blind', small_blind,
  'big_blind', big_blind,
  'ante', ante,
  'min_buy_in', min_buy_in,
  'max_buy_in', max_buy_in,
  'max_players', max_players,
  'turn_time_sec', turn_time_sec,
  'auto_start_at', auto_start_at,
  'auto_start_delay_sec', auto_start_delay_sec,
  'minimum_play_minutes', minimum_play_minutes,
  'rake_percent', rake_percent,
  'rake_cap', rake_cap
)::text, 'sha256'), 'hex'))
WHERE config_snapshot IS NULL OR config_version IS NULL OR config_hash IS NULL;

UPDATE game_hands gh
SET config_snapshot = gt.config_snapshot,
    config_version = gt.config_version,
    config_hash = gt.config_hash
FROM game_tables gt
WHERE gh.table_id = gt.id
  AND (gh.config_snapshot IS NULL OR gh.config_version IS NULL OR gh.config_hash IS NULL);
