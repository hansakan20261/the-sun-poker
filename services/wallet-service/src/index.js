require('dotenv').config();
const express = require('express');
const cors = require('cors');
const walletRoutes = require('./routes/wallet');
const adminWalletRoutes = require('./routes/admin-wallet');
const adminUsersRoutes = require('./routes/admin-users');
const adminAgentsRoutes = require('./routes/admin-agents');
const adminGamesRoutes = require('./routes/admin-games');
const adminClubsRoutes = require('./routes/admin-clubs');
const adminSettingsRoutes = require('./routes/admin-settings');
const adminConfigRoutes = require('./routes/admin-config');
const adminShopRoutes = require('./routes/admin-shop');
const adminReportsRoutes = require('./routes/admin-reports');
const adminPermissionsRoutes = require('./routes/admin-permissions');
const adminTournamentsRoutes = require('./routes/admin-tournaments');
const permissionsMenuRoutes = require('./routes/permissions-menu');
const { pool } = require('./db');
const { executeCleanup, loadCleanupSettings } = require('./cleanup-service');
const { getConfig } = require('./config-service');
const { ConfigRevisionTracker, startConfigListener } = require('../../../config/config-events');
const { CONFIG_DEFINITIONS } = require('../../../config/config-definitions');
const { syncConfigDefinitions } = require('../../../config/config-platform');
const { corsOriginConfig } = require('../../../config/cors');

const app = express();
const PORT = process.env.PORT || 3002;
const configTracker = new ConfigRevisionTracker('wallet-service', Object.keys(CONFIG_DEFINITIONS));
let configListener = null;

app.use(cors({ origin: corsOriginConfig() }));
app.use(express.json());

app.get('/health', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW()');
    res.json({ status: 'ok', service: 'wallet', db: result.rows[0].now, config: configTracker.status() });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

app.get('/ready', async (req, res) => {
  try {
    const config = await configTracker.reconcile(pool);
    const definitionCount = await syncConfigDefinitions(pool);
    res.json({ status: 'ready', service: 'wallet', config, config_definitions: definitionCount });
  } catch (err) {
    res.status(503).json({ status: 'not_ready', service: 'wallet', error: err.message, config: configTracker.status() });
  }
});

app.use('/wallet', walletRoutes);
app.use('/admin', adminWalletRoutes);
app.use('/admin/users', adminUsersRoutes);
app.use('/admin/agents', adminAgentsRoutes);
app.use('/admin/games', adminGamesRoutes);
app.use('/admin/clubs', adminClubsRoutes);
app.use('/admin/settings', adminSettingsRoutes);
app.use('/admin/config', adminConfigRoutes);
app.use('/admin/shop', adminShopRoutes);
app.use('/admin/reports', adminReportsRoutes);
app.use('/admin/permissions', adminPermissionsRoutes);
app.use('/admin/tournaments', adminTournamentsRoutes);
app.use('/permissions-menu', permissionsMenuRoutes);

// Player APIs
const clubsRoutes = require('./routes/clubs');
const gameTablesRoutes = require('./routes/game-tables');
const shopRoutes = require('./routes/shop');
const profileRoutes = require('./routes/profile');
app.use('/clubs', clubsRoutes);
app.use('/tables', gameTablesRoutes);
app.use('/shop', shopRoutes);
app.use('/profile', profileRoutes);

const leaderboardRoutes = require('./routes/leaderboard');
const agentPortalRoutes = require('./routes/agent-portal');
const tournamentsRoutes = require('./routes/tournaments');
app.use('/leaderboard', leaderboardRoutes);
app.use('/agent-portal', agentPortalRoutes);
app.use('/tournaments', tournamentsRoutes);

const dailyBonusRoutes = require('./routes/daily-bonus');
app.use('/daily-bonus', dailyBonusRoutes);

const practiceRoutes = require('./routes/practice');
app.use('/practice', practiceRoutes);

const pokerTournamentsRoutes = require('./routes/poker-tournaments');
app.use('/poker/tournaments', pokerTournamentsRoutes);

const antiCheatRoutes = require('./routes/anti-cheat');
const notificationsRoutes = require('./routes/notifications');
const appSettingsRoutes = require('./routes/app-settings');
app.use('/admin/anti-cheat', antiCheatRoutes);
app.use('/notifications', notificationsRoutes);
app.use('/settings', appSettingsRoutes);

app.listen(PORT, () => {
  console.log(`💰 Wallet Service running on port ${PORT}`);

  configTracker.reconcile(pool)
    .then(() => syncConfigDefinitions(pool))
    .then(() => {
      configListener = startConfigListener({
        tracker: configTracker,
        onEvent: () => configTracker.reconcile(pool).catch(error => {
          configTracker.lastError = error.message;
        }),
      });
    })
    .catch(error => {
      configTracker.listenerState = 'not_ready';
      configTracker.lastError = error.message;
      console.error('Config readiness failed:', error.message);
    });

  // ═══ Auto-Cleanup: ลบห้องที่ผู้เล่นสร้างตามเวลาที่ตั้ง ═══
  let cleanupTimer;
  let cleanupRunning = false;
  const scheduleCleanup = async () => {
    clearTimeout(cleanupTimer);
    try {
      const settings = await loadCleanupSettings(pool);
      cleanupTimer = setTimeout(async () => {
        if (!cleanupRunning) {
          cleanupRunning = true;
          try {
            const lock = await pool.query('SELECT pg_try_advisory_lock(731904) AS acquired');
            if (lock.rows[0]?.acquired) {
              try {
                const current = await loadCleanupSettings(pool);
                if (current.enabled) await executeCleanup(pool, current, { source: 'scheduler' });
                const securityPolicy = await getConfig(pool, 'security_policy');
                await pool.query(
                  `DELETE FROM admin_activity_log
                   WHERE created_at < NOW() - INTERVAL '1 day' * $1`,
                  [securityPolicy.audit_retention_days],
                );
                await pool.query(
                  `DELETE FROM user_sessions
                   WHERE expires_at < NOW()
                     AND created_at < NOW() - INTERVAL '1 day' * $1`,
                  [securityPolicy.audit_retention_days],
                );
              } finally {
                await pool.query('SELECT pg_advisory_unlock(731904)').catch(() => {});
              }
            }
          } catch (err) {
            console.error('Auto-cleanup error:', err.message);
          } finally {
            cleanupRunning = false;
          }
        }
        scheduleCleanup();
      }, settings.cleanup_worker_interval_sec * 1000);
    } catch (err) {
      console.error('Auto-cleanup config error:', err.message);
    }
  };

  scheduleCleanup();

  // ═══ Rake aggregation worker ═══
  let rakeTimer;
  let rakeRunning = false;
  const scheduleRakeAggregation = async () => {
    clearTimeout(rakeTimer);
    try {
      const gameRuntime = await getConfig(pool, 'game_runtime');
      const interval = (gameRuntime.rake_aggregation_interval_sec || 3600) * 1000;
      rakeTimer = setTimeout(async () => {
        if (!rakeRunning) {
          rakeRunning = true;
          try {
            const lock = await pool.query('SELECT pg_try_advisory_lock(731905) AS acquired');
            if (lock.rows[0]?.acquired) {
              try {
                const startOfDay = new Date();
                startOfDay.setUTCHours(0, 0, 0, 0);
                const result = await pool.query(
                  `SELECT COALESCE(SUM(rake_amount), 0) AS total
                   FROM game_hands
                   WHERE ended_at >= $1`,
                  [startOfDay.toISOString()],
                );
                await pool.query(
                  `INSERT INTO admin_activity_log (admin_id, action, target_type, details)
                   VALUES ($1, 'rake_aggregation', 'system', $2)`,
                  [null, JSON.stringify({ total_rake: result.rows[0].total, date: startOfDay.toISOString() })],
                );
              } finally {
                await pool.query('SELECT pg_advisory_unlock(731905)').catch(() => {});
              }
            }
          } catch (err) {
            console.error('Rake aggregation error:', err.message);
          } finally {
            rakeRunning = false;
          }
        }
        scheduleRakeAggregation();
      }, interval);
    } catch (err) {
      console.error('Rake aggregation config error:', err.message);
    }
  };

  scheduleRakeAggregation();

  // ═══ Notification worker ═══
  let notificationTimer;
  let notificationRunning = false;
  const scheduleNotifications = async () => {
    clearTimeout(notificationTimer);
    try {
      const notificationPolicy = await getConfig(pool, 'notification_policy');
      const interval = (notificationPolicy.worker_interval_sec || 60) * 1000;
      const maxRetries = notificationPolicy.max_retry_count || 3;
      notificationTimer = setTimeout(async () => {
        if (!notificationRunning) {
          notificationRunning = true;
          try {
            const lock = await pool.query('SELECT pg_try_advisory_lock(731906) AS acquired');
            if (lock.rows[0]?.acquired) {
              try {
                const pending = await pool.query(
                  `SELECT id, payload, error_count FROM notification_queue
                   WHERE status = 'pending' AND scheduled_at <= NOW()
                   ORDER BY scheduled_at ASC
                   LIMIT 100`,
                );
                for (const row of pending.rows) {
                  try {
                    await pool.query(
                      `UPDATE notification_queue
                       SET status = 'sent', processed_at = NOW()
                       WHERE id = $1`,
                      [row.id],
                    );
                  } catch (sendErr) {
                    const nextError = row.error_count + 1;
                    const newStatus = nextError >= maxRetries ? 'failed' : 'pending';
                    await pool.query(
                      `UPDATE notification_queue
                       SET error_count = $1, status = $2
                       WHERE id = $3`,
                      [nextError, newStatus, row.id],
                    );
                    console.error('Notification send failed:', sendErr.message);
                  }
                }
              } finally {
                await pool.query('SELECT pg_advisory_unlock(731906)').catch(() => {});
              }
            }
          } catch (err) {
            console.error('Notification worker error:', err.message);
          } finally {
            notificationRunning = false;
          }
        }
        scheduleNotifications();
      }, interval);
    } catch (err) {
      console.error('Notification worker config error:', err.message);
    }
  };

  scheduleNotifications();
});
