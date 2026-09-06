#!/bin/bash
# ============================================================
# THE SUN POKER - Run on iOS/Android Simulator
# ============================================================
# Connects to the REAL production server (129.212.236.4)
# or local server based on config.dart setting.
#
# Usage:
#   ./scripts/run-simulator.sh              # Run on default device
#   ./scripts/run-simulator.sh ios          # Run on iOS Simulator
#   ./scripts/run-simulator.sh android      # Run on Android Emulator
#   ./scripts/run-simulator.sh --local      # Override to use localhost
#   ./scripts/run-simulator.sh --prod       # Override to use production
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOBILE_DIR="$PROJECT_DIR/apps/mobile"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

PLATFORM="${1:-}"
SERVER_OVERRIDE=""
DART_DEFINES=""

# Parse arguments
for arg in "$@"; do
  case $arg in
    --local)
      SERVER_OVERRIDE="http://localhost"
      ;;
    --prod)
      SERVER_OVERRIDE="http://129.212.236.4"
      ;;
    ios|android)
      PLATFORM="$arg"
      ;;
  esac
done

# ── Check Flutter ──
if ! command -v flutter &> /dev/null; then
  log_error "Flutter is not installed. Please install Flutter SDK."
  exit 1
fi
log_success "Flutter $(flutter --version 2>&1 | head -1)"

# ── Check server connectivity ──
check_server() {
  local host=$1
  log_info "Checking server connectivity: $host..."

  if curl -s --connect-timeout 5 "$host:3001/health" > /dev/null 2>&1; then
    log_success "Auth Service ($host:3001) ✓"
  else
    log_warn "Auth Service ($host:3001) not reachable"
    return 1
  fi

  if curl -s --connect-timeout 5 "$host:3002/health" > /dev/null 2>&1; then
    log_success "Wallet Service ($host:3002) ✓"
  else
    log_warn "Wallet Service ($host:3002) not reachable"
    return 1
  fi

  return 0
}

# Determine which server to use
if [ -n "$SERVER_OVERRIDE" ]; then
  DART_DEFINES="--dart-define=SERVER_HOST=$SERVER_OVERRIDE"
  log_info "Using server override: $SERVER_OVERRIDE"
  check_server "$SERVER_OVERRIDE" || log_warn "Server may not be running. App will retry on launch."
else
  # Check config.dart setting
  if grep -q "useProduction = true" "$MOBILE_DIR/lib/config.dart"; then
    log_info "Config: useProduction = true → connecting to 129.212.236.4"
    check_server "http://129.212.236.4" || log_warn "Production server may not be reachable from this network."
  else
    log_info "Config: useProduction = false → connecting to localhost"
    check_server "http://localhost" || {
      log_warn "Local server not running. Start with: ./scripts/start-all-services.sh"
      echo ""
      read -p "Continue anyway? (y/n) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi
    }
  fi
fi

# ── Get dependencies ──
cd "$MOBILE_DIR"
log_info "Getting Flutter dependencies..."
flutter pub get
log_success "Dependencies ready"

# ── List available devices ──
echo ""
log_info "Available devices:"
flutter devices
echo ""

# ── Run on simulator ──
case "$PLATFORM" in
  ios)
    log_info "Running on iOS Simulator..."
    # Boot simulator if not running
    if ! xcrun simctl list devices booted 2>/dev/null | grep -q "Booted"; then
      log_info "Booting iOS Simulator..."
      open -a Simulator
      sleep 5
    fi
    flutter run -d ios $DART_DEFINES
    ;;
  android)
    log_info "Running on Android Emulator..."
    # Check if emulator is running
    if ! flutter devices | grep -q "android"; then
      log_warn "No Android emulator running. Please start one from Android Studio."
      exit 1
    fi
    flutter run -d android $DART_DEFINES
    ;;
  *)
    log_info "Running on first available device..."
    flutter run $DART_DEFINES
    ;;
esac
