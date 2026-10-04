#!/usr/bin/env bash
# =============================================================================
# build-ios.sh — Build Octra Wallet iOS IPA / App
# =============================================================================
# Usage:
#   ./build-ios.sh              Build release IPA  (requires Apple signing)
#   ./build-ios.sh --debug      Build debug iOS app (no codesign, simulator)
#   ./build-ios.sh --device     Build release iOS app for physical device
#
# Note: build cache (flutter clean + CocoaPods) is cleaned automatically before every build.
#
# Environment overrides (optional):
#   FLUTTER_BIN     — path to the flutter binary
#   FLUTTER_CHANNEL — Flutter channel to install if missing (default: stable)
#   FLUTTER_VERSION — specific Flutter version tag to clone (e.g. 3.24.3)
#
# Requirements:
#   - macOS with Xcode installed and accepted license
#   - Apple developer certificates for release / IPA builds
#
# Output:
#   build/ios/ipa/           (release IPA)
#   build/ios/Debug-iphoneos/ (debug)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_VERSION="${FLUTTER_VERSION:-}"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[build-ios]${RESET} $*"; }
warn() { echo -e "${YELLOW}[build-ios] ⚠ $*${RESET}"; }
ok()   { echo -e "${GREEN}[build-ios] ✔ $*${RESET}"; }
err()  { echo -e "${RED}[build-ios] ✘ $*${RESET}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Platform check ────────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || err "iOS builds require macOS. Use build-apk.sh for Android on Linux."

# ── Flags ─────────────────────────────────────────────────────────────────────
MODE="ipa"

for arg in "$@"; do
  case "$arg" in
    --debug)    MODE="debug" ;;
    --device)   MODE="device" ;;
    --help|-h)
      sed -n '/^# ====/,/^# ====/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) err "Unknown flag: $arg. Use --debug | --device" ;;
  esac
done

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
    # macOS Homebrew
    "/usr/local/Caskroom/flutter/*/flutter/bin/flutter"
    "$HOME/fvm/default/bin/flutter"
  )
  for c in "${candidates[@]}"; do
    # Support glob expansion for Homebrew paths
    for expanded in $c; do
      [[ -x "$expanded" ]] && { echo "$expanded"; return 0; }
    done
  done
  return 1
}

FLUTTER="$(_find_flutter 2>/dev/null || true)"

# ═══════════════════════════════════════════════════════════════════════════════
# 2.  AUTO-INSTALL FLUTTER (if not found)
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -z "$FLUTTER" ]]; then
  step "Flutter not found — installing automatically"
  FLUTTER_INSTALL_DIR="$HOME/flutter"

  if [[ -d "$FLUTTER_INSTALL_DIR" ]] && [[ ! -x "$FLUTTER_INSTALL_DIR/bin/flutter" ]]; then
    warn "Removing broken Flutter directory and re-cloning..."
    rm -rf "$FLUTTER_INSTALL_DIR"
  fi

  if [[ ! -d "$FLUTTER_INSTALL_DIR" ]]; then
    log "Cloning Flutter ($FLUTTER_CHANNEL) into $FLUTTER_INSTALL_DIR ..."
    command -v git &>/dev/null || {
      log "Installing git via Homebrew...";
      command -v brew &>/dev/null || err "git not found and Homebrew unavailable. Install git manually."
      brew install git
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
"$FLUTTER" --version 2>&1 | head -1

# ═══════════════════════════════════════════════════════════════════════════════
# 3.  XCODE CHECK
# ═══════════════════════════════════════════════════════════════════════════════
step "Checking Xcode"

command -v xcodebuild &>/dev/null || \
  err "Xcode not found. Install Xcode from the App Store, then run: sudo xcode-select --install"

XCODE_VER=$(xcodebuild -version 2>&1 | head -1)
ok "Xcode: $XCODE_VER"

# Accept Xcode license if not yet done
if ! xcodebuild -license status &>/dev/null 2>&1; then
  log "Accepting Xcode license (may prompt for sudo)..."
  sudo xcodebuild -license accept 2>/dev/null || \
    warn "Could not auto-accept Xcode license — run: sudo xcodebuild -license accept"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 4.  COCOAPODS CHECK
# ═══════════════════════════════════════════════════════════════════════════════
step "Checking CocoaPods"

if ! command -v pod &>/dev/null; then
  warn "CocoaPods not found — installing..."
  if command -v brew &>/dev/null; then
    brew install cocoapods
  else
    sudo gem install cocoapods || \
      err "Cannot install CocoaPods. Run: sudo gem install cocoapods"
  fi
fi
ok "CocoaPods: $(pod --version 2>/dev/null)"

# ═══════════════════════════════════════════════════════════════════════════════
# 5.  FLUTTER PRECACHE
# ═══════════════════════════════════════════════════════════════════════════════
step "Flutter precache (iOS)"
"$FLUTTER" precache --ios 2>/dev/null || true
ok "Precache done."

# ═══════════════════════════════════════════════════════════════════════════════
# 6.  PROJECT DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════════
step "Project dependencies"
log "Project: $PROJECT_DIR"
cd "$PROJECT_DIR"

log "Cleaning build cache (flutter clean + CocoaPods)..."
"$FLUTTER" clean
log "Removing Pods..."
rm -rf ios/Pods ios/Podfile.lock 2>/dev/null || true
ok "Clean done."

log "Running flutter pub get..."
"$FLUTTER" pub get
ok "Dependencies resolved."

log "Installing CocoaPods (ios/)..."
(cd ios && pod install --repo-update 2>/dev/null) || \
  warn "pod install failed — you may need to run it manually in ios/"

# ═══════════════════════════════════════════════════════════════════════════════
# 7.  AUTO-INCREMENT VERSION
# ═══════════════════════════════════════════════════════════════════════════════
step "Version bump"

PUBSPEC="$PROJECT_DIR/pubspec.yaml"
CURRENT_VER=$(grep '^version:' "$PUBSPEC" | sed 's/version:[[:space:]]*//')
BUILD_NAME="${CURRENT_VER%%+*}"
OLD_BUILD="${CURRENT_VER##*+}"
BUILD_NUMBER=$(( OLD_BUILD + 1 ))

sed -i "s/^version:.*/version: ${BUILD_NAME}+${BUILD_NUMBER}/" "$PUBSPEC"
ok "Version: ${BUILD_NAME}+${BUILD_NUMBER}  (was +${OLD_BUILD})"

# ═══════════════════════════════════════════════════════════════════════════════
# 8.  BUILD
# ═══════════════════════════════════════════════════════════════════════════════
step "Building iOS  [mode: $MODE]"

case "$MODE" in
  ipa)
    log "Building release IPA..."
    "$FLUTTER" build ipa --release \
      --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
    OUTPUT="$PROJECT_DIR/build/ios/ipa"
    echo ""
    ok "IPA written to: $OUTPUT"
    ls -lh "$OUTPUT"/*.ipa 2>/dev/null || true
    ;;
  device)
    log "Building release iOS app for physical device..."
    "$FLUTTER" build ios --release \
      --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
    echo ""
    ok "Build complete. Open Xcode to archive and distribute."
    ;;
  debug)
    log "Building debug iOS app (no codesign)..."
    "$FLUTTER" build ios --debug --no-codesign \
      --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
    echo ""
    ok "Debug build written to: $PROJECT_DIR/build/ios/Debug-iphoneos/"
    ;;
esac

echo ""
ok "All done!"
