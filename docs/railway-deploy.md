# Railway Deployment Guide

คู่มือนี้ใช้ deploy THE SUN POKER backend ไปยัง Railway เพื่อ verify PostgreSQL/config propagation จริงก่อนทำ P2 ต่อ

## Services ที่ต้องสร้าง

สร้าง Railway project แล้วเพิ่ม service เหล่านี้:

1. PostgreSQL
2. `db-init` — รัน database init SQL หนึ่งครั้ง
3. `auth-service`
4. `wallet-service`
5. `game-engine`

Redis ยังไม่จำเป็นสำหรับ runtime ปัจจุบัน เพราะ services ไม่ได้ใช้ `REDIS_URL` ใน code path หลัก

## Config-as-code files

ในแต่ละ Railway service ให้ชี้ custom config file ตามนี้:

| Railway service | Config file |
| --- | --- |
| `db-init` | `railway.db-init.json` |
| `auth-service` | `railway.auth.json` |
| `wallet-service` | `railway.wallet.json` |
| `game-engine` | `railway.game.json` |

Docker build context ต้องเป็น repository root เสมอ เพราะ services ต้องใช้ shared `config/` directory

## Environment variables

### PostgreSQL service

ใช้ค่าที่ Railway สร้างให้ จากนั้น reference `DATABASE_URL` ไปยัง services อื่น

### db-init

ตั้งค่า:

```text
DATABASE_URL=${{Postgres.DATABASE_URL}}
```

Deploy service นี้หนึ่งครั้งเพื่อ apply ทุกไฟล์ใน `database/init/*.sql`

ถ้า Railway ไม่รองรับ one-off service ให้ใช้ Railway shell/query tool รัน:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/init/001_create_tables.sql
```

แล้วทำตามลำดับไฟล์ทั้งหมดใน `database/init/`

### auth-service

```text
NODE_ENV=production
DATABASE_URL=${{Postgres.DATABASE_URL}}
JWT_SECRET=<generate-strong-secret>
CORS_ORIGINS=https://<admin-domain>,https://<player-domain>
CONFIG_LISTEN_RETRY_MS=5000
```

### wallet-service

```text
NODE_ENV=production
DATABASE_URL=${{Postgres.DATABASE_URL}}
JWT_SECRET=<same-secret-as-auth-service>
CORS_ORIGINS=https://<admin-domain>,https://<player-domain>
PUBLIC_APP_URL=https://<player-domain>
CONFIG_LISTEN_RETRY_MS=5000
```

### game-engine

```text
NODE_ENV=production
DATABASE_URL=${{Postgres.DATABASE_URL}}
JWT_SECRET=<same-secret-as-auth-service>
CORS_ORIGINS=https://<admin-domain>,https://<player-domain>
CONFIG_LISTEN_RETRY_MS=5000
```

Railway จะ inject `PORT` ให้เอง ไม่ต้อง fix เป็น 3001/3002/3003 ใน production

## Verification checklist

หลัง deploy:

1. `db-init` ต้องจบด้วย `Database initialization completed`
2. เปิด health checks:
   - `GET https://<auth-domain>/health`
   - `GET https://<wallet-domain>/health`
   - `GET https://<game-domain>/health`
3. เปิด readiness checks:
   - `GET https://<auth-domain>/ready`
   - `GET https://<wallet-domain>/ready`
   - `GET https://<game-domain>/ready`
4. ตรวจว่า `/ready` ไม่มี missing/stale config
5. ทดสอบ publish config ผ่าน wallet Admin API แล้วดู `config_tracker.listener` ของ auth/game-engine เป็น `listening`
6. สร้างห้องใหม่แล้วตรวจ `game_tables.config_snapshot`, `config_version`, `config_hash`
7. เพิ่ม runtime override แบบ `new_room` แล้วยืนยันว่าห้องเดิมไม่เปลี่ยน

## ข้อควรระวัง

- ห้าม commit `JWT_SECRET`, database password หรือ `DATABASE_URL` ลง repository
- `docker-compose.yml` ตอนนี้ต้องการ `POSTGRES_PASSWORD` และ `JWT_SECRET` ผ่าน environment
- Flutter/Admin frontend ต้องชี้ไปยัง Railway URLs หลัง deploy เสร็จ
- ถ้าใช้ public `DATABASE_URL` จากภายนอก Railway อาจต้องตั้ง `DB_SSL=true`; สำหรับ service-to-service ภายใน Railway ปกติไม่ต้องเปิด
