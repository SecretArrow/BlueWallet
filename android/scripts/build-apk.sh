#!/bin/bash

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
# Usage: ./build-apk.sh [debug|release] [--split-abi] [--force] [--no-daemon] [--arm64-v8a|--x86_64|--universal]
BUILD_TYPE="debug"
SPLIT_ABI=false
FORCE_CLEAN=false
NO_DAEMON=false
TARGET_ABI=""

for arg in "$@"; do
    case "$arg" in
        debug|release) BUILD_TYPE="$arg" ;;
        --split-abi)   SPLIT_ABI=true ;;
        --force)       FORCE_CLEAN=true ;;
        --no-daemon)   NO_DAEMON=true ;;
        --arm64-v8a)   TARGET_ABI="arm64-v8a" ;;
        --x86_64)      TARGET_ABI="x86_64" ;;
        --universal)   TARGET_ABI="universal" ;;
        --help|-h)
            echo "Usage: ./build-apk.sh [debug|release] [--split-abi] [--force] [--no-daemon] [--arm64-v8a|--x86_64|--universal]"
            echo ""
            echo "Options:"
            echo "  debug|release  Build type (default: debug)"
            echo "  --split-abi    Build separate APKs for each CPU architecture"
            echo "  --arm64-v8a    Build only for arm64-v8a architecture"
            echo "  --x86_64       Build only for x86_64 architecture"
            echo "  --universal    Build universal APK (all architectures)"
            echo "  --force        Force full clean before build (slower)"
            echo "  --no-daemon    Disable Gradle daemon (for CI/CD)"
            echo ""
            echo "Examples:"
            echo "  ./build-apk.sh release                    # Fast incremental build"
            echo "  ./build-apk.sh release --arm64-v8a        # Build only arm64"
            echo "  ./build-apk.sh release --split-abi        # Split-ABI release"
            echo "  ./build-apk.sh release --force            # Full clean build"
            exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ANDROID_DIR/build-logs"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/build-${BUILD_TYPE}-${TIMESTAMP}.log"
SDK_PLATFORM="android-35"
SDK_BUILD_TOOLS="35.0.0"
SDK_NDK="27.3.13750724"
CMDLINE_TOOLS_VERSION="13114758"

mkdir -p "$LOG_DIR"
ln -sfn "$(basename "$LOG_FILE")" "$LOG_DIR/latest-${BUILD_TYPE}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

on_exit() {
    local status=$?
    echo ""
    if [ "$status" -eq 0 ]; then
        echo "Build log saved at: $LOG_FILE"
        echo ""
        echo "=== Build Successful ==="
        echo "Tip: For faster builds, omit --force flag"
        echo "     Use --force only when you suspect build issues"
    else
        echo "Build failed. Log saved at: $LOG_FILE"
        echo ""
        echo "=== Error Summary ==="
        grep -n "error:\|FAILED\|Execution failed for task" "$LOG_FILE" | head -n 20 || true
        echo "====================="
    fi
}

trap on_exit EXIT

# ── Auto-increment version (release only) ─────────────────────────────────────
increment_version() {
    if [ "$BUILD_TYPE" != "release" ]; then
        return 0
    fi
    
    local props="$ANDROID_DIR/version.properties"
    [[ -f "$props" ]] || return 0

    local current_code current_name new_code new_name
    current_code="$(grep -E '^VERSION_CODE=' "$props" | cut -d= -f2 | tr -d '[:space:]')"
    current_name="$(grep -E '^VERSION_NAME=' "$props" | cut -d= -f2 | tr -d '[:space:]')"

    # Bump VERSION_CODE
    new_code=$(( current_code + 1 ))

    # Bump patch segment in VERSION_NAME
    local base suffix patch
    base="${current_name%%-*}"
    suffix="${current_name#"$base"}"
    patch="${base##*.}"
    local prefix="${base%.*}"
    new_name="${prefix}.$((patch + 1))${suffix}"

    {
        echo "VERSION_CODE=${new_code}"
        echo "VERSION_NAME=${new_name}"
    } > "$props"

    echo "Version bumped: ${current_name} (${current_code}) → ${new_name} (${new_code})"
}

# ── Selective clean (incremental by default) ──────────────────────────────────
selective_clean() {
    echo ""
    if [ "$FORCE_CLEAN" = true ]; then
        echo "=== Full Clean Cache (requested with --force) ==="
        cd "$ANDROID_DIR"

        echo "Running: gradlew clean..."
        ./gradlew clean --no-daemon --quiet || true

        echo "Deleting Gradle build caches..."
        rm -rf "$ANDROID_DIR/.gradle"
        rm -rf "$ANDROID_DIR/app/build"
        rm -rf "$ANDROID_DIR/.cxx"
        rm -rf "$ANDROID_DIR/app/.cxx"
        rm -rf "$ANDROID_DIR/app/.externalNativeBuild"
        rm -rf "$HOME/.gradle/caches/build-cache-*"
        rm -rf "$HOME/.gradle/caches/transforms-*"
        rm -rf "$HOME/.gradle/caches/modules-*/files-*/*/[0-9]*"  2>/dev/null || true

        echo "Full clean complete."
    else
        echo "=== Incremental Clean (fast build) ==="
        # Only clean app/build, preserve .gradle cache
        if [ -d "$ANDROID_DIR/app/build" ]; then
            echo "Cleaning app/build only (preserving .gradle cache)..."
            rm -rf "$ANDROID_DIR/app/build"
            echo "Incremental clean done."
        else
            echo "No previous build found, skipping clean."
        fi
    fi
    echo ""
}

# ── SDK/Java setup helpers ────────────────────────────────────────────────────
apt_install_if_missing() {
    local pkg="$1"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        return 0
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        return 1
    fi
    if command -v sudo >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "$pkg"
    else
        apt-get update
        apt-get install -y "$pkg"
    fi
}

ensure_download_tools() {
    command -v unzip >/dev/null 2>&1 || apt_install_if_missing unzip || true
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        apt_install_if_missing curl || true
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        echo "Error: unzip is required to bootstrap Android SDK"
        exit 1
    fi
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo "Error: curl or wget is required to bootstrap Android SDK"
        exit 1
    fi
}

download_file() {
    local url="$1"
    local out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL "$url" -o "$out"
    else
        wget -O "$out" "$url"
    fi
}

bootstrap_android_sdk() {
    local preferred_dir="$HOME/android-sdk"
    local tools_zip="$preferred_dir/cmdline-tools.zip"
    local tools_dir="$preferred_dir/cmdline-tools"
    local legacy_url="https://dl.google.com/android/repository/commandlinetools-linux-latest.zip"
    local pinned_url="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"

    echo "Android SDK not found. Bootstrapping to: $preferred_dir"
    ensure_download_tools

    mkdir -p "$preferred_dir"

    echo "Downloading Android command-line tools..."
    if ! download_file "$pinned_url" "$tools_zip"; then
        download_file "$legacy_url" "$tools_zip"
    fi

    rm -rf "$tools_dir"
    mkdir -p "$tools_dir"
    unzip -q "$tools_zip" -d "$tools_dir"
    rm -f "$tools_zip"

    if [ -d "$tools_dir/cmdline-tools" ]; then
        mv "$tools_dir/cmdline-tools" "$tools_dir/latest"
    fi

    SDK_DIR="$preferred_dir"
}

ensure_java() {
    if command -v java >/dev/null 2>&1; then
        return 0
    fi

    echo "Java not found. Installing OpenJDK 17..."
    if command -v apt-get >/dev/null 2>&1; then
        if command -v sudo >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y openjdk-17-jdk
        else
            apt-get update
            apt-get install -y openjdk-17-jdk
        fi
    else
        echo "Error: Java 17 is required but automatic install is not supported on this system."
        echo "Please install OpenJDK 17 manually and re-run this script."
        exit 1
    fi
}

ensure_java_home() {
    if [ -z "${JAVA_HOME:-}" ]; then
        local java_bin
        java_bin="$(command -v java || true)"
        if [ -n "$java_bin" ]; then
            local resolved
            resolved="$(readlink -f "$java_bin" || true)"
            if [ -n "$resolved" ]; then
                JAVA_HOME="$(dirname "$(dirname "$resolved")")"
                export JAVA_HOME
            fi
        fi
    fi

    if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
        echo "Error: JAVA_HOME is not set correctly."
        echo "Please export JAVA_HOME to your JDK 17 path and re-run."
        exit 1
    fi
}

ensure_sdk_components() {
    local sdkmanager=""
    if [ -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]; then
        sdkmanager="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
    elif [ -x "$SDK_DIR/tools/bin/sdkmanager" ]; then
        sdkmanager="$SDK_DIR/tools/bin/sdkmanager"
    fi

    if [ -z "$sdkmanager" ]; then
        echo "Warning: sdkmanager not found, skipping automatic SDK component installation"
        return 0
    fi

    echo "Accepting Android SDK licenses..."
    set +o pipefail
    yes | "$sdkmanager" --sdk_root="$SDK_DIR" --licenses >/dev/null
    set -o pipefail

    echo "Ensuring Android SDK components are installed..."
    "$sdkmanager" --sdk_root="$SDK_DIR" --install \
        "platform-tools" \
        "platforms;$SDK_PLATFORM" \
        "build-tools;$SDK_BUILD_TOOLS" \
        "cmake;3.22.1" \
        "ndk;$SDK_NDK"
}

# ── Main build script ─────────────────────────────────────────────────────────
echo ""
echo "=== Octra Wallet Android Build Script (Fast) ==="
echo "Build type  : $BUILD_TYPE"
echo "Split ABI   : $SPLIT_ABI"
echo "Target ABI  : ${TARGET_ABI:-all}"
echo "Force clean : $FORCE_CLEAN"
echo "No daemon   : $NO_DAEMON"
echo "Build log   : $LOG_FILE"
echo ""

SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

if [ -z "$SDK_DIR" ]; then
    if [ -d "$HOME/Android/Sdk" ]; then
        SDK_DIR="$HOME/Android/Sdk"
    elif [ -d "$HOME/android-sdk" ]; then
        SDK_DIR="$HOME/android-sdk"
    elif [ -d "/opt/android-sdk" ]; then
        SDK_DIR="/opt/android-sdk"
    fi
fi

if [ -z "$SDK_DIR" ] || [ ! -d "$SDK_DIR" ]; then
    bootstrap_android_sdk
fi

export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"

echo "Using Android SDK: $SDK_DIR"

ensure_java
ensure_java_home

echo "Using JAVA_HOME: $JAVA_HOME"
java -version

if [ -f "$ANDROID_DIR/local.properties" ]; then
    if grep -q '^sdk.dir=' "$ANDROID_DIR/local.properties"; then
        sed -i "s|^sdk.dir=.*|sdk.dir=$SDK_DIR|" "$ANDROID_DIR/local.properties"
    else
        echo "sdk.dir=$SDK_DIR" >> "$ANDROID_DIR/local.properties"
    fi
    echo "Updated local.properties"
else
    echo "sdk.dir=$SDK_DIR" > "$ANDROID_DIR/local.properties"
    echo "Created local.properties"
fi

ensure_sdk_components

if [ ! -f "$ANDROID_DIR/gradlew" ]; then
    echo "Creating Gradle wrapper..."
    cd "$ANDROID_DIR"
    gradle wrapper --gradle-version 8.10.2 || {
        echo "Error: Failed to create Gradle wrapper"
        echo "Make sure Gradle is installed: https://gradle.org/install/"
        exit 1
    }
fi

chmod +x "$ANDROID_DIR/gradlew"

cd "$ANDROID_DIR"

# Auto-increment version (release only)
increment_version

# Selective clean (incremental by default)
selective_clean

echo "Building ${BUILD_TYPE} APK (split-abi=${SPLIT_ABI})..."
echo ""

# Build Gradle extra args
GRADLE_EXTRA_ARGS=()
if $SPLIT_ABI; then
    GRADLE_EXTRA_ARGS+=("-PsplitAbi=true")
fi
if [ -n "$TARGET_ABI" ] && [ "$TARGET_ABI" != "universal" ]; then
    GRADLE_EXTRA_ARGS+=("-PabiFilters=$TARGET_ABI")
fi

# Use daemon by default for faster builds (unless --no-daemon is specified)
if $NO_DAEMON; then
    GRADLE_EXTRA_ARGS+=("--no-daemon")
    echo "Using: gradlew (no daemon)"
else
    echo "Using: gradlew (with daemon for faster builds)"
fi

if [ "$BUILD_TYPE" = "release" ]; then
    if [ -f "$ANDROID_DIR/keystore.properties" ]; then
        echo "Using signing configuration from keystore.properties"
    else
        echo "Warning: keystore.properties not found, building unsigned release APK"
    fi
    ./gradlew assembleRelease --stacktrace "${GRADLE_EXTRA_ARGS[@]}"
else
    ./gradlew assembleDebug --stacktrace "${GRADLE_EXTRA_ARGS[@]}"
fi

# ── Verify APKs were built ────────────────────────────────────────────────────
GRADLE_RELEASE_DIR="$ANDROID_DIR/app/build/outputs/apk/release"
GRADLE_DEBUG_DIR="$ANDROID_DIR/app/build/outputs/apk/debug"

FOUND_APKS=()

# Validate mutually exclusive flags
if [ -n "$TARGET_ABI" ] && [ "$SPLIT_ABI" = true ]; then
    echo "Error: --arm64-v8a/--x86_64/--universal cannot be used with --split-abi" >&2
    exit 1
fi

if [ "$BUILD_TYPE" = "release" ]; then
    if [ -n "$TARGET_ABI" ] && [ "$TARGET_ABI" != "universal" ]; then
        for candidate in \
            "$GRADLE_RELEASE_DIR/app-${TARGET_ABI}-release.apk" \
            "$GRADLE_RELEASE_DIR/app-${TARGET_ABI}-release-unsigned.apk"; do
            [ -f "$candidate" ] && {
                FOUND_APKS+=("$candidate")
                break
            }
        done
    elif [ "$TARGET_ABI" = "universal" ]; then
        for candidate in \
            "$GRADLE_RELEASE_DIR/app-release.apk" \
            "$GRADLE_RELEASE_DIR/app-release-unsigned.apk"; do
            [ -f "$candidate" ] && {
                FOUND_APKS+=("$candidate")
                break
            }
        done
    elif $SPLIT_ABI; then
        for abi in arm64-v8a x86_64; do
            src="$GRADLE_RELEASE_DIR/app-${abi}-release.apk"
            if [ ! -f "$src" ]; then
                src="$GRADLE_RELEASE_DIR/app-${abi}-release-unsigned.apk"
            fi
            if [ -f "$src" ]; then
                FOUND_APKS+=("$src")
            fi
        done
        for candidate in \
            "$GRADLE_RELEASE_DIR/app-universal-release.apk" \
            "$GRADLE_RELEASE_DIR/app-release.apk" \
            "$GRADLE_RELEASE_DIR/app-release-unsigned.apk"; do
            [ -f "$candidate" ] && {
                FOUND_APKS+=("$candidate")
                break
            }
        done
    else
        for candidate in \
            "$GRADLE_RELEASE_DIR/app-release.apk" \
            "$GRADLE_RELEASE_DIR/app-release-unsigned.apk"; do
            [ -f "$candidate" ] && {
                FOUND_APKS+=("$candidate")
                break
            }
        done
    fi
else
    if [ -n "$TARGET_ABI" ] && [ "$TARGET_ABI" != "universal" ]; then
        src="$GRADLE_DEBUG_DIR/app-${TARGET_ABI}-debug.apk"
        [ -f "$src" ] && FOUND_APKS+=("$src")
    elif $SPLIT_ABI; then
        for abi in arm64-v8a x86_64; do
            src="$GRADLE_DEBUG_DIR/app-${abi}-debug.apk"
            if [ -f "$src" ]; then
                FOUND_APKS+=("$src")
            fi
        done
    else
        if [ -f "$GRADLE_DEBUG_DIR/app-debug.apk" ]; then
            FOUND_APKS+=("$GRADLE_DEBUG_DIR/app-debug.apk")
        fi
    fi
fi

# Double-check APK existence with absolute path
if [ ${#FOUND_APKS[@]} -eq 0 ]; then
    # Try to find APKs directly
    if [ "$BUILD_TYPE" = "release" ]; then
        if [ -f "$ANDROID_DIR/app/build/outputs/apk/release/app-release-unsigned.apk" ]; then
            FOUND_APKS+=("$ANDROID_DIR/app/build/outputs/apk/release/app-release-unsigned.apk")
        elif [ -f "$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk" ]; then
            FOUND_APKS+=("$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk")
        fi
    else
        if [ -f "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" ]; then
            FOUND_APKS+=("$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk")
        fi
    fi
fi

if [ ${#FOUND_APKS[@]} -eq 0 ]; then
    echo ""
    echo "=== Build Failed ==="
    echo "No APKs found in $GRADLE_RELEASE_DIR or $GRADLE_DEBUG_DIR"
    echo "Checked paths:"
    echo "  - $GRADLE_RELEASE_DIR/app-release-unsigned.apk"
    echo "  - $GRADLE_RELEASE_DIR/app-release.apk"
    ls -la "$GRADLE_RELEASE_DIR" 2>/dev/null || echo "  Directory does not exist"
    exit 1
fi

echo ""
echo "=== Build Successful ==="
for apk in "${FOUND_APKS[@]}"; do
    echo "APK: $apk  ($(du -h "$apk" | cut -f1))"
done

# ── Auto-sign release APKs ────────────────────────────────────────────────────
if [ "$BUILD_TYPE" = "release" ]; then
    echo ""
    echo "=== Auto-signing release APKs ==="
    SIGN_SCRIPT="$SCRIPT_DIR/sign-apk.sh"
    if [ -f "$SIGN_SCRIPT" ]; then
        chmod +x "$SIGN_SCRIPT"
        bash "$SIGN_SCRIPT"
    else
        echo "Warning: sign-apk.sh not found at $SIGN_SCRIPT, skipping auto-sign"
    fi
fi
