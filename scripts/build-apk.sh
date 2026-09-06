#!/bin/bash
# ============================================================
# THE SUN POKER - Build APK for Production
# ============================================================
# Builds a release APK connected to the production server.
# Run simulator tests first before building!
#
# Usage:
#   ./scripts/build-apk.sh              # Build release APK
#   ./scripts/build-apk.sh --debug      # Build debug APK
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

BUILD_MODE="release"
if [ "$1" == "--debug" ]; then
  BUILD_MODE="debug"
fi

# ── Verify production config ──
log_info "Verifying production configuration..."
if grep -q "useProduction = true" "$MOBILE_DIR/lib/config.dart"; then
  log_success "config.dart: useProduction = true ✓"
else
  log_error "config.dart: useProduction is NOT true!"
  log_info "Please set useProduction = true in lib/config.dart before building APK."
  exit 1
fi

# ── Verify server is reachable ──
log_info "Checking production server connectivity..."
if curl -s --connect-timeout 10 "http://129.212.236.4:3001/health" > /dev/null 2>&1; then
  log_success "Production server (129.212.236.4:3001) is reachable ✓"
else
  log_warn "Production server is not reachable. APK will still be built."
  log_warn "Make sure the server is running before distributing the APK."
fi

# ── Build ──
cd "$MOBILE_DIR"

log_info "Getting Flutter dependencies..."
flutter pub get

log_info "Building $BUILD_MODE APK..."
if [ "$BUILD_MODE" == "release" ]; then
  flutter build apk --release \
    --dart-define=SERVER_HOST=http://129.212.236.4
else
  flutter build apk --debug \
    --dart-define=SERVER_HOST=http://129.212.236.4
fi

# ── Output ──
APK_PATH="$MOBILE_DIR/build/app/outputs/flutter-apk/app-$BUILD_MODE.apk"
if [ -f "$APK_PATH" ]; then
  APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
  echo ""
  echo "============================================================"
  echo -e "${GREEN}  ✅ APK BUILD SUCCESSFUL${NC}"
  echo "============================================================"
  echo ""
  echo "  📦 APK: $APK_PATH"
  echo "  📏 Size: $APK_SIZE"
  echo "  🌐 Server: http://129.212.236.4"
  echo "  🔧 Mode: $BUILD_MODE"
  echo ""
  echo "  To distribute via APK server:"
  echo "    cp $APK_PATH $PROJECT_DIR/apk-server/apk/the-sun-poker.apk"
  echo "    docker compose up -d apk-server"
  echo ""
  echo "============================================================"
else
  log_error "APK file not found at expected path."
  log_info "Check Flutter build output above for errors."
  exit 1
fi
