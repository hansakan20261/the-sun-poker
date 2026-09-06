const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');

const router = express.Router();

async function agentOnly(req, res, next) {
  if (req.user.role !== 'agent') return res.status(403).json({ error: 'Agent access required' });
  try {
    const result = await pool.query("SELECT id FROM agents WHERE user_id = $1 AND status = 'active'", [req.user.id]);
    if (result.rows.length === 0) return res.status(403).json({ error: 'Active agent account required' });
    req.agentId = result.rows[0].id;
    next();
  } catch {
    res.status(500).json({ error: 'Internal server error' });
  }
}

// GET /agent-portal/dashboard
router.get('/dashboard', authMiddleware, agentOnly, requireMenu('agent-dashboard'), async (req, res) => {
  try {
    const agent = await pool.query('SELECT * FROM agents WHERE user_id = $1', [req.user.id]);
    if (agent.rows.length === 0) return res.status(404).json({ error: 'Agent not found' });
    const a = agent.rows[0];

    const channels = await pool.query(
      'SELECT * FROM agent_channels WHERE agent_id = $1 ORDER BY created_at', [a.id]);
    const customerCount = await pool.query(
      'SELECT COUNT(*) as total FROM agent_referrals WHERE agent_id = $1', [a.id]);
    const recentCommissions = await pool.query(
      `SELECT ac.*, u.username FROM agent_commissions ac
       JOIN users u ON u.id = ac.user_id WHERE ac.agent_id = $1
       ORDER BY ac.created_at DESC LIMIT 10`, [a.id]);

    res.json({
      agent: a,
      channels: channels.rows,
      customer_count: Number(customerCount.rows[0].total),
      recent_commissions: recentCommissions.rows,
    });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /agent-portal/customers
router.get('/customers', authMiddleware, agentOnly, requireMenu('agent-players'), async (req, res) => {
  try {
    const agent = await pool.query('SELECT id FROM agents WHERE user_id = $1', [req.user.id]);
    if (agent.rows.length === 0) return res.status(404).json({ error: 'Agent not found' });

    const result = await pool.query(
      `SELECT ar.referred_at, u.id, u.username, u.display_name, u.created_at,
              w.balance, ac.channel_name
       FROM agent_referrals ar
       JOIN users u ON u.id = ar.user_id
       LEFT JOIN wallets w ON w.user_id = u.id
       LEFT JOIN agent_channels ac ON ac.id = ar.channel_id
       WHERE ar.agent_id = $1 ORDER BY ar.referred_at DESC`, [agent.rows[0].id]
    );
    res.json({ customers: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /agent-portal/earnings
router.get('/earnings', authMiddleware, agentOnly, requireMenu('agent-wallet'), async (req, res) => {
  try {
    const agent = await pool.query('SELECT id FROM agents WHERE user_id = $1', [req.user.id]);
    if (agent.rows.length === 0) return res.status(404).json({ error: 'Agent not found' });

    const byChannel = await pool.query(
      `SELECT ac.channel_name, ac.commission_rate,
              COUNT(acm.id) as tx_count,
              COALESCE(SUM(acm.topup_amount), 0) as total_topup,
              COALESCE(SUM(acm.commission_amount), 0) as total_commission
       FROM agent_channels ac
       LEFT JOIN agent_commissions acm ON acm.channel_id = ac.id
       WHERE ac.agent_id = $1 GROUP BY ac.id, ac.channel_name, ac.commission_rate`,
      [agent.rows[0].id]
    );
    res.json({ by_channel: byChannel.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /agent-portal/withdrawals — ขอถอนเงิน
router.post('/withdrawals', authMiddleware, agentOnly, requireMenu('agent-wallet'), async (req, res) => {
  try {
    const { amount } = req.body;
    const agent = await pool.query('SELECT * FROM agents WHERE user_id = $1', [req.user.id]);
    if (agent.rows.length === 0) return res.status(404).json({ error: 'Agent not found' });
    const a = agent.rows[0];

    if (Number(a.available_balance) < amount) {
      return res.status(400).json({ error: 'Insufficient balance' });
    }

    await pool.query(
      `INSERT INTO agent_withdrawals (agent_id, amount, bank_info)
       VALUES ($1, $2, $3)`, [a.id, amount, a.bank_info]
    );
    await pool.query(
      'UPDATE agents SET available_balance = available_balance - $1 WHERE id = $2', [amount, a.id]
    );
    res.json({ success: true, message: 'Withdrawal request submitted' });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// GET /agent-portal/withdrawals — ประวัติถอนเงิน
router.get('/withdrawals', authMiddleware, agentOnly, requireMenu('agent-wallet'), async (req, res) => {
  try {
    const agent = await pool.query('SELECT id FROM agents WHERE user_id = $1', [req.user.id]);
    if (agent.rows.length === 0) return res.status(404).json({ error: 'Agent not found' });

    const result = await pool.query(
      'SELECT * FROM agent_withdrawals WHERE agent_id = $1 ORDER BY created_at DESC',
      [agent.rows[0].id]
    );
    res.json({ withdrawals: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
