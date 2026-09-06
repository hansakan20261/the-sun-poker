const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { getConfig } = require('../config-service');

const router = express.Router();

// GET /admin/agents — ดู Agent ทั้งหมด
router.get('/', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try {
    const { search, status, limit = 100, offset = 0 } = req.query;
    let query = `SELECT a.*, u.username, u.email, u.phone,
                   (SELECT COUNT(*) FROM agent_referrals ar WHERE ar.agent_id = a.id) as customer_count,
                   (SELECT COALESCE(SUM(ps.hands_played), 0) FROM agent_referrals ar2 JOIN player_stats ps ON ps.user_id = ar2.user_id WHERE ar2.agent_id = a.id) as total_hands
                 FROM agents a JOIN users u ON u.id = a.user_id WHERE 1=1`;
    const params = [];
    if (search) {
      params.push(`%${search}%`);
      query += ` AND (a.agent_code ILIKE $${params.length} OR a.display_name ILIKE $${params.length} OR u.username ILIKE $${params.length})`;
    }
    if (status) { params.push(status); query += ` AND a.status = $${params.length}`; }
    const countParams = [...params];
    const countQuery = `SELECT COUNT(*) as total FROM agents a JOIN users u ON u.id = a.user_id WHERE 1=1` +
      query.split('WHERE 1=1')[1].split('ORDER BY')[0];
    const countResult = await pool.query(countQuery, countParams);
    params.push(Number(limit));
    query += ` ORDER BY a.created_at DESC LIMIT $${params.length}`;
    params.push(Number(offset));
    query += ` OFFSET $${params.length}`;
    const result = await pool.query(query, params);
    res.json({ agents: result.rows, total: Number(countResult.rows[0].total) });
  } catch (err) { console.error('List agents error:', err); res.status(500).json({ error: 'Internal server error' }); }
});

// POST /admin/agents — สร้าง Agent ใหม่
router.post('/', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { display_name, username, password, email, phone, line_id, commission_rate, bank_info, channels } = req.body;
    if (!display_name || !username || !password) return res.status(400).json({ error: 'display_name, username, password required' });
    const [policy, securityPolicy] = await Promise.all([
      getConfig(pool, 'wallet_economy_policy'),
      getConfig(pool, 'security_policy'),
    ]);
    if (password.length < securityPolicy.password_min_length) {
      return res.status(400).json({ error: `Password must be at least ${securityPolicy.password_min_length} characters` });
    }
    const rate = commission_rate ?? policy.agent_default_commission_percent;
    if (rate < 0 || rate > policy.agent_commission_max_percent) {
      return res.status(400).json({ error: `Commission must be between 0 and ${policy.agent_commission_max_percent}` });
    }
    const publicBaseUrl = process.env.PUBLIC_APP_URL;
    if (!publicBaseUrl) return res.status(500).json({ error: 'PUBLIC_APP_URL is not configured' });
    await client.query('BEGIN');
    const passwordHash = await bcrypt.hash(password, securityPolicy.password_hash_rounds);
    const userResult = await client.query(
      `INSERT INTO users (username, password_hash, email, phone, display_name, role, is_verified) VALUES ($1,$2,$3,$4,$5,'agent',TRUE) RETURNING id`,
      [username, passwordHash, email, phone, display_name]);
    const userId = userResult.rows[0].id;
    await client.query('INSERT INTO wallets (user_id, balance) VALUES ($1, $2)', [userId, policy.initial_wallet_balance]);
    await client.query('INSERT INTO player_stats (user_id) VALUES ($1)', [userId]);
    const agentCode = 'A' + String(Date.now()).slice(-4) + crypto.randomBytes(1).toString('hex').toUpperCase();
    const agentResult = await client.query(
      `INSERT INTO agents (user_id, agent_code, display_name, line_id, status, default_commission_rate, bank_info, created_by)
       VALUES ($1,$2,$3,$4,'active',$5,$6,$7) RETURNING *`,
      [userId, agentCode, display_name, line_id, rate, JSON.stringify(bank_info || {}), req.user.id]);
    const agent = agentResult.rows[0];
    const createdChannels = [];
    const channelList = channels && channels.length > 0 ? channels : [{ name: policy.agent_default_channel_name, commission_rate: rate }];
    for (const ch of channelList) {
      const channelName = ch.name || policy.agent_default_channel_name;
      const refCode = `${agentCode}-${channelName.substring(0, 4).toUpperCase().replace(/\s/g, '')}`;
      const refUrl = `${publicBaseUrl.replace(/\/$/, '')}/ref/${refCode}`;
      const chResult = await client.query(
        `INSERT INTO agent_channels (agent_id, channel_name, channel_type, referral_code, referral_url, commission_rate, created_by)
         VALUES ($1,$2,'referral_link',$3,$4,$5,$6) RETURNING *`,
        [agent.id, channelName, refCode, refUrl, ch.commission_rate || null, req.user.id]);
      createdChannels.push(chResult.rows[0]);
    }
    await client.query(`INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details) VALUES ($1,'create_agent','agent',$2,$3)`,
      [req.user.id, agent.id, JSON.stringify({ agentCode, username, commission_rate: rate })]);
    await client.query('COMMIT');
    res.status(201).json({ agent: { ...agent, username, email, phone }, channels: createdChannels, credentials: { username, password, portal_url: 'https://agent.thesunpoker.com' } });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') return res.status(409).json({ error: 'Username already exists' });
    console.error('Create agent error:', err); res.status(500).json({ error: 'Internal server error' });
  } finally { client.release(); }
});

// ============ WITHDRAWALS (ต้องอยู่ก่อน /:id) ============

router.get('/withdrawals/all', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try {
    const { status } = req.query;
    let query = `SELECT aw.*, a.agent_code, a.display_name as agent_name, u.username
                 FROM agent_withdrawals aw JOIN agents a ON a.id = aw.agent_id
                 JOIN users u ON u.id = a.user_id WHERE 1=1`;
    const params = [];
    if (status) { params.push(status); query += ` AND aw.status = $${params.length}`; }
    query += ' ORDER BY aw.created_at DESC LIMIT 50';
    const result = await pool.query(query, params);
    res.json({ withdrawals: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

router.put('/withdrawals/:wId/approve', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try {
    await pool.query(
      "UPDATE agent_withdrawals SET status = 'approved', reviewed_by = $1, reviewed_at = NOW(), completed_at = NOW() WHERE id = $2",
      [req.user.id, req.params.wId]);
    await pool.query(`INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details) VALUES ($1,'approve_withdrawal','agent_withdrawal',$2,'{}')`,
      [req.user.id, req.params.wId]);
    res.json({ success: true });
  } catch (err) { console.error('Approve error:', err); res.status(500).json({ error: 'Internal server error' }); }
});

router.put('/withdrawals/:wId/reject', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { reason } = req.body;
    await client.query('BEGIN');
    const wd = await client.query('SELECT * FROM agent_withdrawals WHERE id = $1', [req.params.wId]);
    if (wd.rows.length === 0) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Not found' }); }
    await client.query('UPDATE agents SET available_balance = available_balance + $1 WHERE id = $2', [wd.rows[0].amount, wd.rows[0].agent_id]);
    await client.query(
      "UPDATE agent_withdrawals SET status = 'rejected', reviewed_by = $1, reviewed_at = NOW(), note = $2 WHERE id = $3",
      [req.user.id, reason || '', req.params.wId]);
    await client.query(`INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details) VALUES ($1,'reject_withdrawal','agent_withdrawal',$2,$3)`,
      [req.user.id, req.params.wId, JSON.stringify({ reason })]);
    await client.query('COMMIT');
    res.json({ success: true });
  } catch (err) { await client.query('ROLLBACK'); console.error('Reject error:', err); res.status(500).json({ error: 'Internal server error' }); }
  finally { client.release(); }
});

// ============ AGENT DETAIL & MANAGEMENT ============

// PUT /admin/agents/:id — อัพเดท agent_level, hand_commission_rate, parent_agent_id
router.put('/:id', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try {
    const { agent_level, hand_commission_rate, parent_agent_id } = req.body;
    const updates = [];
    const params = [];
    let idx = 1;
    if (agent_level !== undefined) {
      if (!['agent', 'super_agent'].includes(agent_level)) return res.status(400).json({ error: 'agent_level must be agent or super_agent' });
      params.push(agent_level); updates.push(`agent_level = $${idx++}`);
    }
    if (hand_commission_rate !== undefined) {
      if (hand_commission_rate < 0 || hand_commission_rate > 100) return res.status(400).json({ error: 'hand_commission_rate must be 0-100' });
      params.push(hand_commission_rate); updates.push(`hand_commission_rate = $${idx++}`);
    }
    if (parent_agent_id !== undefined) {
      params.push(parent_agent_id); updates.push(`parent_agent_id = $${idx++}`);
    }
    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    params.push(req.params.id);
    const query = `UPDATE agents SET ${updates.join(', ')}, updated_at = NOW() WHERE id = $${idx} RETURNING *`;
    const result = await pool.query(query, params);
    if (result.rows.length === 0) return res.status(404).json({ error: 'Agent not found' });
    await pool.query(`INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details) VALUES ($1,'update_agent','agent',$2,$3)`,
      [req.user.id, req.params.id, JSON.stringify({ agent_level, hand_commission_rate, parent_agent_id })]);
    res.json({ agent: result.rows[0], success: true });
  } catch (err) { console.error('Update agent error:', err); res.status(500).json({ error: 'Internal server error' }); }
});

router.get('/:id', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try {
    const agentResult = await pool.query(`SELECT a.*, u.username, u.email, u.phone FROM agents a JOIN users u ON u.id = a.user_id WHERE a.id = $1`, [req.params.id]);
    if (agentResult.rows.length === 0) return res.status(404).json({ error: 'Agent not found' });
    const channels = await pool.query('SELECT * FROM agent_channels WHERE agent_id = $1 ORDER BY created_at', [req.params.id]);
    const customers = await pool.query(`SELECT ar.*, u.username, u.display_name FROM agent_referrals ar JOIN users u ON u.id = ar.user_id WHERE ar.agent_id = $1 ORDER BY ar.referred_at DESC LIMIT 20`, [req.params.id]);
    res.json({ agent: agentResult.rows[0], channels: channels.rows, recent_customers: customers.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

router.put('/:id/suspend', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try { await pool.query("UPDATE agents SET status = 'suspended', updated_at = NOW() WHERE id = $1", [req.params.id]); res.json({ success: true }); }
  catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

router.put('/:id/activate', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try { await pool.query("UPDATE agents SET status = 'active', updated_at = NOW() WHERE id = $1", [req.params.id]); res.json({ success: true }); }
  catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

router.put('/:id/commission-rate', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try { const { rate } = req.body; await pool.query('UPDATE agents SET default_commission_rate = $1, updated_at = NOW() WHERE id = $2', [rate, req.params.id]); res.json({ success: true, rate }); }
  catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

router.post('/:id/channels', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try {
    const { channel_name, commission_rate } = req.body;
    const agent = await pool.query('SELECT agent_code FROM agents WHERE id = $1', [req.params.id]);
    if (agent.rows.length === 0) return res.status(404).json({ error: 'Agent not found' });
    const suffix = (channel_name || 'NEW').substring(0, 4).toUpperCase().replace(/\s/g, '');
    const refCode = `${agent.rows[0].agent_code}-${suffix}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`;
    const refUrl = `https://thesunpoker.com/ref/${refCode}`;
    const result = await pool.query(
      `INSERT INTO agent_channels (agent_id, channel_name, channel_type, referral_code, referral_url, commission_rate, created_by)
       VALUES ($1,$2,'referral_link',$3,$4,$5,$6) RETURNING *`,
      [req.params.id, channel_name, refCode, refUrl, commission_rate || null, req.user.id]);
    res.status(201).json({ channel: result.rows[0] });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

router.put('/:id/channels/:chId/toggle', authMiddleware, adminOnly, requireMenu('agents'), async (req, res) => {
  try { await pool.query('UPDATE agent_channels SET is_active = NOT is_active WHERE id = $1 AND agent_id = $2', [req.params.chId, req.params.id]); res.json({ success: true }); }
  catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
