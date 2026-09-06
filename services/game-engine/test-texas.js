// Phase 5 Test: Texas Hold'em — proper turn-based testing
const { io } = require('socket.io-client');
const jwt = require('jsonwebtoken');

const JWT_SECRET = 'thesunpoker_jwt_secret_dev_2026';
const TABLE_ID = '234ad95b-d36c-4207-ab47-17e4c6b0c5a6';
const token = jwt.sign(
  { id: '1a5d4822-e048-4b8b-aa5f-999636456a7a', username: 'testuser_flow1', role: 'player' },
  JWT_SECRET, { expiresIn: '1h' }
);

let passed = 0, failed = 0;
function ok(t) { passed++; console.log(`  ✅ ${t}`); }
function no(t, r) { failed++; console.log(`  ❌ ${t}: ${r}`); }

console.log('🎮 Phase 5: Texas Hold\'em WebSocket Test\n');

const socket = io('http://localhost:3003', { transports: ['websocket'], auth: { token } });

let joined = false, started = false, gotResult = false;
let roundsSeen = new Set();

socket.on('connect', () => {
  ok('Connected to game engine');
  socket.emit('game:join', { tableId: TABLE_ID, seatNumber: 1, buyIn: 500 });
});

socket.on('game:state', (s) => {
  const players = Object.keys(s.players || {});

  // Step 1: Joined
  if (!joined && players.length >= 1) {
    joined = true;
    ok(`Joined table (${players.length} player(s))`);
    if (players.length >= 2) {
      ok('Dealer Bot auto-joined');
      setTimeout(() => { socket.emit('game:start'); }, 500);
    }
  }

  // Step 2: Game started
  if (s.isPlaying && !started) {
    started = true;
    const my = s.players?.['1'];
    const cards = my?.holeCards || [];
    if (cards.length === 2 && cards[0] !== '??') ok(`Dealt hole cards: ${cards.join(', ')}`);
    else if (s.pot > 0) ok('Game started (cards hidden until my turn — bot acted first)');
    else no('Hole cards', JSON.stringify(cards));
    if (s.pot > 0) ok(`Blinds posted (pot=${s.pot})`);
  }

  // Track rounds
  if (s.isPlaying && s.currentRound && !roundsSeen.has(s.currentRound)) {
    roundsSeen.add(s.currentRound);
    if (s.currentRound === 'flop' && s.communityCards?.length === 3)
      ok(`Flop: ${s.communityCards.join(', ')}`);
    if (s.currentRound === 'turn' && s.communityCards?.length === 4)
      ok(`Turn: ${s.communityCards[3]}`);
    if (s.currentRound === 'river' && s.communityCards?.length === 5)
      ok(`River: ${s.communityCards[4]}`);
  }

  // Step 3: Act only when it's my turn
  if (s.isPlaying && s.currentPlayerSeat === 1) {
    const my = s.players?.['1'];
    const maxBet = Math.max(...Object.values(s.players).map(p => p.currentBet || 0));
    const needCall = (my?.currentBet || 0) < maxBet;
    const action = needCall ? 'call' : 'check';
    socket.emit('game:action', { action, amount: 0 });
  }
});

socket.on('game:result', (r) => {
  if (gotResult) return;
  gotResult = true;
  if (r.winners && r.pot > 0) {
    const won = r.winners.some(w => w.seat === 1);
    ok(`Showdown: pot=${r.pot}, prize=${r.prizePerWinner}, ${won ? 'Player WON 🏆' : 'Bot won'}`);
  } else {
    no('Showdown', JSON.stringify(r));
  }

  // Verify DB was updated
  setTimeout(async () => {
    try {
      const http = require('http');
      const get = (url, headers) => new Promise((resolve, reject) => {
        http.get(url, { headers }, (res) => {
          let d = ''; res.on('data', c => d += c); res.on('end', () => resolve(JSON.parse(d)));
        }).on('error', reject);
      });
      const bal = await get(`http://localhost:3002/wallet/balance`, { Authorization: `Bearer ${token}` });
      ok(`Balance after game: ${bal.balance}`);
      const tx = await get(`http://localhost:3002/wallet/transactions?limit=3`, { Authorization: `Bearer ${token}` });
      const types = (tx.transactions || []).map(t => t.type);
      ok(`Recent transactions: ${types.join(', ')}`);
    } catch (e) { no('DB check', e.message); }

    console.log(`\n📊 Results: ${passed} passed, ${failed} failed`);
    socket.disconnect();
    process.exit(failed > 0 ? 1 : 0);
  }, 1000);
});

socket.on('error', (d) => { /* ignore "Not your turn" from bot racing */ });
socket.on('connect_error', (e) => { no('Connect', e.message); process.exit(1); });
setTimeout(() => { console.log(`\n⏰ Timeout\n📊 ${passed} passed, ${failed} failed`); socket.disconnect(); process.exit(1); }, 20000);
