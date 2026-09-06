const GameRoom = require('./src/poker/game-room');

// Test 1: Basic hand flow
console.log('=== TEST 1: Basic Hand Flow ===');
const room = new GameRoom('test-1', { smallBlind: 1, bigBlind: 2, rakePercent: 5.5, rakeCap: 0 });
room.addPlayer(1, { id: 'p1', username: 'Player1', chips: 200 });
room.addPlayer(2, { id: 'p2', username: 'Player2', chips: 200 });
room.addPlayer(3, { id: 'p3', username: 'Player3', chips: 200 });
const state = room.startHand();
console.log('Phase:', room.currentRound);
console.log('Pot:', room.pot);
console.log('TEST 1:', room.isPlaying ? '✅ PASS' : '❌ FAIL');

// Test 2: All fold = winner
console.log('\n=== TEST 2: All Fold = Winner ===');
let seat = room.currentPlayerSeat;
room.handleAction(seat, 'call');
seat = room.currentPlayerSeat;
room.handleAction(seat, 'fold');
seat = room.currentPlayerSeat;
let r = room.handleAction(seat, 'fold');
console.log('TEST 2:', r.result ? '✅ PASS (hand ended, winner: ' + r.result.winners[0]?.username + ')' : '❌ FAIL');

// Test 3: Rake on real table
console.log('\n=== TEST 3: Rake (5.5%) ===');
const room3 = new GameRoom('test-3', { smallBlind: 5, bigBlind: 10, rakePercent: 5.5, rakeCap: 0 });
room3.isPractice = false;
room3.addPlayer(1, { id: 'p1', username: 'A', chips: 1000 });
room3.addPlayer(2, { id: 'p2', username: 'B', chips: 1000 });
room3.startHand();
room3.handleAction(room3.currentPlayerSeat, 'raise', 100);
room3.handleAction(room3.currentPlayerSeat, 'call');
if (room3.isPlaying) room3.handleAction(room3.currentPlayerSeat, 'fold');
const expectedRake = Math.floor(room3.pot * 5.5 / 100);
console.log('Pot before rake would be ~200, Rake:', room3.rakeAmount);
console.log('TEST 3:', room3.rakeAmount > 0 ? '✅ PASS' : '❌ FAIL');

// Test 4: No rake on practice
console.log('\n=== TEST 4: Practice = No Rake ===');
const room4 = new GameRoom('test-4', { smallBlind: 1, bigBlind: 2, rakePercent: 5.5, rakeCap: 0 });
room4.isPractice = true;
room4.addPlayer(1, { id: 'p1', username: 'A', chips: 200 });
room4.addPlayer(2, { id: 'p2', username: 'B', chips: 200 });
room4.startHand();
room4.handleAction(room4.currentPlayerSeat, 'raise', 50);
room4.handleAction(room4.currentPlayerSeat, 'fold');
console.log('Practice rake:', room4.rakeAmount);
console.log('TEST 4:', room4.rakeAmount === 0 ? '✅ PASS' : '❌ FAIL');

// Test 5: Full hand (preflop -> river -> showdown)
console.log('\n=== TEST 5: Full Hand (5 community cards) ===');
const room5 = new GameRoom('test-5', { smallBlind: 1, bigBlind: 2, rakePercent: 0, rakeCap: 0 });
room5.addPlayer(1, { id: 'p1', username: 'A', chips: 200 });
room5.addPlayer(2, { id: 'p2', username: 'B', chips: 200 });
room5.startHand();
// Preflop
room5.handleAction(room5.currentPlayerSeat, 'call');
room5.handleAction(room5.currentPlayerSeat, 'check');
const afterPreflop = room5.currentRound;
// Flop
if (room5.isPlaying) room5.handleAction(room5.currentPlayerSeat, 'check');
if (room5.isPlaying) room5.handleAction(room5.currentPlayerSeat, 'check');
const afterFlop = room5.currentRound;
// Turn
if (room5.isPlaying) room5.handleAction(room5.currentPlayerSeat, 'check');
if (room5.isPlaying) room5.handleAction(room5.currentPlayerSeat, 'check');
const afterTurn = room5.currentRound;
// River
if (room5.isPlaying) room5.handleAction(room5.currentPlayerSeat, 'check');
if (room5.isPlaying) r = room5.handleAction(room5.currentPlayerSeat, 'check');
console.log('Flow: preflop->' + afterPreflop + '->' + afterFlop + '->' + afterTurn + '->result');
console.log('Community cards:', room5.communityCards.length);
console.log('Winner:', r?.result?.winners?.[0]?.handName || 'N/A');
console.log('TEST 5:', room5.communityCards.length === 5 && r?.result ? '✅ PASS' : '❌ FAIL');

// Test 6: Side Pots
console.log('\n=== TEST 6: Side Pots ===');
const room6 = new GameRoom('test-6', { smallBlind: 1, bigBlind: 2, rakePercent: 0, rakeCap: 0 });
room6.addPlayer(1, { id: 'p1', username: 'Rich', chips: 500 });
room6.addPlayer(2, { id: 'p2', username: 'Poor', chips: 30 });
room6.addPlayer(3, { id: 'p3', username: 'Med', chips: 200 });
room6.startHand();
// Preflop: Rich raises big, Poor all-in (can only put 30), Med calls Rich's raise
// This creates: Main pot (30x3=90 eligible all) + Side pot (remaining from Rich+Med)
const curSeat1 = room6.currentPlayerSeat;
room6.handleAction(curSeat1, 'raise', 100); // First player raises to 100
const curSeat2 = room6.currentPlayerSeat;
room6.handleAction(curSeat2, 'all_in'); // Poor all-in with 30 (can't match 100)
const curSeat3 = room6.currentPlayerSeat;
room6.handleAction(curSeat3, 'call'); // Third player calls 100
// If there's still action needed (original raiser may need to act again)
if (room6.isPlaying && room6.currentRound === 'preflop') {
  const cur = room6.currentPlayerSeat;
  if (cur) room6.handleAction(cur, 'check');
}
// Now in flop+ rounds, just check through
let att6 = 0;
while (room6.isPlaying && att6++ < 20) {
  const cur = room6.currentPlayerSeat;
  if (!cur) break;
  const p = room6.players.get(cur);
  if (!p || p.folded || p.allIn) break;
  room6.handleAction(cur, 'check');
}
console.log('Side pots:', room6.sidePots.length);
if (room6.sidePots.length >= 2) {
  console.log('  Main pot:', room6.sidePots[0]?.amount, 'eligible:', room6.sidePots[0]?.eligibleSeats);
  console.log('  Side pot:', room6.sidePots[1]?.amount, 'eligible:', room6.sidePots[1]?.eligibleSeats);
  // Verify: Poor should be eligible for main pot only, not side pot
  const poorEligibleMain = room6.sidePots[0]?.eligibleSeats?.includes(2);
  const poorEligibleSide = room6.sidePots[1]?.eligibleSeats?.includes(2);
  console.log('  Poor eligible for main:', poorEligibleMain, '| side:', poorEligibleSide);
  console.log('TEST 6:', poorEligibleMain && !poorEligibleSide ? '✅ PASS' : '❌ FAIL (eligibility wrong)');
} else {
  console.log('TEST 6: ❌ FAIL (expected 2+ pots, got', room6.sidePots.length, ')');
}

// Test 7: Dealer rotation
console.log('\n=== TEST 7: Dealer Rotation ===');
const room7 = new GameRoom('test-7', { smallBlind: 1, bigBlind: 2, rakePercent: 0, rakeCap: 0 });
room7.addPlayer(1, { id: 'p1', username: 'A', chips: 200 });
room7.addPlayer(2, { id: 'p2', username: 'B', chips: 200 });
room7.addPlayer(3, { id: 'p3', username: 'C', chips: 200 });
room7.startHand();
const dealer1 = room7.dealerSeat;
// End hand quickly
room7.handleAction(room7.currentPlayerSeat, 'fold');
room7.handleAction(room7.currentPlayerSeat, 'fold');
// Start new hand
room7.startHand();
const dealer2 = room7.dealerSeat;
console.log('Dealer hand 1:', dealer1, '-> hand 2:', dealer2);
console.log('TEST 7:', dealer1 !== dealer2 ? '✅ PASS (rotated)' : '❌ FAIL');

// Test 8: Min raise enforcement
console.log('\n=== TEST 8: Min Raise ===');
const room8 = new GameRoom('test-8', { smallBlind: 1, bigBlind: 2, rakePercent: 0, rakeCap: 0 });
room8.addPlayer(1, { id: 'p1', username: 'A', chips: 200 });
room8.addPlayer(2, { id: 'p2', username: 'B', chips: 200 });
room8.startHand();
const badRaise = room8.handleAction(room8.currentPlayerSeat, 'raise', 1); // too small
console.log('Bad raise result:', badRaise.error || 'no error');
console.log('TEST 8:', badRaise.error ? '✅ PASS (rejected)' : '❌ FAIL');

console.log('\n' + '='.repeat(50));
console.log('========== TEST SUMMARY ==========');
console.log('='.repeat(50));
