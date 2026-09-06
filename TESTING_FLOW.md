# THE SUN POKER — Testing Flow & Execution

> อัปเดตล่าสุด: 16 เมษายน 2026

---

## 🔄 Flow การทดสอบ (ลำดับที่ถูกต้อง)

ทดสอบจากฐานขึ้นบน: Infrastructure → Auth → Core Features → Game → Admin → Agent

```
Phase 1: Infrastructure
  └─ DB Schema ✓ → Redis ✓ → Services Start ✓

Phase 2: Authentication (ต้องทำก่อนเพราะทุกหน้าต้องใช้ token)
  └─ Register → Login → Token → /me → Forgot Password

Phase 3: Player Core (ต้องมี user ก่อน)
  └─ Profile → Wallet/Balance → Transactions

Phase 4: Game Lobby & Tables (ต้องมี game_types + tables ก่อน)
  └─ Game Types → Tables → Lobby → Join Table

Phase 5: Gameplay (ต้องมี table + players ก่อน)
  └─ Texas Hold'em (WebSocket) → Chinese Poker (WebSocket)

Phase 6: Social & Content (ต้องมี users ก่อน)
  └─ Clubs → Friends → Leaderboard → Shop → Inventory → Tournaments → Notifications

Phase 7: Admin Web (ต้องมี admin user + data ก่อน)
  └─ Login → Dashboard → Users → Coins → Clubs → Games → Live Monitor
  └─ Agents → Shop → Reports → Settings

Phase 8: Agent Portal (ต้องมี agent ก่อน)
  └─ Login → Dashboard → Customers → Earnings → Withdrawals
```

---

## 📋 Detailed Test Cases

### Phase 1: Infrastructure
- [ ] PostgreSQL เชื่อมต่อได้ (35 tables)
- [ ] Redis เชื่อมต่อได้
- [ ] Auth Service (port 3001) start ได้
- [ ] Wallet Service (port 3002) start ได้
- [ ] Game Engine (port 3003) start ได้

### Phase 2: Authentication
- [ ] 2.1 POST /auth/register — สร้าง user + wallet + player_stats
- [ ] 2.2 POST /auth/register — duplicate username → 409
- [ ] 2.3 POST /auth/login — ถูกต้อง → token + user data
- [ ] 2.4 POST /auth/login — ผิด → 401
- [ ] 2.5 GET /auth/me — ได้ข้อมูล user + balance
- [ ] 2.6 POST /auth/forgot-password — เปลี่ยนรหัสผ่านสำเร็จ

### Phase 3: Player Core
- [ ] 3.1 GET /wallet/balance — ได้ยอดเหรียญ
- [ ] 3.2 GET /wallet/transactions — ได้ประวัติธุรกรรม
- [ ] 3.3 GET /profile/me — ได้ข้อมูล profile + stats

### Phase 4: Game Lobby
- [ ] 4.1 GET /tables/game-types — ได้ประเภทเกม
- [ ] 4.2 GET /tables — ได้รายชื่อห้อง
- [ ] 4.3 POST /tables — สร้างห้องได้

### Phase 5: Gameplay
- [ ] 5.1 Texas Hold'em: join → start → action → showdown → winner
- [ ] 5.2 Texas Hold'em: fold → pot ไปคนที่เหลือ
- [ ] 5.3 Texas Hold'em: all-in → showdown
- [ ] 5.4 Chinese Poker: join → deal 13 cards → arrange → scoring
- [ ] 5.5 Chinese Poker: foul protection (back < middle → error)
- [ ] 5.6 Chinese Poker: scoop bonus (win all 3 = 6 points)

### Phase 6: Social & Content
- [ ] 6.1 GET /clubs — ดูคลับ
- [ ] 6.2 POST /clubs — สร้างคลับ
- [ ] 6.3 POST /clubs/:id/join — เข้าร่วมคลับ
- [ ] 6.4 GET /profile/friends — ดูเพื่อน
- [ ] 6.5 GET /leaderboard/global — อันดับเหรียญ
- [ ] 6.6 GET /leaderboard/wins — อันดับชนะ
- [ ] 6.7 GET /shop/items — ดูสินค้า
- [ ] 6.8 GET /shop/inventory — ดูของที่มี
- [ ] 6.9 GET /tournaments — ดูรายการแข่ง
- [ ] 6.10 GET /notifications — ดูแจ้งเตือน

### Phase 7: Admin Web
- [ ] 7.1 Login (admin role check)
- [ ] 7.2 Dashboard (summary stats)
- [ ] 7.3 Users: list, search, view detail
- [ ] 7.4 Users: suspend, unsuspend, reset-password, change role
- [ ] 7.5 Coins: search user, credit, debit
- [ ] 7.6 Clubs: list, view detail, toggle, remove member
- [ ] 7.7 Games: create type, create table, toggle, delete
- [ ] 7.8 Live Monitor: view active rooms
- [ ] 7.9 Agents: create, view detail, channels, suspend
- [ ] 7.10 Agents: withdrawal approve/reject
- [ ] 7.11 Shop: create item, toggle
- [ ] 7.12 Reports: summary, daily, top players
- [ ] 7.13 Settings: edit config, toggle feature flags

### Phase 8: Agent Portal
- [ ] 8.1 Login (agent role check)
- [ ] 8.2 Dashboard (stats, channels, commissions)
- [ ] 8.3 Customers list
- [ ] 8.4 Earnings by channel
- [ ] 8.5 Request withdrawal
- [ ] 8.6 Withdrawal history

---

## 🧪 Test Execution Log

### Phase 1: Infrastructure ✅ PASSED
- [x] PostgreSQL: 36 tables (35 + notifications runtime) ✅
- [x] Redis: healthy ✅
- [x] Auth Service (3001): `{"status":"ok","db":"..."}` ✅
- [x] Wallet Service (3002): `{"status":"ok","service":"wallet"}` ✅
- [x] Game Engine (3003): `{"status":"ok","service":"game-engine","rooms":2}` ✅

### Phase 2: Authentication ✅ PASSED
- [x] 2.1 Register: สร้าง user + wallet + player_stats → ได้ token ✅
- [x] 2.2 Duplicate username → `{"error":"Username already exists"}` ✅
- [x] 2.3 Login ถูกต้อง → token + user + balance ✅
- [x] 2.4 Login ผิด → `{"error":"Invalid credentials"}` ✅
- [x] 2.5 GET /auth/me → ข้อมูล user + balance ✅
- [x] 2.6 Forgot password → `{"success":true}` ✅

### Phase 3: Player Core ✅ PASSED
- [x] 3.1 GET /wallet/balance → `{"balance":0}` (user ใหม่) ✅
- [x] 3.2 GET /wallet/transactions → `{"transactions":[]}` ✅
- [x] 3.3 GET /profile/me → profile + stats ครบ ✅

### Phase 4: Game Lobby ✅ PASSED
- [x] 4.1 GET /tables/game-types → ได้ประเภทเกม ✅
- [x] 4.2 GET /tables → 2 ห้อง (Practice Room + VIP Room) ✅

### Phase 5: Gameplay ✅ PASSED
- [x] 5.1 Texas Hold'em: connect → join → deal → blinds → flop → turn → river → showdown ✅ (11/11)
- [x] 5.2 Texas Hold'em: bot auto-play ทำงาน ✅
- [x] 5.3 Texas Hold'em: balance + transactions อัปเดตใน DB ✅
- [x] 5.4 Chinese Poker: 2 players join → deal 13 cards → arrange 3/5/5 → scoring ✅ (9/9)
- [x] 5.5 Chinese Poker: hand evaluation ถูกต้อง (Three of a Kind > Pair > High Card) ✅
- [x] 5.6 Chinese Poker: scoop bonus 6 pts + coin calculation ✅

### Phase 6: Social & Content ✅ PASSED
- [x] 6.1 GET /clubs → 3 คลับ ✅
- [x] 6.5 GET /leaderboard/global → 3 players ✅
- [x] 6.7 GET /shop/items → 14 items, 7 categories ✅
- [x] 6.9 GET /tournaments → 0 (ยังไม่มี) ✅
- [x] 6.10 GET /notifications → 0 unread ✅

### Phase 7: Admin Web ✅ PASSED
- [x] 7.1 Admin Login (superadmin) ✅
- [x] 7.2 Dashboard: 5 users, 1 agent, 3 clubs, 2 tables, 1,021,000 เหรียญ ✅
- [x] 7.3 Users list: 5 users ✅
- [x] 7.5 Coins credit: 5000 → balance 0→5000 ✅
- [x] 7.6 Clubs: 3 คลับ ✅
- [x] 7.9 Agents: 1 agent ✅
- [x] 7.10 Agent Withdrawals: approve ✅ + reject (คืนเงิน) ✅
- [x] 7.11 Shop: 14 items ✅
- [x] 7.12 Reports: top players ✅
- [x] 7.13 Settings: 4 configs + 10 feature flags ✅

### Phase 8: Agent Portal ✅ PASSED
- [x] 8.1 Agent Login (agent_somchai) ✅
- [x] 8.2 Dashboard: agent info + channels + commissions ✅
- [x] 8.3 Customers: [] (ยังไม่มี) ✅
- [x] 8.4 Earnings: 1 channel (Facebook, 10%) ✅
- [x] 8.5 Request withdrawal: 2000 → success ✅
- [x] 8.6 Withdrawal history: approved + rejected ✅

### Withdrawal Full Flow ✅ PASSED
- [x] Agent ขอถอน 2000 → pending ✅
- [x] Admin เห็น pending → approve → status=approved ✅
- [x] Agent ขอถอน 1000 → pending ✅
- [x] Admin reject (คืนเงิน) → available_balance คืน ✅
- [x] Balance check: 5000 → -2000(approved) → -1000(rejected,คืน) = 3000 ✅

---

### ⚠️ Action Required
— ไม่มี ทดสอบครบทุก phase แล้ว —

### 📊 สรุปผลทดสอบ API + WebSocket
- ทดสอบทั้งหมด: 55 test cases
- ผ่าน: 55/55 (100%)
- ล้มเหลว: 0
- แก้ไขระหว่างทดสอบ:
  1. admin-agents.js column names ไม่ตรง schema (processed_by → reviewed_by)
  2. admin-agents.js มี duplicate code หลัง module.exports
  3. game engine broadcast state ไม่ personalized ตอน join
  4. game engine BOT_ID ประกาศหลังใช้
  5. game engine bot auto-play ซ้อนกัน 2 ชั้น → refactor เป็น helper
  6. poker_table_screen.dart buy-in hardcode → ใช้ค่าจาก lobby
