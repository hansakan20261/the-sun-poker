const test = require('node:test');
const assert = require('node:assert/strict');
const GameRoom = require('./src/poker/game-room');
const { clearRoomTurnTimer, scheduleRoomTurnTimer } = require('./src/poker/turn-timer');
const { TEST_ROOM_CONFIG } = require('./test-room-config');

function scheduleAt(turnTimeSec, now = 1_700_000_000_000) {
  const room = new GameRoom('table-1', { ...TEST_ROOM_CONFIG, turnTimeSec });
  let scheduled;
  let timeoutHandler;
  const timerId = { id: 'timer-1' };
  scheduleRoomTurnTimer(room, () => {}, {
    now: () => now,
    setTimer: (handler, delay) => {
      timeoutHandler = handler;
      scheduled = delay;
      return timerId;
    },
  });
  return { now, room, scheduled, timeoutHandler, timerId };
}

for (const turnTimeSec of [10, 30, 60]) {
  test(`turn timer uses the room-configured ${turnTimeSec} second duration`, () => {
    const { now, room, scheduled, timerId } = scheduleAt(turnTimeSec);
    const state = room.getState();
    assert.equal(scheduled, turnTimeSec * 1000);
    assert.equal(room._turnTimer, timerId);
    assert.equal(state.turnTotalSeconds, turnTimeSec);
    assert.equal(state.turnStartedAt, now);
    assert.equal(state.turnDeadlineAt, now + turnTimeSec * 1000);
  });
}

test('turn timer clears timing state before invoking the timeout handler', () => {
  const room = new GameRoom('table-1', { ...TEST_ROOM_CONFIG, turnTimeSec: 10 });
  let timeoutHandler;
  let stateDuringTimeout;
  scheduleRoomTurnTimer(room, () => {
    stateDuringTimeout = room.getState();
  }, {
    now: () => 1_700_000_000_000,
    setTimer: (handler) => {
      timeoutHandler = handler;
      return { id: 'timer-1' };
    },
  });
  timeoutHandler();
  assert.equal(room._turnTimer, null);
  assert.equal(stateDuringTimeout.turnTotalSeconds, null);
  assert.equal(stateDuringTimeout.turnStartedAt, null);
  assert.equal(stateDuringTimeout.turnDeadlineAt, null);
});

test('clearing a turn timer cancels the scheduled callback and clears state', () => {
  const { room, timerId } = scheduleAt(30);
  let clearedTimer;
  clearRoomTurnTimer(room, (id) => { clearedTimer = id; });
  assert.equal(clearedTimer, timerId);
  assert.equal(room._turnTimer, null);
  assert.equal(room.getState().turnDeadlineAt, null);
});

test('rescheduling cancels the previous room timer', () => {
  const room = new GameRoom('table-1', { ...TEST_ROOM_CONFIG, turnTimeSec: 30 });
  const firstTimer = { id: 'timer-1' };
  const secondTimer = { id: 'timer-2' };
  const cleared = [];
  let calls = 0;
  scheduleRoomTurnTimer(room, () => { calls++; }, {
    setTimer: () => firstTimer,
    clearTimer: (id) => cleared.push(id),
  });
  scheduleRoomTurnTimer(room, () => { calls++; }, {
    setTimer: () => secondTimer,
    clearTimer: (id) => cleared.push(id),
  });
  assert.deepEqual(cleared, [firstTimer]);
  assert.equal(room._turnTimer, secondTimer);
  assert.equal(calls, 0);
});

test('turn timer rejects invalid room configuration', () => {
  const room = new GameRoom('table-1', { ...TEST_ROOM_CONFIG, turnTimeSec: 0 });
  assert.throws(() => scheduleRoomTurnTimer(room, () => {}, { setTimer: () => null }), /turnTimeSec/);
});
