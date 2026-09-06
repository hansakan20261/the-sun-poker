const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { getRequiredConfig } = require('../config-service');

const router = express.Router();

// GET /admin/users/search?q=username — ค้นหาผู้ใช้
router.get('/users/search', authMiddleware, adminOnly, requireMenu('finance'), async (req, res) => {
  try {
    const { q } = req.query;
    if (!q) return res.status(400).json({ error: 'Search query required' });
    const result = await pool.query(
      `SELECT u.id, u.username, u.email, u.phone, u.display_name, u.role,
              u.is_suspended, u.avatar_url, u.created_at, w.balance
       FROM users u LEFT JOIN wallets w ON w.user_id = u.id
       WHERE u.username ILIKE $1 OR u.email ILIKE $1 OR u.phone ILIKE $1 OR u.display_name ILIKE $1
       LIMIT 1`,
      [`%${q}%`]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'User not found' });
    res.json({ user: result.rows[0] });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /admin/users/:userId/credit — Admin เติมเหรียญให้ผู้เล่น
router.post('/users/:userId/credit', authMiddleware, adminOnly, requireMenu('finance'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { userId } = req.params;
    const { cash_amount, note, slip_image_url } = req.body;

    if (!cash_amount || cash_amount <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const [coinSettings, economyPolicy] = await Promise.all([
      getRequiredConfig(client, 'coin_settings'),
      getRequiredConfig(client, 'wallet_economy_policy'),
    ]);
    if (economyPolicy.admin_adjustment_requires_reason && !note?.trim()) {
      return res.status(400).json({ error: 'Adjustment reason is required' });
    }
    if (cash_amount < coinSettings.min_deposit_thb || cash_amount > coinSettings.max_deposit_thb_per_day) {
      return res.status(400).json({ error: 'Deposit amount is outside configured bounds' });
    }
    const rate = coinSettings.deposit_rate;
    const coinAmount = Math.floor(cash_amount * rate);
    if (coinAmount > economyPolicy.max_transfer_amount) {
      return res.status(400).json({ error: 'Transfer exceeds configured maximum' });
    }
    const todayCredits = await client.query(
      `SELECT COALESCE(SUM(cash_amount), 0) AS total
       FROM admin_coin_transactions
       WHERE user_id = $1 AND type = 'credit' AND created_at::date = CURRENT_DATE`,
      [userId],
    );
    if (Number(todayCredits.rows[0].total) + cash_amount > coinSettings.max_deposit_thb_per_day) {
      return res.status(400).json({ error: 'Daily deposit limit exceeded' });
    }

    await client.query('BEGIN');

    // ดึงยอดปัจจุบัน
    const walletResult = await client.query(
      'SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE', [userId]
    );
    if (walletResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'User wallet not found' });
    }

    const balanceBefore = Number(walletResult.rows[0].balance);
    const balanceAfter = balanceBefore + coinAmount;

    // อัปเดตยอดเหรียญ
    await client.query(
      'UPDATE wallets SET balance = $1, updated_at = NOW() WHERE user_id = $2',
      [balanceAfter, userId]
    );

    // บันทึก transactions
    await client.query(
      `INSERT INTO transactions (user_id, type, amount, balance_after, description)
       VALUES ($1, 'admin_credit', $2, $3, $4)`,
      [userId, coinAmount, balanceAfter, note || 'Admin credit']
    );

    // บันทึก admin_coin_transactions (audit)
    await client.query(
      `INSERT INTO admin_coin_transactions
       (admin_id, user_id, type, coin_amount, cash_amount, exchange_rate,
        balance_before, balance_after, note, slip_image_url)
       VALUES ($1, $2, 'credit', $3, $4, $5, $6, $7, $8, $9)`,
      [req.user.id, userId, coinAmount, cash_amount, rate,
       balanceBefore, balanceAfter, note, slip_image_url]
    );

    // บันทึก admin activity log
    await client.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'credit_coins', 'user', $2, $3)`,
      [req.user.id, userId, JSON.stringify({ coinAmount, cash_amount, rate })]
    );

    await client.query('COMMIT');

    res.json({
      success: true,
      coin_amount: coinAmount,
      cash_amount,
      exchange_rate: rate,
      balance_before: balanceBefore,
      balance_after: balanceAfter,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Credit error:', err);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// POST /admin/users/:userId/debit — Admin ถอนเหรียญจากผู้เล่น
router.post('/users/:userId/debit', authMiddleware, adminOnly, requireMenu('finance'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { userId } = req.params;
    const { coin_amount, note } = req.body;

    if (!coin_amount || coin_amount <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const [coinSettings, economyPolicy] = await Promise.all([
      getRequiredConfig(client, 'coin_settings'),
      getRequiredConfig(client, 'wallet_economy_policy'),
    ]);
    if (economyPolicy.admin_adjustment_requires_reason && !note?.trim()) {
      return res.status(400).json({ error: 'Adjustment reason is required' });
    }
    if (coin_amount < coinSettings.min_withdrawal_coins || coin_amount > coinSettings.max_withdrawal_coins_per_day) {
      return res.status(400).json({ error: 'Withdrawal amount is outside configured bounds' });
    }
    if (coin_amount > economyPolicy.max_transfer_amount) {
      return res.status(400).json({ error: 'Transfer exceeds configured maximum' });
    }
    const rate = coinSettings.withdrawal_rate;
    const cashAmount = coin_amount * rate;
    const todayDebits = await client.query(
      `SELECT COALESCE(SUM(coin_amount), 0) AS total
       FROM admin_coin_transactions
       WHERE user_id = $1 AND type = 'debit' AND created_at::date = CURRENT_DATE`,
      [userId],
    );
    if (Number(todayDebits.rows[0].total) + coin_amount > coinSettings.max_withdrawal_coins_per_day) {
      return res.status(400).json({ error: 'Daily withdrawal limit exceeded' });
    }

    await client.query('BEGIN');

    const walletResult = await client.query(
      'SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE', [userId]
    );
    if (walletResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'User wallet not found' });
    }

    const balanceBefore = Number(walletResult.rows[0].balance);
    if (balanceBefore < coin_amount) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Insufficient balance' });
    }

    const balanceAfter = balanceBefore - coin_amount;

    await client.query(
      'UPDATE wallets SET balance = $1, updated_at = NOW() WHERE user_id = $2',
      [balanceAfter, userId]
    );

    await client.query(
      `INSERT INTO transactions (user_id, type, amount, balance_after, description)
       VALUES ($1, 'admin_debit', $2, $3, $4)`,
      [userId, -coin_amount, balanceAfter, note || 'Admin debit']
    );

    await client.query(
      `INSERT INTO admin_coin_transactions
       (admin_id, user_id, type, coin_amount, cash_amount, exchange_rate,
        balance_before, balance_after, note)
       VALUES ($1, $2, 'debit', $3, $4, $5, $6, $7, $8)`,
      [req.user.id, userId, coin_amount, cashAmount, rate,
       balanceBefore, balanceAfter, note]
    );

    await client.query(
      `INSERT INTO admin_activity_log (admin_id, action, target_type, target_id, details)
       VALUES ($1, 'debit_coins', 'user', $2, $3)`,
      [req.user.id, userId, JSON.stringify({ coin_amount, cashAmount, rate })]
    );

    await client.query('COMMIT');

    res.json({
      success: true,
      coin_amount,
      cash_amount: cashAmount,
      exchange_rate: rate,
      balance_before: balanceBefore,
      balance_after: balanceAfter,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Debit error:', err);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// GET /admin/coin-transactions — ดูประวัติเติม/ถอนทั้งระบบ
router.get('/coin-transactions', authMiddleware, adminOnly, requireMenu('finance'), async (req, res) => {
  try {
    const { userId, type, limit = 20, offset = 0 } = req.query;
    let query = `SELECT act.*, u.username as user_username, a.username as admin_username
                 FROM admin_coin_transactions act
                 JOIN users u ON u.id = act.user_id
                 JOIN users a ON a.id = act.admin_id
                 WHERE 1=1`;
    const params = [];

    if (userId) {
      params.push(userId);
      query += ` AND act.user_id = $${params.length}`;
    }
    if (type) {
      params.push(type);
      query += ` AND act.type = $${params.length}`;
    }

    params.push(Number(limit));
    query += ` ORDER BY act.created_at DESC LIMIT $${params.length}`;
    params.push(Number(offset));
    query += ` OFFSET $${params.length}`;

    const result = await pool.query(query, params);
    res.json({ transactions: result.rows });
  } catch (err) {
    console.error('Coin transactions error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
