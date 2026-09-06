const test = require('node:test');
const assert = require('node:assert/strict');
const GameRoom = require('./src/poker/game-room');
const ChinesePokerRoom = require('./src/poker/chinese-poker');
const { TEST_ROOM_CONFIG } = require('./test-room-config');

for (const [name, create] of [
  ['Texas Holdem', (minutes) => new GameRoom('table-1', { ...TEST_ROOM_CONFIG, minPlayMinutes: minutes })],
  ['Chinese Poker', (minutes) => new ChinesePokerRoom('table-1', { ...TEST_ROOM_CONFIG, minPlayMinutes: minutes })],
]) {
  test(`${name} allows leaving before the first hand`, () => {
    assert.equal(create(30).canLeave(1).allowed, true);
  });

  test(`${name} enforces configured minimum play time`, () => {
    const room = create(30);
    room._playerFirstPlayTime.set(1, Date.now() - 29 * 60 * 1000);
    const result = room.canLeave(1);
    assert.equal(result.allowed, false);
    assert.equal(result.remainingMinutes, 1);
  });

  test(`${name} supports zero minimum play time`, () => {
    const room = create(0);
    room._playerFirstPlayTime.set(1, Date.now());
    assert.equal(room.canLeave(1).allowed, true);
  });
}
