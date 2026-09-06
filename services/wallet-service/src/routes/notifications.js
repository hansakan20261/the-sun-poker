const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();

// In-app notifications stored in DB
// สร้างตาราง notifications ถ้ายังไม่มี (จะรันตอน startup)
async function ensureTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS notifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) NOT NULL,
        title VARCHAR(200) NOT NULL,
        message TEXT,
        type VARCHAR(30) DEFAULT 'info',
        is_read BOOLEAN DEFAULT FALSE,
        data JSONB,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )`);
    await pool.query('CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, is_read)');
  } catch (_) {}
}
ensureTable();

// GET /notifications — ดูแจ้งเตือนของตัวเอง
router.get('/', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50',
      [req.user.id]
    );
    const unread = await pool.query(
      'SELECT COUNT(*) as count FROM notifications WHERE user_id = $1 AND is_read = FALSE',
      [req.user.id]
    );
    res.json({ notifications: result.rows, unread_count: Number(unread.rows[0].count) });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// PUT /notifications/read-all — อ่านทั้งหมด
router.put('/read-all', authMiddleware, async (req, res) => {
  try {
    await pool.query('UPDATE notifications SET is_read = TRUE WHERE user_id = $1', [req.user.id]);
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: 'Internal server error' }); }
});

// Helper: ส่ง notification (ใช้จาก service อื่น)
async function sendNotification(userId, title, message, type = 'info', data = {}) {
  try {
    await pool.query(
      'INSERT INTO notifications (user_id, title, message, type, data) VALUES ($1,$2,$3,$4,$5)',
      [userId, title, message, type, JSON.stringify(data)]
    );
    // TODO: Push notification via FCM/APNs
    // await sendPushNotification(userId, title, message);
  } catch (err) { console.error('Send notification error:', err); }
}

router.sendNotification = sendNotification;
module.exports = router;
