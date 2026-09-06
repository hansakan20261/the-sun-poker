const express = require('express');
const { pool } = require('../db');
const { authMiddleware, adminOnly } = require('../middleware/auth');
const { requireMenu } = require('../middleware/menu-permission');
const { getConfig } = require('../config-service');

const router = express.Router();

// GET /admin/shop/items — ดูสินค้าทั้งหมด
router.get('/items', authMiddleware, adminOnly, requireMenu('shop'), async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT si.*, sc.name as category_name, sc.slug as category_slug
       FROM shop_items si JOIN shop_categories sc ON sc.id = si.category_id
       ORDER BY sc.sort_order, si.sort_order`
    );
    const categories = await pool.query('SELECT * FROM shop_categories ORDER BY sort_order');
    res.json({ items: result.rows, categories: categories.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /admin/shop/items — เพิ่มสินค้า
router.post('/items', authMiddleware, adminOnly, requireMenu('shop'), async (req, res) => {
  try {
    const { category_id, name, description, image_url, animation_url, price, is_consumable } = req.body;
    const policy = await getConfig(pool, 'wallet_economy_policy');
    if (!Number.isInteger(Number(price)) || price < 0 || price > policy.max_shop_item_price) {
      return res.status(400).json({ error: `Price must be between 0 and ${policy.max_shop_item_price}` });
    }
    const result = await pool.query(
      `INSERT INTO shop_items (category_id, name, description, image_url, animation_url, price, is_consumable)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [category_id, name, description, image_url, animation_url, price, is_consumable ?? true]
    );
    res.status(201).json({ item: result.rows[0] });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/shop/items/:id — แก้ไขสินค้า
router.put('/items/:id', authMiddleware, adminOnly, requireMenu('shop'), async (req, res) => {
  try {
    const { name, price, is_active, description } = req.body;
    if (price !== undefined) {
      const policy = await getConfig(pool, 'wallet_economy_policy');
      if (!Number.isInteger(Number(price)) || price < 0 || price > policy.max_shop_item_price) {
        return res.status(400).json({ error: `Price must be between 0 and ${policy.max_shop_item_price}` });
      }
    }
    await pool.query(
      `UPDATE shop_items SET name=COALESCE($1,name), price=COALESCE($2,price),
       is_active=COALESCE($3,is_active), description=COALESCE($4,description) WHERE id=$5`,
      [name, price, is_active, description, req.params.id]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /admin/shop/items/:id/toggle — เปิด/ปิดสินค้า
router.put('/items/:id/toggle', authMiddleware, adminOnly, requireMenu('shop'), async (req, res) => {
  try {
    await pool.query('UPDATE shop_items SET is_active = NOT is_active WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
