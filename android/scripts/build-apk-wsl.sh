#!/bin/bash
# Build Octra Wallet Android APK (WSL version)
# Usage: ./android/scripts/build-apk.sh [debug|release] [--split-abi]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ANDROID_DIR"

echo "=== Octra Wallet Android Build (WSL) ==="
echo "Working directory: $(pwd)"
echo ""

# Stop Gradle daemon to prevent conflicts
echo "Stopping Gradle daemon..."
./gradlew --stop || true

# Clean build directories
echo "Cleaning build directories..."
rm -rf app/build
rm -rf build

# Determine build type
BUILD_TYPE="debug"
GRADLE_TASK="assembleDebug"
SPLIT_ABI=""

for arg in "$@"; do
    case "$arg" in
        release)
            BUILD_TYPE="release"
            GRADLE_TASK="assembleRelease"
            ;;
        --split-abi)
            SPLIT_ABI="-PsplitAbi=true"
            ;;
    esac
done

echo "Build type: $BUILD_TYPE"
echo "Split ABI: ${SPLIT_ABI:-no}"
echo ""

# Build APK
echo "Building APK..."
./gradlew $GRADLE_TASK $SPLIT_ABI --no-daemon

# Check build result
if [ "$BUILD_TYPE" = "release" ]; then
    APK_PATH="app/build/outputs/apk/release"
else
    APK_PATH="app/build/outputs/apk/debug"
fi

echo ""
if [ -f "$APK_PATH/app-release.apk" ] || [ -f "$APK_PATH/app-debug.apk" ]; then
    echo "=== BUILD SUCCESSFUL ==="
    echo ""
    echo "APK location: $APK_PATH/"
    ls -lh $APK_PATH/*.apk 2>/dev/null || true
    echo ""
    echo "To install on device:"
    echo "  adb install -r $APK_PATH/app-${BUILD_TYPE}.apk"
else
    echo "=== BUILD FAILED ==="
    echo "APK not found in $APK_PATH"
    exit 1
fi
