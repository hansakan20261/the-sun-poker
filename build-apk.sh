#!/bin/bash
# Build APK and update download server

set -e

echo "🔨 Building Flutter APK..."
cd apps/mobile
flutter pub get
flutter build apk --release --split-per-abi
cd ../..

echo "📦 Copying APK files to server..."
mkdir -p apk-server/apk
cp apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk apk-server/apk/the-sun-poker-arm64.apk
cp apps/mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk apk-server/apk/the-sun-poker-armv7.apk
cp apps/mobile/build/app/outputs/flutter-apk/app-x86_64-release.apk apk-server/apk/the-sun-poker-x86_64.apk

echo "🐳 Rebuilding Docker container..."
docker compose build apk-server
docker compose up -d apk-server

echo ""
echo "✅ Done! APK download server is running at:"
echo "   http://localhost:8080"
echo ""
echo "📱 Direct download links:"
echo "   http://localhost:8080/apk/the-sun-poker-arm64.apk  (ARM64 - แนะนำ)"
echo "   http://localhost:8080/apk/the-sun-poker-armv7.apk  (ARMv7)"
echo "   http://localhost:8080/apk/the-sun-poker-x86_64.apk (x86_64)"
