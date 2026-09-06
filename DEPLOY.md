# THE SUN POKER — Production Deployment

## Prerequisites
- Docker + Docker Compose
- `POSTGRES_PASSWORD` and `JWT_SECRET` env vars
- (Optional) `DATABASE_URL` for `scripts/migrate.js`

## Fresh deployment (new server)

1. Clone the repo and `cd` into it.
2. Copy environment:
```bash
cp .env.example .env
# edit .env with real POSTGRES_PASSWORD, JWT_SECRET, etc.
```
3. Start all services and the database:
```bash
docker compose up -d
```
4. The `database/init` files run automatically on first PostgreSQL start.
5. Seed snapshots for existing rooms (if you loaded a backup):
```bash
docker compose exec wallet-service node /app/scripts/backfill-room-snapshots.cjs
# or from local with DATABASE_URL set:
node scripts/backfill-room-snapshots.cjs
```

## Existing database (incremental migration)

1. Export the latest dump and restore it on the server.
2. Run migrations and backfill:
```bash
node scripts/migrate.cjs
node scripts/backfill-room-snapshots.cjs
```
3. Start app services:
```bash
docker compose up -d --build
```

## Verification after deploy

```bash
# health
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3003/health

# config readiness
curl http://localhost:3002/ready
curl http://localhost:3003/ready

# hardcode check
cd /path/to/repo
node scripts/check-config-hardcodes.js
```

## Reverse proxy / SSL (recommended)
- Auth: `auth.yourdomain.com` -> `http://127.0.0.1:3001`
- Wallet/API: `api.yourdomain.com` -> `http://127.0.0.1:3002`
- Game: `game.yourdomain.com` -> `http://127.0.0.1:3003`
- Admin: `admin.yourdomain.com` -> static build in `apps/admin-web`
- Flutter Web: `app.yourdomain.com` -> `apps/mobile/build/web`
