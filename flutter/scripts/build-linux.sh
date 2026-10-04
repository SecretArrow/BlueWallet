#!/usr/bin/env bash
# =============================================================================
# build-linux.sh — Build Octra Wallet Linux Desktop App
# =============================================================================
# Usage:
#   ./build-linux.sh              Build release Linux bundle
#   ./build-linux.sh --debug      Build debug Linux bundle
#
# Note: build cache is cleaned automatically before every build.
#
# Environment overrides (optional):
#   FLUTTER_BIN     — path to the flutter binary
#   FLUTTER_CHANNEL — Flutter channel to install if missing (default: stable)
#   FLUTTER_VERSION — specific Flutter version tag to clone (e.g. 3.24.3)
#
# Requirements:
#   - gcc / g++ (GCC 9+)
#   - cmake (3.13+)
#   - libgtk-3-dev
#   - libssl-dev  (OpenSSL)
#   - pkg-config
#   Install on Ubuntu/Debian:
#     sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
#                      libssl-dev libblkid-dev liblzma-dev
#
# Output:
#   build/linux/x64/release/bundle/    (release)
#   build/linux/x64/debug/bundle/      (debug)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_VERSION="${FLUTTER_VERSION:-}"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[build-linux]${RESET} $*"; }
warn() { echo -e "${YELLOW}[build-linux] ⚠ $*${RESET}"; }
ok()   { echo -e "${GREEN}[build-linux] ✔ $*${RESET}"; }
err()  { echo -e "${RED}[build-linux] ✘ $*${RESET}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Flags ─────────────────────────────────────────────────────────────────────
MODE="release"

for arg in "$@"; do
  case "$arg" in
    --debug)  MODE="debug" ;;
    --help|-h)
      sed -n '/^# ====/,/^# ====/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) err "Unknown flag: $arg. Use --debug" ;;
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
  step "Flutter not found — installing automatically"
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
"$FLUTTER" --version 2>&1 | head -1

# ═══════════════════════════════════════════════════════════════════════════════
# 3.  SYSTEM DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════════
step "Checking system dependencies"

MISSING=()
for pkg in cmake ninja-build pkg-config; do
  command -v "$pkg" &>/dev/null || MISSING+=("$pkg")
done

# Check for GTK, OpenSSL, and libsecret pkg-config modules
pkg-config --exists gtk+-3.0 2>/dev/null   || MISSING+=("libgtk-3-dev")
pkg-config --exists openssl 2>/dev/null    || MISSING+=("libssl-dev")
pkg-config --exists libsecret-1 2>/dev/null || MISSING+=("libsecret-1-dev")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  warn "Missing dependencies: ${MISSING[*]}"
  if command -v apt-get &>/dev/null; then
    log "Installing via apt-get..."
    sudo apt-get install -y clang lld cmake ninja-build pkg-config \
      libgtk-3-dev libssl-dev libblkid-dev liblzma-dev \
      libsecret-1-dev libjsoncpp-dev libsqlite3-dev 2>/dev/null || \
      err "apt-get install failed. Install manually: ${MISSING[*]}"
  else
    err "Cannot auto-install. Install manually: ${MISSING[*]}"
  fi
fi
ok "Dependencies satisfied."

# ═══════════════════════════════════════════════════════════════════════════════
# 4.  FLUTTER PRECACHE
# ═══════════════════════════════════════════════════════════════════════════════
step "Flutter precache (Linux)"
"$FLUTTER" precache --linux 2>/dev/null || true
ok "Precache done."

# ═══════════════════════════════════════════════════════════════════════════════
# 5.  PROJECT DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════════
step "Project dependencies"
log "Project: $PROJECT_DIR"
cd "$PROJECT_DIR"

log "Cleaning build cache..."
"$FLUTTER" clean
ok "Clean done."

log "Running flutter pub get..."
"$FLUTTER" pub get
ok "Dependencies resolved."

# ═══════════════════════════════════════════════════════════════════════════════
# 6.  AUTO-INCREMENT VERSION
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
# 7.  BUILD
# ═══════════════════════════════════════════════════════════════════════════════
step "Building Linux bundle  [mode: $MODE]"

if [[ "$MODE" == "debug" ]]; then
  "$FLUTTER" build linux --debug \
    --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
  OUTPUT_DIR="$PROJECT_DIR/build/linux/x64/debug/bundle"
else
  "$FLUTTER" build linux --release \
    --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
  OUTPUT_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
fi

echo ""
ok "Bundle written to: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR" 2>/dev/null || true

echo ""
ok "All done!"
