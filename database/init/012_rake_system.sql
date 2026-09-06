-- Rake System: House account for collecting table fees
-- Rake: 5.5% of pot per hand (NLH + Chinese Poker)

-- Create house/platform user (for rake collection)
INSERT INTO users (id, username, email, password_hash, role)
VALUES ('00000000-0000-0000-0000-000000000000', 'House', 'house@thesunpoker.com', 'SYSTEM_ACCOUNT', 'admin')
ON CONFLICT (id) DO NOTHING;

-- Create house wallet
INSERT INTO wallets (user_id, balance)
VALUES ('00000000-0000-0000-0000-000000000000', 0)
ON CONFLICT (user_id) DO NOTHING;

-- Add rake_amount column to game_hands for tracking per-hand rake
ALTER TABLE game_hands ADD COLUMN IF NOT EXISTS rake_amount BIGINT DEFAULT 0;
ALTER TABLE game_hands ADD COLUMN IF NOT EXISTS rake_percent DECIMAL(5,2) DEFAULT 5.5;

-- Index for rake reporting
CREATE INDEX IF NOT EXISTS idx_transactions_rake ON transactions(type) WHERE type = 'rake';

-- View: Daily rake summary for admin dashboard
CREATE OR REPLACE VIEW rake_daily_summary AS
SELECT 
  DATE(created_at) as date,
  COUNT(*) as total_hands_raked,
  SUM(amount) as total_rake,
  AVG(amount) as avg_rake_per_hand
FROM transactions 
WHERE type = 'rake' 
  AND user_id = '00000000-0000-0000-0000-000000000000'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- View: Monthly rake summary
CREATE OR REPLACE VIEW rake_monthly_summary AS
SELECT 
  DATE_TRUNC('month', created_at) as month,
  COUNT(*) as total_hands_raked,
  SUM(amount) as total_rake,
  AVG(amount) as avg_rake_per_hand
FROM transactions 
WHERE type = 'rake' 
  AND user_id = '00000000-0000-0000-0000-000000000000'
GROUP BY DATE_TRUNC('month', created_at)
ORDER BY month DESC;
