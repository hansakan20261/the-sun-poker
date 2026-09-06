-- ============================================
-- THE SUN POKER — Daily Bonuses
-- ============================================

-- Daily bonus tracking table for 10-day reward calendar
CREATE TABLE daily_bonuses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id) NOT NULL,
    day_number      INT NOT NULL CHECK (day_number BETWEEN 1 AND 10),
    coins_awarded   BIGINT NOT NULL,
    streak_count    INT NOT NULL DEFAULT 1,
    claimed_date    DATE NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, claimed_date)
);

CREATE INDEX idx_daily_bonus_user ON daily_bonuses(user_id);
CREATE INDEX idx_daily_bonus_date ON daily_bonuses(claimed_date);
