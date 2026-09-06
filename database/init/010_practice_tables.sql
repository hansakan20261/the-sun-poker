-- ============================================
-- THE SUN POKER — Practice Tables Support
-- ============================================

-- Add is_practice flag to game_tables
ALTER TABLE game_tables ADD COLUMN IF NOT EXISTS is_practice BOOLEAN DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_game_tables_practice ON game_tables(is_practice);
