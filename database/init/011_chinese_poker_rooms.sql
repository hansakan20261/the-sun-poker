-- ============================================
-- THE SUN POKER — ห้องไพ่สามกอง (Chinese Poker / OFC) 8 ห้อง
-- ตามเรท: ห้อง / เงินซื้อ (min buy-in) / เงินเหลือ (≈25% ของ buy-in)
-- ============================================
-- เรท (ante/big_blind) | ซื้อเข้าขั้นต่ำ | ซื้อเข้าสูงสุด (5x) | เงินเหลือ (≈25%)
-- 5                     | 250             | 1,250               | 62
-- 10                    | 500             | 2,500               | 125
-- 20                    | 1,000           | 5,000               | 250
-- 30                    | 1,500           | 7,500               | 375
-- 40                    | 2,000           | 10,000              | 500
-- 50                    | 2,500           | 12,500              | 625
-- 100                   | 5,000           | 25,000              | 1,250
-- 200                   | 10,000          | 50,000              | 2,500

-- Remove old chinese poker rooms (cleanup duplicates)
DELETE FROM game_tables
WHERE game_type_id = (SELECT id FROM game_types WHERE slug = 'chinese_poker')
  AND id NOT IN (SELECT DISTINCT table_id FROM table_players WHERE is_active = TRUE);

-- Insert 8 rooms with correct rates
INSERT INTO game_tables (game_type_id, name, mode, max_players, small_blind, big_blind, min_buy_in, max_buy_in, ante, turn_time_sec, status, is_featured, hide_from_lobby)
VALUES
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 5',   'cash', 4, 0, 5,   250,   1250,  5,   60, 'waiting', TRUE, FALSE),
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 10',  'cash', 4, 0, 10,  500,   2500,  10,  60, 'waiting', TRUE, FALSE),
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 20',  'cash', 4, 0, 20,  1000,  5000,  20,  60, 'waiting', TRUE, FALSE),
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 30',  'cash', 4, 0, 30,  1500,  7500,  30,  60, 'waiting', TRUE, FALSE),
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 40',  'cash', 4, 0, 40,  2000,  10000, 40,  60, 'waiting', TRUE, FALSE),
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 50',  'cash', 4, 0, 50,  2500,  12500, 50,  60, 'waiting', TRUE, FALSE),
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 100', 'cash', 4, 0, 100, 5000,  25000, 100, 60, 'waiting', TRUE, FALSE),
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 200', 'cash', 4, 0, 200, 10000, 50000, 200, 60, 'waiting', TRUE, FALSE);
