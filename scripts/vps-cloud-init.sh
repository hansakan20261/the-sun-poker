#!/bin/bash
# Cloud-init / user data script for a fresh Ubuntu VPS (Kamatera/DigitalOcean/...)
# Deploys THE SUN POKER backend (Postgres, Redis, auth, wallet, game) via Docker Compose.

set -e

# ====== แก้ไขตรงนี้ก่อน copy/paste ======
# ถ้า repo เป็น private: ใส่ GitHub token ที่มี scope repo
# ถ้า repo เป็น public: ให้ปล่อยว่าง ""
GH_TOKEN="YOUR_GITHUB_TOKEN"
# ========================================

APP_DIR="/opt/the-sun-poker"
LOG_FILE="/var/log/sunpoker-deploy.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Updating system ==="
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common git openssl

echo "=== Installing Docker ==="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

echo "=== Installing Node.js 20 ==="
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "=== Cloning repository ==="
if [ -d "$APP_DIR" ]; then
  rm -rf "$APP_DIR"
fi
if [ -z "$GH_TOKEN" ]; then
  REPO_URL="https://github.com/hansakan20261/the-sun-poker.git"
else
  REPO_URL="https://${GH_TOKEN}@github.com/hansakan20261/the-sun-poker.git"
fi
git clone --depth 1 "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

echo "=== Generating .env ==="
POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '=+/')
JWT_SECRET=$(openssl rand -base64 64 | tr -d '=+/')
cat > "$APP_DIR/.env" <<EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=sunpoker
POSTGRES_USER=sunpoker
JWT_SECRET=${JWT_SECRET}
CORS_ORIGINS=*
DATABASE_URL=postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}
EOF

echo "=== Installing local Node dependencies ==="
npm install

echo "=== Building and starting services ==="
docker compose up -d --build

echo "=== Waiting for services to be healthy ==="
for i in {1..60}; do
  if curl -fsS http://localhost:3001/health >/dev/null 2>&1 && \
     curl -fsS http://localhost:3002/health >/dev/null 2>&1 && \
     curl -fsS http://localhost:3003/health >/dev/null 2>&1; then
    break
  fi
  echo "Waiting... ($i)"
  sleep 5
done

echo "=== Applying incremental migrations (skip init because docker-entrypoint already ran) ==="
SKIP_INIT=1 node scripts/migrate.cjs

echo "=== Backfilling room snapshots ==="
node scripts/backfill-room-snapshots.cjs

echo "=== Deployment complete ==="
IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || echo "<unknown>")
echo "Public IP: $IP"
echo "Auth:      http://${IP}:3001/health"
echo "Wallet:    http://${IP}:3002/health"
echo "Game:      http://${IP}:3003/health"
