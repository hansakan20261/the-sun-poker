CREATE TABLE IF NOT EXISTS user_sessions (
    id             UUID PRIMARY KEY,
    user_id        UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    device_info    JSONB NOT NULL DEFAULT '{}',
    ip_address     VARCHAR(45),
    expires_at     TIMESTAMPTZ NOT NULL,
    revoked_at     TIMESTAMPTZ,
    last_seen_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_user_active
    ON user_sessions(user_id, expires_at)
    WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS role_permission_templates (
    role           VARCHAR(20) PRIMARY KEY,
    menus          JSONB NOT NULL DEFAULT '[]',
    data_scope     VARCHAR(20) NOT NULL DEFAULT 'all' CHECK (data_scope IN ('all', 'own_club', 'read_only')),
    updated_by     UUID REFERENCES users(id),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_menu_permissions (
    user_id        UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    menus          JSONB NOT NULL DEFAULT '[]',
    data_scope     VARCHAR(20) NOT NULL DEFAULT 'all' CHECK (data_scope IN ('all', 'own_club', 'read_only')),
    club_scope     UUID REFERENCES clubs(id) ON DELETE SET NULL,
    updated_by     UUID REFERENCES users(id),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS menu_permission_audit_log (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    admin_id       UUID REFERENCES users(id) NOT NULL,
    before_value   JSONB,
    after_value    JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO role_permission_templates (role, menus, data_scope) VALUES
    ('super_admin', '["all"]', 'all'),
    ('admin', '["all"]', 'all'),
    ('club_owner', '["club-dashboard","club-agents","club-players","club-tables","club-rake","club-chips","club-settlements"]', 'own_club'),
    ('club_admin', '["club-dashboard","club-agents","club-players","club-tables","club-rake","club-chips"]', 'own_club'),
    ('agent', '["agent-dashboard","agent-players","agent-tables","agent-wallet"]', 'own_club'),
    ('player', '[]', 'read_only')
ON CONFLICT (role) DO NOTHING;
