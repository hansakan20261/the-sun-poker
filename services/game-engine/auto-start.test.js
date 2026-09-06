const test = require('node:test');
const assert = require('node:assert/strict');
const { clearRoomAutoStart, scheduleRoomAutoStart } = require('./src/poker/auto-start');

function createRoom(playerCount, config = {}) {
  return {
    config: { autoStartAt: 3, autoStartDelaySec: 4, ...config },
    players: new Map(Array.from({ length: playerCount }, (_, index) => [index + 1, {}])),
    isPlaying: false,
    _autoStartTimer: null,
    _autoStartStartedAt: null,
    _autoStartDeadlineAt: null,
  };
}

test('auto-start schedules from the room threshold and delay', () => {
  const room = createRoom(3);
  let delay;
  let handler;
  const scheduled = scheduleRoomAutoStart(room, () => {}, {
    now: () => 1000,
    setTimer: (callback, milliseconds) => {
      handler = callback;
      delay = milliseconds;
      return { id: 'timer' };
    },
  });
  assert.equal(scheduled, true);
  assert.equal(delay, 4000);
  assert.equal(room._autoStartStartedAt, 1000);
  assert.equal(room._autoStartDeadlineAt, 5000);
  assert.equal(typeof handler, 'function');
});

test('auto-start does not schedule below the configured threshold', () => {
  const room = createRoom(2);
  let scheduledCount = 0;
  assert.equal(scheduleRoomAutoStart(room, () => {}, {
    setTimer: () => { scheduledCount++; },
  }), false);
  assert.equal(scheduledCount, 0);
});

test('auto-start cancels when player count drops below threshold', () => {
  const room = createRoom(3);
  const timerId = { id: 'timer' };
  let cleared;
  scheduleRoomAutoStart(room, () => {}, { setTimer: () => timerId });
  room.players.delete(3);
  assert.equal(scheduleRoomAutoStart(room, () => {}, {
    clearTimer: (id) => { cleared = id; },
  }), false);
  assert.equal(cleared, timerId);
  assert.equal(room._autoStartDeadlineAt, null);
});

test('auto-start callback rechecks threshold before starting', () => {
  const room = createRoom(3);
  let handler;
  let starts = 0;
  scheduleRoomAutoStart(room, () => { starts++; }, {
    setTimer: (callback) => {
      handler = callback;
      return { id: 'timer' };
    },
  });
  room.players.delete(3);
  handler();
  assert.equal(starts, 0);
});

test('clearing auto-start removes timer and countdown state', () => {
  const room = createRoom(3);
  const timerId = { id: 'timer' };
  let cleared;
  scheduleRoomAutoStart(room, () => {}, { setTimer: () => timerId });
  clearRoomAutoStart(room, (id) => { cleared = id; });
  assert.equal(cleared, timerId);
  assert.equal(room._autoStartTimer, null);
  assert.equal(room._autoStartStartedAt, null);
  assert.equal(room._autoStartDeadlineAt, null);
});
