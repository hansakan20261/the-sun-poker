INSERT INTO system_config (key, value) VALUES
('app_control', '{"maintenance_enabled":false,"maintenance_message":"กำลังปรับปรุงระบบ กรุณาลองใหม่ภายหลัง","maintenance_starts_at":null,"maintenance_ends_at":null,"min_supported_version":"1.0.0","force_update_message":"กรุณาอัปเดตแอปเป็นเวอร์ชันล่าสุด","announcement":null}'),
('room_defaults', '{"small_blind":10,"big_blind":20,"min_buy_in":400,"max_buy_in":2000,"max_players":9,"turn_time_sec":30,"auto_start_at":2,"auto_start_delay_sec":2,"rake_percent":5.5,"rake_cap":0}'),
('card_back_settings', '{"style":"blue"}'),
('game_runtime', '{"auto_deal_delay_sec":5,"result_display_sec":12,"socket_reconnect_delay_sec":3,"socket_reconnect_attempts":10,"room_access_token_minutes":5}')
ON CONFLICT (key) DO NOTHING;

INSERT INTO feature_flags (feature_key, name, is_enabled) VALUES
('menu_clubs', 'เมนูคลับ', TRUE),
('menu_tournaments', 'เมนูทัวร์นาเมนต์', TRUE),
('menu_practice', 'เมนูฝึกซ้อม', TRUE),
('feature_private_rooms', 'ห้องส่วนตัว', TRUE),
('feature_room_creation', 'สร้างห้อง', TRUE)
ON CONFLICT (feature_key) DO NOTHING;
