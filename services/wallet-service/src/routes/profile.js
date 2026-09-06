const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { getConfig } = require('../config-service');

const router = express.Router();

// GET /profile/me
router.get('/me', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.display_name, u.email, u.phone, u.avatar_url,
              u.bio, u.vip_level, u.locale, u.created_at, w.balance,
              ps.total_games, ps.total_wins, ps.win_rate, ps.biggest_pot_won, ps.hands_played
       FROM users u LEFT JOIN wallets w ON w.user_id = u.id
       LEFT JOIN player_stats ps ON ps.user_id = u.id WHERE u.id = $1`, [req.user.id]
    );
    res.json({ profile: result.rows[0] });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /profile/me
router.put('/me', authMiddleware, async (req, res) => {
  try {
    const { display_name, bio, locale, avatar_url } = req.body;
    await pool.query(
      `UPDATE users SET display_name=COALESCE($1,display_name), bio=COALESCE($2,bio),
       locale=COALESCE($3,locale), avatar_url=COALESCE($4,avatar_url), updated_at=NOW() WHERE id=$5`,
      [display_name, bio, locale, avatar_url, req.user.id]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /profile/change-password
router.put('/change-password', authMiddleware, async (req, res) => {
  try {
    const { current_password, new_password } = req.body;
    const securityPolicy = await getConfig(pool, 'security_policy');
    if (!current_password || !new_password || new_password.length < securityPolicy.password_min_length) {
      return res.status(400).json({ error: `รหัสผ่านใหม่ต้องมีอย่างน้อย ${securityPolicy.password_min_length} ตัวอักษร` });
    }
    const bcrypt = require('bcrypt');
    const user = await pool.query('SELECT password_hash FROM users WHERE id = $1', [req.user.id]);
    const valid = await bcrypt.compare(current_password, user.rows[0].password_hash);
    if (!valid) return res.status(401).json({ error: 'รหัสผ่านปัจจุบันไม่ถูกต้อง' });
    const hash = await bcrypt.hash(new_password, securityPolicy.password_hash_rounds);
    await pool.query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2', [hash, req.user.id]);
    res.json({ success: true, message: 'เปลี่ยนรหัสผ่านสำเร็จ' });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// DELETE /profile/delete-account
router.delete('/delete-account', authMiddleware, async (req, res) => {
  const client = await pool.connect();
  try {
    const { password } = req.body;
    if (!password) return res.status(400).json({ error: 'กรุณากรอกรหัสผ่าน' });
    const bcrypt = require('bcrypt');
    const user = await client.query('SELECT password_hash FROM users WHERE id = $1', [req.user.id]);
    const valid = await bcrypt.compare(password, user.rows[0].password_hash);
    if (!valid) return res.status(401).json({ error: 'รหัสผ่านไม่ถูกต้อง' });
    await client.query('BEGIN');
    await client.query('DELETE FROM wallets WHERE user_id = $1', [req.user.id]);
    await client.query('DELETE FROM player_stats WHERE user_id = $1', [req.user.id]);
    await client.query('DELETE FROM transactions WHERE user_id = $1', [req.user.id]);
    await client.query("UPDATE users SET is_suspended = TRUE, username = username || '_deleted_' || NOW()::text, email = NULL, phone = NULL, updated_at = NOW() WHERE id = $1", [req.user.id]);
    await client.query('COMMIT');
    res.json({ success: true, message: 'ลบบัญชีสำเร็จ' });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: 'Internal server error' });
  } finally { client.release(); }
});

// GET /friends
router.get('/friends', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT f.*, u.username, u.display_name, u.avatar_url FROM friendships f
       JOIN users u ON u.id = CASE WHEN f.user_id = $1 THEN f.friend_id ELSE f.user_id END
       WHERE (f.user_id = $1 OR f.friend_id = $1) AND f.status = 'accepted'`, [req.user.id]
    );
    res.json({ friends: result.rows });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// POST /friends/request/:userId
router.post('/friends/request/:userId', authMiddleware, async (req, res) => {
  try {
    await pool.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1,$2,'pending')
       ON CONFLICT (user_id, friend_id) DO NOTHING`, [req.user.id, req.params.userId]
    );
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

module.exports = router;
