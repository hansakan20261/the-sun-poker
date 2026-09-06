-- ============================================
-- THE SUN POKER — Seed Data
-- ============================================

-- Super Admin account (password: SunPoker@2026 — bcrypt hashed)
INSERT INTO users (id, username, email, password_hash, display_name, role, is_verified)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'superadmin',
    'admin@thesunpoker.com',
    '$2b$12$.Lpgu841dJ9imzkyD5FvuOU9aTfAlJ0RwijCpkGkuOykhe1lcpIpC',
    'Super Admin',
    'super_admin',
    TRUE
);

-- Create wallet for super admin
INSERT INTO wallets (user_id, balance) VALUES
('a0000000-0000-0000-0000-000000000001', 0);

-- Game Types
INSERT INTO game_types (slug, name, name_th, min_players, max_players, sort_order, is_active) VALUES
('texas_holdem',  'Texas Hold''em',  'เท็กซัสโฮลเอ็ม', 2, 9, 1, TRUE),
('omaha',         'Omaha',           'โอมาฮา',         2, 9, 2, TRUE),
('chinese_poker', 'Chinese Poker',   'ไพ่สามกอง',       2, 4, 3, TRUE);

-- System Config
INSERT INTO system_config (key, value) VALUES
('coin_settings', '{
    "coin_name": "เหรียญ",
    "coin_symbol": "🪙",
    "deposit_rate": 1.00,
    "withdrawal_rate": 1.00,
    "min_deposit_thb": 100,
    "max_deposit_thb_per_day": 50000,
    "min_withdrawal_coins": 100,
    "max_withdrawal_coins_per_day": 50000,
    "max_balance": 1000000
}'),
('rake_settings', '{
    "default_rake_percent": 5.00,
    "default_rake_cap": 100
}'),
('room_creation_limits', '{
    "player_can_create": true,
    "max_rooms_per_player": 3,
    "min_small_blind": 5,
    "max_small_blind": 1000,
    "min_players": 2,
    "max_players": 9,
    "min_turn_time_sec": 10,
    "max_turn_time_sec": 60
}'),
('default_agent_commission', '{"rate": 10.00}');

-- Feature Flags
INSERT INTO feature_flags (feature_key, name, is_enabled) VALUES
('menu_shop',           'เมนูร้านค้า',          TRUE),
('menu_leaderboard',    'เมนู Leaderboard',    TRUE),
('feature_multi_table', 'เล่นหลายโต๊ะ',         TRUE),
('feature_gift',        'ส่งของขวัญ',           TRUE),
('feature_chat',        'แชทในห้อง',            TRUE),
('feature_transfer',    'โอนเหรียญ',            FALSE),
('game_texas_holdem',   'Texas Hold''em',       TRUE),
('game_omaha',          'Omaha',                TRUE),
('game_chinese_poker',  'ไพ่สามกอง',             TRUE),
('maintenance_mode',    'โหมดซ่อมบำรุง',         FALSE);

-- Shop Categories
INSERT INTO shop_categories (slug, name, sort_order) VALUES
('sticker',      'สติกเกอร์',     1),
('gift',         'ของขวัญ',       2),
('avatar_frame', 'กรอบรูปโปรไฟล์', 3),
('table_theme',  'ธีมโต๊ะ',       4),
('emoji',        'อีโมจิพิเศษ',    5);
