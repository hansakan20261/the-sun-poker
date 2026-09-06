#!/bin/bash
# Deploy APK server to 129.212.236.4
# Usage: ./deploy.sh <ssh-user> [ssh-key-path]
# Example: ./deploy.sh root
# Example: ./deploy.sh ubuntu ~/.ssh/id_rsa

set -e

SERVER_IP="129.212.236.4"
SERVER_PORT="22"
REMOTE_DIR="/var/www/sunpoker-apk"
USER="${1:-root}"
SSH_KEY="${2:-}"

SSH_OPTS="-o StrictHostKeyChecking=no"
if [ -n "$SSH_KEY" ]; then
  SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

echo "🚀 Deploying to $USER@$SERVER_IP..."

# 1. Create remote directory
ssh $SSH_OPTS $USER@$SERVER_IP "mkdir -p $REMOTE_DIR/apk $REMOTE_DIR/logs"

# 2. Upload server files
echo "📤 Uploading server files..."
scp $SSH_OPTS package.json server.js ecosystem.config.js index.html nginx.conf \
  $USER@$SERVER_IP:$REMOTE_DIR/

# 3. Upload APK
echo "📦 Uploading APK (this may take a while ~83MB)..."
scp $SSH_OPTS apk/thesunpoker.apk $USER@$SERVER_IP:$REMOTE_DIR/apk/

# 4. Install dependencies and start with PM2
echo "⚙️  Installing dependencies and starting PM2..."
ssh $SSH_OPTS $USER@$SERVER_IP "
  cd $REMOTE_DIR
  npm install --production
  
  # Install PM2 if not exists
  if ! command -v pm2 &> /dev/null; then
    npm install -g pm2
  fi
  
  # Start or restart
  pm2 delete sunpoker-apk 2>/dev/null || true
  pm2 start ecosystem.config.js
  pm2 save
  
  # Setup PM2 startup (auto-start on reboot)
  pm2 startup | tail -1 | bash 2>/dev/null || true
  
  echo ''
  pm2 status sunpoker-apk
"

echo ""
echo "✅ Deploy สำเร็จ!"
echo ""
echo "🔗 Download link:"
echo "   http://$SERVER_IP:8080/download/thesunpoker.apk"
echo ""
echo "📊 Health check:"
echo "   http://$SERVER_IP:8080/health"
