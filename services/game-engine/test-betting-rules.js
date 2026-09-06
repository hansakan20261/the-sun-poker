// ============================================================
// DETAILED BETTING RULES TEST
// ตรวจสอบกฎการลงเงิน/เก/ตาม ตามหลัก No-Limit Texas Hold'em
// ============================================================

const GameRoom = require('./src/poker/game-room');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) { passed++; console.log(`  ✅ ${msg}`); }
  else { failed++; console.log(`  ❌ FAIL: ${msg}`); }
}

console.log('='.repeat(60));
console.log('💰 BETTING RULES TEST — No-Limit Texas Hold\'em');
console.log('='.repeat(60));

// ============================================================
// TEST 1: Blind posting ถูกต้อง
// ============================================================
console.log('\n📋 Test 1: Blind posting');
{
  const room = new GameRoom('t1', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 500 });
  room.addPlayer(4, { id: 'p4', username: 'D', chips: 500 });
  room.startHand();

  assert(room.pot === 15, 'Pot = SB(5) + BB(10) = 15');
  assert(room.players.get(room.smallBlindSeat).chips === 495, 'SB ลง 5 → เหลือ 495');
  assert(room.players.get(room.bigBlindSeat).chips === 490, 'BB ลง 10 → เหลือ 490');
  assert(room.players.get(room.smallBlindSeat).currentBet === 5, 'SB currentBet = 5');
  assert(room.players.get(room.bigBlindSeat).currentBet === 10, 'BB currentBet = 10');
}

// ============================================================
// TEST 2: Call = จ่ายส่วนต่างจาก currentBet ถึง maxBet
// ============================================================
console.log('\n📋 Test 2: Call — จ่ายส่วนต่าง');
{
  const room = new GameRoom('t2', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 500 });
  room.startHand();
  // D=1, SB=2(5), BB=3(10), UTG=1

  // UTG calls: ต้องจ่าย 10 (maxBet=10, myBet=0)
  room.handleAction(1, 'call');
  assert(room.players.get(1).chips === 490, 'UTG call 10 → เหลือ 490');
  assert(room.players.get(1).currentBet === 10, 'UTG currentBet = 10');

  // SB calls: ต้องจ่ายส่วนต่าง 5 (maxBet=10, myBet=5)
  room.handleAction(2, 'call');
  assert(room.players.get(2).chips === 490, 'SB call ส่วนต่าง 5 → เหลือ 490');
  assert(room.players.get(2).currentBet === 10, 'SB currentBet = 10');
}

// ============================================================
// TEST 3: Raise — ขั้นต่ำ = BB (preflop) หรือ last raise size
// ============================================================
console.log('\n📋 Test 3: Minimum raise rules');
{
  const room = new GameRoom('t3', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 500 });
  room.startHand();

  // Min raise preflop = BB (10)
  assert(room.minRaise === 10, 'Initial minRaise = BB (10)');

  // UTG raises: call 10 + raise 10 = 20 total
  room.handleAction(1, 'raise', 20);
  assert(room.players.get(1).currentBet === 20, 'UTG raise to 20');
  assert(room.minRaise === 10, 'minRaise stays 10 (raise portion = 10)');

  // SB tries to min-raise: must raise at least 10 more (to 30)
  // SB raise: call 15 (20-5) + raise 10 = 25 additional
  room.handleAction(2, 'raise', 25);
  assert(room.players.get(2).currentBet === 30, 'SB raise to 30 (min re-raise)');

  // BB tries under-raise (should fail)
  const badRaise = room.handleAction(3, 'raise', 15); // call 20 + raise 5 = only 5 raise
  assert(badRaise.error !== undefined, 'Under-raise rejected (raise 5 < minRaise 10)');

  // BB valid raise: call 20 + raise 10 = 30 additional
  room.handleAction(3, 'raise', 30);
  assert(room.players.get(3).currentBet === 40, 'BB raise to 40');
}

// ============================================================
// TEST 4: Raise re-opens action — ทุกคนต้อง act ใหม่
// ============================================================
console.log('\n📋 Test 4: Raise re-opens action');
{
  const room = new GameRoom('t4', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 500 });
  room.startHand();

  room.handleAction(1, 'call'); // UTG calls 10
  room.handleAction(2, 'call'); // SB calls to 10
  // BB raises
  room.handleAction(3, 'raise', 20); // BB raises to 30 (call 0 + raise 20)
  assert(room.players.get(3).currentBet === 30, 'BB raised to 30');

  // Action re-opens: UTG and SB must act again
  assert(room.currentPlayerSeat === 1, 'Action back to UTG');
  assert(room.players.get(1).hasActed === false, 'UTG hasActed reset to false');
  assert(room.players.get(2).hasActed === false, 'SB hasActed reset to false');
}

// ============================================================
// TEST 5: Check — ได้เฉพาะเมื่อไม่มีใครลงเพิ่ม
// ============================================================
console.log('\n📋 Test 5: Check rules');
{
  const room = new GameRoom('t5', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.startHand();

  // Preflop: SB cannot check (must call or raise)
  const badCheck = room.handleAction(1, 'check');
  assert(badCheck.error !== undefined, 'SB cannot check preflop (must call BB)');

  // SB calls
  room.handleAction(1, 'call');
  // BB can check (option)
  const bbCheck = room.handleAction(2, 'check');
  assert(bbCheck.error === undefined, 'BB can check (option)');

  // Flop: first player can check (no bets yet)
  assert(room.currentRound === 'flop', 'Now on flop');
  const flopCheck = room.handleAction(2, 'check');
  assert(flopCheck.error === undefined, 'Can check on flop (no bets)');
}

// ============================================================
// TEST 6: All-in ที่น้อยกว่า min raise — ไม่ re-open action
// ============================================================
console.log('\n📋 Test 6: Short all-in does NOT re-open action');
{
  const room = new GameRoom('t6', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 14 }); // Short stack
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 500 });
  room.startHand();
  // D=1, SB=2(5, short), BB=3(10)

  // UTG calls 10
  room.handleAction(1, 'call');
  // SB goes all-in for 14 total (9 more from current 5)
  room.handleAction(2, 'all_in');
  assert(room.players.get(2).currentBet === 14, 'SB all-in for 14');
  assert(room.players.get(2).allIn === true, 'SB is all-in');

  // The all-in of 14 is only 4 more than maxBet(10) — less than minRaise(10)
  // So it should NOT re-open action for UTG who already acted
  // BB still needs to act (hasn't acted yet)
  assert(room.currentPlayerSeat === 3, 'Action goes to BB (not back to UTG)');
}

// ============================================================
// TEST 7: Post-flop action order — starts left of dealer
// ============================================================
console.log('\n📋 Test 7: Post-flop action order');
{
  const room = new GameRoom('t7', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 500 });
  room.addPlayer(4, { id: 'p4', username: 'D', chips: 500 });
  room.startHand();
  // D=1, SB=2, BB=3, UTG=4

  // Everyone calls preflop
  room.handleAction(4, 'call');
  room.handleAction(1, 'call');
  room.handleAction(2, 'call');
  room.handleAction(3, 'check'); // BB option

  assert(room.currentRound === 'flop', 'On flop');
  // Post-flop: first active player left of dealer
  // Dealer=1, so first = seat 2 (SB)
  assert(room.currentPlayerSeat === 2, 'Flop: SB (seat 2) acts first (left of dealer)');
}

// ============================================================
// TEST 8: Fold ไม่เสียเงินเพิ่ม
// ============================================================
console.log('\n📋 Test 8: Fold — ไม่เสียเงินเพิ่ม');
{
  const room = new GameRoom('t8', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 500 });
  room.startHand();

  const chipsBefore = room.players.get(1).chips; // 500 (UTG hasn't bet)
  room.handleAction(1, 'fold');
  assert(room.players.get(1).chips === chipsBefore, 'Fold ไม่เสียเงินเพิ่ม');
  assert(room.players.get(1).folded === true, 'Player marked as folded');
}

// ============================================================
// TEST 9: All-in call — จ่ายได้แค่ที่มี
// ============================================================
console.log('\n📋 Test 9: Call with insufficient chips (partial call)');
{
  const room = new GameRoom('t9', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 7 }); // Short stack, less than BB
  room.startHand();
  // D=1, SB=2(5), BB=3(7 all-in as blind)

  assert(room.players.get(3).allIn === true, 'BB with 7 chips goes all-in posting blind');
  assert(room.players.get(3).currentBet === 7, 'BB bet = 7 (all they have)');
  assert(room.players.get(3).chips === 0, 'BB chips = 0');
}

// ============================================================
// TEST 10: Multiple raises in one round
// ============================================================
console.log('\n📋 Test 10: Multiple raises (raise war)');
{
  const room = new GameRoom('t10', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 1000 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 1000 });
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 1000 });
  room.startHand();

  // UTG raises to 20
  room.handleAction(1, 'raise', 20);
  assert(room.players.get(1).currentBet === 20, 'UTG raises to 20');

  // SB re-raises to 50 (call 15 + raise 30)
  room.handleAction(2, 'raise', 45);
  assert(room.players.get(2).currentBet === 50, 'SB re-raises to 50');
  assert(room.minRaise === 30, 'minRaise updated to 30');

  // BB re-raises to 110 (call 40 + raise 60)
  room.handleAction(3, 'raise', 100);
  assert(room.players.get(3).currentBet === 110, 'BB re-raises to 110');
  assert(room.minRaise === 60, 'minRaise updated to 60');

  // UTG 4-bets to 230 (call 90 + raise 120)
  room.handleAction(1, 'raise', 210);
  assert(room.players.get(1).currentBet === 230, 'UTG 4-bets to 230');
}

// ============================================================
// TEST 11: Pot calculation across rounds
// ============================================================
console.log('\n📋 Test 11: Pot accumulates across rounds');
{
  const room = new GameRoom('t11', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.startHand();

  // Preflop: SB calls (5 more), BB checks → pot = 20
  room.handleAction(1, 'call');
  room.handleAction(2, 'check');
  assert(room.pot === 20, 'Preflop pot = 20 (10+10)');

  // Flop: both bet 10 → pot = 40
  room.handleAction(2, 'raise', 10);
  room.handleAction(1, 'call');
  assert(room.pot === 40, 'Flop pot = 40 (20+10+10)');

  // Turn: both check → pot stays 40
  room.handleAction(2, 'check');
  room.handleAction(1, 'check');
  assert(room.pot === 40, 'Turn pot = 40 (no bets)');
}

// ============================================================
// TEST 12: Cannot act out of turn
// ============================================================
console.log('\n📋 Test 12: Cannot act out of turn');
{
  const room = new GameRoom('t12', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.addPlayer(3, { id: 'p3', username: 'C', chips: 500 });
  room.startHand();
  // First to act = UTG (seat 1)

  const wrongTurn = room.handleAction(2, 'call'); // SB tries to act
  assert(wrongTurn.error !== undefined, 'Cannot act out of turn');
  assert(room.currentPlayerSeat === 1, 'Current player unchanged');
}

// ============================================================
// TEST 13: totalBetThisHand tracks across rounds for side pots
// ============================================================
console.log('\n📋 Test 13: totalBetThisHand accumulates across rounds');
{
  const room = new GameRoom('t13', { smallBlind: 5, bigBlind: 10, maxSeats: 9 });
  room.addPlayer(1, { id: 'p1', username: 'A', chips: 500 });
  room.addPlayer(2, { id: 'p2', username: 'B', chips: 500 });
  room.startHand();

  // Preflop: SB calls → both at 10
  room.handleAction(1, 'call');
  room.handleAction(2, 'check');
  assert(room.players.get(1).totalBetThisHand === 10, 'After preflop: totalBet = 10');
  assert(room.players.get(1).currentBet === 0, 'After round change: currentBet reset to 0');

  // Flop: both bet 20
  room.handleAction(2, 'raise', 20);
  room.handleAction(1, 'call');
  assert(room.players.get(1).totalBetThisHand === 30, 'After flop: totalBet = 10+20 = 30');
  assert(room.players.get(2).totalBetThisHand === 30, 'Player 2 totalBet = 10+20 = 30');
}

// ============================================================
// SUMMARY
// ============================================================
console.log('\n' + '='.repeat(60));
console.log(`📊 BETTING RULES: ${passed} passed, ${failed} failed`);
console.log('='.repeat(60));
if (failed === 0) {
  console.log('🎉 ALL BETTING RULES CORRECT!');
} else {
  console.log(`⚠️  ${failed} rule(s) incorrect — review above`);
}
process.exit(failed > 0 ? 1 : 0);
