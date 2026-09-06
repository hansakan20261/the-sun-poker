-- ============================================
-- THE SUN POKER — ห้องไพ่สามกอง (Chinese Poker) เพิ่มห้องวงเงินสูง
-- เรท 300 / 500 / 1000
-- ============================================
-- เรท (ante/big_blind) | ซื้อเข้าขั้นต่ำ | ซื้อเข้าสูงสุด (5x) | เงินเหลือ (≈25%)
-- 300                   | 15,000          | 75,000              | 3,750
-- 500                   | 25,000          | 125,000             | 6,250
-- 1000                  | 50,000          | 250,000             | 12,500

INSERT INTO game_tables (game_type_id, name, mode, max_players, small_blind, big_blind, min_buy_in, max_buy_in, ante, turn_time_sec, status, is_featured, hide_from_lobby)
VALUES
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 300',  'cash', 4, 0, 300,  15000,  75000,   300, 60, 'waiting', TRUE, FALSE),
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 500',  'cash', 4, 0, 500,  25000,  125000,  500, 60, 'waiting', TRUE, FALSE),
  ((SELECT id FROM game_types WHERE slug = 'chinese_poker'), 'ห้อง 1000', 'cash', 4, 0, 1000, 50000,  250000, 1000, 60, 'waiting', TRUE, FALSE);
