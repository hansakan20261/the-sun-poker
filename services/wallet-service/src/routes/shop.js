const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { getConfig } = require('../config-service');

const router = express.Router();

// GET /shop/items
router.get('/items', authMiddleware, async (req, res) => {
  try {
    const { category } = req.query;
    let query = `SELECT si.*, sc.name as category_name, sc.slug as category_slug
                 FROM shop_items si JOIN shop_categories sc ON sc.id = si.category_id
                 WHERE si.is_active = TRUE`;
    const params = [];
    if (category) { params.push(category); query += ` AND sc.slug = $${params.length}`; }
    query += ' ORDER BY sc.sort_order, si.sort_order';
    const result = await pool.query(query, params);
    const categories = await pool.query('SELECT * FROM shop_categories WHERE is_active = TRUE ORDER BY sort_order');
    res.json({ items: result.rows, categories: categories.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /shop/purchase — ซื้อสินค้า
router.post('/purchase', authMiddleware, async (req, res) => {
  const client = await pool.connect();
  try {
    const { item_id, quantity } = req.body;
    const policy = await getConfig(client, 'wallet_economy_policy');
    const qty = quantity ?? policy.shop_default_quantity;
    if (!Number.isInteger(qty) || qty < 1) return res.status(400).json({ error: 'Invalid quantity' });
    await client.query('BEGIN');
    const todayCount = await client.query(
      `SELECT COALESCE(SUM(quantity), 0) AS total FROM shop_purchases
       WHERE user_id = $1 AND created_at::date = CURRENT_DATE`,
      [req.user.id],
    );
    if (Number(todayCount.rows[0].total) + qty > policy.max_shop_items_per_day) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Daily purchase limit reached' });
    }
    const item = await client.query('SELECT * FROM shop_items WHERE id = $1 AND is_active = TRUE', [item_id]);
    if (item.rows.length === 0) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Item not found' }); }
    const totalPrice = Number(item.rows[0].price) * qty;
    const wallet = await client.query('SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE', [req.user.id]);
    if (Number(wallet.rows[0].balance) < totalPrice) { await client.query('ROLLBACK'); return res.status(400).json({ error: 'Insufficient balance' }); }

    await client.query('UPDATE wallets SET balance = balance - $1 WHERE user_id = $2', [totalPrice, req.user.id]);
    await client.query(`INSERT INTO shop_purchases (user_id, item_id, quantity, total_price) VALUES ($1,$2,$3,$4)`,
      [req.user.id, item_id, qty, totalPrice]);
    await client.query(`INSERT INTO user_inventory (user_id, item_id, quantity) VALUES ($1,$2,$3)
      ON CONFLICT (user_id, item_id) DO UPDATE SET quantity = user_inventory.quantity + $3`,
      [req.user.id, item_id, qty]);
    await client.query(`INSERT INTO transactions (user_id, type, amount, balance_after, reference_id)
      VALUES ($1,'shop_purchase',$2,(SELECT balance FROM wallets WHERE user_id=$1),$3)`,
      [req.user.id, -totalPrice, item_id]);
    await client.query('COMMIT');
    res.json({ success: true, total_price: totalPrice });
  } catch (err) { await client.query('ROLLBACK'); res.status(500).json({ error: 'Internal server error' }); }
  finally { client.release(); }
});

// GET /shop/inventory — ดูของที่มี
router.get('/inventory', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT ui.*, si.name, si.image_url, si.animation_url, sc.slug as category
       FROM user_inventory ui JOIN shop_items si ON si.id = ui.item_id
       JOIN shop_categories sc ON sc.id = si.category_id WHERE ui.user_id = $1`, [req.user.id]
    );
    res.json({ inventory: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
