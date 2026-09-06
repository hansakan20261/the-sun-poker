const test = require('node:test');
const assert = require('node:assert/strict');
const GameRoom = require('./src/poker/game-room');

function createTexasRoom(config = {}) {
  return new GameRoom('table-policy-test', {
    smallBlind: 10,
    bigBlind: 20,
    ante: 0,
    minBuyIn: 100,
    maxBuyIn: 1000,
    maxSeats: 9,
    turnTimeSec: 30,
    autoStartAt: 2,
    autoStartDelaySec: 0,
    minPlayMinutes: 0,
    rakePercent: 0,
    rakeCap: 0,
    texasPolicy: {
      allow_straddle: true,
      allow_rebuy: true,
      allow_run_twice: false,
      auto_timeout_action: 'check_or_fold',
      time_bank_sec: 0,
      max_raises_per_round: 0,
      sit_out_timeout_sec: 0,
      no_flop_no_drop: true,
      minimum_rake_pot: 0,
      max_hands_per_room: 0,
      max_room_duration_hours: 0,
    },
    ...config,
  });
}

function addPlayer(room, seat, chips = 1000) {
  room.addPlayer(seat, {
    id: `user-${seat}`,
    username: `Player ${seat}`,
    chips,
    socketId: `socket-${seat}`,
  });
}

test('Texas antes are posted from room config', () => {
  const room = createTexasRoom({ ante: 5 });
  addPlayer(room, 1);
  addPlayer(room, 2);
  const state = room.startHand();
  assert.equal(state.pot, 40); // antes 5x2 + blinds 10+20
  assert.equal(room.players.get(1).totalBetThisHand, 15);
  assert.equal(room.players.get(2).totalBetThisHand, 25);
});

test('Texas straddle is posted by UTG only when enabled', () => {
  const room = createTexasRoom();
  addPlayer(room, 1);
  addPlayer(room, 2);
  addPlayer(room, 3);
  const request = room.requestStraddle(1, true);
  assert.equal(request.straddleSeat, 1);
  const state = room.startHand();
  assert.equal(state.straddleSeat, 1);
  assert.equal(room.players.get(1).currentBet, 40);
  assert.equal(room.players.get(1).hasStraddled, true);
  assert.equal(state.currentPlayerSeat, 2);
  assert.equal(state.pot, 70); // 10 + 20 + 40
});

test('Texas straddle is rejected when policy disables it', () => {
  const room = createTexasRoom({
    texasPolicy: { allow_straddle: false },
  });
  addPlayer(room, 1);
  const result = room.requestStraddle(1, true);
  assert.equal(result.error, 'Straddle is disabled for this room');
});

test('Texas run-it-twice creates two boards for all-in showdown', () => {
  const room = createTexasRoom({
    texasPolicy: { allow_run_twice: true },
  });
  addPlayer(room, 1, 100);
  addPlayer(room, 2, 100);
  room.startHand();
  for (const [seat, player] of room.players) {
    player.holeCards = seat === 1 ? ['Ah', 'Ad'] : ['Kh', 'Kd'];
    player.chips = 0;
    player.allIn = true;
    player.currentBet = 100;
    player.totalBetThisHand = 100;
    player.hasActed = true;
  }
  room.pot = 200;
  room.currentRound = 'river';
  room.communityCards = ['2h', '7d', '9c'];
  const result = room._dealRemainingAndShowdown();
  assert.equal(result.result.runCount, 2);
  assert.equal(result.result.runBoards.length, 2);
  assert.equal(result.result.runBoards[0].length, 5);
  assert.equal(result.result.runBoards[1].length, 5);
  assert.equal(result.result.winners.reduce((sum, winner) => sum + winner.amount, 0), 200);
});
