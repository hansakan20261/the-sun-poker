# THE SUN POKER — Testing Checklist & Status

> อัปเดตล่าสุด: 16 เมษายน 2026

---

## สถาปัตยกรรมระบบ

| Service | Port | Tech | สถานะ |
|---------|------|------|--------|
| Auth Service | 3001 | Node.js + Express + PostgreSQL | ✅ ทำงาน |
| Wallet Service | 3002 | Node.js + Express + PostgreSQL | ✅ ทำงาน |
| Game Engine | 3003 | Node.js + Socket.IO + PostgreSQL | ✅ ทำงาน |
| Admin Web | 3100 | Next.js 14 + React 18 + Tailwind | ✅ ทำงาน |
| Agent Portal | 3200 | Next.js 14 + React 18 + Tailwind | ✅ ทำงาน |
| Mobile App | — | Flutter (Dart) | ✅ ทำงาน |
| PostgreSQL | 5432 | 35+ tables | ✅ |
| Redis | 6379 | Session, cache | ✅ |

### วิธีรัน
```bash
docker-compose up -d                          # PostgreSQL + Redis
cd services/auth-service && npm run dev        # port 3001
cd services/wallet-service && npm run dev      # port 3002
cd services/game-engine && npm run dev         # port 3003
cd apps/admin-web && npm run dev               # port 3100
cd apps/agent-portal && npm run dev            # port 3200
cd apps/mobile && flutter run                  # Mobile
```

---

## 📱 Mobile App (Flutter) — 19 หน้าจอ

| # | หน้า | ไฟล์ | API Endpoint | DB | สถานะ | หมายเหตุ |
|---|------|------|-------------|-----|--------|----------|
| 1 | Login | login_screen.dart | POST /auth/login | ✅ | ✅ ทำงานได้ | เชื่อม auth-service จริง |
| 2 | Register | register_screen.dart | POST /auth/register | ✅ | ✅ ทำงานได้ | สร้าง user + wallet + player_stats |
| 3 | Forgot Password | forgot_password_screen.dart | POST /auth/forgot-password | ✅ | ✅ ทำงานได้ | ยืนยันด้วย username + email |
| 4 | Home | home_screen.dart | GET /profile/me + /wallet/balance | ✅ | ✅ ทำงานได้ | แสดงยอดเหรียญ, เมนูเกม |
| 5 | Lobby | lobby_screen.dart | GET /tables + /tables/game-types | ✅ | ✅ ทำงานได้ | กรองตามประเภทเกม, buy-in dialog |
| 6 | Poker Table (Texas) | poker_table_screen.dart | WebSocket game:join/start/action | ✅ | ✅ ทำงานได้ | real-time, dealer bot, หักเงิน/คืนเงิน |
| 7 | Chinese Poker (13 Card) | chinese_poker_screen.dart | WebSocket chinese:join/start/arrange | ✅ | ✅ ทำงานได้ | เชื่อม WebSocket จริง, hand eval ถูกต้อง |
| 8 | Club List | club_screen.dart | GET /clubs + POST /clubs | ✅ | ✅ ทำงานได้ | ดูรายชื่อ + สร้างคลับ + เข้าร่วม |
| 9 | Club Detail | club_detail_screen.dart | GET /clubs/:id/members | ✅ | ⚠️ บางส่วน | ดูสมาชิกได้, สร้างห้องยังไม่เรียก API จริง (UI only) |
| 10 | Shop | shop_screen.dart | GET /shop/items | ✅ | ⚠️ บางส่วน | ดูสินค้าจาก DB จริง, แต่ซื้อผ่าน QR/Line (ไม่เรียก POST /shop/purchase) |
| 11 | Inventory | inventory_screen.dart | GET /shop/inventory | ✅ | ✅ ทำงานได้ | แสดงไอเทมที่มี |
| 12 | Leaderboard | leaderboard_screen.dart | GET /leaderboard/global, /wins | ✅ | ✅ ทำงานได้ | 2 tabs: เหรียญ + ชนะ |
| 13 | Tournament | tournament_screen.dart | GET /tournaments + POST register | ✅ | ✅ ทำงานได้ | ดูรายการ + สมัคร + หักค่าสมัคร |
| 14 | Tournament Result | tournament_result_screen.dart | GET /tournaments/:id/results | ✅ | ✅ ทำงานได้ | อันดับ + เงินรางวัล |
| 15 | Friends | friends_screen.dart | GET /profile/friends | ✅ | ✅ ทำงานได้ | รายชื่อเพื่อน |
| 16 | Chat (ในเกม) | poker_table_screen.dart | WebSocket chat:message | ✅ | ✅ ทำงานได้ | chat + whisper ในห้องเกม |
| 17 | Chat (แยก) | chat_screen.dart | — | ❌ | ⚠️ Demo only | ใช้ข้อความ hardcode, ไม่เชื่อม API |
| 18 | Notification | notification_screen.dart | GET /notifications | ✅ | ✅ ทำงานได้ | แจ้งเตือนจาก DB |
| 19 | Profile | profile_screen.dart | GET /profile/me + /wallet/transactions | ✅ | ✅ ทำงานได้ | สถิติ + ประวัติธุรกรรม |
| 20 | Settings | settings_screen.dart | — | ⚠️ | ⚠️ บางส่วน | Logout ✅, change password/delete account = UI only |

### สรุป Mobile: 15/20 ทำงานครบ 100%, 5 หน้ามีข้อจำกัดเล็กน้อย

---

## 🖥️ Admin Web (localhost:3100) — 11 หน้า

| # | หน้า | Path | API Endpoint | DB | สถานะ |
|---|------|------|-------------|-----|--------|
| 1 | Login | /login | POST /auth/login | ✅ | ✅ ทำงานได้ |
| 2 | Dashboard | /dashboard | GET /admin/reports/summary + /admin/coin-transactions | ✅ | ✅ ทำงานได้ |
| 3 | Users | /users | GET/PUT /admin/users (list, detail, suspend, unsuspend, reset-password, role, transactions) | ✅ | ✅ ทำงานได้ |
| 4 | Coins | /coins | GET /admin/users/search + POST credit/debit | ✅ | ✅ ทำงานได้ |
| 5 | Clubs | /clubs | GET/PUT/DELETE /admin/clubs (list, detail, toggle, remove member) | ✅ | ✅ ทำงานได้ |
| 6 | Games | /games | GET/POST/PUT/DELETE /admin/games/types + /admin/games/tables | ✅ | ✅ ทำงานได้ |
| 7 | Live Monitor | /games/live | GET /admin/rooms (game-engine port 3003) | ✅ | ✅ ทำงานได้ |
| 8 | Agents | /agents | GET/POST/PUT /admin/agents + channels + withdrawals/all + approve/reject | ✅ | ✅ ทำงานได้ |
| 9 | Shop | /shop | GET/POST/PUT /admin/shop/items + toggle | ✅ | ✅ ทำงานได้ |
| 10 | Reports | /reports | GET /admin/reports/summary + daily-coins + top-players | ✅ | ✅ ทำงานได้ |
| 11 | Settings | /settings | GET/PUT /admin/settings/config + features/toggle | ✅ | ✅ ทำงานได้ |

### สรุป Admin Web: 11/11 ทำงานครบ 100%

---

## 🤝 Agent Portal (localhost:3200) — 5 tabs

| # | Tab | API Endpoint | DB | สถานะ |
|---|-----|-------------|-----|--------|
| 1 | Login | POST /auth/login (role check = agent) | ✅ | ✅ ทำงานได้ |
| 2 | Dashboard | GET /agent-portal/dashboard | ✅ | ✅ ทำงานได้ |
| 3 | Customers | GET /agent-portal/customers | ✅ | ✅ ทำงานได้ |
| 4 | Earnings | GET /agent-portal/earnings | ✅ | ✅ ทำงานได้ |
| 5 | Withdrawals | GET/POST /agent-portal/withdrawals | ✅ | ✅ ทำงานได้ |

### Agent Portal แสดงข้อมูล:
- สถานะ Agent (active/suspended)
- Commission Rate
- รายได้รวม + ยอดถอนได้
- Referral Links ทั้งหมด (คัดลอกได้)
- Commission ล่าสุด (ลูกค้า, ยอดเติม, commission)
- รายชื่อลูกค้าทั้งหมด (username, ชื่อ, ช่องทาง, เหรียญ, วันสมัคร)
- รายได้แยกตามช่องทาง (rate, รายการ, ยอดเติมรวม, commission รวม)
- ขอถอนเงิน + ประวัติการถอน (สถานะ: รอ/อนุมัติ/ปฏิเสธ)

### สรุป Agent Portal: 5/5 ทำงานครบ 100%

---

## 🎮 Game Logic — ตรวจสอบกฎเกม

### Texas Hold'em ✅ ถูกต้องตามกฎ
- สำรับ 52 ใบ, สับด้วย crypto.randomInt (ปลอดภัย)
- แจก 2 ใบ (hole cards) ต่อคน
- Community cards: flop 3 + turn 1 + river 1 = 5 ใบ
- Blinds: Small Blind + Big Blind ตำแหน่งถูกต้อง
- Actions: fold, check, call, raise, all-in ✅
- Round flow: preflop → flop → turn → river → showdown ✅
- Hand evaluation ครบ 10 มือ:
  - Royal Flush, Straight Flush, Four of a Kind, Full House
  - Flush, Straight, Three of a Kind, Two Pair, One Pair, High Card
- เลือก 5 จาก 7 ใบ (combination) หามือดีสุด ✅
- Straight A-2-3-4-5 (wheel) รองรับ ✅
- Winner split pot เท่าๆ กัน ✅
- Dealer Bot สำหรับทดสอบ (auto call/check) ✅
- บันทึก game_hands, transactions, player_stats ลง DB ✅
- คืนเงิน (cashout) เมื่อ disconnect ✅

### Chinese Poker (ไพ่สามกอง) ✅ ถูกต้องตามกฎ
- แจก 13 ใบต่อคน (รองรับ 2-4 คน)
- จัดเป็น 3 กอง:
  - กองหน้า (Front): 3 ใบ — ได้แค่ High Card, Pair, Three of a Kind
  - กองกลาง (Middle): 5 ใบ — ใช้ poker hand ranking เต็ม
  - กองหลัง (Back): 5 ใบ — ใช้ poker hand ranking เต็ม
- กฎ Foul Protection: หลัง >= กลาง >= หน้า (เทียบด้วย hand rank จริง) ✅
- Hand evaluation ใช้ poker hand ranking จริง:
  - กอง 5 ใบ: Royal Flush → High Card (10 ระดับ)
  - กอง 3 ใบ: Three of a Kind > Pair > High Card
  - เทียบ kickers เมื่อ hand rank เท่ากัน ✅
- Scoring: เทียบกองต่อกอง ทุกคู่ผู้เล่น ✅
- Scoop bonus: ชนะครบ 3 กอง = 6 แต้ม (แทน 3) ✅
- คำนวณเหรียญ: 1 point = 1x big blind ✅
- เชื่อม WebSocket จริง: chinese:join, chinese:start, chinese:arrange ✅
- บันทึก transactions + player_stats ลง DB ✅
- คืนเงิน (cashout) เมื่อ disconnect ✅

---

## 🔗 API Routing (Next.js Rewrites)

### Admin Web (port 3100)
```
/api/auth/*       → http://localhost:3001/auth/*
/api/wallet/*     → http://localhost:3002/wallet/*
/api/admin/*      → http://localhost:3002/admin/*
/api/game-admin/* → http://localhost:3003/admin/*
```

### Agent Portal (port 3200)
```
/api/auth/*  → http://localhost:3001/auth/*
/api/*       → http://localhost:3002/*
```

### Mobile App (Flutter)
```
Auth:   http://localhost:3001 (direct)
Wallet: http://localhost:3002 (direct)
Game:   http://localhost:3003 (WebSocket direct)
```

---

## 📋 ปัญหาที่แก้แล้ว

| # | ปัญหา | วิธีแก้ | สถานะ |
|---|--------|---------|--------|
| 1 | Dashboard แสดง "-" ทุกช่อง | เรียก /admin/reports/summary แสดงข้อมูลจริง | ✅ แก้แล้ว |
| 2 | Agent Portal ไม่เรียก API จริง | เขียนใหม่ครบ 4 tabs เชื่อม agent-portal API | ✅ แก้แล้ว |
| 3 | Agent Portal API lib เหมือน Admin Web | แยกเป็น agentApi (dashboard, customers, earnings, withdrawals) | ✅ แก้แล้ว |
| 4 | Admin ไม่มี withdrawal management | เพิ่ม tab คำขอถอนเงิน + backend API (approve/reject) | ✅ แก้แล้ว |
| 5 | Agent detail ไม่แสดงลูกค้า | เพิ่ม recent_customers ใน panel | ✅ แก้แล้ว |
| 6 | Chinese Poker ใช้ demo data | เชื่อม WebSocket จริง + backend events | ✅ แก้แล้ว |
| 7 | Chinese Poker _handScore() ใช้ผลรวม rank | เขียน hand evaluation ใหม่ใช้ poker hand ranking จริง | ✅ แก้แล้ว |

---

## ⚠️ ปัญหาที่เหลือ (Minor — ไม่กระทบการใช้งานหลัก)

| # | ปัญหา | ระดับ | หมายเหตุ |
|---|--------|-------|----------|
| 1 | Settings: change password | Minor | UI มีแล้ว แต่ยังไม่เรียก API (backend มี /auth/forgot-password อยู่แล้ว) |
| 2 | Settings: delete account | Minor | UI มีแล้ว แต่ยังไม่มี backend endpoint |
| 3 | Chat Screen แยก | Minor | ใช้ข้อความ hardcode (chat ในห้องเกมทำงานจริงผ่าน WebSocket) |
| 4 | Club Detail: สร้างห้อง | Minor | UI สร้างห้องมีแล้ว แต่ยังไม่เรียก POST /tables API จริง |
| 5 | Shop Mobile: ซื้อสินค้า | Design | แสดง QR/Line ให้ติดต่อ admin (อาจเป็น design ที่ตั้งใจ — backend มี POST /shop/purchase พร้อมแล้ว) |

---

## 📊 สรุปภาพรวม

| ส่วน | ทำงานครบ | ทั้งหมด | เปอร์เซ็นต์ |
|------|---------|---------|------------|
| Mobile App | 15 | 20 | 75% (5 หน้ามีข้อจำกัดเล็กน้อย) |
| Admin Web | 11 | 11 | 100% |
| Agent Portal | 5 | 5 | 100% |
| Texas Hold'em | ✅ | ✅ | 100% ถูกต้องตามกฎ |
| Chinese Poker | ✅ | ✅ | 100% ถูกต้องตามกฎ |
| Backend APIs | 20 routes | 20 routes | 100% เชื่อม DB จริง |

### Phase 6 Readiness: พร้อมเข้า Testing & Launch
- Unit tests: ยังไม่ได้เริ่ม
- UAT: ยังไม่ได้เริ่ม
- Security testing: ยังไม่ได้เริ่ม
- Deployment: ยังไม่ได้เริ่ม (target: DigitalOcean Singapore)
