CREATE TABLE IF NOT EXISTS poker_tournaments (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                  VARCHAR(200) NOT NULL,
  type                  VARCHAR(30) NOT NULL DEFAULT 'sit_and_go',
  game                  VARCHAR(50) NOT NULL DEFAULT 'texas_holdem',
  buy_in                BIGINT NOT NULL DEFAULT 0 CHECK (buy_in >= 0),
  entry_fee             BIGINT NOT NULL DEFAULT 0 CHECK (entry_fee >= 0),
  max_players           INTEGER NOT NULL CHECK (max_players >= 2),
  players_per_table     INTEGER NOT NULL CHECK (players_per_table BETWEEN 2 AND 10),
  starting_chips        BIGINT NOT NULL CHECK (starting_chips > 0),
  blind_level_minutes   INTEGER NOT NULL CHECK (blind_level_minutes > 0),
  start_time            TIMESTAMPTZ,
  started_at            TIMESTAMPTZ,
  finished_at           TIMESTAMPTZ,
  cancelled_at          TIMESTAMPTZ,
  cancel_reason         TEXT,
  cancellation_policy   VARCHAR(30),
  prize_pool            BIGINT NOT NULL DEFAULT 0 CHECK (prize_pool >= 0),
  description           TEXT,
  status                VARCHAR(30) NOT NULL DEFAULT 'registration'
    CHECK (status IN ('draft', 'registration', 'running', 'final_table', 'finished', 'cancelled')),
  created_by            UUID REFERENCES users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS poker_blind_levels (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id       UUID NOT NULL REFERENCES poker_tournaments(id) ON DELETE CASCADE,
  level_no            INTEGER NOT NULL CHECK (level_no > 0),
  small_blind         BIGINT NOT NULL CHECK (small_blind >= 0),
  big_blind           BIGINT NOT NULL CHECK (big_blind >= 0),
  ante                BIGINT NOT NULL DEFAULT 0 CHECK (ante >= 0),
  duration_seconds    INTEGER NOT NULL CHECK (duration_seconds > 0),
  UNIQUE (tournament_id, level_no)
);

CREATE TABLE IF NOT EXISTS poker_tournament_tables (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id       UUID NOT NULL REFERENCES poker_tournaments(id) ON DELETE CASCADE,
  table_no            INTEGER NOT NULL CHECK (table_no > 0),
  status              VARCHAR(30) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'broken', 'finished')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (tournament_id, table_no)
);

CREATE TABLE IF NOT EXISTS poker_tournament_players (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id       UUID NOT NULL REFERENCES poker_tournaments(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  table_id            UUID REFERENCES poker_tournament_tables(id) ON DELETE SET NULL,
  seat_no             INTEGER CHECK (seat_no IS NULL OR seat_no BETWEEN 1 AND 10),
  chips               BIGINT NOT NULL DEFAULT 0 CHECK (chips >= 0),
  status              VARCHAR(30) NOT NULL DEFAULT 'registered'
    CHECK (status IN ('registered', 'seated', 'eliminated', 'winner', 'cancelled')),
  finish_rank         INTEGER,
  prize               BIGINT NOT NULL DEFAULT 0 CHECK (prize >= 0),
  rebuy_count         INTEGER NOT NULL DEFAULT 0 CHECK (rebuy_count >= 0),
  addon_count         INTEGER NOT NULL DEFAULT 0 CHECK (addon_count >= 0),
  registered_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (tournament_id, user_id),
  UNIQUE (table_id, seat_no)
);

CREATE INDEX IF NOT EXISTS idx_poker_tournaments_status ON poker_tournaments(status, start_time);
CREATE INDEX IF NOT EXISTS idx_poker_tournament_players_tournament ON poker_tournament_players(tournament_id, status);
CREATE INDEX IF NOT EXISTS idx_poker_tournament_tables_tournament ON poker_tournament_tables(tournament_id, status);

CREATE TABLE IF NOT EXISTS tournament_hands (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id       UUID NOT NULL REFERENCES poker_tournaments(id) ON DELETE CASCADE,
  tournament_table_id UUID NOT NULL REFERENCES poker_tournament_tables(id) ON DELETE CASCADE,
  hand_number         INTEGER NOT NULL,
  community_cards     JSONB,
  player_data         JSONB,
  actions             JSONB,
  pot_total           BIGINT NOT NULL DEFAULT 0 CHECK (pot_total >= 0),
  rake_amount         BIGINT NOT NULL DEFAULT 0 CHECK (rake_amount >= 0),
  winner_ids          UUID[],
  config_revision     BIGINT,
  config_hash         VARCHAR(64),
  started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (tournament_table_id, hand_number)
);

CREATE INDEX IF NOT EXISTS idx_tournament_hands_tournament ON tournament_hands(tournament_id, started_at DESC);
