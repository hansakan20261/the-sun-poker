# Config-Driven System Refactor Tasks

## เป้าหมาย

ปรับระบบ THE SUN POKER ให้ค่าที่เป็นนโยบายเกม ธุรกิจ การทำงานของระบบ และพฤติกรรมที่ต้องเปลี่ยนระหว่าง Runtime ถูกควบคุมจากระบบหลังบ้าน โดยไม่ต้องแก้โค้ดหรือ Deploy ใหม่ และไม่มี fallback แบบ hardcode กระจายตาม Service หรือ Client

ผลลัพธ์ที่ต้องได้:

1. Admin ตั้งค่าได้ผ่านฟอร์มที่มีชนิดข้อมูลและ Validation ชัดเจน
2. Backend มีแหล่ง Config กลางเพียงชุดเดียวและคำนวณ Effective Config ด้วยกฎเดียวกัน
3. ห้องใหม่บันทึก Config Snapshot ที่ใช้จริง
4. Game Engine ใช้ค่าจาก Snapshot/Effective Config จริงทุกจุด
5. การแก้ Config ระบุชัดว่ามีผลทันที, มือถัดไป, ห้องใหม่ หรือหลัง Restart
6. ทุกการเปลี่ยนแปลงมี Audit, Version, Preview และ Rollback
7. Automated tests ยืนยันว่าการเปลี่ยนค่าจาก Admin เปลี่ยนพฤติกรรม Runtime จริง

---

## หลักการและขอบเขต

คำว่า "ห้าม hardcode" ในแผนนี้หมายถึงค่าที่เป็น Business Policy หรือ Operational Behavior เช่น เวลาเล่น จำนวนผู้เล่น Rake Buy-in Auto-start Cleanup และ Feature behavior

ค่าต่อไปนี้ต้องไม่เปิดให้แก้จาก Admin:

- Secret, Password, JWT signing key, Database credential และ API key: เก็บใน Environment/Secret Manager เท่านั้น
- Protocol invariant และกฎที่ทำให้เกมไม่ถูกต้อง เช่น จำนวนไพ่ในสำรับหรือจำนวนไพ่ Texas Hold'em
- Database constraint และ Security invariant ขั้นต่ำที่ห้ามลดผ่าน Admin
- UI spacing, font size และค่าตกแต่งระดับ implementation ที่ไม่ใช่ Remote UI configuration

ทุก Config ต้องมี Server-side bounds แม้ Admin จะเป็น Super Admin เพื่อป้องกันค่าที่ทำให้เกมหรือระบบล่ม

---

## สถานะงาน

- `[ ]` ยังไม่เริ่ม
- `[-]` กำลังทำ
- `[x]` เสร็จและผ่าน Acceptance Criteria
- `[!]` ติดปัญหา/ต้องตัดสินใจ

---

## P0: แก้จุดที่ Config มีอยู่แต่ Runtime ไม่ใช้

### CFG-P0-001: ใช้ `turn_time_sec` จริงใน Texas Hold'em

สถานะ: เสร็จแล้ว — 6/6 รายการ

- [x] ลบการพึ่งพา `TURN_TIME_SEC = 30` ใน `services/game-engine/src/index.js`
- [x] ให้ `startTurnTimer` ใช้ `room.config.turnTimeSec`
- [x] Validate ว่าค่าเป็นจำนวนเต็มบวกและอยู่ในช่วงที่ Config Registry อนุญาต
- [x] ส่ง `turnTotalSeconds`, `turnStartedAt` และ `turnDeadlineAt` ใน game state โดยยึดเวลา Server
- [x] เมื่อเปลี่ยนค่าห้องระหว่างเล่น ให้ใช้ค่าใหม่ตั้งแต่มือถัดไป ไม่เปลี่ยน timer กลาง Turn
- [x] เพิ่ม unit test สำหรับ 10, 30 และ 60 วินาทีโดยใช้ fake timers

ผลตรวจล่าสุด:

- Game Engine tests ผ่าน 22/22
- ตรวจ syntax ของ Game Engine ผ่าน
- Flutter Web production build ผ่าน
- Flutter countdown ใช้เวลาคงเหลือและ deadline จาก Server และไม่ส่ง auto-fold ซ้ำกับ Server
- ป้องกัน `game:start`/`game:action` ของห้อง Tournament ไม่ให้เข้าทาง Cash Game timer
- `flutter analyze` ยังรายงานปัญหาเดิมใน `poker_table_screen.dart`; ไม่พบ compile error ใหม่จากงานนี้

Acceptance Criteria:

- ห้องที่ตั้ง 10 วินาที auto-check/auto-fold ตามเวลา 10 วินาที
- ห้องที่ตั้ง 60 วินาทีไม่ timeout ที่ 30 วินาที
- Client แสดงเวลาตรงกับ deadline จาก Server

### CFG-P0-002: ใช้ `turn_time_sec` จริงใน Chinese Poker

สถานะ: เสร็จแล้ว — 4/4 รายการ

- [x] ส่ง `turnTimeSec` ที่ผ่าน Config Registry เข้า `ChinesePokerRoom` ทั้ง join และ spectate paths
- [x] ตรวจทุก path ที่สร้าง Chinese room รวมถึง Practice/Demo; ปัจจุบันยังไม่มี Chinese Tournament room factory
- [x] ใช้ Server deadline เป็นแหล่งจริงสำหรับเวลาจัดไพ่
- [x] เพิ่ม tests สำหรับ arrange timeout และ force-foul ตามค่าห้อง

ผลตรวจล่าสุด:

- ทดสอบเวลา 10, 30 และ 60 วินาทีผ่าน
- ทดสอบ timeout callback และ force-foul ผ่าน
- Join/Spectate ใช้ resolver และขอบเขต Config ชุดเดียวกัน
- Game Engine tests รวมผ่าน 22/22
- Flutter Web production build ผ่าน

Acceptance Criteria:

- ห้องที่ตั้ง 60 วินาทีรายงานและ timeout ที่ 60 วินาที
- Join และ Spectate เห็นเวลาคงเหลือชุดเดียวกัน

### CFG-P0-003: ใช้ `auto_start_at` และ Auto-start delay จริง

สถานะ: เสร็จแล้ว — 7/7 รายการ

- [x] เพิ่ม `autoStartAt` และ `autoStartDelaySec` ใน Room Runtime Config
- [x] โหลด `auto_start_at` และ `auto_start_delay_sec` จาก `game_tables` เข้า GameRoom/ChinesePokerRoom
- [x] แทนที่เงื่อนไข `players.size >= 2` ที่เป็น policy ด้วยค่าจากห้อง
- [x] แทนที่ delay 500ms/2000ms ที่เป็น policy ด้วย Config
- [x] แยกค่า Practice/Demo ออกเป็นค่าต่อห้อง และกัน Tournament ออกจาก Cash Game handlers
- [x] ยกเลิก timer เก่าเมื่อจำนวนผู้เล่นลดต่ำกว่า threshold
- [x] Broadcast `autoStartAt`, `autoStartStartedAt`, `autoStartDeadlineAt` และ `autoStartRemainingSeconds`

ผลตรวจล่าสุด:

- เพิ่ม migration `017_auto_start_config.sql`; ต้อง apply ก่อน deploy Service รุ่นนี้
- Admin โหลดค่าเริ่มต้นจาก Backend Config และกำหนด threshold/delay ต่อห้องได้
- Player/Admin/Practice room creation บันทึก Auto-start config ลง `game_tables`
- Game Engine และ Config Registry tests ผ่าน 29/29
- Wallet Service tests ผ่าน 8/8
- Admin production build ผ่าน
- Flutter Web production build ผ่าน
- Docker Compose validation ผ่าน

Acceptance Criteria:

- ตั้ง `auto_start_at = 5` แล้วเกมไม่เริ่มเมื่อมี 2-4 คน
- เมื่อครบ 5 คน เกมเริ่มหลัง delay ที่ตั้งไว้
- ผู้เล่นออกก่อน countdown จบแล้วระบบยกเลิกการเริ่มได้ถูกต้อง

### CFG-P0-004: เชื่อม `game_runtime` เข้ากับ Runtime จริง

สถานะ: เสร็จแล้ว — 8/8 รายการ

- [x] สร้าง typed config สำหรับ `game_runtime`
- [x] เชื่อม `auto_deal_delay_sec` กับ Cash/Practice/Tournament
- [x] เชื่อม `result_display_sec` กับ Game Engine และ Flutter
- [x] เชื่อม `socket_reconnect_delay_sec`
- [x] เชื่อม `socket_reconnect_attempts` ทั้ง Texas/Chinese
- [x] เชื่อม `room_access_token_minutes`
- [x] เพิ่ม `seat_reservation_ttl_sec`, `disconnect_grace_sec`, `idle_timeout_sec`
- [x] ลบ Runtime delay/TTL เดิมที่ซ้ำใน Game Engine และ Flutter

ผลตรวจล่าสุด:

- เพิ่ม Public/Typed Admin API สำหรับ `game_runtime`
- Game Engine โหลด Config จากฐานข้อมูลก่อน schedule
- Flutter โหลด Runtime Config ก่อนเชื่อม Socket
- เพิ่ม Seat reservation expiry, reconnect grace และ idle disconnect
- ไม่พบ hardcode เดิมที่กำหนดไว้ใน P0-004 จาก source scan

Acceptance Criteria:

- Search ไม่พบ Runtime delay เดิมที่เป็น magic number
- การเปลี่ยนค่าจาก Admin ส่งผลตาม `apply_mode` ที่กำหนด

### CFG-P0-005: ทำให้เวลาเล่นขั้นต่ำออกจากห้องเป็น Config

สถานะ: เสร็จแล้ว — 5/5 รายการ

- [x] เพิ่ม `minimum_play_minutes` ระดับ System/Game Type/Room
- [x] ส่งค่าเข้า `GameRoom` และ `ChinesePokerRoom`
- [x] กำหนด Tournament/Practice ผ่าน `game_runtime` policy ไม่ใช่ assignment กระจาย
- [x] แสดงค่านี้ในหน้าสร้างห้อง รายการห้อง และ game state
- [x] เพิ่ม test ขอบเขต 0, 1 และค่าสูงสุดที่อนุญาต

ผลตรวจล่าสุด:

- Resolver ใช้ลำดับ Room → Game Type → System default
- Flutter ใช้ `minimumPlayMinutes` จาก Server แทน 15/30 นาทีตายตัว
- เพิ่ม tests สำหรับ Texas, Chinese และ Config bounds

### CFG-P0-006: แก้ Auto-cleanup ให้ใช้ Config ครบทุก Field

สถานะ: เสร็จแล้ว — 6/6 รายการ

- [x] ใช้ `enabled`, `delete_empty_after_minutes`, `delete_all_player_rooms_after_hours`, `only_player_created`
- [x] แยกความหมาย "ปิดห้องทุกห้องที่หมดอายุ" กับ "ปิดเฉพาะห้องว่าง" ให้ชัดเจน
- [x] เพิ่ม `cleanup_worker_interval_sec` และให้ Scheduler reload ค่าได้
- [x] ป้องกันการปิดห้องที่กำลังเล่น เว้นแต่ policy อนุญาตโดยชัดเจน
- [x] บันทึกเหตุผลและ Config version ลง Audit log ทุกครั้งที่ cleanup
- [x] เพิ่ม dry-run API เพื่อให้ Admin Preview รายการห้องก่อนกด Run now

ผลตรวจล่าสุด:

- Worker ใช้ dynamic one-shot scheduler และ PostgreSQL advisory lock
- Game Engine sync `table_players` เพื่อให้ Cleanup เห็น occupancy จริง
- Admin ตั้ง policy ครบทุก field ดู Preview และสั่ง Cleanup ได้
- Cleanup tests ครอบคลุม validation, dry-run และ audit

---

## P1: สร้าง Config Platform กลาง

สถานะ implementation ล่าสุด: P1 สมบูรณ์ทั้งโค้ด — Central Config Platform, Config Domains และ Game Engine enforcement ทำงานครบแล้ว ยังเหลือเฉพาะ production/staging verification กับ PostgreSQL จริง ส่วน Admin typed-form/template/history UI เป็น P2

ผลตรวจล่าสุด:

- Wallet Service tests: 25/25 ผ่าน
- Game Engine tests: 36/36 ผ่าน
- Auth Service tests: 2/2 ผ่าน
- Node syntax checks สำหรับไฟล์ที่แก้: ผ่าน
- `node scripts/check-config-hardcodes.js`: ผ่าน และ generated inventory มี 16 categories
- `database/migrations/019_config_platform.sql` และ `database/init/019_config_platform.sql`: identical
- Admin Web production build: ผ่าน
- Flutter Web production build: ผ่าน
- `flutter analyze`: ไม่พบ compile error ใหม่ แต่ยังมี warning/info เดิมรวม 1,389 รายการ
- เตรียม Railway deployment config/Docker context และ database init image แล้วใน `docs/railway-deploy.md`
- ยังไม่ได้ deploy หรือทำ real PostgreSQL/staging/API integration verification; ต้อง apply migration กับฐานข้อมูลจริงก่อนปิด P1 เป็น production-complete

### CFG-P1-001: จัดทำ Config Inventory

- [x] Scan `services/`, `apps/mobile/lib/`, `apps/admin-web/` และ `apps/agent-portal/`
- [x] บันทึก magic numbers, default values, timeout, interval, limit, percentage และ feature switches
- [x] จัดแต่ละค่าเป็นหนึ่งในกลุ่มต่อไปนี้:
  - `admin_runtime_config`
  - `environment_config`
  - `security_invariant`
  - `protocol_invariant`
  - `client_presentation_config`
- [x] ระบุ Owner, Consumer, Scope, Data type, Unit, Bounds และ Apply mode ทุก key
- [x] เพิ่ม allowlist/check script ป้องกัน Runtime hardcode ใหม่ พร้อมใช้ใน CI ผ่าน `.github/workflows/config-hardcodes.yml`

Deliverable ที่สร้างแล้ว:

- `config/config-definitions.js` — Admin-editable registry พร้อม metadata
- `config/non-admin-config-inventory.json` — environment/security/protocol/client-presentation inventory
- `config/config-inventory.json` — generated catalog จาก scanner
- `scripts/check-config-hardcodes.js` — hardcode scanner + allowlist enforcement

Deliverable:

- Config catalog ที่ Machine-readable และใช้ร่วมกับ Backend validation/Admin form ได้

### CFG-P1-002: สร้าง Typed Config Registry

- [x] สร้าง Registry กลางที่ระบุ metadata ของทุก key ปัจจุบัน 16 categories
- [x] Metadata ขั้นต่ำต้องมี:
  - key และ category
  - type และ unit
  - default seed value
  - min/max หรือ enum
  - scope ที่รองรับ
  - apply mode
  - sensitive flag
  - description ภาษาไทย/อังกฤษ
- [x] ห้าม Route รับ JSON ใด ๆ โดยไม่มี schema validation
- [x] เปลี่ยน `DEFAULT_CONFIGS` ให้เป็น bootstrap seed ที่ versioned ไม่ใช่ fallback เงียบ
- [x] หาก Config สำคัญหายหรือผิด schema ให้ Service fail readiness พร้อมข้อความชัดเจน
- [x] แยก `getRequiredConfig` และ `getOptionalConfig`

### CFG-P1-003: ออกแบบลำดับชั้น Config

กำหนด precedence เดียวทั้งระบบ:

1. Security/Protocol invariant
2. Per-room runtime override ที่ Admin อนุมัติ
3. Room snapshot ตอนสร้างห้อง
4. Room template
5. Game-type config
6. System default
7. Versioned bootstrap seed

Tasks:

- [x] สร้าง `ConfigResolver` ที่คืนทั้งค่าและ `source`
- [x] เพิ่ม API สำหรับดู Effective Config ก่อนสร้างห้อง
- [x] เพิ่ม conflict validation เช่น `min_buy_in <= max_buy_in`
- [x] เพิ่ม cross-field validation เช่น `auto_start_at <= max_players`
- [x] ห้าม Client เป็นผู้ resolve defaults เอง หน้าหลักทั้งหมดใช้ server/effective config แล้ว

### CFG-P1-004: Database schema และ Versioning

- [x] เพิ่ม revision/version ให้ `system_config`
- [x] เพิ่ม `config_definitions` หรือ Machine-readable registry deployment table
- [x] เพิ่ม `config_history` แบบ append-only
- [x] เพิ่ม `room_templates`
- [x] เพิ่ม `game_type_configs`
- [x] เพิ่ม `config_snapshot JSONB`, `config_version` และ `config_hash` ใน `game_tables`
- [x] เพิ่ม `runtime_overrides` พร้อม `effective_at`, `expires_at`, `apply_mode`
- [x] บันทึก `updated_by`, เหตุผล, before/after และ correlation ID
- [x] สร้าง migration แบบ idempotent และ rollback plan
- [x] Backfill ห้องเดิมจากค่าคอลัมน์เดิมก่อนเปิดใช้ snapshot

Acceptance Criteria:

- ห้องทุกห้องระบุได้ว่าใช้ Config version ใด
- ตรวจย้อนหลังได้ว่าเกมหนึ่งมือใช้ค่าอะไร
- Rollback Config ไม่ลบ History เดิม

### CFG-P1-005: Config API แบบปลอดภัย

- [x] `GET /admin/config/definitions`
- [x] `GET /admin/config/values?scope=...`
- [x] `GET /admin/config/effective?gameTypeId=...&templateId=...&tableId=...`
- [x] `POST /admin/config/validate`
- [x] `PUT /admin/config/values/:key` พร้อม optimistic locking
- [x] `POST /admin/config/publish`
- [x] `POST /admin/config/rollback/:revision`
- [x] `GET /admin/config/history`
- [x] `POST /admin/config/apply-existing` พร้อม dry-run
- [x] จำกัด publish/rollback ให้ Super Admin หรือ permission เฉพาะ
- [x] ใส่ rate limit และ audit ทุก write operation

Acceptance Criteria:

- Update ด้วย revision เก่าถูกปฏิเสธด้วย conflict response
- Invalid type/range/cross-field ถูกปฏิเสธก่อนเขียน DB
- API ไม่คืน Secret หรือ Environment-only config

### CFG-P1-006: Config propagation และ Cache invalidation

- [x] เลือกกลไกแจ้งการเปลี่ยน Config: PostgreSQL LISTEN/NOTIFY
- [x] ห้ามแต่ละ Service ใช้ cache โดยไม่มี revision/checksum
- [x] Game Engine subscribe การ publish Config
- [x] Wallet/Auth subscribe เฉพาะ category ที่ตัวเองใช้
- [x] Flutter รับ Public App Config ผ่าน bootstrap/runtime endpoints
- [x] กำหนด retry/reconnect เมื่อ subscriber หลุด
- [x] เพิ่ม readiness check สำหรับ stale/missing config
- [x] Metrics/readiness แสดง current revision ของแต่ละ instance ผ่าน `/ready`

Acceptance Criteria:

- ทุก instance เห็น revision ใหม่ภายในเวลาที่กำหนด
- Instance ที่พลาด event สามารถ reconcile จาก DB/API ได้
- ไม่มี partial publish ระหว่าง key ที่ต้องเปลี่ยนพร้อมกัน

หมายเหตุ verification:

- Unit tests ครอบคลุม typed events, reconnect, reconcile และ readiness แล้ว
- Multi-key publish ทำใน transaction เดียวและส่ง `pg_notify` ภายใน transaction เดียวกัน
- ยังไม่ได้ทดสอบ propagation latency กับ PostgreSQL จริงหลาย instance; ต้องทำใน staging

---

## P1: Config Domains ที่ต้องรองรับ

### CFG-P1-101: Room creation policy

- [x] สิทธิ์ผู้เล่นสร้างห้อง
- [x] จำนวนห้องสูงสุดต่อผู้เล่น/Agent/Club
- [x] Min/Max players
- [x] Min/Max blind, ante และ buy-in
- [x] Allowed game types/modes
- [x] Private room/password policy
- [x] Room name/password length
- [x] Room expiration และ visibility
- [x] Allowed turn-time range
- [x] Allowed rake range

### CFG-P1-102: Texas Hold'em runtime

สถานะ: ทั้ง Registry และ Game Engine ใช้ค่าจริงแล้ว

- [x] Turn time
- [x] Time bank
- [x] Auto-check/auto-fold policy
- [x] Auto-start threshold/delay
- [x] Result display/next-hand delay
- [x] Disconnect grace/reconnect policy
- [x] Sit-out/idle/kick timeout
- [x] Minimum play duration
- [x] Seat reservation TTL
- [x] Blind, ante, straddle และ rebuy policy
- [x] Rake percent/cap
- [x] No-flop-no-drop/minimum rake pot
- [x] Maximum hands/room duration ถ้ามี

### CFG-P1-103: Chinese Poker runtime

สถานะ: ทั้ง Registry และ Game Engine ใช้ค่าจริงแล้ว

- [x] Arrange time
- [x] Auto-arrange/force-foul policy
- [x] Result display/next-round delay
- [x] Fantasyland rules
- [x] Royalty table version
- [x] Scoop/foul bonus
- [x] Player count และ buy-in limits
- [x] Minimum play duration
- [x] Rake policy

### CFG-P1-104: Tournament runtime

สถานะ: ทั้ง Registry และ Game Engine ใช้ค่าจริงแล้ว

- [x] Registration window
- [x] Late registration
- [x] Start policy
- [x] Action time/time bank
- [x] Blind level schedule
- [x] Break schedule
- [x] Rebuy/add-on policy
- [x] Table balancing thresholds
- [x] Disconnect timeout
- [x] Prize distribution policy
- [x] Cancellation/refund policy

### CFG-P1-105: Practice/Demo/Bot policy

- [x] เปิด/ปิด Bot ต่อ environment/mode
- [x] จำนวน Bot
- [x] Bot think-time range
- [x] Auto-start delay
- [x] Practice chip amount
- [x] Strategy profile/version
- [x] ห้าม Bot policy ของ Practice ไหลไป Cash/Tournament
- [x] Demo bot IDs/profiles มาจาก `practice_policy.demo_bot_profiles` ไม่ hardcode ใน Game Engine

### CFG-P1-106: Wallet/Economy policy

สถานะ: registry และ backend enforcement ใช้ค่าจริงแล้ว

- [x] Coin conversion
- [x] Credit/debit limits
- [x] Daily/transaction limits
- [x] Minimum/maximum wallet balance
- [x] Daily bonus/streak/reward
- [x] Shop price/purchase/inventory limits
- [x] Agent commission/withdrawal limits
- [x] Rake และ house-account identity
- [x] Idempotency/approval thresholds ที่เป็น policy

### CFG-P1-107: Security/Session operational policy

- [x] Access/session/room-token TTL โดยมี minimum security bounds
- [x] Login attempt/rate limits
- [x] Lockout duration
- [x] Password policy version และ bcrypt rounds
- [x] Session concurrency/device limits
- [x] Admin re-authentication window สำหรับ config writes
- [x] Audit retention
- [x] CORS origins มาจาก environment/deployment config ไม่ใช่ Admin free-text
- [x] Signing keys และ credentials ยังคงอยู่ใน Secret Manager เท่านั้น

### CFG-P1-108: Notifications, polling และ client runtime

- [x] API timeout/retry policy
- [x] Socket reconnect attempts/delay/max-delay/randomization
- [x] Balance/notification/lobby polling interval
- [x] Announcement/maintenance/update policy
- [x] Public feature flags
- [x] Result/turn display durations ที่ต้องตรงกับ Server
- [x] Client ใช้ Server deadline ไม่ใช้ local countdown เป็น authority

---

## P2: Admin Back-office

สถานะ P2: สมบูรณ์แล้วทั้งหมด — Admin Back-office, Game Engine integration, Worker/Scheduler, Public Client Config API และ Flutter/Agent client config ใช้งานได้ครบ

### CFG-P2-001: เปลี่ยน Raw JSON Editor เป็น Typed Forms

- [x] สร้างหน้าแยกตาม Category
- [x] Generate field จาก Config Registry
- [x] แสดง unit, min/max, default, effective value และ source
- [x] Inline validation และ cross-field validation
- [x] มี Preview diff ก่อน Publish
- [x] บังคับใส่เหตุผลสำหรับค่าความเสี่ยงสูง
- [x] แสดง Apply mode ทุก field
- [x] รองรับ Draft, Publish และ Cancel

### CFG-P2-002: Room template management

- [x] List/Create/Clone/Edit/Archive template
- [x] เลือก Game Type และ Mode
- [x] Preview Effective Config
- [x] ตั้งค่า Texas/Chinese/Tournament ตาม schema ของประเภทเกม
- [x] แสดงว่ามีห้องใดใช้ template/revision นี้
- [x] ป้องกันแก้ template revision ที่ถูกใช้แล้ว ให้สร้าง revision ใหม่แทน

### CFG-P2-003: ปรับหน้าสร้างและแก้ไขห้อง

- [x] เลือก Template ก่อนกรอก override
- [x] โหลด default จาก Effective Config API ไม่ hardcode ใน React state
- [x] แสดงเฉพาะ field ที่อนุญาตให้ override
- [x] Admin แก้ค่าห้องเดิมได้ครบ
- [x] แสดงผลกระทบ `ทันที/มือถัดไป/ห้องใหม่`
- [x] มี Apply existing แบบ dry-run และ confirmation
- [x] ลบ TODO ของ full edit endpoint

### CFG-P2-004: Config history, audit และ rollback UI

- [x] Timeline ของ revision
- [x] Diff ก่อน/หลัง
- [x] ผู้แก้ เวลา เหตุผล และ scope
- [x] Filter ตาม category/game type/table/admin
- [x] Rollback preview
- [x] แสดงสถานะ propagation ของแต่ละ Service instance

### CFG-P2-005: Permission model

- [x] แยก permission ผ่าน menu/role (config เข้าถึงผ่านเมนู settings)
- [x] แยก permission ตาม category ที่มีความเสี่ยง
- [x] Economy/Security policy ต้องใช้ Super Admin หรือ dual approval ตามที่กำหนด
- [x] ซ่อน field ที่ role ไม่มีสิทธิ์และตรวจซ้ำที่ Backend

---

## P2: Game Engine และ Service Integration

### CFG-P2-101: สร้าง Room Config Snapshot ตอนสร้างห้อง

- [x] Player/Admin creation ใช้ resolver เดียวกัน
- [x] Validate request ก่อน resolve
- [x] บันทึก resolved snapshot แบบ atomic พร้อม `game_tables`
- [x] ไม่ให้ Client ส่งค่าที่ไม่อยู่ใน override allowlist
- [x] Response คืน effective config และ source summary
- [x] Hash snapshot เพื่อใช้ตรวจ consistency

### CFG-P2-102: สร้าง Room Factory กลาง

- [x] รวมทุก path ที่สร้าง `GameRoom`, `ChinesePokerRoom`, Practice และ Tournament room
- [x] Factory รับ typed snapshot เท่านั้น
- [x] ห้าม constructor ใช้ `|| default` ที่ทำให้ค่า 0 ถูกแทนโดยไม่ตั้งใจ
- [x] ใช้ nullish handling และ schema validation
- [x] Log room/config revision โดยไม่ log secret

### CFG-P2-103: Runtime update semantics

กำหนด apply mode:

- `immediate`: feature visibility, announcement
- `next_turn`: ใช้เฉพาะกรณีที่พิสูจน์ว่าปลอดภัย
- `next_hand`: turn time, result delay, selected game policy
- `new_room`: blind/buy-in/template defaults
- `restart_required`: infrastructure-level setting

Tasks:

- [x] Queue update สำหรับ next-hand
- [x] ยืนยันว่า timer กลาง Turn ไม่ถูกยืด/หดโดยไม่คาดคิด
- [x] Broadcast config revision change ให้ Client
- [x] บันทึก revision ต่อ hand history
- [x] Reject incompatible update ขณะห้องกำลังเล่น

### CFG-P2-104: Worker/Scheduler configuration

- [x] Auto-cleanup schedule
- [x] Tournament scheduler
- [x] Notification jobs
- [x] Stats/rake aggregation jobs
- [x] Session cleanup jobs
- [x] ทุก worker ต้อง reload config โดยไม่สร้าง interval ซ้อน
- [x] ใช้ distributed lock เมื่อมีหลาย instance

---

## P2: Flutter Web/Mobile และ Agent Portal

### CFG-P2-201: Public Client Config API

- [x] คืนเฉพาะค่าที่ Client ต้องรู้
- [x] มี schema version, config revision, ETag และ cache TTL
- [x] ไม่ส่ง Internal/Security config
- [x] รองรับ refresh เมื่อ Server แจ้ง revision ใหม่
- [x] มี last-known-good cache สำหรับ network failure

### CFG-P2-202: ลบ Client business defaults

- [x] URL/service endpoints มาจาก build environment หรือ bootstrap discovery
- [x] Socket reconnect policy มาจาก Public Config
- [x] Polling intervals มาจาก Public Config
- [x] Feature availability มาจาก Server
- [x] Room creation form มาจาก definitions/effective config
- [x] Countdown ใช้ Server timestamps/deadlines
- [x] Client fallback ต้องเป็น versioned last-known-good ไม่ใช่ค่ากระจายใน Widget

### CFG-P2-203: Config compatibility

- [x] Client ส่ง supported config schema version
- [x] Server ปฏิเสธ/บังคับอัปเดต Client ที่อ่าน policy สำคัญไม่ได้
- [x] เพิ่ม compatibility tests ระหว่าง Flutter และ API schema
- [x] แสดง diagnostic config revision ในหน้า About/Debug เฉพาะ role ที่อนุญาต

---

## P3: Testing และ Quality Gates

### CFG-P3-001: Config Registry tests

- [ ] ทุก key มี type, bounds, unit, scope และ apply mode
- [ ] ไม่มี key ซ้ำ
- [ ] Seed ผ่าน schema ล่าสุด
- [ ] Invalid/missing required config ทำให้ test ล้มเหลว
- [ ] Cross-field validation ครบ

### CFG-P3-002: Room creation integration tests

- [ ] System default -> room snapshot
- [ ] Game type override -> room snapshot
- [ ] Template override -> room snapshot
- [ ] Per-room override -> room snapshot
- [ ] Player cannot override restricted field
- [ ] Admin permission controls
- [ ] Concurrent config publish/room creation ได้ snapshot revision เดียวกัน

### CFG-P3-003: Runtime behavior tests

- [ ] Texas turn timeout ตาม 10/30/60 วินาที
- [ ] Chinese arrange timeout ตามค่าห้อง
- [ ] Auto-start threshold/delay
- [ ] Result/next-hand delay
- [ ] Disconnect/reconnect grace
- [ ] Seat reservation expiry
- [ ] Minimum play duration
- [ ] Auto-cleanup policy
- [ ] Rake/buy-in/blind จาก snapshot
- [ ] Update แบบ next-hand ไม่กระทบ hand ปัจจุบัน

### CFG-P3-004: Admin E2E tests

- [ ] Draft/validate/publish
- [ ] Invalid value ถูกปฏิเสธ
- [ ] Preview effective config
- [ ] Create room from template
- [ ] Apply existing dry-run
- [ ] Rollback
- [ ] RBAC/permission denial
- [ ] Audit history แสดงข้อมูลครบ

### CFG-P3-005: Hardcode prevention

- [ ] เพิ่ม static check สำหรับ timeout/interval/policy constants ใน Runtime directories
- [ ] Allowlist เฉพาะ Protocol/Security invariant พร้อมเหตุผล
- [ ] CI fail เมื่อพบ magic number ใหม่ที่ไม่มี annotation/registry mapping
- [ ] ตรวจ source เท่านั้น ไม่ตรวจ generated files, `.next`, `build`, `node_modules`

### CFG-P3-006: Regression suite

- [x] Backend unit tests ผ่านทั้งหมด
- [ ] Backend integration tests ผ่านทั้งหมด
- [ ] Flutter analyze ไม่มี error/warning ที่กำหนดเป็น gate
- [ ] Flutter tests ผ่านทั้งหมด รวม responsive tests ที่ล้มเหลวอยู่
- [x] Flutter Web build ผ่าน
- [~] Admin/Agent production builds ผ่าน (Admin Web next build ผ่าน, Agent Portal ยังไม่ตรวจ)
- [ ] Load test การ publish config และห้องพร้อมกัน
- [ ] Failover test เมื่อ Config event/cache/DB ชั่วคราวใช้งานไม่ได้

---

## P3: Migration และ Rollout

### CFG-P3-101: เตรียมข้อมูล

- [ ] Inventory ค่าปัจจุบันจาก DB และ source
- [ ] แปลง magic numbers ปัจจุบันเป็น versioned seed revision 1
- [x] Backfill `game_tables.config_snapshot`
- [x] เปรียบเทียบ effective values ก่อนและหลัง migration
- [x] ห้ามเปลี่ยนพฤติกรรม Production ใน migration แรก

### CFG-P3-102: Dual-read / Shadow comparison

- [ ] Runtime อ่านค่าเดิมและ Config ใหม่คู่กันแต่ยังใช้ค่าเดิม
- [ ] Log mismatch พร้อม table/config revision
- [ ] Dashboard แสดง mismatch rate
- [ ] แก้ mismatch ให้เป็นศูนย์ก่อน cutover

### CFG-P3-103: Controlled cutover

- [ ] เปิดใช้ทีละ domain ด้วย feature flag
- [ ] เริ่มจาก Practice/Demo
- [ ] ต่อด้วยห้องใหม่ Cash Game
- [ ] ต่อด้วย Chinese Poker
- [ ] ต่อด้วย Tournament
- [ ] เปิด runtime updates หลัง snapshot flow เสถียร
- [ ] มี kill switch กลับ old reader ชั่วคราวระหว่าง rollout

### CFG-P3-104: Remove legacy hardcodes

- [ ] ลบ constants/defaults เก่าหลัง cutover
- [ ] ลบ DB/config keys ที่ไม่มี consumer
- [ ] ลบ duplicate config paths
- [ ] อัปเดต System Architecture และ Runbook
- [ ] เปิด CI hardcode gate เป็น blocking

---

## ลำดับการทำงานที่แนะนำ

1. CFG-P0-001 ถึง CFG-P0-006: แก้ Config ที่ UI/DB มีแล้วแต่ Runtime ไม่ใช้
2. CFG-P1-001 ถึง CFG-P1-006: สร้าง Registry, Resolver, Version และ Propagation
3. CFG-P1-101 ถึง CFG-P1-108: ย้าย Config ทีละ Domain
4. CFG-P2-101 ถึง CFG-P2-104: ทำ Snapshot/Factory/Runtime semantics
5. CFG-P2-001 ถึง CFG-P2-005: ปรับ Admin UI และ Permission
6. CFG-P2-201 ถึง CFG-P2-203: ปรับ Flutter/Agent clients
7. CFG-P3-001 ถึง CFG-P3-006: Tests และ Quality Gates
8. CFG-P3-101 ถึง CFG-P3-104: Migration, Cutover และลบ Legacy hardcodes

---

## Definition of Done

งานนี้ถือว่าเสร็จเมื่อ:

- [ ] ไม่มี Business/Operational magic numbers ใน Runtime source นอก allowlist
- [ ] ทุก Config key อยู่ใน Typed Registry
- [ ] Admin แก้ค่าได้ด้วย typed form และ Server-side validation
- [ ] ห้องทุกห้องมี immutable config snapshot/revision/hash
- [ ] ทุกมือเกมอ้างอิง revision ที่ใช้จริงได้
- [ ] Texas, Chinese และ Tournament ใช้ค่าจาก Effective Config จริง
- [ ] Config publish มี audit, preview, version, apply mode และ rollback
- [ ] Active room update มี semantics ที่ชัดเจนและไม่เปลี่ยนเกมกลางมือ
- [ ] Secrets ไม่อยู่ใน Admin config และไม่อยู่ใน source/Docker Compose
- [ ] Automated tests และ production builds ผ่านทั้งหมด
- [ ] CI ป้องกันการเพิ่ม hardcode กลับเข้าระบบ
- [ ] เอกสาร Architecture และ Operations ตรงกับ implementation จริง
