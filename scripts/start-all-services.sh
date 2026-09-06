#!/bin/bash
# ============================================================
# THE SUN POKER - Start All Backend Services (Local Dev)
# ============================================================
# This script starts all backend services locally so the
# iOS/Android simulator can connect to the real server stack.
#
# Usage:
#   ./scripts/start-all-services.sh          # Start all services
#   ./scripts/start-all-services.sh --docker  # Start via Docker Compose
#   ./scripts/start-all-services.sh --stop    # Stop all services
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Stop all services ──
stop_services() {
  log_info "Stopping all services..."
  pkill -f "node.*auth-service" 2>/dev/null || true
  pkill -f "node.*wallet-service" 2>/dev/null || true
  pkill -f "node.*game-engine" 2>/dev/null || true
  log_success "All services stopped."
}

# ── Check prerequisites ──
check_prereqs() {
  log_info "Checking prerequisites..."

  if ! command -v node &> /dev/null; then
    log_error "Node.js is not installed. Please install Node.js 18+."
    exit 1
  fi
  log_success "Node.js $(node --version)"

  if ! command -v npm &> /dev/null; then
    log_error "npm is not installed."
    exit 1
  fi
  log_success "npm $(npm --version)"

  # Check if PostgreSQL is running
  if pg_isready -h localhost -p 5432 &> /dev/null; then
    log_success "PostgreSQL is running on port 5432"
  else
    log_warn "PostgreSQL is not running on localhost:5432"
    log_info "Starting PostgreSQL via Docker..."
    cd "$PROJECT_DIR"
    docker compose up -d postgres redis
    sleep 5
    if pg_isready -h localhost -p 5432 &> /dev/null; then
      log_success "PostgreSQL started via Docker"
    else
      log_error "Cannot start PostgreSQL. Please start it manually or run: docker compose up -d postgres redis"
      exit 1
    fi
  fi

  # Check Redis
  if redis-cli ping &> /dev/null 2>&1; then
    log_success "Redis is running on port 6379"
  else
    log_warn "Redis is not running. Starting via Docker..."
    cd "$PROJECT_DIR"
    docker compose up -d redis
    sleep 3
  fi
}

# ── Install dependencies ──
install_deps() {
  log_info "Installing dependencies..."

  cd "$PROJECT_DIR/services/auth-service"
  if [ ! -d "node_modules" ]; then
    npm install
  fi
  log_success "auth-service dependencies ready"

  cd "$PROJECT_DIR/services/wallet-service"
  if [ ! -d "node_modules" ]; then
    npm install
  fi
  log_success "wallet-service dependencies ready"

  cd "$PROJECT_DIR/services/game-engine"
  if [ ! -d "node_modules" ]; then
    npm install
  fi
  log_success "game-engine dependencies ready"
}

# ── Start services ──
start_services() {
  log_info "Starting backend services..."

  # Auth Service (port 3001)
  cd "$PROJECT_DIR/services/auth-service"
  node src/index.js &
  AUTH_PID=$!
  sleep 2
  if kill -0 $AUTH_PID 2>/dev/null; then
    log_success "Auth Service started (PID: $AUTH_PID, port 3001)"
  else
    log_error "Auth Service failed to start"
    exit 1
  fi

  # Wallet Service (port 3002)
  cd "$PROJECT_DIR/services/wallet-service"
  node src/index.js &
  WALLET_PID=$!
  sleep 2
  if kill -0 $WALLET_PID 2>/dev/null; then
    log_success "Wallet Service started (PID: $WALLET_PID, port 3002)"
  else
    log_error "Wallet Service failed to start"
    exit 1
  fi

  # Game Engine (port 3003)
  cd "$PROJECT_DIR/services/game-engine"
  node src/index.js &
  GAME_PID=$!
  sleep 2
  if kill -0 $GAME_PID 2>/dev/null; then
    log_success "Game Engine started (PID: $GAME_PID, port 3003)"
  else
    log_error "Game Engine failed to start"
    exit 1
  fi

  echo ""
  echo "============================================================"
  echo -e "${GREEN}  ✅ ALL SERVICES RUNNING${NC}"
  echo "============================================================"
  echo ""
  echo "  🔑 Auth Service:    http://localhost:3001"
  echo "  💰 Wallet Service:  http://localhost:3002"
  echo "  🎮 Game Engine:     http://localhost:3003 (WebSocket)"
  echo ""
  echo "  📱 Mobile App Config:"
  echo "     Set useProduction = false in config.dart for localhost"
  echo "     Set useProduction = true for production (129.212.236.4)"
  echo ""
  echo "  🧪 Health Check:"
  echo "     curl http://localhost:3001/health"
  echo "     curl http://localhost:3002/health"
  echo ""
  echo "  Press Ctrl+C to stop all services"
  echo "============================================================"

  # Wait for all background processes
  trap "stop_services; exit 0" SIGINT SIGTERM
  wait
}

# ── Docker mode ──
start_docker() {
  log_info "Starting all services via Docker Compose..."
  cd "$PROJECT_DIR"
  docker compose up --build -d
  sleep 5

  echo ""
  echo "============================================================"
  echo -e "${GREEN}  ✅ ALL DOCKER SERVICES RUNNING${NC}"
  echo "============================================================"
  echo ""
  docker compose ps
  echo ""
  echo "  🧪 Health Check:"
  echo "     curl http://localhost:3001/health"
  echo "     curl http://localhost:3002/health"
  echo ""
  echo "  📱 For Simulator: set useProduction = false in config.dart"
  echo "  🌐 For Production: set useProduction = true in config.dart"
  echo ""
  echo "  Stop: docker compose down"
  echo "============================================================"
}

# ── Main ──
case "${1:-}" in
  --stop)
    stop_services
    ;;
  --docker)
    start_docker
    ;;
  *)
    check_prereqs
    install_deps
    start_services
    ;;
esac
