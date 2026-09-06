const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();

// GET /wallet/balance — ดูยอดเหรียญ
router.get('/balance', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT balance FROM wallets WHERE user_id = $1', [req.user.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Wallet not found' });
    }
    res.json({ balance: Number(result.rows[0].balance) });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /wallet/transactions — ประวัติธุรกรรม
router.get('/transactions', authMiddleware, async (req, res) => {
  try {
    const { limit = 20, offset = 0, type } = req.query;
    let query = 'SELECT * FROM transactions WHERE user_id = $1';
    const params = [req.user.id];

    if (type) {
      if (type === 'game') {
        query += ` AND type LIKE 'game_%'`;
      } else if (type === 'topup') {
        query += ` AND type IN ('topup', 'deposit', 'admin_credit', 'daily_bonus', 'referral_bonus')`;
      } else if (type === 'withdraw') {
        query += ` AND type IN ('withdraw', 'admin_debit')`;
      } else if (type === 'shop') {
        query += ` AND type = 'shop_purchase'`;
      } else {
        query += ' AND type = $2';
        params.push(type);
      }
    }

    query += ' ORDER BY created_at DESC LIMIT $' + (params.length + 1) +
             ' OFFSET $' + (params.length + 2);
    params.push(Number(limit), Number(offset));

    const result = await pool.query(query, params);
    res.json({ transactions: result.rows });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
