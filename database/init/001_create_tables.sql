-- ============================================
-- THE SUN POKER — Database Schema
-- ============================================

-- 1. users
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username        VARCHAR(50) UNIQUE NOT NULL,
    email           VARCHAR(255) UNIQUE,
    phone           VARCHAR(20),
    password_hash   VARCHAR(255) NOT NULL,
    display_name    VARCHAR(100),
    first_name      VARCHAR(100),
    last_name       VARCHAR(100),
    gender          VARCHAR(10),
    date_of_birth   DATE,
    country         VARCHAR(50),
    bio             TEXT,
    avatar_url      VARCHAR(500),
    avatar_frame_id UUID,
    table_theme_id  UUID,
    status_message  VARCHAR(200),
    is_verified     BOOLEAN DEFAULT FALSE,
    two_fa_enabled  BOOLEAN DEFAULT FALSE,
    two_fa_secret   VARCHAR(255),
    role            VARCHAR(20) DEFAULT 'player',
    is_suspended    BOOLEAN DEFAULT FALSE,
    locale          VARCHAR(10) DEFAULT 'th',
    vip_level       INT DEFAULT 0,
    vip_exp         BIGINT DEFAULT 0,
    last_login_at   TIMESTAMPTZ,
    last_login_ip   VARCHAR(45),
    login_count     INT DEFAULT 0,
    device_info     JSONB,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 2. user_oauth
CREATE TABLE user_oauth (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    provider    VARCHAR(20) NOT NULL,
    provider_id VARCHAR(255) NOT NULL,
    UNIQUE(provider, provider_id)
);

-- 3. player_stats
CREATE TABLE player_stats (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES users(id) UNIQUE NOT NULL,
    total_games         INT DEFAULT 0,
    total_wins          INT DEFAULT 0,
    total_losses        INT DEFAULT 0,
    win_rate            DECIMAL(5,2) DEFAULT 0,
    total_chips_won     BIGINT DEFAULT 0,
    total_chips_lost    BIGINT DEFAULT 0,
    biggest_pot_won     BIGINT DEFAULT 0,
    longest_win_streak  INT DEFAULT 0,
    total_play_time_min INT DEFAULT 0,
    favorite_game_type  VARCHAR(30),
    hands_played        INT DEFAULT 0,
    flop_seen_rate      DECIMAL(5,2) DEFAULT 0,
    showdown_win_rate   DECIMAL(5,2) DEFAULT 0,
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- 4. wallets
CREATE TABLE wallets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES users(id) UNIQUE NOT NULL,
    balance     BIGINT DEFAULT 0,
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 5. transactions
CREATE TABLE transactions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id) NOT NULL,
    type            VARCHAR(30) NOT NULL,
    amount          BIGINT NOT NULL,
    balance_after   BIGINT NOT NULL,
    reference_id    VARCHAR(255),
    description     TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_transactions_user ON transactions(user_id);
CREATE INDEX idx_transactions_type ON transactions(type);
CREATE INDEX idx_transactions_created ON transactions(created_at);

-- 6. admin_coin_transactions
CREATE TABLE admin_coin_transactions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id        UUID REFERENCES users(id) NOT NULL,
    user_id         UUID REFERENCES users(id) NOT NULL,
    type            VARCHAR(10) NOT NULL,
    coin_amount     BIGINT NOT NULL,
    cash_amount     DECIMAL(12,2),
    exchange_rate   DECIMAL(10,4),
    balance_before  BIGINT NOT NULL,
    balance_after   BIGINT NOT NULL,
    note            TEXT,
    slip_image_url  VARCHAR(500),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_admin_coin_tx_user ON admin_coin_transactions(user_id);
CREATE INDEX idx_admin_coin_tx_created ON admin_coin_transactions(created_at);

-- 7. clubs
CREATE TABLE clubs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100) NOT NULL,
    description     TEXT,
    owner_id        UUID REFERENCES users(id) NOT NULL,
    avatar_url      VARCHAR(500),
    max_members     INT DEFAULT 200,
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 8. club_members
CREATE TABLE club_members (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id     UUID REFERENCES clubs(id) ON DELETE CASCADE NOT NULL,
    user_id     UUID REFERENCES users(id) NOT NULL,
    role        VARCHAR(20) DEFAULT 'member',
    status      VARCHAR(20) DEFAULT 'pending',
    joined_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(club_id, user_id)
);

-- 9. game_types
CREATE TABLE game_types (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug            VARCHAR(50) UNIQUE NOT NULL,
    name            VARCHAR(100) NOT NULL,
    name_th         VARCHAR(100),
    description     TEXT,
    description_th  TEXT,
    icon_url        VARCHAR(500),
    banner_url      VARCHAR(500),
    min_players     INT DEFAULT 2,
    max_players     INT DEFAULT 9,
    rules_url       VARCHAR(500),
    is_active       BOOLEAN DEFAULT TRUE,
    sort_order      INT DEFAULT 0,
    config          JSONB DEFAULT '{}',
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 10. game_tables
CREATE TABLE game_tables (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id         UUID REFERENCES clubs(id),
    game_type_id    UUID REFERENCES game_types(id) NOT NULL,
    name            VARCHAR(100),
    mode            VARCHAR(20) DEFAULT 'cash',
    max_players     INT DEFAULT 9,
    small_blind     BIGINT NOT NULL,
    big_blind       BIGINT NOT NULL,
    min_buy_in      BIGINT NOT NULL,
    max_buy_in      BIGINT NOT NULL,
    ante            BIGINT DEFAULT 0,
    turn_time_sec   INT DEFAULT 30,
    auto_start_at   INT DEFAULT 2,
    auto_start_delay_sec INT DEFAULT 2,
    minimum_play_minutes INT,
    allow_rebuy     BOOLEAN DEFAULT TRUE,
    allow_straddle  BOOLEAN DEFAULT FALSE,
    allow_run_twice BOOLEAN DEFAULT FALSE,
    room_code       VARCHAR(20) UNIQUE,
    password        VARCHAR(100),
    is_private      BOOLEAN DEFAULT FALSE,
    hide_from_lobby BOOLEAN DEFAULT FALSE,
    is_featured     BOOLEAN DEFAULT FALSE,
    rake_percent    DECIMAL(5,2),
    rake_cap        BIGINT,
    status          VARCHAR(20) DEFAULT 'waiting',
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 11. table_players
CREATE TABLE table_players (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id    UUID REFERENCES game_tables(id) ON DELETE CASCADE NOT NULL,
    user_id     UUID REFERENCES users(id) NOT NULL,
    seat_number INT NOT NULL,
    chip_count  BIGINT NOT NULL DEFAULT 0,
    is_active   BOOLEAN DEFAULT TRUE,
    joined_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(table_id, seat_number)
);

-- 12. game_hands
CREATE TABLE game_hands (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id        UUID REFERENCES game_tables(id) NOT NULL,
    hand_number     INT NOT NULL,
    community_cards JSONB,
    pot_total       BIGINT DEFAULT 0,
    rake_amount     BIGINT DEFAULT 0,
    winner_ids      UUID[],
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    ended_at        TIMESTAMPTZ
);

-- 13. hand_actions
CREATE TABLE hand_actions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hand_id     UUID REFERENCES game_hands(id) NOT NULL,
    user_id     UUID REFERENCES users(id) NOT NULL,
    action_type VARCHAR(20) NOT NULL,
    amount      BIGINT DEFAULT 0,
    round       VARCHAR(20) NOT NULL,
    hole_cards  JSONB,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 14. tournaments
CREATE TABLE tournaments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(200) NOT NULL,
    description         TEXT,
    game_type_id        UUID REFERENCES game_types(id) NOT NULL,
    tournament_format   VARCHAR(30) NOT NULL,
    status              VARCHAR(20) DEFAULT 'draft',
    entry_fee           BIGINT DEFAULT 0,
    rebuy_fee           BIGINT DEFAULT 0,
    rebuy_limit         INT DEFAULT 0,
    starting_chips      BIGINT NOT NULL,
    prize_pool          BIGINT DEFAULT 0,
    prize_structure     JSONB,
    min_players         INT DEFAULT 2,
    max_players         INT NOT NULL,
    players_per_table   INT DEFAULT 9,
    blind_structure     JSONB NOT NULL,
    current_blind_level INT DEFAULT 1,
    late_registration_levels INT DEFAULT 3,
    scheduled_at        TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    finished_at         TIMESTAMPTZ,
    created_by          UUID REFERENCES users(id),
    club_id             UUID REFERENCES clubs(id),
    is_visible          BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- 15. tournament_players
CREATE TABLE tournament_players (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id   UUID REFERENCES tournaments(id) ON DELETE CASCADE NOT NULL,
    user_id         UUID REFERENCES users(id) NOT NULL,
    status          VARCHAR(20) DEFAULT 'registered',
    table_id        UUID REFERENCES game_tables(id),
    seat_number     INT,
    chip_count      BIGINT DEFAULT 0,
    finish_position INT,
    prize_won       BIGINT DEFAULT 0,
    rebuy_count     INT DEFAULT 0,
    registered_at   TIMESTAMPTZ DEFAULT NOW(),
    eliminated_at   TIMESTAMPTZ,
    UNIQUE(tournament_id, user_id)
);

-- 16. agents
CREATE TABLE agents (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID REFERENCES users(id) UNIQUE NOT NULL,
    agent_code              VARCHAR(20) UNIQUE NOT NULL,
    display_name            VARCHAR(100),
    line_id                 VARCHAR(100),
    status                  VARCHAR(20) DEFAULT 'active',
    default_commission_rate DECIMAL(5,2) DEFAULT 10.00,
    total_earned            BIGINT DEFAULT 0,
    available_balance       BIGINT DEFAULT 0,
    bank_info               JSONB,
    created_by              UUID REFERENCES users(id),
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

-- 17. agent_channels
CREATE TABLE agent_channels (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id          UUID REFERENCES agents(id) ON DELETE CASCADE NOT NULL,
    channel_name      VARCHAR(100) NOT NULL,
    channel_type      VARCHAR(30) NOT NULL,
    referral_code     VARCHAR(50) UNIQUE NOT NULL,
    referral_url      VARCHAR(500),
    qr_code_url       VARCHAR(500),
    commission_rate   DECIMAL(5,2),
    is_active         BOOLEAN DEFAULT TRUE,
    click_count       BIGINT DEFAULT 0,
    register_count    BIGINT DEFAULT 0,
    created_by        UUID REFERENCES users(id),
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- 18. agent_referrals
CREATE TABLE agent_referrals (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id    UUID REFERENCES agents(id) NOT NULL,
    channel_id  UUID REFERENCES agent_channels(id) NOT NULL,
    user_id     UUID REFERENCES users(id) UNIQUE NOT NULL,
    referred_at TIMESTAMPTZ DEFAULT NOW()
);

-- 19. agent_commissions
CREATE TABLE agent_commissions (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id          UUID REFERENCES agents(id) NOT NULL,
    channel_id        UUID REFERENCES agent_channels(id) NOT NULL,
    user_id           UUID REFERENCES users(id) NOT NULL,
    transaction_id    UUID REFERENCES transactions(id) NOT NULL,
    topup_amount      BIGINT NOT NULL,
    commission_rate   DECIMAL(5,2) NOT NULL,
    commission_amount BIGINT NOT NULL,
    status            VARCHAR(20) DEFAULT 'credited',
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- 20. agent_withdrawals
CREATE TABLE agent_withdrawals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id        UUID REFERENCES agents(id) NOT NULL,
    amount          BIGINT NOT NULL,
    status          VARCHAR(20) DEFAULT 'pending',
    bank_info       JSONB,
    reviewed_by     UUID REFERENCES users(id),
    reviewed_at     TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    note            TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 21-25. shop
CREATE TABLE shop_categories (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(100) NOT NULL,
    slug        VARCHAR(50) UNIQUE NOT NULL,
    sort_order  INT DEFAULT 0,
    is_active   BOOLEAN DEFAULT TRUE
);

CREATE TABLE shop_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id     UUID REFERENCES shop_categories(id) NOT NULL,
    name            VARCHAR(100) NOT NULL,
    description     TEXT,
    image_url       VARCHAR(500),
    animation_url   VARCHAR(500),
    price           BIGINT NOT NULL,
    is_consumable   BOOLEAN DEFAULT TRUE,
    is_active       BOOLEAN DEFAULT TRUE,
    sort_order      INT DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_inventory (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID REFERENCES users(id) NOT NULL,
    item_id      UUID REFERENCES shop_items(id) NOT NULL,
    quantity     INT DEFAULT 1,
    equipped     BOOLEAN DEFAULT FALSE,
    purchased_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, item_id)
);

CREATE TABLE shop_purchases (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES users(id) NOT NULL,
    item_id     UUID REFERENCES shop_items(id) NOT NULL,
    quantity    INT DEFAULT 1,
    total_price BIGINT NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE gift_transactions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id   UUID REFERENCES users(id) NOT NULL,
    receiver_id UUID REFERENCES users(id) NOT NULL,
    item_id     UUID REFERENCES shop_items(id) NOT NULL,
    table_id    UUID REFERENCES game_tables(id),
    message     VARCHAR(200),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 26-28. chat, friends, invitations
CREATE TABLE chat_messages (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id     UUID REFERENCES game_tables(id) NOT NULL,
    sender_id    UUID REFERENCES users(id) NOT NULL,
    receiver_id  UUID REFERENCES users(id),
    message_type VARCHAR(20) NOT NULL,
    content      TEXT,
    sticker_id   UUID REFERENCES shop_items(id),
    metadata     JSONB,
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE friendships (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID REFERENCES users(id) NOT NULL,
    friend_id  UUID REFERENCES users(id) NOT NULL,
    status     VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, friend_id)
);

CREATE TABLE invitations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inviter_id  UUID REFERENCES users(id) NOT NULL,
    invitee_id  UUID REFERENCES users(id) NOT NULL,
    invite_type VARCHAR(20) NOT NULL,
    target_id   UUID NOT NULL,
    status      VARCHAR(20) DEFAULT 'pending',
    message     VARCHAR(200),
    expires_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 29-35. admin & system
CREATE TABLE user_permissions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID REFERENCES users(id) NOT NULL,
    permission_key VARCHAR(50) NOT NULL,
    is_allowed     BOOLEAN DEFAULT TRUE,
    blocked_by     UUID REFERENCES users(id),
    blocked_reason TEXT,
    blocked_at     TIMESTAMPTZ,
    expires_at     TIMESTAMPTZ,
    UNIQUE(user_id, permission_key)
);

CREATE TABLE permission_audit_log (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID REFERENCES users(id) NOT NULL,
    admin_id       UUID REFERENCES users(id) NOT NULL,
    action         VARCHAR(20) NOT NULL,
    permission_key VARCHAR(50) NOT NULL,
    reason         TEXT,
    created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE feature_flags (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_key VARCHAR(50) UNIQUE NOT NULL,
    name        VARCHAR(100) NOT NULL,
    description TEXT,
    is_enabled  BOOLEAN DEFAULT TRUE,
    config      JSONB DEFAULT '{}',
    updated_by  UUID REFERENCES users(id),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE support_tickets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES users(id),
    subject     VARCHAR(255) NOT NULL,
    description TEXT,
    status      VARCHAR(20) DEFAULT 'open',
    assigned_to UUID REFERENCES users(id),
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE system_config (
    key        VARCHAR(100) PRIMARY KEY,
    value      JSONB NOT NULL,
    updated_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE announcements (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title      VARCHAR(200) NOT NULL,
    content    TEXT,
    image_url  VARCHAR(500),
    link_url   VARCHAR(500),
    type       VARCHAR(20) DEFAULT 'banner',
    target     VARCHAR(20) DEFAULT 'all',
    is_active  BOOLEAN DEFAULT TRUE,
    sort_order INT DEFAULT 0,
    starts_at  TIMESTAMPTZ,
    ends_at    TIMESTAMPTZ,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE admin_activity_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id    UUID REFERENCES users(id) NOT NULL,
    action      VARCHAR(100) NOT NULL,
    target_type VARCHAR(50),
    target_id   UUID,
    details     JSONB,
    ip_address  VARCHAR(45),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_admin_log_admin ON admin_activity_log(admin_id);
CREATE INDEX idx_admin_log_created ON admin_activity_log(created_at);

CREATE TABLE IF NOT EXISTS notification_queue (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    scope           VARCHAR(50) DEFAULT 'user',
    scope_id        UUID,
    channel         VARCHAR(20) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    scheduled_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at    TIMESTAMPTZ,
    error_count     INT NOT NULL DEFAULT 0,
    payload         JSONB NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_queue_status_scheduled
    ON notification_queue (status, scheduled_at)
    WHERE status = 'pending';
