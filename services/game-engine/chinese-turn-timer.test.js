const test = require('node:test');
const assert = require('node:assert/strict');
const ChinesePokerRoom = require('./src/poker/chinese-poker');
const { TEST_ROOM_CONFIG } = require('./test-room-config');

for (const turnTimeSec of [10, 30, 60]) {
  test(`Chinese Poker arrange timer uses the configured ${turnTimeSec} second duration`, () => {
    const originalNow = Date.now;
    const originalSetTimeout = global.setTimeout;
    const now = 1_700_000_000_000;
    let scheduledDelay;
    let timeoutHandler;
    let timedOutRoom;
    Date.now = () => now;
    global.setTimeout = (handler, delay) => {
      timeoutHandler = handler;
      scheduledDelay = delay;
      return { id: 'arrange-timer' };
    };
    try {
      const room = new ChinesePokerRoom('table-1', { ...TEST_ROOM_CONFIG, turnTimeSec });
      room.phase = 'arranging';
      room.startArrangeTimer((timedOut) => { timedOutRoom = timedOut; });
      const state = room.getState();
      assert.equal(scheduledDelay, turnTimeSec * 1000);
      assert.equal(state.turnTotalSeconds, turnTimeSec);
      assert.equal(state.turnStartedAt, now);
      assert.equal(state.turnDeadlineAt, now + turnTimeSec * 1000);
      assert.equal(state.turnRemainingSeconds, turnTimeSec);
      timeoutHandler();
      assert.equal(timedOutRoom, room);
    } finally {
      Date.now = originalNow;
      global.setTimeout = originalSetTimeout;
    }
  });
}

test('Chinese Poker timeout can force an unarranged player to foul', () => {
  const originalSetTimeout = global.setTimeout;
  let timeoutHandler;
  global.setTimeout = (handler) => {
    timeoutHandler = handler;
    return { id: 'arrange-timer' };
  };
  try {
    const room = new ChinesePokerRoom('table-1', { ...TEST_ROOM_CONFIG, turnTimeSec: 30 });
    room.addPlayer(1, { id: 'player-1', username: 'Player 1', chips: 1000 });
    room.phase = 'arranging';
    room.players.get(1).hand = ['As', 'Ah', 'Ad', 'Ks', 'Kh', 'Kd', 'Qs', 'Qh', 'Jd', 'Tc', '9s', '8h', '7d'];
    room.startArrangeTimer((timedOutRoom) => timedOutRoom.forceFoulForSeat(1));
    timeoutHandler();
    assert.equal(room.players.get(1).arranged.isFoul, true);
  } finally {
    global.setTimeout = originalSetTimeout;
  }
});

test('Chinese Poker clears the server arrange deadline', () => {
  const room = new ChinesePokerRoom('table-1', { ...TEST_ROOM_CONFIG, turnTimeSec: 30 });
  room.phase = 'arranging';
  room.startArrangeTimer(() => {});
  room.clearArrangeTimer();
  const state = room.getState();
  assert.equal(state.turnStartedAt, null);
  assert.equal(state.turnDeadlineAt, null);
});
