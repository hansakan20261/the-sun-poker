const { databaseConfigFromEnv } = require('./database-env');

const CHANNEL = 'config_events';

async function notifyConfigChanged(executor, { keys, revision, revisions, actorId, correlationId, applyMode, applyModes }) {
  const payload = JSON.stringify({
    type: 'config_changed',
    keys,
    revision,
    revisions,
    apply_mode: applyMode || null,
    apply_modes: applyModes || null,
    actor_id: actorId || null,
    correlation_id: correlationId || null,
    emitted_at: new Date().toISOString(),
  });
  await executor.query('SELECT pg_notify($1, $2)', [CHANNEL, payload]);
}

class ConfigRevisionTracker {
  constructor(serviceName, requiredKeys = []) {
    this.serviceName = serviceName;
    this.requiredKeys = requiredKeys;
    this.revisions = new Map();
    this.expectedRevisions = new Map();
    this.lastEventAt = null;
    this.lastEvent = null;
    this.listenerState = 'stopped';
    this.lastError = null;
  }

  async reconcile(pool) {
    const result = await pool.query(
      'SELECT key, revision, updated_at FROM system_config WHERE key = ANY($1::varchar[])',
      [this.requiredKeys],
    );
    this.revisions.clear();
    for (const row of result.rows) this.revisions.set(row.key, Number(row.revision || 0));
    const missing = this.requiredKeys.filter(key => !this.revisions.has(key) || this.revisions.get(key) < 1);
    if (missing.length) throw new Error(`Missing required config revisions: ${missing.join(', ')}`);
    const stale = [...this.expectedRevisions.entries()]
      .filter(([key, revision]) => this.requiredKeys.includes(key) && this.revisions.get(key) < revision)
      .map(([key, revision]) => `${key}<${revision}`);
    if (stale.length) throw new Error(`Stale config revisions: ${stale.join(', ')}`);
    return this.status();
  }

  handleEvent(event) {
    this.lastEventAt = new Date().toISOString();
    this.lastEvent = event;
    if (Array.isArray(event.keys)) {
      for (const key of event.keys) {
        const revision = Number(event.revisions?.[key] ?? event.revision);
        if (Number.isInteger(revision) && revision > 0) {
          this.expectedRevisions.set(key, revision);
          this.revisions.set(key, revision);
        }
      }
    }
  }

  status() {
    return {
      service: this.serviceName,
      listener: this.listenerState,
      last_event_at: this.lastEventAt,
      last_event: this.lastEvent,
      last_error: this.lastError,
      revisions: Object.fromEntries(this.revisions),
    };
  }
}

function startConfigListener({ tracker, onEvent, clientFactory, retryMs }) {
  const reconnectDelayMs = Math.max(10, Number(retryMs ?? process.env.CONFIG_LISTEN_RETRY_MS ?? 5000));
  let stopped = false;
  let client = null;
  let reconnectTimer = null;

  const connect = async () => {
    if (stopped) return;
    tracker.listenerState = 'connecting';
    try {
      client = clientFactory
        ? clientFactory()
        : new (require('pg').Client)(databaseConfigFromEnv());
      client.on('notification', message => {
        if (message.channel !== CHANNEL) return;
        try {
          const event = JSON.parse(message.payload || '{}');
          tracker.handleEvent(event);
          if (onEvent) onEvent(event);
        } catch (error) {
          tracker.lastError = `Invalid config event: ${error.message}`;
        }
      });
      client.on('error', error => {
        tracker.listenerState = 'error';
        tracker.lastError = error.message;
        client.end().catch(() => {}).finally(scheduleReconnect);
      });
      client.on('end', scheduleReconnect);
      await client.connect();
      await client.query(`LISTEN ${CHANNEL}`);
      tracker.listenerState = 'listening';
      tracker.lastError = null;
      if (onEvent) onEvent({ type: 'listener_connected', keys: [] });
    } catch (error) {
      tracker.listenerState = 'error';
      tracker.lastError = error.message;
      scheduleReconnect();
    }
  };

  const scheduleReconnect = () => {
    if (stopped || reconnectTimer) return;
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connect();
    }, reconnectDelayMs);
  };

  connect();
  return {
    async stop() {
      stopped = true;
      tracker.listenerState = 'stopped';
      if (reconnectTimer) clearTimeout(reconnectTimer);
      if (client) await client.end().catch(() => {});
    },
  };
}

module.exports = {
  CHANNEL,
  ConfigRevisionTracker,
  notifyConfigChanged,
  startConfigListener,
};
