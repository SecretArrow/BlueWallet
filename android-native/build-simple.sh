#!/bin/bash
# Simple build script for Octra Wallet Android

set -e

echo "=== Building Octra Wallet Android ==="
echo ""

cd "$(dirname "$0")/.."

# Stop Gradle daemon
echo "Stopping Gradle..."
./gradlew --stop || true

# Clean
echo "Cleaning..."
rm -rf app/build build

# Build
echo "Building debug APK..."
./gradlew assembleDebug --no-daemon

echo ""
echo "=== Build Complete ==="
echo ""
echo "APK: app/build/outputs/apk/debug/app-debug.apk"
echo ""

# Show APK info
if [ -f "app/build/outputs/apk/debug/app-debug.apk" ]; then
    ls -lh app/build/outputs/apk/debug/app-debug.apk
else
    echo "ERROR: APK not found!"
    exit 1
fi
