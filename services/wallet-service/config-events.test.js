const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('events');
const {
  CHANNEL,
  ConfigRevisionTracker,
  notifyConfigChanged,
  startConfigListener,
} = require('../../config/config-events');

test('config publish sends a typed PostgreSQL notification inside the transaction', async () => {
  const calls = [];
  await notifyConfigChanged(
    { query: async (text, params) => { calls.push({ text, params }); return { rows: [] }; } },
    { keys: ['game_runtime'], revision: 7, actorId: 'admin-1', correlationId: 'corr-1' },
  );
  assert.equal(calls[0].params[0], CHANNEL);
  const payload = JSON.parse(calls[0].params[1]);
  assert.equal(payload.type, 'config_changed');
  assert.equal(payload.revision, 7);
  assert.deepEqual(payload.keys, ['game_runtime']);
});

test('revision tracker reconciles required keys and reports missing config', async () => {
  const tracker = new ConfigRevisionTracker('test', ['room_defaults', 'game_runtime']);
  const pool = {
    query: async () => ({ rows: [
      { key: 'room_defaults', revision: 3 },
      { key: 'game_runtime', revision: 5 },
    ] }),
  };
  const status = await tracker.reconcile(pool);
  assert.deepEqual(status.revisions, { room_defaults: 3, game_runtime: 5 });
  tracker.requiredKeys.push('missing_config');
  await assert.rejects(tracker.reconcile(pool), /missing_config/);
});

test('listener accepts config events and reconciles the subscriber', async () => {
  const tracker = new ConfigRevisionTracker('test', ['room_defaults']);
  const client = new EventEmitter();
  client.connect = async () => {};
  client.end = async () => {};
  client.query = async text => {
    assert.match(text, /LISTEN config_events/);
    return { rows: [] };
  };
  let eventReceived = false;
  const listener = startConfigListener({
    tracker,
    clientFactory: () => client,
    onEvent: () => { eventReceived = true; },
  });
  await new Promise(resolve => setImmediate(resolve));
  client.emit('notification', {
    channel: CHANNEL,
    payload: JSON.stringify({ keys: ['room_defaults'], revision: 8 }),
  });
  await listener.stop();
  assert.equal(eventReceived, true);
  assert.equal(tracker.revisions.get('room_defaults'), 8);

  client.emit('notification', {
    channel: CHANNEL,
    payload: JSON.stringify({ keys: ['room_defaults'], revisions: { room_defaults: 9 } }),
  });
  assert.equal(tracker.revisions.get('room_defaults'), 9);
});

test('listener reconnects after a PostgreSQL notification error', async () => {
  const clients = [];
  const clientFactory = () => {
    const client = new EventEmitter();
    client.connect = async () => {};
    client.end = async () => {};
    client.query = async () => ({ rows: [] });
    clients.push(client);
    return client;
  };
  const tracker = new ConfigRevisionTracker('test', ['room_defaults']);
  const listener = startConfigListener({ tracker, clientFactory, retryMs: 10 });
  await new Promise(resolve => setImmediate(resolve));
  clients[0].emit('error', new Error('connection lost'));
  await new Promise(resolve => setTimeout(resolve, 30));
  await listener.stop();
  assert.equal(clients.length, 2);
  assert.equal(tracker.listenerState, 'stopped');
});
