# Deploy on Railway

## 1. Push code to GitHub

```bash
# From project root
git add .
git commit -m "Prepare Railway deployment"
git remote add origin https://github.com/<your-username>/the-sun-poker.git
git push -u origin main
```

## 2. Create Railway project

1. Open https://railway.com/new and choose **GitHub Repository**.
2. Select your `the-sun-poker` repo.
3. Choose **Deploy from railway.json file** when asked (so Railway uses per-service `railway.json`).

## 3. Add PostgreSQL

1. In the Railway project canvas, click **New** → **Database** → **Add PostgreSQL**.
2. Copy the `DATABASE_URL` and add it as a shared variable for all services:
   - `DATABASE_URL` = value from PostgreSQL service.

## 4. Add Redis (optional but recommended)

1. **New** → **Database** → **Add Redis**.
2. Add `REDIS_URL` = value from Redis service.

## 5. Create services

Add one service for each folder that contains `railway.json`. For each service, in the service **Settings** → **Source**, set the **Root Directory** to:

- `services/auth-service`
- `services/wallet-service`
- `services/game-engine`
- `apk-server`

## 6. Environment variables per service

### All services need:
- `DATABASE_URL`
- `JWT_SECRET` (generate a strong random string)

### `auth-service` needs:
- `JWT_SECRET`
- `JWT_EXPIRES_IN=7d`
- `JWT_REFRESH_EXPIRES_IN=30d`

### `wallet-service` needs:
- `DATABASE_URL`
- `JWT_SECRET`
- `REDIS_URL` (optional)

### `game-engine` needs:
- `DATABASE_URL`
- `JWT_SECRET`
- `REDIS_URL`

## 7. First-time database setup

After PostgreSQL is up and services are deployed, run migrations from `wallet-service`:

```bash
railway run --service wallet-service -- node /app/scripts/migrate.js
railway run --service wallet-service -- node /app/scripts/backfill-room-snapshots.js
```

Or from your local with `DATABASE_URL` set:

```bash
node scripts/migrate.js
node scripts/backfill-room-snapshots.js
```

## 8. Verify

```bash
curl https://<auth-service-domain>/health
curl https://<wallet-service-domain>/health
curl https://<game-service-domain>/health
```

## 9. Admin Web / Flutter Web (static)

Build locally and deploy the output as a static site (e.g. Vercel/Cloudflare Pages) or another Railway service with `npx serve`:

```bash
cd apps/admin-web && npm run build
cd apps/mobile && flutter build web
```
