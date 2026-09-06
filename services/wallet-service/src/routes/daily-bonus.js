const express = require('express');
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { getConfig } = require('../config-service');

const router = express.Router();

// POST /daily-bonus/claim — Claim today's daily bonus
router.post('/claim', authMiddleware, async (req, res) => {
  const client = await pool.connect();
  try {
    const userId = req.user.id;
    const policy = await getConfig(client, 'wallet_economy_policy');
    const rewards = policy.daily_bonus_reward_schedule;
    const today = new Date().toISOString().split('T')[0]; // UTC date string

    await client.query('BEGIN');

    // Check if already claimed today
    const existing = await client.query(
      'SELECT id FROM daily_bonuses WHERE user_id = $1 AND claimed_date = $2',
      [userId, today]
    );
    if (existing.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Already claimed today' });
    }

    // Determine streak: find most recent claim
    const lastClaim = await client.query(
      `SELECT day_number, claimed_date, streak_count
       FROM daily_bonuses WHERE user_id = $1
       ORDER BY claimed_date DESC LIMIT 1`,
      [userId]
    );

    let dayNumber = 1;
    let streakCount = 1;

    if (lastClaim.rows.length > 0) {
      const last = lastClaim.rows[0];
      const yesterday = new Date();
      yesterday.setUTCDate(yesterday.getUTCDate() - 1);
      const yesterdayStr = yesterday.toISOString().split('T')[0];

      // Compare claimed_date (Date object from pg) to yesterday string
      const lastDateStr = last.claimed_date instanceof Date
        ? last.claimed_date.toISOString().split('T')[0]
        : String(last.claimed_date);

      if (lastDateStr === yesterdayStr) {
        // Consecutive day — advance streak
        streakCount = last.streak_count + 1;
        dayNumber = (last.day_number % rewards.length) + 1;
      }
      // else: streak broken, reset to day 1, streak 1
    }

    const coinsAwarded = rewards[dayNumber - 1];

    // Credit wallet
    await client.query(
      'UPDATE wallets SET balance = balance + $1 WHERE user_id = $2',
      [coinsAwarded, userId]
    );

    // Record daily bonus claim
    await client.query(
      `INSERT INTO daily_bonuses (user_id, day_number, coins_awarded, streak_count, claimed_date)
       VALUES ($1, $2, $3, $4, $5)`,
      [userId, dayNumber, coinsAwarded, streakCount, today]
    );

    // Record transaction with updated balance
    await client.query(
      `INSERT INTO transactions (user_id, type, amount, balance_after, description)
       VALUES ($1, 'daily_bonus', $2, (SELECT balance FROM wallets WHERE user_id = $1), $3)`,
      [userId, coinsAwarded, `Day ${dayNumber} daily bonus`]
    );

    await client.query('COMMIT');

    const balanceResult = await client.query(
      'SELECT balance FROM wallets WHERE user_id = $1',
      [userId]
    );

    res.json({
      success: true,
      dayNumber,
      coinsAwarded,
      streakCount,
      newBalance: Number(balanceResult.rows[0].balance),
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Daily bonus claim error:', err);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// GET /daily-bonus/status — Check current daily bonus status
router.get('/status', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const policy = await getConfig(pool, 'wallet_economy_policy');
    const rewards = policy.daily_bonus_reward_schedule;
    const today = new Date().toISOString().split('T')[0];

    // Find the most recent claim for this user
    const lastClaim = await pool.query(
      `SELECT day_number, claimed_date, streak_count
       FROM daily_bonuses WHERE user_id = $1
       ORDER BY claimed_date DESC LIMIT 1`,
      [userId]
    );

    let dayNumber = 1;
    let streakCount = 0;
    let canClaim = true;

    if (lastClaim.rows.length > 0) {
      const last = lastClaim.rows[0];
      const lastDateStr = last.claimed_date instanceof Date
        ? last.claimed_date.toISOString().split('T')[0]
        : String(last.claimed_date);

      if (lastDateStr === today) {
        // Already claimed today
        canClaim = false;
        dayNumber = last.day_number;
        streakCount = last.streak_count;
      } else {
        const yesterday = new Date();
        yesterday.setUTCDate(yesterday.getUTCDate() - 1);
        const yesterdayStr = yesterday.toISOString().split('T')[0];

        if (lastDateStr === yesterdayStr) {
          // Consecutive day — show next day info
          streakCount = last.streak_count;
          dayNumber = (last.day_number % rewards.length) + 1;
        }
        // else: streak broken, defaults apply (day 1, streak 0)
      }
    }

    const rewardSchedule = rewards.map((coins, i) => ({
      day: i + 1,
      coins,
    }));

    res.json({
      dayNumber,
      canClaim,
      streakCount,
      rewardSchedule,
    });
  } catch (err) {
    console.error('Daily bonus status error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
