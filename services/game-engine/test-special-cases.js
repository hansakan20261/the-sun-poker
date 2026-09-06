// ============================================================
// SPECIAL CASE TESTS
// Scenario 1: Side Pot + Split Pot (Poker)
// Scenario 2: Naturals (Dragon) + Royalties (Chinese Poker)
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
// SCENARIO 1: Side Pot + Split Pot
// A(BTN, 1000), B(SB, 300), C(BB, 1000)
// Turn board: 10c, Jh, Qd, 3s → River: Ks
// B: Ac,9d (Straight AKQJT)
// C: Ah,2h (Straight AKQJT)
// A: Kh,Kd (Three Kings)
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🃏 SCENARIO 1: Side Pot + Split Pot');
console.log('='.repeat(60));

{
  const room = new GameRoom('sp1', { smallBlind: 10, bigBlind: 20, maxSeats: 9 });
  room.addPlayer(1, { id: 'A', username: 'A (BTN)', chips: 1000 });
  room.addPlayer(2, { id: 'B', username: 'B (SB)', chips: 300 });
  room.addPlayer(3, { id: 'C', username: 'C (BB)', chips: 1000 });

  // Force dealer position
  room.dealerSeat = 3; // Will rotate to 1
  room.startHand();

  assert(room.dealerSeat === 1, 'Dealer = A (seat 1)');
  assert(room.smallBlindSeat === 2, 'SB = B (seat 2)');
  assert(room.bigBlindSeat === 3, 'BB = C (seat 3)');

  // Force hole cards
  room.players.get(1).holeCards = ['Kh', 'Kd']; // A: pair K
  room.players.get(2).holeCards = ['Ac', '9d']; // B: will make straight
  room.players.get(3).holeCards = ['Ah', '2h']; // C: will make straight

  console.log('\n--- Pre-flop: get to flop quickly ---');
  // Preflop: everyone calls BB (20)
  // Heads-up preflop: SB=seat2 acts first (but 3 players so UTG first... wait)
  // D=1(BTN), SB=2, BB=3, no UTG in 3-player → first to act = seat 1 (BTN)
  // Actually with 3 players: D=1, SB=2, BB=3, first preflop = seat 1 (after BB)
  room.handleAction(1, 'call'); // A calls 20
  room.handleAction(2, 'call'); // B calls to 20 (pays 10 more)
  room.handleAction(3, 'check'); // BB checks
  assert(room.currentRound === 'flop', 'Moved to flop');
  assert(room.pot === 60, 'Pot after preflop = 60');

  console.log('\n--- Flop: 10c, Jh, Qd ---');
  // Force community cards for the scenario
  room.communityCards = ['Tc', 'Jh', 'Qd'];
  // Flop: everyone checks
  room.handleAction(2, 'check'); // B
  room.handleAction(3, 'check'); // C
  room.handleAction(1, 'check'); // A
  assert(room.currentRound === 'turn', 'Moved to turn');

  console.log('\n--- Turn: 3s ---');
  room.communityCards.push('3s');
  // Skip the actual card deal — we forced it
  // Now the scenario action:
  // Pot so far = 60, B has 280 chips left

  // B all-in 280
  room.handleAction(2, 'all_in');
  assert(room.players.get(2).allIn === true, 'B is all-in');
  assert(room.players.get(2).chips === 0, 'B has 0 chips');
  const bBet = room.players.get(2).currentBet;
  console.log(`  B bet: ${bBet}, pot: ${room.pot}`);

  // C calls B's all-in
  room.handleAction(3, 'call');
  console.log(`  C bet: ${room.players.get(3).currentBet}, pot: ${room.pot}`);

  // A raises to 600 (additional from 0)
  room.handleAction(1, 'raise', 600);
  console.log(`  A bet: ${room.players.get(1).currentBet}, pot: ${room.pot}`);

  // C calls A's raise (pays difference)
  room.handleAction(3, 'call');
  console.log(`  C bet: ${room.players.get(3).currentBet}, pot: ${room.pot}`);

  assert(room.currentRound === 'river', 'Moved to river');

  console.log('\n--- River: Ks ---');
  room.communityCards = ['Tc', 'Jh', 'Qd', '3s', 'Ks']; // Force final board

  // A and C check
  room.handleAction(3, 'check'); // C
  room.handleAction(1, 'check'); // A

  console.log('\n--- Showdown ---');
  assert(room.currentRound === 'result', 'Showdown reached');

  // Check results
  const aChips = room.players.get(1).chips;
  const bChips = room.players.get(2).chips;
  const cChips = room.players.get(3).chips;
  console.log(`  A chips: ${aChips} (started 1000)`);
  console.log(`  B chips: ${bChips} (started 300)`);
  console.log(`  C chips: ${cChips} (started 1000)`);

  // Expected:
  // B total bet this hand: 20 (preflop) + 280 (turn all-in) = 300
  // A total bet this hand: 20 (preflop) + 600 (turn) = 620
  // C total bet this hand: 20 (preflop) + 600 (turn) = 620
  // Total pot = 300 + 620 + 620 = 1540 (including the 60 from preflop)

  // Side pots:
  // Main pot: 300 * 3 = 900 from turn bets... actually need to use totalBetThisHand
  // B totalBet = 300, A totalBet = 620, C totalBet = 620
  // Main pot (up to B's 300): 300*3 = 900 → eligible: A, B, C
  // Side pot (300 to 620): (620-300)*2 = 640 → eligible: A, C only

  // Winners:
  // B: Ac,9d + Tc,Jh,Qd,3s,Ks → best 5: A,K,Q,J,T = Straight (Ace-high)
  // C: Ah,2h + Tc,Jh,Qd,3s,Ks → best 5: A,K,Q,J,T = Straight (Ace-high)
  // A: Kh,Kd + Tc,Jh,Qd,3s,Ks → best 5: K,K,K,Q,J = Three of a Kind

  // Main pot (900): B and C tie (both Straight) → split 900/2 = 450 each
  // Side pot (640): C wins (Straight beats Three Kings) → C gets 640

  // Final chips:
  // A: 1000 - 620 = 380 (lost everything bet)
  // B: 0 + 450 = 450 (got half main pot)
  // C: 1000 - 620 + 450 + 640 = 1470 (got half main pot + side pot)

  const totalChips = aChips + bChips + cChips;
  assert(totalChips === 2300, `Zero-sum: total chips = 2300 (got ${totalChips})`);

  // A should have lost (Three Kings < Straight)
  assert(aChips === 380, `A chips = 1000-620 = 380 (got ${aChips})`);

  // B should get half of main pot
  assert(bChips === 450, `B chips = 0+450 (half main pot) = 450 (got ${bChips})`);

  // C should get half main pot + full side pot
  assert(cChips === 1470, `C chips = 380+450+640 = 1470 (got ${cChips})`);

  // Verify B got profit (started with 300, ended with 450)
  assert(bChips > 300, `B profited: started 300, ended ${bChips}`);

  // Verify A lost
  assert(aChips < 1000, `A lost: started 1000, ended ${aChips}`);
}

// ============================================================
// SCENARIO 2: Chinese Poker - Naturals (Dragon) + Royalties
// A: Dragon (13 different ranks) → auto-win +13 from each
// B: Straight Flush(back), Full House(middle), Pair 5(front)
// C: Full House(back), Straight(middle), High card KQJ(front)
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🀄 SCENARIO 2: Naturals (Dragon) + Royalties');
console.log('='.repeat(60));

{
  // Note: Our current engine does NOT have "Dragon/Natural" rule built in.
  // Dragon = 13 cards with all different ranks (A-K) regardless of suit.
  // This is a special rule that some variants use.
  // We'll test what we CAN test: B vs C with royalties.

  console.log('\n--- Testing B vs C (with Royalties) ---');
  console.log('  (Dragon/Natural rule not implemented — testing royalty scoring)');

  const room = new ChinesePokerRoom('sp2', { bigBlind: 100 }); // 1 unit = 100
  room.addPlayer(1, { id: 'B', username: 'B', chips: 5000 });
  room.addPlayer(2, { id: 'C', username: 'C', chips: 5000 });
  room.startHand();

  // B: Straight Flush(back), Full House(middle), Pair 5(front)
  room.players.get(1).hand = ['5h', '6h', '7h', '8h', '9h', '9d', '9c', '2s', '2d', '5s', '5d', '4c', '3d'];
  // Back: 5h,6h,7h,8h,9h (Straight Flush)
  // Middle: 9d,9c,2s,2d,5s (wait — need Full House) 
  // Let me fix: need 3+2 for full house
  // Middle: 9d,9c,9s,2s,2d → but we used 9h already... 
  // Let me use different cards:
  room.players.get(1).hand = ['5h', '6h', '7h', '8h', '9h', 'Td', 'Ts', 'Tc', '4d', '4s', '5s', '5d', '3c'];
  // Back: 5h,6h,7h,8h,9h (Straight Flush 5-9)
  // Middle: Td,Ts,Tc,4d,4s (Full House: Tens full of Fours)
  // Front: 5s,5d,3c (Pair 5)

  const bResult = room.arrangeCards(1, ['5s', '5d', '3c'], ['Td', 'Ts', 'Tc', '4d', '4s'], ['5h', '6h', '7h', '8h', '9h']);
  assert(!bResult.error, 'B arrangement accepted');
  assert(room.players.get(1).arranged.isFoul === false, 'B: NOT foul');
  assert(room.players.get(1).arranged.backName === 'Straight Flush', `B back = Straight Flush (got ${room.players.get(1).arranged.backName})`);
  assert(room.players.get(1).arranged.middleName === 'Full House', `B middle = Full House (got ${room.players.get(1).arranged.middleName})`);

  // C: Full House(back), Straight(middle), High card KQJ(front)
  room.players.get(2).hand = ['8s', '8d', '8c', '3s', '3h', '4h', '5c', '6c', '7d', '2c', 'Kh', 'Qd', 'Js'];
  // Back: 8s,8d,8c,3s,3h (Full House: Eights full of Threes)
  // Middle: 4h,5c,6c,7d,2c → not straight... need 3,4,5,6,7 or 4,5,6,7,8
  // Fix: use 4h,5c,6c,7d,8s → but 8s is in back...
  // Let me restructure:
  room.players.get(2).hand = ['8s', '8d', '8c', '3s', '3h', '4h', '5c', '6c', '7c', '2c', 'Kh', 'Qd', 'Js'];
  // Back: 8s,8d,8c,3s,3h (Full House)
  // Middle: 4h,5c,6c,7c,2c → not straight (2,4,5,6,7 not consecutive)
  // Need: 3,4,5,6,7 straight
  room.players.get(2).hand = ['8s', '8d', '8c', '2s', '2h', '3d', '4h', '5c', '6c', '7d', 'Kh', 'Qd', 'Js'];
  // Back: 8s,8d,8c,2s,2h (Full House: Eights full of Twos)
  // Middle: 3d,4h,5c,6c,7d (Straight 3-7)
  // Front: Kh,Qd,Js (High card KQJ)

  const cResult = room.arrangeCards(2, ['Kh', 'Qd', 'Js'], ['3d', '4h', '5c', '6c', '7d'], ['8s', '8d', '8c', '2s', '2h']);
  assert(cResult.result !== undefined, 'All arranged → scoring triggered');
  assert(room.players.get(2).arranged.isFoul === false, 'C: NOT foul');
  assert(room.players.get(2).arranged.backName === 'Full House', `C back = Full House (got ${room.players.get(2).arranged.backName})`);
  assert(room.players.get(2).arranged.middleName === 'Straight', `C middle = Straight (got ${room.players.get(2).arranged.middleName})`);

  console.log('\n--- Scoring Results ---');
  const results = cResult.result.results;
  const bScore = results.find(r => r.seat === 1);
  const cScore = results.find(r => r.seat === 2);
  console.log(`  B points: ${bScore.points}, coinChange: ${bScore.coinChange}`);
  console.log(`  C points: ${cScore.points}, coinChange: ${cScore.coinChange}`);

  // B vs C:
  // Back: B(Straight Flush) beats C(Full House) → B wins +1
  // Middle: B(Full House) beats C(Straight) → B wins +1
  // Front: B(Pair 5) beats C(High card KQJ) → B wins +1
  // B wins all 3 → SCOOP: base 3 → doubled to 6

  // Royalties:
  // B back: Straight Flush = +15
  // B middle: Full House = +12 (middle royalty for full house)
  // B front: Pair 5 = 0 (pairs 6+ get royalty)
  // C back: Full House = +6
  // C middle: Straight = +4
  // C front: High card = 0

  // B royalty total = 15 + 12 = 27
  // C royalty total = 6 + 4 = 10
  // Royalty difference: B gets +(27-10) = +17 from C

  // Total B vs C: 6 (scoop) + 17 (royalty diff) = +23
  // But wait — scoop already includes the 3 row wins doubled
  // Let me re-read the scoring code...
  // Code: if aWins===3 → aPoints=6, then adds royalty diff
  // So: B points = 6 + (27-10) = 6 + 17 = 23

  assert(bScore.points > 0, `B wins (got ${bScore.points} points)`);
  assert(cScore.points < 0, `C loses (got ${cScore.points} points)`);
  assert(bScore.points + cScore.points === 0, `Zero-sum: B+C = 0 (got ${bScore.points + cScore.points})`);

  // Verify scoop happened (B won all 3 rows)
  assert(bScore.points >= 6, `B got scoop (6+) with royalties (got ${bScore.points})`);

  // Verify royalties are included
  // Straight Flush back = 15, Full House middle = 12 → B royalty = 27
  // Full House back = 6, Straight middle = 4 → C royalty = 10
  // Net royalty for B = 27-10 = 17
  // Total = 6 (scoop) + 17 (royalties) = 23
  assert(bScore.points === 23, `B total = 6(scoop) + 17(royalty diff) = 23 (got ${bScore.points})`);
  assert(cScore.points === -23, `C total = -23 (got ${cScore.points})`);

  // Coin change
  assert(bScore.coinChange === 2300, `B gets +2300 baht (got ${bScore.coinChange})`);
  assert(cScore.coinChange === -2300, `C pays -2300 baht (got ${cScore.coinChange})`);

  console.log('\n--- Dragon (Natural) Note ---');
  console.log('  ⚠️ Dragon/Natural rule (13 different ranks = auto-win +13/person)');
  console.log('  is NOT currently implemented in the engine.');
  console.log('  This is a variant rule used in some regions.');
  console.log('  If needed, it can be added as a special check before scoring.');
}

// ============================================================
// SUMMARY
// ============================================================
console.log('\n' + '='.repeat(60));
console.log(`📊 SPECIAL CASE TESTS: ${passed} passed, ${failed} failed, ${passed + failed} total`);
console.log('='.repeat(60));
if (failed === 0) {
  console.log('🎉 ALL SPECIAL CASE TESTS PASSED!');
} else {
  console.log(`⚠️  ${failed} test(s) failed — review above`);
}
process.exit(failed > 0 ? 1 : 0);
