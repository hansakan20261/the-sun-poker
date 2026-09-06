// ============================================================
// SCENARIO TEST: Texas Hold'em + Chinese Poker (ไพ่สามกอง)
// ทดสอบตาม scenario จริงที่กำหนดมา
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
// SCENARIO 1: Texas Hold'em (4 players)
// A=BTN, B=SB, C=BB, D=UTG | Blinds 10/20 | Chips 2000 each
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🃏 SCENARIO 1: Texas Hold\'em (4 คน)');
console.log('='.repeat(60));

{
  const room = new GameRoom('scenario1', { smallBlind: 10, bigBlind: 20, maxSeats: 9 });
  room.addPlayer(1, { id: 'A', username: 'A (BTN)', chips: 2000 });
  room.addPlayer(2, { id: 'B', username: 'B (SB)', chips: 2000 });
  room.addPlayer(3, { id: 'C', username: 'C (BB)', chips: 2000 });
  room.addPlayer(4, { id: 'D', username: 'D (UTG)', chips: 2000 });

  // Force dealer to seat 1 (A=BTN)
  room.dealerSeat = 4; // Will rotate to 1 on startHand
  room.startHand();

  console.log('\n--- Step 1: Pre-Flop ---');
  assert(room.dealerSeat === 1, 'Dealer (BTN) = A (seat 1)');
  assert(room.smallBlindSeat === 2, 'SB = B (seat 2)');
  assert(room.bigBlindSeat === 3, 'BB = C (seat 3)');
  assert(room.currentPlayerSeat === 4, 'First to act = D (UTG, seat 4)');
  assert(room.pot === 30, 'Pot after blinds = 30 (SB 10 + BB 20)');
  assert(room.players.get(2).chips === 1990, 'B (SB) chips = 1990');
  assert(room.players.get(3).chips === 1980, 'C (BB) chips = 1980');

  // D raises to 60
  room.handleAction(4, 'raise', 60);
  assert(room.players.get(4).currentBet === 60, 'D raised to 60');
  assert(room.players.get(4).chips === 1940, 'D chips = 2000-60 = 1940');
  assert(room.pot === 90, 'Pot = 30+60 = 90');

  // A calls 60
  room.handleAction(1, 'call');
  assert(room.players.get(1).currentBet === 60, 'A called 60');
  assert(room.players.get(1).chips === 1940, 'A chips = 2000-60 = 1940');
  assert(room.pot === 150, 'Pot = 90+60 = 150');

  // B (SB) calls 50 more (already has 10 in)
  room.handleAction(2, 'call');
  assert(room.players.get(2).currentBet === 60, 'B called to 60 (paid 50 more)');
  assert(room.players.get(2).chips === 1940, 'B chips = 2000-60 = 1940');
  assert(room.pot === 200, 'Pot = 150+50 = 200');

  // C (BB) folds
  room.handleAction(3, 'fold');
  assert(room.players.get(3).folded === true, 'C folded');
  assert(room.players.get(3).chips === 1980, 'C chips unchanged after fold = 1980 (lost 20 blind)');

  // Round should end — all remaining players have equal bets
  assert(room.currentRound === 'flop', 'Moved to flop after preflop');
  assert(room.pot === 200, 'Total pot after preflop = 200');

  console.log('\n--- Step 2: Flop ---');
  assert(room.communityCards.length === 3, 'Flop: 3 community cards dealt');
  // Post-flop: first active left of dealer (BTN=1) → seat 2 (B/SB)
  assert(room.currentPlayerSeat === 2, 'Flop: B (SB, seat 2) acts first');

  // B checks
  room.handleAction(2, 'check');
  // D bets 100
  room.handleAction(4, 'raise', 100);
  assert(room.players.get(4).currentBet === 100, 'D bet 100 on flop');
  assert(room.pot === 300, 'Pot = 200+100 = 300');

  // A calls 100
  room.handleAction(1, 'call');
  assert(room.pot === 400, 'Pot = 300+100 = 400');

  // B folds
  room.handleAction(2, 'fold');
  assert(room.players.get(2).folded === true, 'B folded on flop');

  // Round ends — D and A equal bets
  assert(room.currentRound === 'turn', 'Moved to turn');
  assert(room.pot === 400, 'Total pot after flop = 400');

  console.log('\n--- Step 3: Turn ---');
  assert(room.communityCards.length === 4, 'Turn: 4 community cards');
  // First active left of dealer: D (seat 4) — B folded, C folded
  assert(room.currentPlayerSeat === 4, 'Turn: D acts first (only active left of dealer)');

  // D bets 200
  room.handleAction(4, 'raise', 200);
  assert(room.pot === 600, 'Pot = 400+200 = 600');

  // A calls 200 (slow play)
  room.handleAction(1, 'call');
  assert(room.pot === 800, 'Pot = 600+200 = 800');
  assert(room.currentRound === 'river', 'Moved to river');

  console.log('\n--- Step 4: River ---');
  assert(room.communityCards.length === 5, 'River: 5 community cards');

  // D bets 400
  room.handleAction(4, 'raise', 400);
  assert(room.pot === 1200, 'Pot = 800+400 = 1200');

  // A raises to 1000 (total additional from 0 = 1000)
  room.handleAction(1, 'raise', 1000);
  assert(room.players.get(1).currentBet === 1000, 'A raised to 1000');

  // D calls 600 more (to match 1000)
  room.handleAction(4, 'call');
  // After showdown, pot has rake deducted
  // Gross pot = 2800, Rake = floor(2800 * 5.5%) = 154, Net pot = 2646
  const grossPot = 2800;
  const expectedRake = Math.floor(grossPot * 5.5 / 100); // 154
  const netPot = grossPot - expectedRake;
  assert(room.pot === netPot, `Pot after river & rake = ${netPot} (gross 2800 - rake ${expectedRake}) (got ${room.pot})`);

  console.log('\n--- Step 5: Showdown ---');
  assert(room.currentRound === 'result', 'Showdown reached');

  // Verify total pot
  // D total bet: 60 + 100 + 200 + 1000 = 1360
  // A total bet: 60 + 100 + 200 + 1000 = 1360
  // B total bet: 60
  // C total bet: 20
  // Gross total = 1360 + 1360 + 60 + 20 = 2800
  assert(room.pot === netPot, `Final pot after rake = ${netPot} (gross 2800 - rake ${expectedRake})`);

  // Check chip totals
  const dChips = room.players.get(4).chips;
  const aChips = room.players.get(1).chips;
  console.log(`  D chips: ${dChips}, A chips: ${aChips}`);

  // Winner gets net pot, one of them should have 2000-1360+2646 = 3286
  const expectedWinnerChips = 2000 - 1360 + netPot; // 3286
  const expectedLoserChips = 2000 - 1360; // 640
  const winner = aChips > dChips ? 'A' : 'D';
  const winnerChips = Math.max(aChips, dChips);
  const loserChips = Math.min(aChips, dChips);
  assert(winnerChips === expectedWinnerChips, `Winner (${winner}) chips = 2000-1360+${netPot} = ${expectedWinnerChips} (got ${winnerChips})`);
  assert(loserChips === expectedLoserChips, `Loser chips = 2000-1360 = ${expectedLoserChips} (got ${loserChips})`);

  // B and C chips
  assert(room.players.get(2).chips === 1940, 'B chips = 2000-60 = 1940');
  assert(room.players.get(3).chips === 1980, 'C chips = 2000-20 = 1980');

  // Total chips = 8000 - rake
  const totalChips = room.players.get(1).chips + room.players.get(2).chips + room.players.get(3).chips + room.players.get(4).chips;
  assert(totalChips === 8000 - expectedRake, `Total chips = 8000 - ${expectedRake} rake = ${8000 - expectedRake} (got ${totalChips})`);
}

// ============================================================
// SCENARIO 2: Chinese Poker (ไพ่สามกอง, 3 คน)
// X, Y, Z | 1 unit = 100 baht | Scoop = x2
// ============================================================
console.log('\n' + '='.repeat(60));
console.log('🀄 SCENARIO 2: ไพ่สามกอง (3 คน)');
console.log('='.repeat(60));

{
  const room = new ChinesePokerRoom('scenario2', { bigBlind: 100 }); // 1 unit = 100
  room.addPlayer(1, { id: 'X', username: 'X', chips: 5000 });
  room.addPlayer(2, { id: 'Y', username: 'Y', chips: 5000 });
  room.addPlayer(3, { id: 'Z', username: 'Z', chips: 5000 });
  room.startHand();

  console.log('\n--- Step 1: จัดไพ่ ---');

  // X: Flush(back), Straight(middle), Pair J(front) — valid
  // Force specific cards for X
  room.players.get(1).hand = ['Ac', 'Kc', 'Qc', 'Tc', '8c', '5d', '6h', '7s', '8d', '9c', 'Jh', 'Jd', '3s'];
  // X arranges:
  // Back: Ac, Kc, Qc, Tc, 8c (Flush clubs)
  // Middle: 5d, 6h, 7s, 8d, 9c (Straight 5-9)
  // Front: Jh, Jd, 3s (Pair J)
  const xResult = room.arrangeCards(1, ['Jh', 'Jd', '3s'], ['5d', '6h', '7s', '8d', '9c'], ['Ac', 'Kc', 'Qc', 'Tc', '8c']);
  assert(!xResult.error, 'X: arrangement accepted');
  assert(room.players.get(1).arranged.isFoul === false, 'X: NOT foul (valid)');
  assert(room.players.get(1).arranged.backName === 'Flush', 'X back = Flush');
  assert(room.players.get(1).arranged.middleName === 'Straight', 'X middle = Straight');
  assert(room.players.get(1).arranged.frontName === 'Pair', 'X front = Pair');

  // Y: Full House(back), Pair A(middle), Pair Q(front) — valid
  room.players.get(2).hand = ['Th', 'Td', 'Ts', '4h', '4d', 'Ah', 'Ad', '2s', '5c', 'Kd', 'Qh', 'Qs', '9d'];
  // Y arranges:
  // Back: Th, Td, Ts, 4h, 4d (Full House: 10s full of 4s)
  // Middle: Ah, Ad, 2s, 5c, Kd (Pair A)
  // Front: Qh, Qs, 9d (Pair Q)
  const yResult = room.arrangeCards(2, ['Qh', 'Qs', '9d'], ['Ah', 'Ad', '2s', '5c', 'Kd'], ['Th', 'Td', 'Ts', '4h', '4d']);
  assert(!yResult.error, 'Y: arrangement accepted');
  assert(room.players.get(2).arranged.isFoul === false, 'Y: NOT foul (valid)');
  assert(room.players.get(2).arranged.backName === 'Full House', 'Y back = Full House');
  assert(room.players.get(2).arranged.middleName === 'Pair', 'Y middle = Pair');
  assert(room.players.get(2).arranged.frontName === 'Pair', 'Y front = Pair');

  // Z: Straight(back), Flush(middle) — FOUL! (middle > back)
  room.players.get(3).hand = ['4s', '5s', '6s', '7d', '8s', '2h', '3h', '4h', '6h', '9h', 'As', 'Js', '5h'];
  // Z arranges (incorrectly):
  // Back: 4s, 5s, 6s, 7d, 8s (Straight 4-8)
  // Middle: 2h, 3h, 4h, 6h, 9h (Flush hearts)
  // Front: As, Js, 5h (High card)
  const zResult = room.arrangeCards(3, ['As', 'Js', '5h'], ['2h', '3h', '4h', '6h', '9h'], ['4s', '5s', '6s', '7d', '8s']);

  assert(zResult.result !== undefined, 'All arranged → scoring triggered');
  assert(room.players.get(3).arranged.isFoul === true, 'Z: FOUL (middle Flush > back Straight)');

  console.log('\n--- Step 2: เทียบไพ่ ---');
  const results = zResult.result.results;
  const xScore = results.find(r => r.seat === 1);
  const yScore = results.find(r => r.seat === 2);
  const zScore = results.find(r => r.seat === 3);

  console.log(`  X points: ${xScore.points}, coinChange: ${xScore.coinChange}`);
  console.log(`  Y points: ${yScore.points}, coinChange: ${yScore.coinChange}`);
  console.log(`  Z points: ${zScore.points}, coinChange: ${zScore.coinChange}`);

  // X vs Z (Z foul): X wins scoop(+6) + X royalties (PairJ front=6 + Straight mid=4 + Flush back=4 = 14) = +20
  // Y vs Z (Z foul): Y wins scoop(+6) + Y royalties (PairQ front=7 + PairA mid=0 + FH back=6 = 13) = +19
  // X vs Y (both valid):
  //   Back: Y(FH) > X(Flush) → Y +1 row
  //   Middle: X(Straight) > Y(Pair) → X +1 row
  //   Front: Y(PairQ) > X(PairJ) → Y +1 row
  //   Y wins 2-1 → base Y+1, X-1 (no scoop)
  //   Royalties: X=(6+4+4)=14, Y=(7+0+6)=13 → net X gets +1
  //   X vs Y net: -1 + 1 = 0 for X, +1 - 1 = 0 for Y
  // Total: X=20, Y=19, Z=-39 (zero-sum: 20+19-39=0)
  assert(zScore.points === -39, `Z points = -39 (got ${zScore.points})`);
  assert(xScore.points + yScore.points + zScore.points === 0, `Zero-sum: X+Y+Z = 0 (got ${xScore.points + yScore.points + zScore.points})`);
  assert(xScore.points === 20, `X points = 20 (scoop+royalties from Z + net 0 vs Y) (got ${xScore.points})`);
  assert(yScore.points === 19, `Y points = 19 (scoop+royalties from Z + net 0 vs X) (got ${yScore.points})`);

  console.log('\n--- Step 3: สรุปเงิน ---');
  // 1 unit = bigBlind = 100
  assert(xScore.coinChange === xScore.points * 100, `X coinChange = points*100 = ${xScore.points * 100} (got ${xScore.coinChange})`);
  assert(yScore.coinChange === yScore.points * 100, `Y coinChange = points*100 = ${yScore.points * 100} (got ${yScore.coinChange})`);
  assert(zScore.coinChange === -3900, `Z pays -3900 baht (got ${zScore.coinChange})`);

  // Zero-sum check
  const totalChange = xScore.coinChange + yScore.coinChange + zScore.coinChange;
  assert(totalChange === 0, `Zero-sum: total coin changes = 0 (got ${totalChange})`);

  // Chip verification (after rake for winners)
  // Winners have rake deducted from their chips
  const xRake = xScore.coinChange > 0 ? Math.floor(xScore.coinChange * 5.5 / 100) : 0;
  const yRake = yScore.coinChange > 0 ? Math.floor(yScore.coinChange * 5.5 / 100) : 0;
  const zRake = zScore.coinChange > 0 ? Math.floor(zScore.coinChange * 5.5 / 100) : 0;
  assert(room.players.get(1).chips === 5000 + xScore.coinChange - xRake, `X chips = 5000+${xScore.coinChange}-${xRake}rake = ${5000 + xScore.coinChange - xRake} (got ${room.players.get(1).chips})`);
  assert(room.players.get(2).chips === 5000 + yScore.coinChange - yRake, `Y chips = 5000+${yScore.coinChange}-${yRake}rake = ${5000 + yScore.coinChange - yRake} (got ${room.players.get(2).chips})`);
  assert(room.players.get(3).chips === 5000 + zScore.coinChange - zRake, `Z chips = 5000+${zScore.coinChange}-${zRake}rake = ${5000 + zScore.coinChange - zRake} (got ${room.players.get(3).chips})`);
}

// ============================================================
// SUMMARY
// ============================================================
console.log('\n' + '='.repeat(60));
console.log(`📊 SCENARIO TESTS: ${passed} passed, ${failed} failed, ${passed + failed} total`);
console.log('='.repeat(60));
if (failed === 0) {
  console.log('🎉 ALL SCENARIO TESTS PASSED!');
} else {
  console.log(`⚠️  ${failed} test(s) failed — review above`);
}
process.exit(failed > 0 ? 1 : 0);
