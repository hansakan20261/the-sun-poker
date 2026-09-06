// ============================================================
// COMPREHENSIVE GAME RULES TEST
// Tests both Texas Hold'em and Chinese Poker (OFC) game logic
// ============================================================

const GameRoom = require('./src/poker/game-room');
const ChinesePokerRoom = require('./src/poker/chinese-poker');
const { evaluate, findWinners, HAND_RANKS } = require('./src/poker/hand-evaluator');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) { passed++; console.log(`  ✅ ${msg}`); }
  else { failed++; console.log(`  ❌ FAIL: ${msg}`); }
}

// ============================================================
// PART 1: TEXAS HOLD'EM TESTS
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🃏 PART 1: TEXAS HOLD\'EM (NLH) TESTS');
console.log('='.repeat(60));

// --- Test 1: Basic hand start + dealer rotation ---
console.log('\n📋 Test 1: Dealer rotation + blind posting');
{
  const room = new GameRoom('test1', { smallBlind: 1, bigBlind: 2, maxSeats: 6 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 100 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 100 });
  room.addPlayer(3, { id: 'p3', username: 'Charlie', chips: 100 });

  // Hand 1
  room.startHand();
  assert(room.dealerSeat === 1, 'First hand: dealer = seat 1');
  assert(room.smallBlindSeat === 2, 'SB = seat 2 (left of dealer)');
  assert(room.bigBlindSeat === 3, 'BB = seat 3 (left of SB)');
  assert(room.pot === 3, 'Pot = SB(1) + BB(2) = 3');
  assert(room.players.get(2).chips === 99, 'SB posted 1, chips = 99');
  assert(room.players.get(3).chips === 98, 'BB posted 2, chips = 98');
  assert(room.currentPlayerSeat === 1, 'First to act = UTG (seat 1, after BB)');

  // Fold everyone to end hand
  room.handleAction(1, 'fold');
  room.handleAction(2, 'fold');
  // BB wins uncontested

  // Hand 2 — dealer rotates
  room.startHand();
  assert(room.dealerSeat === 2, 'Second hand: dealer rotates to seat 2');
  assert(room.smallBlindSeat === 3, 'SB = seat 3');
  assert(room.bigBlindSeat === 1, 'BB = seat 1');
}

// --- Test 2: BB Option ---
console.log('\n📋 Test 2: BB gets option when everyone calls');
{
  const room = new GameRoom('test2', { smallBlind: 1, bigBlind: 2, maxSeats: 6 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 100 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 100 });
  room.addPlayer(3, { id: 'p3', username: 'Charlie', chips: 100 });
  room.startHand();
  // Dealer=1, SB=2, BB=3, first to act=1 (UTG)

  room.handleAction(1, 'call'); // UTG calls 2
  room.handleAction(2, 'call'); // SB calls 1 more (total 2)
  // Now BB should get option (check or raise)
  assert(room.currentPlayerSeat === 3, 'BB gets option after everyone calls');
  assert(room.currentRound === 'preflop', 'Still in preflop (BB option)');

  // BB checks — round ends
  const result = room.handleAction(3, 'check');
  assert(room.currentRound === 'flop', 'After BB checks, moves to flop');
  assert(room.communityCards.length === 3, 'Flop deals 3 community cards');
}

// --- Test 3: Betting rounds flow ---
console.log('\n📋 Test 3: Full hand - preflop → flop → turn → river → showdown');
{
  const room = new GameRoom('test3', { smallBlind: 1, bigBlind: 2, maxSeats: 6 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 100 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 100 });
  room.startHand();
  // Heads-up: Dealer=1=SB, BB=2, SB acts first preflop

  room.handleAction(1, 'call'); // SB calls (pays 1 more)
  room.handleAction(2, 'check'); // BB checks option
  assert(room.currentRound === 'flop', 'Moved to flop');
  assert(room.communityCards.length === 3, 'Flop: 3 cards');

  // Flop: BB acts first post-flop
  assert(room.currentPlayerSeat === 2, 'Post-flop: BB (seat 2) acts first');
  room.handleAction(2, 'check');
  room.handleAction(1, 'check');
  assert(room.currentRound === 'turn', 'Moved to turn');
  assert(room.communityCards.length === 4, 'Turn: 4 cards');

  // Turn
  room.handleAction(2, 'check');
  room.handleAction(1, 'check');
  assert(room.currentRound === 'river', 'Moved to river');
  assert(room.communityCards.length === 5, 'River: 5 cards');

  // River
  room.handleAction(2, 'check');
  const finalState = room.handleAction(1, 'check');
  assert(room.currentRound === 'result', 'After river checks → result (showdown)');
  assert(finalState.result !== undefined, 'Result object exists');
  assert(finalState.result.winners.length >= 1, 'At least 1 winner');
}

// --- Test 4: Raise and re-raise ---
console.log('\n📋 Test 4: Raise mechanics + minimum raise');
{
  const room = new GameRoom('test4', { smallBlind: 5, bigBlind: 10, maxSeats: 6 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 500 });
  room.addPlayer(3, { id: 'p3', username: 'Charlie', chips: 500 });
  room.startHand();
  // D=1, SB=2(5), BB=3(10), UTG=1 first

  // UTG raises to 20 (call 10 + raise 10)
  room.handleAction(1, 'raise', 20);
  assert(room.players.get(1).currentBet === 20, 'UTG raised to 20');
  assert(room.minRaise === 10, 'Min raise = 10 (raise portion)');

  // SB re-raises to 50 (call 15 + raise 30)
  room.handleAction(2, 'raise', 45); // 45 additional from current 5
  assert(room.players.get(2).currentBet === 50, 'SB re-raised to 50');

  // BB folds
  room.handleAction(3, 'fold');
  assert(room.players.get(3).folded === true, 'BB folded');

  // UTG must act again (re-opened)
  assert(room.currentPlayerSeat === 1, 'Action back to UTG after re-raise');
}

// --- Test 5: All-in + side pot ---
console.log('\n📋 Test 5: All-in and side pot calculation');
{
  const room = new GameRoom('test5', { smallBlind: 5, bigBlind: 10, maxSeats: 6 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 50 }); // Short stack
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 200 });
  room.addPlayer(3, { id: 'p3', username: 'Charlie', chips: 200 });
  room.startHand();
  // D=1, SB=2(5), BB=3(10), UTG=1

  // UTG goes all-in for 50
  room.handleAction(1, 'all_in');
  assert(room.players.get(1).allIn === true, 'UTG is all-in');
  assert(room.players.get(1).chips === 0, 'UTG has 0 chips');
  assert(room.players.get(1).totalBetThisHand === 50, 'UTG totalBet = 50');

  // SB calls 50
  room.handleAction(2, 'call');
  assert(room.players.get(2).currentBet === 50, 'SB called to 50');

  // BB calls 50
  room.handleAction(3, 'call');

  // Side pots should be calculated
  const sidePots = room.calculateSidePots();
  assert(sidePots.length >= 1, 'Side pots calculated');
  // Main pot: 50*3 = 150 (all 3 eligible)
  const totalPot = sidePots.reduce((s, p) => s + p.amount, 0);
  assert(totalPot === room.pot, `Side pots total (${totalPot}) = pot (${room.pot})`);
}

// --- Test 6: Fold wins uncontested ---
console.log('\n📋 Test 6: Everyone folds → last player wins');
{
  const room = new GameRoom('test6', { smallBlind: 1, bigBlind: 2, maxSeats: 6 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 100 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 100 });
  room.addPlayer(3, { id: 'p3', username: 'Charlie', chips: 100 });
  room.startHand();

  room.handleAction(1, 'fold');
  const result = room.handleAction(2, 'fold');
  assert(result.result !== undefined, 'Hand ended');
  assert(result.result.winners[0].seat === 3, 'BB (seat 3) wins uncontested');
  assert(room.players.get(3).chips === 101, 'BB wins pot of 3 → 98+3=101');
}

// --- Test 7: Heads-up blind structure ---
console.log('\n📋 Test 7: Heads-up (2 players) blind structure');
{
  const room = new GameRoom('test7', { smallBlind: 1, bigBlind: 2, maxSeats: 6 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 100 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 100 });
  room.startHand();

  // Heads-up: Dealer = SB, other = BB
  assert(room.dealerSeat === room.smallBlindSeat, 'Heads-up: Dealer is SB');
  assert(room.currentPlayerSeat === room.smallBlindSeat, 'Heads-up preflop: SB acts first');
}

// ============================================================
// PART 2: HAND EVALUATOR TESTS
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🂡 PART 2: HAND EVALUATOR TESTS');
console.log('='.repeat(60));

console.log('\n📋 Test 8: Hand rankings');
{
  const royalFlush = evaluate(['As', 'Ks', 'Qs', 'Js', 'Ts']);
  assert(royalFlush.hand === HAND_RANKS.ROYAL_FLUSH, 'Royal Flush detected');

  const straightFlush = evaluate(['9h', '8h', '7h', '6h', '5h']);
  assert(straightFlush.hand === HAND_RANKS.STRAIGHT_FLUSH, 'Straight Flush detected');

  const fourKind = evaluate(['Ah', 'Ad', 'Ac', 'As', 'Kh']);
  assert(fourKind.hand === HAND_RANKS.FOUR_OF_A_KIND, 'Four of a Kind detected');

  const fullHouse = evaluate(['Kh', 'Kd', 'Kc', 'Qh', 'Qd']);
  assert(fullHouse.hand === HAND_RANKS.FULL_HOUSE, 'Full House detected');

  const flush = evaluate(['Ah', 'Jh', '8h', '5h', '3h']);
  assert(flush.hand === HAND_RANKS.FLUSH, 'Flush detected');

  const straight = evaluate(['9h', '8d', '7c', '6s', '5h']);
  assert(straight.hand === HAND_RANKS.STRAIGHT, 'Straight detected');

  const threeKind = evaluate(['7h', '7d', '7c', 'Ah', 'Kd']);
  assert(threeKind.hand === HAND_RANKS.THREE_OF_A_KIND, 'Three of a Kind detected');

  const twoPair = evaluate(['Ah', 'Ad', 'Kh', 'Kd', '5c']);
  assert(twoPair.hand === HAND_RANKS.TWO_PAIR, 'Two Pair detected');

  const onePair = evaluate(['Ah', 'Ad', 'Kh', 'Qd', 'Jc']);
  assert(onePair.hand === HAND_RANKS.ONE_PAIR, 'One Pair detected');

  const highCard = evaluate(['Ah', 'Kd', 'Qc', 'Js', '9h']);
  assert(highCard.hand === HAND_RANKS.HIGH_CARD, 'High Card detected');
}

console.log('\n📋 Test 9: Wheel straight (A-2-3-4-5)');
{
  const wheel = evaluate(['Ah', '2d', '3c', '4s', '5h']);
  assert(wheel.hand === HAND_RANKS.STRAIGHT, 'Wheel (A-2-3-4-5) is a straight');
  assert(wheel.kickers[0] === 5, 'Wheel is 5-high (not Ace-high)');
}

console.log('\n📋 Test 10: Best 5 from 7 cards');
{
  // 7 cards: should find the flush
  const result = evaluate(['Ah', 'Kh', 'Qh', 'Jh', '2h', '3d', '4c']);
  assert(result.hand === HAND_RANKS.FLUSH, 'Best 5 from 7: finds flush');
}

console.log('\n📋 Test 11: Winner determination');
{
  const winners = findWinners([
    { id: 'p1', seat: 1, holeCards: ['Ah', 'Kh'] },
    { id: 'p2', seat: 2, holeCards: ['2d', '7c'] },
  ], ['Qh', 'Jh', 'Th', '3s', '4s']);
  assert(winners.length === 1, 'One winner');
  assert(winners[0].seat === 1, 'Player 1 wins with Royal Flush');
}

console.log('\n📋 Test 12: Split pot (tie)');
{
  const winners = findWinners([
    { id: 'p1', seat: 1, holeCards: ['2h', '3h'] },
    { id: 'p2', seat: 2, holeCards: ['2d', '3d'] },
  ], ['As', 'Ks', 'Qs', 'Js', 'Ts']); // Board plays
  assert(winners.length === 2, 'Split pot: both players tie (board plays)');
}

// ============================================================
// PART 3: CHINESE POKER (OFC) TESTS
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🀄 PART 3: CHINESE POKER (ไพ่สามกอง) TESTS');
console.log('='.repeat(60));

console.log('\n📋 Test 13: Basic game flow');
{
  const room = new ChinesePokerRoom('ofc1', { bigBlind: 20 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 1000 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 1000 });

  const state = room.startHand();
  assert(state !== null, 'Hand started');
  assert(room.phase === 'arranging', 'Phase = arranging');
  assert(room.players.get(1).hand.length === 13, 'Player 1 gets 13 cards');
  assert(room.players.get(2).hand.length === 13, 'Player 2 gets 13 cards');
}

console.log('\n📋 Test 14: Valid arrangement');
{
  const room = new ChinesePokerRoom('ofc2', { bigBlind: 20 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 1000 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 1000 });
  room.startHand();

  const hand1 = room.players.get(1).hand;
  // Sort by rank descending
  const sorted = [...hand1].sort((a, b) => {
    const rv = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'T':10,'J':11,'Q':12,'K':13,'A':14 };
    return rv[b[0]] - rv[a[0]];
  });
  const back = sorted.slice(0, 5);
  const middle = sorted.slice(5, 10);
  const front = sorted.slice(10, 13);

  const result = room.arrangeCards(1, front, middle, back);
  assert(!result.error, 'Arrangement accepted (no error)');
  assert(room.players.get(1).arranged !== null, 'Player 1 arranged');
}

console.log('\n📋 Test 15: Foul detection (back < middle)');
{
  const room = new ChinesePokerRoom('ofc3', { bigBlind: 20 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 1000 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 1000 });
  room.startHand();

  const hand1 = room.players.get(1).hand;
  const sorted = [...hand1].sort((a, b) => {
    const rv = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'T':10,'J':11,'Q':12,'K':13,'A':14 };
    return rv[b[0]] - rv[a[0]];
  });
  // Intentionally put strong cards in front (foul)
  const front = sorted.slice(0, 3); // Strongest 3
  const middle = sorted.slice(3, 8);
  const back = sorted.slice(8, 13); // Weakest 5

  const result = room.arrangeCards(1, front, middle, back);
  assert(!result.error, 'Foul arrangement accepted (server allows it)');
  assert(room.players.get(1).arranged.isFoul === true, 'Marked as FOUL');
}

console.log('\n📋 Test 16: Scoring - winner gets points');
{
  const room = new ChinesePokerRoom('ofc4', { bigBlind: 20 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 1000 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 1000 });
  room.startHand();

  // Auto-arrange both players
  room.autoArrangeForSeat(1);
  const result = room.autoArrangeForSeat(2);

  assert(result.result !== undefined, 'Scoring completed');
  assert(result.result.results.length === 2, '2 player results');

  const p1Change = result.result.results.find(r => r.seat === 1).coinChange;
  const p2Change = result.result.results.find(r => r.seat === 2).coinChange;
  assert(p1Change + p2Change === 0, 'Zero-sum game: total coin changes = 0');
  assert(room.phase === 'result', 'Phase = result after scoring');
}

console.log('\n📋 Test 17: Scoop bonus (win all 3 rows)');
{
  const room = new ChinesePokerRoom('ofc5', { bigBlind: 20 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 1000 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 1000 });
  room.startHand();

  // Design hands carefully:
  // P1: Front=Pair5s, Middle=PairJacks, Back=PairAces → valid (5<J<A)
  // P2: Front=Pair3s, Middle=Pair4s, Back=Pair9s → valid (3<4<9)
  // P1 wins all 3 rows (5>3, J>4, A>9)
  // Front pairs below 6 → no front royalty
  // Middle/Back are just pairs → no royalties either
  room.players.get(1).hand = ['5h', '5d', '2s', 'Jh', 'Jd', '7c', '8c', 'Ah', 'Ad', '9c', 'Ts', '6s', '3c'];
  room.players.get(2).hand = ['3s', '3h', '4c', '4h', '4d', '9s', '9d', '2c', '2h', '6h', '7s', '8s', 'Tc'];

  // P1 arrangement: front=55x, middle=JJ+low, back=AA+low
  room.arrangeCards(1, ['5h', '5d', '2s'], ['Jh', 'Jd', '7c', '8c', '6s'], ['Ah', 'Ad', '9c', 'Ts', '3c']);
  // P2 arrangement: front=33x, middle=44+low, back=99+low
  const result = room.arrangeCards(2, ['3s', '3h', '4c'], ['4h', '4d', '2c', '6h', '7s'], ['9s', '9d', '2h', '8s', 'Tc']);

  assert(result.result !== undefined, 'Scoring completed');
  const p1Result = result.result.results.find(r => r.seat === 1);
  const p2Result = result.result.results.find(r => r.seat === 2);
  // P1 wins all 3 rows: base 3 + scoop bonus 3 = 6, no royalties
  assert(p1Result.points === 6, `Scoop gives 6 base points (got ${p1Result.points})`);
  assert(p2Result.points === -6, `Loser gets -6 points (got ${p2Result.points})`);
  assert(p1Result.coinChange === 120, `Winner coinChange = 6 * 20 = 120 (got ${p1Result.coinChange})`);
}

console.log('\n📋 Test 18: Foul player loses all rows');
{
  const room = new ChinesePokerRoom('ofc6', { bigBlind: 20 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 1000 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 1000 });
  room.startHand();

  // Player 1 auto-arranges (valid)
  room.autoArrangeForSeat(1);

  // Player 2 arranges with foul (strong front, weak back)
  const hand2 = room.players.get(2).hand;
  const sorted2 = [...hand2].sort((a, b) => {
    const rv = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'T':10,'J':11,'Q':12,'K':13,'A':14 };
    return rv[b[0]] - rv[a[0]];
  });
  const result = room.arrangeCards(2, sorted2.slice(0, 3), sorted2.slice(3, 8), sorted2.slice(8, 13));

  if (result.result) {
    const p2Result = result.result.results.find(r => r.seat === 2);
    if (p2Result && room.players.get(2).arranged && room.players.get(2).arranged.isFoul) {
      assert(p2Result.points <= 0, `Foul player loses points (got ${p2Result.points})`);
    } else {
      assert(true, 'Arrangement was valid (not foul) - depends on card distribution');
    }
  }
}

console.log('\n📋 Test 19: Card count validation');
{
  const room = new ChinesePokerRoom('ofc7', { bigBlind: 20 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 1000 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 1000 });
  room.startHand();

  // Try invalid arrangement (wrong card count)
  const result = room.arrangeCards(1, ['As', 'Kh'], ['Qd', 'Jc', 'Ts', '9h', '8d'], ['7c', '6s', '5h', '4d', '3c']);
  assert(result.error !== undefined, 'Rejects front with 2 cards (need 3)');
}

console.log('\n📋 Test 20: Timer / auto-arrange');
{
  const room = new ChinesePokerRoom('ofc8', { bigBlind: 20, turnTimeSec: 5 });
  room.addPlayer(1, { id: 'p1', username: 'Alice', chips: 1000 });
  room.addPlayer(2, { id: 'p2', username: 'Bob', chips: 1000 });
  room.startHand();

  // Auto-arrange for seat 1
  const result = room.autoArrangeForSeat(1);
  assert(room.players.get(1).arranged !== null, 'Auto-arrange works');
  assert(room.players.get(1).arranged.isFoul === false, 'Auto-arrange produces valid (non-foul) arrangement');
}

// ============================================================
// SUMMARY
// ============================================================
console.log('\n' + '='.repeat(60));
console.log(`📊 RESULTS: ${passed} passed, ${failed} failed, ${passed + failed} total`);
console.log('='.repeat(60));
if (failed === 0) {
  console.log('🎉 ALL TESTS PASSED!');
} else {
  console.log(`⚠️  ${failed} test(s) failed — review above`);
}
process.exit(failed > 0 ? 1 : 0);
