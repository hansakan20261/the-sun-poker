#!/bin/bash
TOKEN=$(cat /tmp/sunpoker_token.txt)
PASS=0
FAIL=0

test_api() {
  local name="$1"
  local url="$2"
  local check_key="$3"
  
  RESP=$(curl -s "$url" -H "Authorization: Bearer $TOKEN")
  if echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if '$check_key' in d else 1)" 2>/dev/null; then
    echo "✅ $name"
    PASS=$((PASS+1))
  else
    echo "❌ $name → $(echo "$RESP" | head -c 80)"
    FAIL=$((FAIL+1))
  fi
}

test_post() {
  local name="$1"
  local url="$2"
  local body="$3"
  local check_key="$4"
  
  RESP=$(curl -s -X POST "$url" -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d "$body")
  if echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if '$check_key' in d else 1)" 2>/dev/null; then
    echo "✅ $name"
    PASS=$((PASS+1))
  else
    echo "❌ $name → $(echo "$RESP" | head -c 80)"
    FAIL=$((FAIL+1))
  fi
}

echo "========================================="
echo "  THE SUN POKER — API Test Suite"
echo "========================================="
echo ""

echo "--- AUTH SERVICE (port 3001) ---"
test_post "Register" "http://localhost:3001/auth/register" "{\"username\":\"apitest_$$\",\"password\":\"Test1234\"}" "user"
test_post "Login" "http://localhost:3001/auth/login" '{"username":"superadmin","password":"SunPoker@2026"}' "token"
test_api  "Auth Me" "http://localhost:3001/auth/me" "user"
test_post "Forgot Password" "http://localhost:3001/auth/forgot-password" '{"username":"superadmin","email":"admin@thesunpoker.com","new_password":"SunPoker@2026"}' "success"

echo ""
echo "--- PLAYER APIs (port 3002) ---"
test_api "Wallet Balance" "http://localhost:3002/wallet/balance" "balance"
test_api "Wallet Transactions" "http://localhost:3002/wallet/transactions?limit=5" "transactions"
test_api "Profile Me" "http://localhost:3002/profile/me" "profile"
test_api "Game Types" "http://localhost:3002/tables/game-types" "game_types"
test_api "Tables List" "http://localhost:3002/tables" "tables"
test_api "Hand History" "http://localhost:3002/tables/hand-history?limit=5" "hands"
test_api "Shop Items" "http://localhost:3002/shop/items" "items"
test_api "Shop Inventory" "http://localhost:3002/shop/inventory" "inventory"
test_api "Clubs List" "http://localhost:3002/clubs" "clubs"
test_api "Tournaments" "http://localhost:3002/tournaments" "tournaments"
test_api "Tournament History" "http://localhost:3002/tournaments/my/history" "history"
test_api "Leaderboard Global" "http://localhost:3002/leaderboard/global" "leaderboard"
test_api "Leaderboard Wins" "http://localhost:3002/leaderboard/wins" "leaderboard"
test_api "Notifications" "http://localhost:3002/notifications" "notifications"

echo ""
echo "--- ADMIN APIs (port 3002) ---"
test_api "Admin: Search User" "http://localhost:3002/admin/users/search?q=superadmin" "user"
test_api "Admin: Users List" "http://localhost:3002/admin/users?limit=3" "users"
test_api "Admin: Game Types" "http://localhost:3002/admin/games/types" "game_types"
test_api "Admin: Tables" "http://localhost:3002/admin/games/tables" "tables"
test_api "Admin: Clubs" "http://localhost:3002/admin/clubs" "clubs"
test_api "Admin: Settings" "http://localhost:3002/admin/settings" "config"
test_api "Admin: Reports Summary" "http://localhost:3002/admin/reports/summary" "summary"
test_api "Admin: Shop Items" "http://localhost:3002/admin/shop/items" "items"
test_api "Admin: Agents" "http://localhost:3002/admin/agents" "agents"
test_api "Admin: Tournaments" "http://localhost:3002/admin/tournaments" "tournaments"
test_api "Admin: Coin Transactions" "http://localhost:3002/admin/coin-transactions?limit=3" "transactions"
test_api "Admin: Permissions" "http://localhost:3002/admin/permissions" "permissions"

echo ""
echo "--- GAME ENGINE (port 3003) ---"
test_api "Game Engine Health" "http://localhost:3003/health" "status"
test_api "Admin: Live Rooms" "http://localhost:3003/admin/rooms" "rooms"

echo ""
echo "========================================="
echo "  RESULTS: $PASS passed / $FAIL failed"
echo "========================================="
