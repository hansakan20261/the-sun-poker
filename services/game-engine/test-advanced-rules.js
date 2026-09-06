// ============================================================
// ADVANCED RULES TEST
// Dragon/Natural, Fantasy Land, Misdeal, Dead Button
// ============================================================

const GameRoom = require('./src/poker/game-room');
const ChinesePokerRoom = require('./src/poker/chinese-poker');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) { passed++; console.log(`  ✅ ${msg}`); }
  else { failed++; console.log(`  ❌ FAIL: ${msg}`); }
}

// ============================================================
// TEST 1: Dragon/Natural (13 different ranks)
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🐉 TEST 1: Dragon/Natural');
console.log('='.repeat(60));
{
  const room = new ChinesePokerRoom('dragon1', { bigBlind: 100 });
  room.addPlayer(1, { id: 'A', username: 'A', chips: 5000 });
  room.addPlayer(2, { id: 'B', username: 'B', chips: 5000 });
  room.addPlayer(3, { id: 'C', username: 'C', chips: 5000 });
  room.startHand();

  // A has Dragon: all 13 different ranks
  room.players.get(1).hand = ['As', '2h', '3d', '4c', '5s', '6h', '7d', '8c', '9s', 'Th', 'Jd', 'Qc', 'Ks'];
  // B: NOT dragon (has duplicate ranks)
  room.players.get(2).hand = ['Ah', 'Ad', 'Kh', 'Kd', 'Qh', 'Jh', 'Td', '9d', '8d', '7c', '6c', '5c', '4d'];
  // C: NOT dragon (has duplicate ranks)
  room.players.get(3).hand = ['Ac', 'Kc', 'Qd', 'Qs', 'Js', 'Ts', '9c', '8s', '7s', '6d', '5d', '4s', '3s'];

  // A arranges Dragon (valid: back > middle > front)
  room.arrangeCards(1, ['2h', '3d', '4c'], ['5s', '6h', '7d', '8c', '9s'], ['As', 'Ks', 'Qc', 'Jd', 'Th']);
  // B arranges (valid — NOT dragon because has AA, KK duplicates)
  room.arrangeCards(2, ['5c', '4d', '6c'], ['9d', '8d', '7c', 'Jh', 'Td'], ['Ah', 'Ad', 'Kh', 'Kd', 'Qh']);
  // C arranges (valid — NOT dragon because has QQ duplicates)
  const result = room.arrangeCards(3, ['4s', '3s', '5d'], ['9c', '8s', '7s', '6d', 'Ts'], ['Ac', 'Kc', 'Qd', 'Qs', 'Js']);

  assert(result.result !== undefined, 'Scoring completed');
  const aScore = result.result.results.find(r => r.seat === 1);
  const bScore = result.result.results.find(r => r.seat === 2);
  const cScore = result.result.results.find(r => r.seat === 3);

  console.log(`  A points: ${aScore.points} (Dragon)`);
  console.log(`  B points: ${bScore.points}`);
  console.log(`  C points: ${cScore.points}`);

  // A gets +13 from B and +13 from C = +26
  assert(aScore.points === 26, `Dragon A gets +26 (13 from each opponent) (got ${aScore.points})`);
  assert(aScore.coinChange === 2600, `A gets +2600 baht (got ${aScore.coinChange})`);

  // Zero-sum
  const total = aScore.points + bScore.points + cScore.points;
  assert(total === 0, `Zero-sum: A+B+C = 0 (got ${total})`);
}

// ============================================================
// TEST 2: Fantasy Land qualification
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🏰 TEST 2: Fantasy Land Qualification');
console.log('='.repeat(60));
{
  const room = new ChinesePokerRoom('fl1', { bigBlind: 100 });
  room.addPlayer(1, { id: 'A', username: 'A', chips: 5000 });
  room.addPlayer(2, { id: 'B', username: 'B', chips: 5000 });
  room.startHand();

  // A: front has Pair Q → qualifies for Fantasy Land
  room.players.get(1).hand = ['Qh', 'Qd', '2s', '3c', '4c', '5d', '6s', '7c', '8c', '9s', 'Ts', 'Jc', 'Ac'];
  // Valid: Back=Ac,Jc,Ts,9s,8c(Straight!) | Middle=3c,4c,5d,6s,7c(Straight 3-7) | Front=Qh,Qd,2s(Pair Q)
  // Wait — both straights, back(8-high) < middle... need back stronger
  // Back=9s,Ts,Jc,Qh... no, Qh is in front
  // Let me use: Back=Ac,Ts,9s,8c,7c → no straight, just High A
  // Middle=3c,4c,5d,6s,2s → not straight either (2,3,4,5,6 = straight!)
  // OK: Front=Qh,Qd,2s | Middle=6s,7c,8c,9s,Ts(no straight—not consecutive) | Back=Ac,Jc,5d,4c,3c
  // Hmm let me think simpler:
  // Front: Qh,Qd,2s (Pair Q) 
  // Middle: 3c,4c,5d,6s,7c (Straight 3-7)
  // Back: 8c,9s,Ts,Jc,Ac (Straight 8-Q? No... 8,9,T,J,A not consecutive)
  // Back needs to be stronger than Straight. Use Flush or higher straight.
  // Change hand to include flush possibility:
  room.players.get(1).hand = ['Qh', 'Qd', '2s', '3h', '4h', '5h', '6h', '7h', '8c', '9s', 'Ts', 'Jc', 'Ac'];
  // Front: Qh,Qd,2s (Pair Q)
  // Middle: 8c,9s,Ts,Jc,Ac (Straight T-A? No... 8,9,T,J,A not straight)
  // Let me just use: Middle=8c,9s,Ts,Jc,2s... no 2s is in front
  // Simplify completely:
  room.players.get(1).hand = ['Qh', 'Qd', '3s', '4s', '5s', '6s', '7s', '8d', '9d', 'Td', 'Jd', 'Kd', 'Ad'];
  // Front: Qh,Qd,3s (Pair Q)
  // Middle: 4s,5s,6s,7s,8d (not flush, not straight — just high 8)
  // Back: 9d,Td,Jd,Kd,Ad (Flush diamonds!)
  room.arrangeCards(1, ['Qh', 'Qd', '3s'], ['4s', '5s', '6s', '7s', '8d'], ['Ad', 'Kd', 'Jd', 'Td', '9d']);

  // B: front has Pair J → does NOT qualify
  room.players.get(2).hand = ['Jh', 'Jd', '2h', '4h', '5h', '6d', '7d', '8h', '9h', 'Th', 'Qs', 'Ks', 'As'];
  // Front: Jh,Jd,2h (Pair J)
  // Middle: 4h,5h,6d,7d,8h (High 8)
  // Back: 9h,Th,Qs,Ks,As (High A)
  const result = room.arrangeCards(2, ['Jh', 'Jd', '2h'], ['4h', '5h', '6d', '7d', '8h'], ['As', 'Ks', 'Qs', 'Th', '9h']);

  assert(result.result !== undefined, 'Scoring completed');
  const aResult = result.result.results.find(r => r.seat === 1);
  const bResult = result.result.results.find(r => r.seat === 2);

  assert(aResult.qualifiesFantasyland === true, 'A qualifies for Fantasy Land (Pair Q front)');
  assert(bResult.qualifiesFantasyland === false, 'B does NOT qualify (Pair J < Pair Q)');
}

// ============================================================
// TEST 3: Fantasy Land — Pair K and Pair A also qualify
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🏰 TEST 3: Fantasy Land — Pair K/A qualify');
console.log('='.repeat(60));
{
  const room = new ChinesePokerRoom('fl2', { bigBlind: 100 });
  room.addPlayer(1, { id: 'A', username: 'A', chips: 5000 });
  room.addPlayer(2, { id: 'B', username: 'B', chips: 5000 });
  room.startHand();

  // A: front has Pair K
  room.players.get(1).hand = ['Kh', 'Kd', '2s', '3c', '4c', '5d', '6s', '7c', '8c', '9s', 'Ts', 'Jc', 'Qc'];
  room.arrangeCards(1, ['Kh', 'Kd', '2s'], ['3c', '4c', '5d', '6s', '7c'], ['Qc', 'Jc', 'Ts', '9s', '8c']);

  // B: front has Pair 10 (doesn't qualify)
  room.players.get(2).hand = ['Th', 'Td', '2h', '3d', '4d', '5c', '6d', '7d', '8d', '9d', 'Js', 'Qs', 'As'];
  const result = room.arrangeCards(2, ['Th', 'Td', '2h'], ['3d', '4d', '5c', '6d', '7d'], ['As', 'Qs', 'Js', '9d', '8d']);

  const aResult = result.result.results.find(r => r.seat === 1);
  const bResult = result.result.results.find(r => r.seat === 2);

  assert(aResult.qualifiesFantasyland === true, 'Pair K qualifies for Fantasy Land');
  assert(bResult.qualifiesFantasyland === false, 'Pair 10 does NOT qualify');
}

// ============================================================
// TEST 4: Three of a Kind on Front — Super Royalty
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('👑 TEST 4: Three of a Kind on Front (Super Royalty)');
console.log('='.repeat(60));
{
  const room = new ChinesePokerRoom('trip1', { bigBlind: 100 });
  room.addPlayer(1, { id: 'A', username: 'A', chips: 5000 });
  room.addPlayer(2, { id: 'B', username: 'B', chips: 5000 });
  room.startHand();

  // A: Trip Aces on front (royalty = 10 + (14-2) = 22)
  room.players.get(1).hand = ['Ah', 'Ad', 'As', '2c', '3c', '4c', '5c', '6c', '7d', '8d', '9d', 'Td', 'Jd'];
  // Back: Jd,Td,9d,8d,7d (Straight Flush!) → royalty +15
  // Middle: 2c,3c,4c,5c,6c (Straight Flush!) → royalty +30
  // Front: Ah,Ad,As (Trip Aces) → royalty +22
  room.arrangeCards(1, ['Ah', 'Ad', 'As'], ['2c', '3c', '4c', '5c', '6c'], ['7d', '8d', '9d', 'Td', 'Jd']);

  // B: normal hand (valid: Pair K back > High 9 middle > High 4 front)
  room.players.get(2).hand = ['Kh', 'Kd', 'Qs', 'Js', '9s', '8s', '7s', '6h', '5h', '4h', '3h', '2h', 'Ts'];
  // Front: 4h,3h,2h (High 4)
  // Middle: 6h,7s,8s,9s,Ts (Straight 6-T) — NO! need non-straight
  // Middle: 5h,7s,8s,9s,Ts (not straight — gap at 6)
  // Back: Kh,Kd,Qs,Js,6h (Pair K)
  const result = room.arrangeCards(2, ['4h', '3h', '2h'], ['5h', '7s', '8s', '9s', 'Ts'], ['Kh', 'Kd', 'Qs', 'Js', '6h']);

  const aResult = result.result.results.find(r => r.seat === 1);
  console.log(`  A points: ${aResult.points} (Trip Aces front + SF middle + SF back)`);

  // A should have massive royalties
  // Front: Trip A = +22
  // Middle: Straight Flush = +30
  // Back: Straight Flush = +15
  // Total royalty = 67
  assert(aResult.points > 20, `A has massive points from royalties (got ${aResult.points})`);
  assert(aResult.qualifiesFantasyland === true, 'Trip Aces front qualifies for Fantasy Land');
}

// ============================================================
// TEST 5: Dead Button (player busts between hands)
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🪦 TEST 5: Dead Button (player leaves)');
console.log('='.repeat(60));
{
  const room = new GameRoom('db1', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'A', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'B', username: 'B', chips: 500 });
  room.addPlayer(3, { id: 'C', username: 'C', chips: 500 });
  room.addPlayer(4, { id: 'D', username: 'D', chips: 500 });

  // Hand 1
  room.startHand();
  const dealer1 = room.dealerSeat;
  room.handleAction(room.currentPlayerSeat, 'fold');
  room.handleAction(room.currentPlayerSeat, 'fold');
  room.handleAction(room.currentPlayerSeat, 'fold');
  // Hand ends

  // Remove player at seat 2 (simulating bust)
  room.removePlayer(2);

  // Hand 2 — dealer should rotate past the empty seat
  room.startHand();
  assert(room.players.has(room.dealerSeat), 'Dealer is on an occupied seat');
  assert(room.players.has(room.smallBlindSeat), 'SB is on an occupied seat');
  assert(room.players.has(room.bigBlindSeat), 'BB is on an occupied seat');
  assert(room.players.size === 3, '3 players remaining');
  console.log(`  Dealer: seat ${room.dealerSeat}, SB: seat ${room.smallBlindSeat}, BB: seat ${room.bigBlindSeat}`);
}

// ============================================================
// TEST 6: Misdeal detection (Chinese Poker)
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🔄 TEST 6: Misdeal Detection');
console.log('='.repeat(60));
{
  const room = new ChinesePokerRoom('md1', { bigBlind: 100 });
  room.addPlayer(1, { id: 'A', username: 'A', chips: 5000 });
  room.addPlayer(2, { id: 'B', username: 'B', chips: 5000 });
  room.startHand();

  // After startHand, both players should have exactly 13 cards
  assert(room.players.get(1).hand.length === 13, 'Player 1 has exactly 13 cards');
  assert(room.players.get(2).hand.length === 13, 'Player 2 has exactly 13 cards');

  // Verify no duplicate cards between players
  const allCards = [...room.players.get(1).hand, ...room.players.get(2).hand];
  const uniqueCards = new Set(allCards);
  assert(uniqueCards.size === 26, 'No duplicate cards between players (26 unique)');
}

// ============================================================
// SUMMARY
// ============================================================
console.log('\n' + '='.repeat(60));
console.log(`📊 ADVANCED RULES: ${passed} passed, ${failed} failed, ${passed + failed} total`);
console.log('='.repeat(60));
if (failed === 0) {
  console.log('🎉 ALL ADVANCED RULES TESTS PASSED!');
} else {
  console.log(`⚠️  ${failed} test(s) failed — review above`);
}
process.exit(failed > 0 ? 1 : 0);
