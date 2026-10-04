#!/bin/bash
# Clean build script for Octra Wallet Android

set -e

echo "=== Octra Wallet Android Clean Build ==="
echo ""

# Stop Gradle daemon
echo "Stopping Gradle daemon..."
./gradlew --stop || true

# Clean build directories
echo "Cleaning build directories..."
rm -rf app/build
rm -rf build
rm -rf .gradle

# Build debug APK
echo "Building debug APK..."
./gradlew assembleDebug --no-daemon --stacktrace

echo ""
echo "=== Build Complete ==="
echo "APK location: app/build/outputs/apk/debug/app-debug.apk"
echo ""
echo "To install on device:"
echo "  adb install -r app/build/outputs/apk/debug/app-debug.apk"
