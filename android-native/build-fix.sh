#!/bin/bash
# Complete build fix script for Octra Wallet Android
# This script fixes all common build issues

set -e

echo "========================================"
echo "  Octra Wallet Android - Build Fix"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Stop all Gradle daemons
echo -e "${YELLOW}[1/6] Stopping Gradle daemons...${NC}"
./gradlew --stop || true
sleep 2

# Step 2: Clean all build directories
echo -e "${YELLOW}[2/6] Cleaning build directories...${NC}"
rm -rf app/build
rm -rf build
rm -rf .gradle
rm -rf ~/.gradle/caches/build-cache-*
echo "  ✓ Cleaned"

# Step 3: Verify Java version
echo -e "${YELLOW}[3/6] Checking Java version...${NC}"
JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
if [ "$JAVA_VERSION" -eq 17 ]; then
    echo -e "  ${GREEN}✓ Java 17 detected${NC}"
elif [ "$JAVA_VERSION" -gt 17 ]; then
    echo -e "  ${YELLOW}⚠ Java $JAVA_VERSION detected (Java 17 recommended)${NC}"
else
    echo -e "  ${RED}✗ Java $JAVA_VERSION detected (Java 17+ required)${NC}"
    exit 1
fi

# Step 4: Verify Android SDK
echo -e "${YELLOW}[4/6] Checking Android SDK...${NC}"
if [ -z "$ANDROID_HOME" ]; then
    echo -e "  ${RED}✗ ANDROID_HOME not set${NC}"
    exit 1
else
    echo -e "  ${GREEN}✓ Android SDK: $ANDROID_HOME${NC}"
fi

# Step 5: Download Gradle wrapper
echo -e "${YELLOW}[5/6] Verifying Gradle wrapper...${NC}"
if [ ! -f "./gradlew" ]; then
    echo -e "  ${RED}✗ gradlew not found${NC}"
    exit 1
else
    chmod +x gradlew
    echo -e "  ${GREEN}✓ Gradle wrapper ready${NC}"
fi

# Step 6: Build APK
echo -e "${YELLOW}[6/6] Building debug APK...${NC}"
echo ""
./gradlew assembleDebug --no-daemon --stacktrace

# Check build result
if [ -f "app/build/outputs/apk/debug/app-debug.apk" ]; then
    echo ""
    echo "========================================"
    echo -e "  ${GREEN}✓ BUILD SUCCESSFUL${NC}"
    echo "========================================"
    echo ""
    echo "APK location: app/build/outputs/apk/debug/app-debug.apk"
    APK_SIZE=$(du -h app/build/outputs/apk/debug/app-debug.apk | cut -f1)
    echo "APK size: $APK_SIZE"
    echo ""
    echo "To install on device:"
    echo "  adb install -r app/build/outputs/apk/debug/app-debug.apk"
    echo ""
else
    echo ""
    echo "========================================"
    echo -e "  ${RED}✗ BUILD FAILED${NC}"
    echo "========================================"
    echo ""
    echo "Check the error messages above."
    exit 1
fi
