CREATE TABLE IF NOT EXISTS game_wallet_sessions (
    id             UUID PRIMARY KEY,
    table_id       UUID NOT NULL,
    user_id        UUID REFERENCES users(id) NOT NULL,
    buy_in         BIGINT NOT NULL CHECK (buy_in >= 0),
    cash_out       BIGINT CHECK (cash_out >= 0),
    status         VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cashed_out')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cashed_out_at  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_game_wallet_sessions_user_status
    ON game_wallet_sessions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_game_wallet_sessions_table
    ON game_wallet_sessions(table_id);
