# THE SUN POKER - Scripts & Deployment Guide

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Mobile App (Flutter)                                        │
│  iOS Simulator / Android Emulator / Physical Device          │
└──────────────┬──────────────────────────────┬───────────────┘
               │ HTTP REST                     │ WebSocket
               ▼                               ▼
┌──────────────────────┐    ┌──────────────────────────────┐
│  Auth Service :3001  │    │  Game Engine :3003            │
│  Wallet Service :3002│    │  (Socket.IO - Real-time)     │
└──────────┬───────────┘    └──────────────┬───────────────┘
           │                                │
           ▼                                ▼
┌──────────────────────┐    ┌──────────────────────────────┐
│  PostgreSQL :5432    │    │  Redis :6379                  │
└──────────────────────┘    └──────────────────────────────┘
```

## 🚀 Quick Start

### Option 1: Connect to Production Server (Recommended for Testing)

The mobile app is configured to connect to the production server at `129.212.236.4`.

```bash
# Run on iOS Simulator
./scripts/run-simulator.sh ios

# Run on Android Emulator
./scripts/run-simulator.sh android

# Run on first available device
./scripts/run-simulator.sh
```

### Option 2: Run Everything Locally

```bash
# Start all backend services locally
./scripts/start-all-services.sh

# Or via Docker Compose (requires Docker running)
./scripts/start-all-services.sh --docker

# Then run the app pointing to localhost
./scripts/run-simulator.sh --local
```

### Option 3: Docker Compose (Full Stack)

```bash
docker compose up --build -d
```

## 📱 Running on Simulator

### iOS Simulator

```bash
# 1. Open Simulator
open -a Simulator

# 2. Run the app
./scripts/run-simulator.sh ios
```

### Android Emulator

```bash
# 1. Start emulator from Android Studio or command line
# 2. Run the app
./scripts/run-simulator.sh android
```

### Override Server URL

```bash
# Force connect to production
./scripts/run-simulator.sh --prod

# Force connect to localhost
./scripts/run-simulator.sh --local
```

## 🔧 Configuration

### Mobile App (`apps/mobile/lib/config.dart`)

| Setting | Value | Description |
|---------|-------|-------------|
| `useProduction` | `true` | Connect to 129.212.236.4 |
| `useProduction` | `false` | Connect to localhost |

You can also override at build time:
```bash
flutter run --dart-define=SERVER_HOST=http://your-server-ip
```

### Backend Services

| Service | Port | Health Check |
|---------|------|-------------|
| Auth Service | 3001 | `curl http://localhost:3001/health` |
| Wallet Service | 3002 | `curl http://localhost:3002/health` |
| Game Engine | 3003 | WebSocket at ws://localhost:3003 |

## 📦 Building APK

```bash
# Build release APK (connects to production server)
./scripts/build-apk.sh

# Build debug APK
./scripts/build-apk.sh --debug
```

Output: `apps/mobile/build/app/outputs/flutter-apk/app-release.apk`

## 🧪 Testing Workflow

1. **Start services** (production or local)
2. **Run on simulator** to test all features
3. **Verify connectivity**: Login, wallet, game tables, WebSocket
4. **Build APK** when satisfied with testing

## 🔍 Troubleshooting

### Server not reachable
- Check if services are running: `curl http://129.212.236.4:3001/health`
- For local: ensure Docker is running and services are up

### iOS Simulator HTTP blocked
- Already configured: `NSAllowsArbitraryLoads = true` in Info.plist

### Android cleartext traffic
- Already configured: `android:usesCleartextTraffic="true"` in AndroidManifest.xml

### WebSocket not connecting
- Verify token is valid (login first)
- Check game engine is running on port 3003
- Socket.IO uses websocket transport only
