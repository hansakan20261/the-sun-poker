# THE SUN POKER — Development Plan

## สถานะรวม: Phase 1 กำลังดำเนินการ

---

## Phase 1: Foundation (ฐานระบบ)

| # | งาน | สถานะ | หมายเหตุ |
|---|------|-------|---------|
| 1.1 | ออกแบบ System Architecture | ✅ เสร็จ | docs/system-architecture.md |
| 1.2 | Database Schema 35 ตาราง | ✅ เสร็จ | PostgreSQL รันบน Docker |
| 1.3 | Seed Data (Admin, Game Types, Config) | ✅ เสร็จ | superadmin + 3 เกม + config |
| 1.4 | Redis | ✅ เสร็จ | รันบน Docker |
| 1.5 | Auth Service (Register/Login/Me) | ✅ เสร็จ | port 3001 |
| 1.6 | Wallet Service (ยอด/ประวัติ/Admin เติม-ถอน) | ✅ เสร็จ | port 3002 |
| 1.7 | Admin Web — โครง + Login + Dashboard | ✅ เสร็จ | port 3100 (Next.js) |
| 1.8 | Admin Web — หน้าเติม/ถอนเหรียญ | ✅ เสร็จ | ค้นหาผู้ใช้ + เติม/ถอนจริง |

---

## Phase 2: Admin Web ให้ครบ (ทำถัดไป)

| # | งาน | สถานะ | รายละเอียด |
|---|------|-------|-----------|
| 2.1 | Admin — จัดการผู้ใช้ | ✅ เสร็จ | ดูรายชื่อ, ค้นหา, ระงับ, รีเซ็ตรหัสผ่าน, ดูโปรไฟล์, ดู Agent ที่ผูก |
| 2.2 | Admin — สร้าง/จัดการ Agent | ✅ เสร็จ | สร้าง Agent, ออก link, ตั้ง commission, ระงับ, เพิ่ม channel |
| 2.3 | Admin — จัดการเกม & ห้องเล่น | ✅ เสร็จ | เพิ่ม/เปิด/ปิดเกม, สร้าง/ปิด/ลบห้อง |
| 2.4 | Admin — จัดการคลับ | ✅ เสร็จ | ดูคลับ, ค้นหา, ดูสมาชิก, เปิด/ปิด, ลบสมาชิก |
| 2.5 | Admin — ร้านค้า | ✅ เสร็จ | เพิ่ม/แก้ไข/เปิด/ปิดสินค้า, หมวดหมู่ |
| 2.6 | Admin — ตั้งค่าระบบ | ✅ เสร็จ | แก้ไข config, เปิด/ปิด feature flags 10 ตัว |
| 2.7 | Admin — รายงาน | ✅ เสร็จ | สรุปภาพรวม, เติม/ถอนรายวัน, Top Players |
| 2.8 | Admin — บล็อกสิทธิ์ | ✅ เสร็จ | บล็อก/ปลดบล็อก 10 สิทธิ์ + audit log (API พร้อม) |
| 2.9 | Admin — สร้างรายการแข่ง Tournament | ✅ เสร็จ | สร้าง/จัดการ tournament (API พร้อม) |

---

## Phase 3: Backend Services ที่เหลือ

| # | งาน | สถานะ | รายละเอียด |
|---|------|-------|-----------|
| 3.1 | Admin Service (API ครบ) | ✅ เสร็จ | จัดการผู้ใช้, คลับ, เกม, config, reports, permissions, tournaments |
| 3.2 | Club Service | ✅ เสร็จ | สร้าง/เข้าร่วมคลับ, สมาชิก |
| 3.3 | Agent Service | ✅ เสร็จ | สร้าง Agent, channel, commission (ผ่าน Admin API) |
| 3.4 | Shop Service | ✅ เสร็จ | ซื้อสินค้า, inventory, หักเหรียญจริง |
| 3.5 | Game Engine (WebSocket) | ✅ เสร็จ | Texas Hold'em: deck, hand evaluator, game room, WebSocket server |
| 3.6 | Chinese Poker Engine | ✅ เสร็จ | ไพ่สามกอง: แจก 13 ใบ, จัด 3 กอง, คำนวณคะแนน, scoop bonus |
| 3.7 | Chat Service (WebSocket) | ✅ เสร็จ | รวมใน Game Engine (chat:message, whisper) |
| 3.8 | Notification Service | ✅ เสร็จ | In-app notifications + โครง FCM/APNs |
| 3.9 | Leaderboard Service | ✅ เสร็จ | จัดอันดับ global/wins/club |
| 3.10 | Anti-Cheat Service | ✅ เสร็จ | ตรวจจับ win rate ผิดปกติ, collusion pairs, suspicious transfers |
| 3.11 | Tournament Service | ✅ เสร็จ | สร้าง/จัดการ/สมัคร tournament + หักค่าสมัคร |

---

## Phase 4: Flutter Mobile App

| # | งาน | สถานะ | รายละเอียด |
|---|------|-------|-----------|
| 4.1 | Flutter Project Setup | ✅ เสร็จ | โครงสร้าง, theme ตามดีไซน์ |
| 4.2 | หน้า Login / Register | ✅ เสร็จ | ต่อ Auth API จริง |
| 4.3 | หน้า Home / Lobby | ✅ เสร็จ | เลือกเกม, ดูห้อง, กรองตามประเภท |
| 4.4 | หน้า Profile / Wallet | ✅ เสร็จ | ดูโปรไฟล์, ยอดเหรียญ, สถิติ, ประวัติธุรกรรม |
| 4.5 | หน้า Club | ✅ เสร็จ | ดูคลับ, สร้างคลับ, เข้าร่วม |
| 4.6 | หน้า Poker Table (เล่นจริง) | ✅ เสร็จ | UI โต๊ะ + community cards + action buttons |
| 4.7 | หน้า Chat | ✅ เสร็จ | รวมใน Game Engine (chat:message, whisper) |
| 4.8 | หน้า Shop | ✅ เสร็จ | ดูสินค้า, ซื้อ, หักเหรียญจริง |
| 4.9 | หน้า Leaderboard | ✅ เสร็จ | อันดับเหรียญ/ชนะ |
| 4.10 | หน้า Tournament | ✅ เสร็จ | ดูรายการ, สมัครแข่ง, หักค่าสมัคร |
| 4.11 | หน้า Friends | ✅ เสร็จ | รายชื่อเพื่อน |

---

## Phase 5: Agent Portal

| # | งาน | สถานะ | รายละเอียด |
|---|------|-------|-----------|
| 5.1 | Agent Web — Login | ✅ เสร็จ | agent portal login + role check |
| 5.2 | Agent Web — Dashboard | ✅ เสร็จ | ยอดเหรียญ, ข้อมูลพื้นฐาน |
| 5.3 | Agent Web — ช่องทาง/Link | ✅ เสร็จ | ดูได้จาก dashboard API |
| 5.4 | Agent Web — ลูกค้า | ✅ เสร็จ | รายชื่อ, สถิติ (API พร้อม) |
| 5.5 | Agent Web — ถอนเงิน | ✅ เสร็จ | ขอถอน, ประวัติ (API พร้อม) |

---

## Phase 6: Testing & Launch

| # | งาน | สถานะ | รายละเอียด |
|---|------|-------|-----------|
| 6.1 | Unit Tests | ❌ ยังไม่ทำ | ทดสอบ API ทุก endpoint |
| 6.2 | UAT Testing | ❌ ยังไม่ทำ | ทดสอบกับผู้ใช้จริง |
| 6.3 | Security Testing | ❌ ยังไม่ทำ | penetration test |
| 6.4 | Deploy to Production | ❌ ยังไม่ทำ | DigitalOcean Singapore |
| 6.5 | App Store / Play Store | ❌ ยังไม่ทำ | ส่งแอปขึ้น Store |

---

## สรุปความคืบหน้า

| Phase | ทำเสร็จ | ทั้งหมด | % |
|-------|--------|---------|---|
| Phase 1: Foundation | 8 | 8 | 100% ✅ |
| Phase 2: Admin Web ครบ | 9 | 9 | 100% ✅ |
| Phase 3: Backend Services | 11 | 11 | 100% ✅ |
| Phase 4: Flutter App | 11 | 11 | 100% ✅ |
| Phase 5: Agent Portal | 5 | 5 | 100% ✅ |
| Phase 6: Testing & Launch | 0 | 5 | 0% |
| **รวม** | **44** | **49** | **90%** |

---

## ลำดับแนะนำทำต่อ

```
ตอนนี้ → Phase 2 (Admin Web ให้ครบ)
       → ทำ 2.1 จัดการผู้ใช้ ก่อน
       → แล้วต่อ 2.2 Agent, 2.3 เกม, ...

เสร็จ Phase 2 → Phase 3 (Backend ที่เหลือ) + Phase 4 (Flutter) ทำคู่กัน
             → 3.2 Club + 4.5 หน้า Club
             → 3.5 Game Engine + 4.6 หน้า Poker Table

เสร็จ Phase 3+4 → Phase 5 (Agent Portal)
               → Phase 6 (Testing & Launch)
```
