#!/usr/bin/env bash
# =============================================================================
# build-apk.sh — Build Octra Wallet Android APK (Fast Build)
# =============================================================================
# Usage:
#   ./build-apk.sh              Build release APK (incremental)
#   ./build-apk.sh --debug      Build debug APK (incremental)
#   ./build-apk.sh --split-abi  Build release APKs split per ABI
#   ./build-apk.sh --install    Build release APK and install to connected device
#   ./build-apk.sh --force      Force full clean before build (slower)
#   ./build-apk.sh --no-daemon  Disable Flutter daemon (for CI/CD)
#   ./build-apk.sh --arm64-v8a       Build only for arm64-v8a architecture
#   ./build-apk.sh --armeabi-v7a     Build only for armeabi-v7a architecture
#   ./build-apk.sh --x86_64          Build only for x86_64 architecture
#   ./build-apk.sh --universal       Build universal APK (all architectures)
#
# Environment overrides (optional):
#   FLUTTER_BIN     — path to the flutter binary
#   ANDROID_HOME    — path to the Android SDK root
#   FLUTTER_CHANNEL — Flutter channel to install if missing (default: stable)
#   FLUTTER_VERSION — specific Flutter version tag to clone (e.g. 3.24.3)
#
# Output:
#   build/app/outputs/flutter-apk/
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_VERSION="${FLUTTER_VERSION:-}"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[build-apk]${RESET} $*"; }
warn() { echo -e "${YELLOW}[build-apk] * $*${RESET}"; }
ok()   { echo -e "${GREEN}[build-apk] + $*${RESET}"; }
err()  { echo -e "${RED}[build-apk] x $*${RESET}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}== $* ==${RESET}"; }

# ── Flags ─────────────────────────────────────────────────────────────────────
MODE="release"
SPLIT_ABI=false
INSTALL=false
FORCE_CLEAN=false
NO_DAEMON=false
TARGET_ABI=""

for arg in "$@"; do
  case "$arg" in
    --debug)        MODE="debug" ;;
    --split-abi)    SPLIT_ABI=true ;;
    --install)      INSTALL=true ;;
    --force)        FORCE_CLEAN=true ;;
    --no-daemon)    NO_DAEMON=true ;;
    --arm64-v8a)    TARGET_ABI="arm64-v8a" ;;
    --armeabi-v7a)  TARGET_ABI="armeabi-v7a" ;;
    --x86_64)       TARGET_ABI="x86_64" ;;
    --universal)    TARGET_ABI="universal" ;;
    --help|-h)
      sed -n '/^# ====/,/^# ====/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) err "Unknown flag: $arg. Use --debug | --split-abi | --arm64-v8a | --armeabi-v7a | --x86_64 | --universal | --install | --force | --no-daemon" ;;
  esac
done

# Validate mutually exclusive flags
if [ -n "$TARGET_ABI" ] && [ "$SPLIT_ABI" = true ]; then
  err "--arm64-v8a/--armeabi-v7a/--x86_64/--universal cannot be used with --split-abi"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 1.  AUTO-DETECT FLUTTER
# ═══════════════════════════════════════════════════════════════════════════════
step "Locating Flutter"

_find_flutter() {
  if [[ -n "${FLUTTER_BIN:-}" ]] && [[ -x "${FLUTTER_BIN}" ]]; then
    echo "$FLUTTER_BIN"; return 0
  fi
  if command -v flutter &>/dev/null; then
    echo "$(command -v flutter)"; return 0
  fi
  local candidates=(
    "$HOME/flutter/bin/flutter"
    "$HOME/development/flutter/bin/flutter"
    "$HOME/snap/flutter/common/flutter/bin/flutter"
    "/opt/flutter/bin/flutter"
    "/usr/local/flutter/bin/flutter"
    "/flutter/bin/flutter"
  )
  for c in "${candidates[@]}"; do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

FLUTTER="$(_find_flutter 2>/dev/null || true)"

# ═══════════════════════════════════════════════════════════════════════════════
# 2.  AUTO-INSTALL FLUTTER (if not found)
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -z "$FLUTTER" ]]; then
  step "Flutter not found - installing automatically"
  FLUTTER_INSTALL_DIR="$HOME/flutter"

  if [[ -d "$FLUTTER_INSTALL_DIR" ]] && [[ ! -x "$FLUTTER_INSTALL_DIR/bin/flutter" ]]; then
    warn "Removing broken Flutter directory and re-cloning..."
    rm -rf "$FLUTTER_INSTALL_DIR"
  fi

  if [[ ! -d "$FLUTTER_INSTALL_DIR" ]]; then
    log "Cloning Flutter ($FLUTTER_CHANNEL) into $FLUTTER_INSTALL_DIR ..."
    command -v git &>/dev/null || {
      log "Installing git...";
      sudo apt-get install -y git 2>/dev/null || err "Cannot install git."
    }
    if [[ -n "$FLUTTER_VERSION" ]]; then
      git clone --depth 1 --branch "$FLUTTER_VERSION" \
        https://github.com/flutter/flutter.git "$FLUTTER_INSTALL_DIR"
    else
      git clone --depth 1 --branch "$FLUTTER_CHANNEL" \
        https://github.com/flutter/flutter.git "$FLUTTER_INSTALL_DIR"
    fi
  fi
  FLUTTER="$FLUTTER_INSTALL_DIR/bin/flutter"
fi

[[ -x "$FLUTTER" ]] || err "Flutter binary not executable at '$FLUTTER'"
FLUTTER_ROOT="$(dirname "$(dirname "$FLUTTER")")"
export PATH="$FLUTTER_ROOT/bin:$PATH"
ok "Flutter: $FLUTTER"
"$FLUTTER" --version 2>&1 | head -1 || true

# ═══════════════════════════════════════════════════════════════════════════════
# 3.  CONFIGURE ANDROID SDK
# ═══════════════════════════════════════════════════════════════════════════════
step "Configuring Android SDK"

_find_android_sdk() {
  local candidates=(
    "${ANDROID_HOME:-}"
    "${ANDROID_SDK_ROOT:-}"
    "$HOME/android-sdk"
    "$HOME/Android/Sdk"
    "$HOME/Library/Android/sdk"
    "/opt/android-sdk"
    "/usr/lib/android-sdk"
  )
  for c in "${candidates[@]}"; do
    [[ -n "$c" ]] && [[ -d "$c/platform-tools" ]] && { echo "$c"; return 0; }
  done
  return 1
}

ANDROID_SDK="$(_find_android_sdk 2>/dev/null || true)"

if [[ -z "$ANDROID_SDK" ]]; then
  warn "Android SDK not found in common locations."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y android-sdk 2>/dev/null || true
    ANDROID_SDK="$(_find_android_sdk 2>/dev/null || true)"
  fi
  [[ -n "$ANDROID_SDK" ]] || err "Android SDK not found. Set ANDROID_HOME to the SDK path and re-run."
fi

export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_SDK_ROOT="$ANDROID_SDK"
export PATH="$ANDROID_SDK/platform-tools:$ANDROID_SDK/cmdline-tools/latest/bin:$PATH"
ok "Android SDK: $ANDROID_SDK"

# ═══════════════════════════════════════════════════════════════════════════════
# 4.  JAVA CHECK
# ═══════════════════════════════════════════════════════════════════════════════
step "Checking Java"

if ! command -v java &>/dev/null; then
  warn "Java not found - installing OpenJDK 17..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y openjdk-17-jdk 2>/dev/null || err "Cannot install Java."
  elif command -v brew &>/dev/null; then
    brew install --cask temurin@17 || err "Cannot install Java."
  else
    err "Java not found. Install JDK 17 manually and re-run."
  fi
fi
JAVA_VER="$(java -version 2>&1 | head -1 || true)"
ok "Java: $JAVA_VER"

# ═══════════════════════════════════════════════════════════════════════════════
# 5.  ACCEPT ANDROID LICENSES
# ═══════════════════════════════════════════════════════════════════════════════
step "Android licenses"

if [[ ! -f "$ANDROID_SDK/licenses/android-sdk-license" ]]; then
  log "Accepting SDK licenses..."
  yes | "$FLUTTER" doctor --android-licenses 2>/dev/null || \
    yes | sdkmanager --licenses 2>/dev/null || \
    warn "Could not auto-accept licenses - run 'flutter doctor --android-licenses' manually if the build fails."
else
  ok "Licenses already accepted."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 6.  FLUTTER PRECACHE
# ═══════════════════════════════════════════════════════════════════════════════
step "Flutter precache (Android)"
"$FLUTTER" precache --android 2>/dev/null || true
ok "Precache done."

# ═══════════════════════════════════════════════════════════════════════════════
# 7.  PROJECT DEPENDENCIES (INCREMENTAL BY DEFAULT)
# ═══════════════════════════════════════════════════════════════════════════════
step "Project dependencies"
log "Project: $PROJECT_DIR"
cd "$PROJECT_DIR"

if [[ "$FORCE_CLEAN" == true ]]; then
  log "Full clean requested with --force..."
  "$FLUTTER" clean
  rm -rf "$PROJECT_DIR/android/.gradle" "$PROJECT_DIR/android/build" 2>/dev/null || true
  ok "Full clean done"
else
  log "Using incremental build (skip clean)"
  # Only run pub get to ensure dependencies
  log "Running flutter pub get..."
  "$FLUTTER" pub get
  ok "Dependencies resolved"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 8.  READ VERSION
# ═══════════════════════════════════════════════════════════════════════════════
step "Version"

PUBSPEC="$PROJECT_DIR/pubspec.yaml"
CURRENT_VER=$(grep '^version:' "$PUBSPEC" | sed 's/version:[[:space:]]*//')
BUILD_NAME="${CURRENT_VER%%+*}"
BUILD_NUMBER="${CURRENT_VER##*+}"
ok "Version: ${BUILD_NAME}+${BUILD_NUMBER}"

# ═══════════════════════════════════════════════════════════════════════════════
# 9.  BUILD APK
# ═══════════════════════════════════════════════════════════════════════════════
step "Building APK  [mode: $MODE, target: ${TARGET_ABI:-all}]"

OUTPUT_DIR="$PROJECT_DIR/build/app/outputs/flutter-apk"

# Map target ABI to Flutter target-platform
abi_to_platform() {
  case "$1" in
    arm64-v8a)    echo "android-arm64" ;;
    armeabi-v7a)  echo "android-arm" ;;
    x86_64)       echo "android-x64" ;;
    *)            echo "" ;;
  esac
}

if [[ "$SPLIT_ABI" == true ]]; then
  log "Building split-ABI release APKs..."
  mkdir -p "$OUTPUT_DIR"

  ABI_MATRIX=(
    "android-arm:armeabi-v7a"
    "android-arm64:arm64-v8a"
    "android-x64:x86_64"
  )

  for entry in "${ABI_MATRIX[@]}"; do
    target_platform="${entry%%:*}"
    abi_name="${entry##*:}"

    log "Building $abi_name ..."
    "$FLUTTER" build apk --release --target-platform "$target_platform" \
      --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"

    src_apk="$OUTPUT_DIR/app-release.apk"
    dst_apk="$OUTPUT_DIR/app-${abi_name}-release.apk"
    [[ -f "$src_apk" ]] || err "Expected APK not found: $src_apk"

    cp -f "$src_apk" "$dst_apk"
    ok "Created $(basename "$dst_apk")"
  done
elif [[ -n "$TARGET_ABI" ]] && [[ "$TARGET_ABI" != "universal" ]]; then
  PLATFORM="$(abi_to_platform "$TARGET_ABI")"
  [[ -n "$PLATFORM" ]] || err "Unknown ABI: $TARGET_ABI"
  log "Building $TARGET_ABI APK (target-platform: $PLATFORM)..."
  if [[ "$MODE" == "debug" ]]; then
    "$FLUTTER" build apk --debug --target-platform "$PLATFORM" \
      --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
  else
    "$FLUTTER" build apk --release --target-platform "$PLATFORM" \
      --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
  fi
  src_apk="$OUTPUT_DIR/app-release.apk"
  [[ "$MODE" == "debug" ]] && src_apk="$OUTPUT_DIR/app-debug.apk"
  dst_apk="$OUTPUT_DIR/app-${TARGET_ABI}-${MODE}.apk"
  if [[ -f "$src_apk" ]]; then
    cp -f "$src_apk" "$dst_apk"
    ok "Created $(basename "$dst_apk")"
  fi
elif [[ "$MODE" == "debug" ]]; then
  log "Building debug APK..."
  "$FLUTTER" build apk --debug \
    --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
else
  log "Building release APK..."
  "$FLUTTER" build apk --release \
    --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
fi

echo ""
ok "APK(s) written to: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"/*.apk 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════════
# 10. OPTIONAL INSTALL
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$INSTALL" == true ]]; then
  step "Installing to device"
  if ! adb devices 2>/dev/null | grep -q "device$"; then
    warn "No device connected via adb. Connect a device with USB debugging enabled."
  else
    "$FLUTTER" install
    ok "Installed to device."
  fi
fi

echo ""
ok "All done!"

echo ""
echo "Build Summary:"
echo "  Mode     : $MODE"
echo "  Clean    : $(if [[ "$FORCE_CLEAN" == true ]]; then echo "Full (--force)"; else echo "Incremental (fast)"; fi)"
echo "  SplitAbi : $SPLIT_ABI"
echo "  Target   : ${TARGET_ABI:-all}"
echo ""
echo "Tip: For faster builds, omit --force flag"
echo "     Use --force only when you suspect build issues"
