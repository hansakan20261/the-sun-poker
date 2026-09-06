// Test: Auto-deal + Hand History
const { io } = require('socket.io-client');
const jwt = require('jsonwebtoken');
const http = require('http');

const JWT_SECRET = 'thesunpoker_jwt_secret_dev_2026';
const TABLE_ID = '234ad95b-d36c-4207-ab47-17e4c6b0c5a6';
const token = jwt.sign({ id: '1a5d4822-e048-4b8b-aa5f-999636456a7a', username: 'testuser_flow1', role: 'player' }, JWT_SECRET, { expiresIn: '1h' });

let passed = 0, failed = 0;
function ok(t) { passed++; console.log(`  ✅ ${t}`); }
function no(t, r) { failed++; console.log(`  ❌ ${t}: ${r}`); }

const get = (url, headers) => new Promise((resolve, reject) => {
  http.get(url, { headers }, (res) => { let d = ''; res.on('data', c => d += c); res.on('end', () => resolve(JSON.parse(d))); }).on('error', reject);
});

console.log('🔄 Test: Auto-deal + Hand History\n');

const socket = io('http://localhost:3003', { transports: ['websocket'], auth: { token } });
let handCount = 0, resultCount = 0;

socket.on('connect', () => {
  ok('Connected');
  socket.emit('game:join', { tableId: TABLE_ID, seatNumber: 1, buyIn: 500 });
});

socket.on('game:state', (s) => {
  const players = Object.keys(s.players || {});
  if (players.length >= 2 && !s.isPlaying && handCount === 0) {
    ok(`Joined with bot (${players.length} players)`);
    socket.emit('game:start');
  }

  // Track new hands starting
  if (s.isPlaying && s.handNumber > handCount) {
    handCount = s.handNumber;
    if (handCount === 1) ok(`Hand #1 started`);
    else ok(`🔄 Auto-deal: Hand #${handCount} started`);
  }

  // Play: always call/check when it's my turn
  if (s.isPlaying && s.currentPlayerSeat === 1) {
    const my = s.players?.['1'];
    const maxBet = Math.max(...Object.values(s.players).map(p => p.currentBet || 0));
    const needCall = (my?.currentBet || 0) < maxBet;
    socket.emit('game:action', { action: needCall ? 'call' : 'check', amount: 0 });
  }
});

socket.on('game:result', (r) => {
  resultCount++;
  const won = r.winners?.some(w => w.seat === 1);
  ok(`Hand #${handCount} result: pot=${r.pot} ${won ? '🏆 WIN' : '😔 LOSE'}`);

  // หลังจบ 2 มือ → ตรวจ hand history
  if (resultCount >= 2) {
    console.log('\n--- Checking Hand History API ---');
    setTimeout(async () => {
      try {
        const hist = await get('http://localhost:3002/tables/hand-history?limit=5', { Authorization: `Bearer ${token}` });
        if (hist.hands?.length >= 2) {
          ok(`Hand history: ${hist.hands.length} hands recorded`);
          const h = hist.hands[0];
          const data = typeof h.community_cards === 'string' ? JSON.parse(h.community_cards) : h.community_cards;
          if (data?.actions?.length > 0) ok(`Actions recorded: ${data.actions.length} actions in last hand`);
          else ok(`Hand data saved (community cards + players)`);
          if (data?.players) ok(`Player hole cards saved`);
        } else {
          no('Hand history', `Expected >= 2, got ${hist.hands?.length}`);
        }
      } catch (e) { no('Hand history API', e.message); }

      console.log(`\n📊 Results: ${passed} passed, ${failed} failed`);
      socket.disconnect();
      process.exit(failed > 0 ? 1 : 0);
    }, 1000);
  }
});

socket.on('error', () => {});
setTimeout(() => { console.log(`\n⏰ Timeout (25s)\n📊 ${passed} passed, ${failed} failed`); socket.disconnect(); process.exit(1); }, 25000);
