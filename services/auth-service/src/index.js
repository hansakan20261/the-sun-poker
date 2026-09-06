require('dotenv').config();
const express = require('express');
const cors = require('cors');
const authRoutes = require('./routes/auth');
const { pool } = require('./db');
const { ConfigRevisionTracker, startConfigListener } = require('../../../config/config-events');
const { corsOriginConfig } = require('../../../config/cors');

const app = express();
const PORT = process.env.PORT || 3001;
const configTracker = new ConfigRevisionTracker('auth-service', ['app_control', 'security_policy', 'wallet_economy_policy']);
let configListener = null;

app.use(cors({ origin: corsOriginConfig() }));
app.use(express.json());

// Health check
app.get('/health', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW()');
    res.json({ status: 'ok', db: result.rows[0].now, config: configTracker.status() });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

app.get('/ready', async (req, res) => {
  try {
    const config = await configTracker.reconcile(pool);
    res.json({ status: 'ready', service: 'auth', config });
  } catch (err) {
    res.status(503).json({ status: 'not_ready', service: 'auth', error: err.message, config: configTracker.status() });
  }
});

// Routes
app.use('/auth', authRoutes);

app.listen(PORT, () => {
  console.log(`🔑 Auth Service running on port ${PORT}`);
  configTracker.reconcile(pool)
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
});
