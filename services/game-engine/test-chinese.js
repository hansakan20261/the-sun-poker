// Phase 5 Test: Chinese Poker WebSocket
const { io } = require('socket.io-client');
const jwt = require('jsonwebtoken');

const JWT_SECRET = 'thesunpoker_jwt_secret_dev_2026';
const TABLE_ID = '234ad95b-d36c-4207-ab47-17e4c6b0c5a6';
const token1 = jwt.sign({ id: '1a5d4822-e048-4b8b-aa5f-999636456a7a', username: 'testuser_flow1', role: 'player' }, JWT_SECRET, { expiresIn: '1h' });
const token2 = jwt.sign({ id: 'e2360fa3-532c-4465-abff-9ccf72b96356', username: 'testuser_flow2', role: 'player' }, JWT_SECRET, { expiresIn: '1h' });

let passed = 0, failed = 0;
function ok(t) { passed++; console.log(`  ✅ ${t}`); }
function no(t, r) { failed++; console.log(`  ❌ ${t}: ${r}`); }

console.log('🀄 Phase 5.4-5.6: Chinese Poker Test\n');

const p1 = io('http://localhost:3003', { transports: ['websocket'], auth: { token: token1 } });
const p2 = io('http://localhost:3003', { transports: ['websocket'], auth: { token: token2 } });

let started = false, p1Arranged = false, p2Arranged = false;

// P1 connects → join → wait for P2
p1.on('connect', () => {
  ok('P1 connected');
  p1.emit('chinese:join', { tableId: TABLE_ID, seatNumber: 1, buyIn: 500 });
});

// P2 connects → join
p2.on('connect', () => {
  ok('P2 connected');
  // ให้ P1 join ก่อน แล้วค่อย P2 join
  setTimeout(() => p2.emit('chinese:join', { tableId: TABLE_ID, seatNumber: 2, buyIn: 500 }), 500);
});

// P1 listens for state
p1.on('chinese:state', (s) => {
  const players = Object.keys(s.players || {});

  // เมื่อ 2 คน join ครบ → start
  if (players.length >= 2 && !started && s.phase === 'waiting') {
    started = true;
    ok(`Both players joined (${players.length})`);
    setTimeout(() => p1.emit('chinese:start'), 300);
  }

  // ได้ไพ่ → จัดกอง
  const my = s.players?.['1'];
  if (s.phase === 'arranging' && my?.hand?.length === 13 && !p1Arranged) {
    p1Arranged = true;
    ok(`P1 dealt 13 cards`);
    const sorted = [...my.hand];
    const front = sorted.slice(10, 13);
    const middle = sorted.slice(5, 10);
    const back = sorted.slice(0, 5);
    ok(`P1 arranged: F=${front.length} M=${middle.length} B=${back.length}`);
    p1.emit('chinese:arrange', { front, middle, back });
  }
});

// P2 listens for state
p2.on('chinese:state', (s) => {
  const my = s.players?.['2'];
  if (s.phase === 'arranging' && my?.hand?.length === 13 && !p2Arranged) {
    p2Arranged = true;
    ok(`P2 dealt 13 cards`);
    const sorted = [...my.hand];
    const front = sorted.slice(10, 13);
    const middle = sorted.slice(5, 10);
    const back = sorted.slice(0, 5);
    ok(`P2 arranged: F=${front.length} M=${middle.length} B=${back.length}`);
    p2.emit('chinese:arrange', { front, middle, back });
  }
});

// Result
p1.on('chinese:result', (r) => {
  console.log('\n--- Result ---');
  if (r.results?.length >= 2) {
    ok('Scoring completed');
    for (const p of r.results) {
      const s = p.coinChange > 0 ? '🏆' : p.coinChange < 0 ? '😔' : '🤝';
      console.log(`  ${s} ${p.username}: ${p.points}pts ${p.coinChange > 0 ? '+' : ''}${p.coinChange} coins | F:${p.frontName} M:${p.middleName} B:${p.backName}`);
    }
    ok(`Unit: ${r.unit}/pt`);
  } else { no('Scoring', JSON.stringify(r)); }

  console.log(`\n📊 Results: ${passed} passed, ${failed} failed`);
  setTimeout(() => { p1.disconnect(); p2.disconnect(); process.exit(failed > 0 ? 1 : 0); }, 500);
});

p1.on('error', (d) => console.log(`  ⚠️ P1 error: ${d.message}`));
p2.on('error', (d) => console.log(`  ⚠️ P2 error: ${d.message}`));
setTimeout(() => { console.log(`\n⏰ Timeout\n📊 ${passed} passed, ${failed} failed`); p1.disconnect(); p2.disconnect(); process.exit(1); }, 15000);
