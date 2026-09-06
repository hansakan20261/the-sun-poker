-- Agent Hierarchy: Master → Super Agent → Agent
-- Commission based on total hands played (not topup)

-- Add super_agent role
-- (users.role already supports varchar, just need to allow 'super_agent')

-- Add parent_agent_id to agents table (for hierarchy)
ALTER TABLE agents ADD COLUMN IF NOT EXISTS parent_agent_id UUID REFERENCES agents(id);
ALTER TABLE agents ADD COLUMN IF NOT EXISTS agent_level VARCHAR(20) DEFAULT 'agent'; -- 'super_agent' or 'agent'
ALTER TABLE agents ADD COLUMN IF NOT EXISTS hand_commission_rate DECIMAL(5,2) DEFAULT 0.3; -- % per total hands

-- Index for hierarchy queries
CREATE INDEX IF NOT EXISTS idx_agents_parent ON agents(parent_agent_id);
CREATE INDEX IF NOT EXISTS idx_agents_level ON agents(agent_level);

-- View: hands per player (for commission calculation)
CREATE OR REPLACE VIEW player_hands_summary AS
SELECT 
  u.id as user_id,
  u.username,
  ar.agent_id,
  a.agent_level,
  a.parent_agent_id,
  COALESCE(ps.hands_played, 0) as total_hands
FROM users u
JOIN agent_referrals ar ON ar.user_id = u.id
JOIN agents a ON a.id = ar.agent_id
LEFT JOIN player_stats ps ON ps.user_id = u.id;

-- View: agent commission summary (hands-based)
CREATE OR REPLACE VIEW agent_hand_commission AS
SELECT 
  a.id as agent_id,
  a.user_id,
  a.agent_level,
  a.parent_agent_id,
  a.hand_commission_rate,
  (SELECT au.username FROM users au WHERE au.id = a.user_id) as agent_username,
  (SELECT au.display_name FROM users au WHERE au.id = a.user_id) as agent_name,
  COUNT(DISTINCT ar.user_id) as customer_count,
  COALESCE(SUM(ps.hands_played), 0) as total_hands,
  COALESCE(SUM(ps.hands_played), 0) * a.hand_commission_rate / 100.0 as commission_earned
FROM agents a
LEFT JOIN agent_referrals ar ON ar.agent_id = a.id
LEFT JOIN player_stats ps ON ps.user_id = ar.user_id
GROUP BY a.id, a.user_id, a.agent_level, a.parent_agent_id, a.hand_commission_rate;
