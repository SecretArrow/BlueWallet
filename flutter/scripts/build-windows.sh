#!/usr/bin/env bash
# =============================================================================
# build-windows.sh — Build Octra Wallet Windows Desktop App (Fast Build)
# =============================================================================
# Run this script from:
#   - Windows with MSYS2 / Git Bash / WSL2 (cross-compile not supported)
#   - A Windows machine with Flutter and Visual Studio 2022 installed
#
# Usage:
#   ./build-windows.sh              Build release Windows bundle (incremental)
#   ./build-windows.sh --debug      Build debug Windows bundle (incremental)
#   ./build-windows.sh --force      Force full clean before build (slower)
#
# Note: Build cache is NOT cleaned by default for faster builds.
#       Use --force to perform full clean.
#
# Environment overrides (optional):
#   FLUTTER_BIN     — path to the flutter binary
#   FLUTTER_CHANNEL — Flutter channel to install if missing (default: stable)
#   FLUTTER_VERSION — specific Flutter version tag to clone (e.g. 3.24.3)
#
# Requirements (Windows):
#   - Visual Studio 2022 (with "Desktop development with C++" workload)
#     OR MSYS2 with mingw-w64-x86_64-gcc + mingw-w64-x86_64-openssl
#   - CMake 3.14+
#   - Flutter SDK
#
# Output:
#   build\windows\x64\runner\Release\    (release)
#   build\windows\x64\runner\Debug\      (debug)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_VERSION="${FLUTTER_VERSION:-}"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[build-windows]${RESET} $*"; }
warn() { echo -e "${YELLOW}[build-windows] ⚠ $*${RESET}"; }
ok()   { echo -e "${GREEN}[build-windows] ✔ $*${RESET}"; }
err()  { echo -e "${RED}[build-windows] ✘ $*${RESET}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Platform guard ────────────────────────────────────────────────────────────
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT) : ;;  # OK
  *)
    err "Windows builds must be run on Windows (MSYS2, Git Bash, or native CMD/PowerShell). Current OS: $(uname -s)"
    ;;
esac

# ── Flags ─────────────────────────────────────────────────────────────────────
MODE="release"
FORCE_CLEAN=false

for arg in "$@"; do
  case "$arg" in
    --debug)  MODE="debug" ;;
    --force)  FORCE_CLEAN=true ;;
    --help|-h)
      sed -n '/^# ====/,/^# ====/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) err "Unknown flag: $arg. Use --debug | --force" ;;
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
    "/c/flutter/bin/flutter"
    "/c/src/flutter/bin/flutter"
    "$LOCALAPPDATA/flutter/bin/flutter"
    "$PROGRAMFILES/flutter/bin/flutter"
  )
  for c in "${candidates[@]}"; do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

FLUTTER="$(_find_flutter 2>/dev/null || true)"

# ═══════════════════════════════════════════════════════════════════════════════
# 2.  AUTO-INSTALL FLUTTER (if not found, via git)
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
    command -v git &>/dev/null || err "git not found. Install Git for Windows from https://git-scm.com"
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
# 3.  VISUAL STUDIO / CMAKE CHECK
# ═══════════════════════════════════════════════════════════════════════════════
step "Checking build tools"

if ! command -v cmake &>/dev/null; then
  err "CMake not found. Install from https://cmake.org or via 'winget install Kitware.CMake'"
fi
ok "CMake: $(cmake --version | head -1)"

# Flutter on Windows requires Visual Studio 2022 or MSYS2 toolchain.
if command -v cl &>/dev/null; then
  ok "MSVC compiler found."
elif command -v g++ &>/dev/null; then
  ok "MinGW g++ found: $(g++ --version | head -1)"
else
  warn "No C++ compiler detected. Ensure Visual Studio 2022 (with C++ workload) or MSYS2 mingw64 is in PATH."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 4.  FLUTTER PRECACHE
# ═══════════════════════════════════════════════════════════════════════════════
step "Flutter precache (Windows)"
"$FLUTTER" precache --windows 2>/dev/null || true
ok "Precache done."

# ═══════════════════════════════════════════════════════════════════════════════
# 5.  PROJECT DEPENDENCIES (INCREMENTAL BY DEFAULT)
# ═══════════════════════════════════════════════════════════════════════════════
step "Project dependencies"
log "Project: $PROJECT_DIR"
cd "$PROJECT_DIR"

if [[ "$FORCE_CLEAN" == true ]]; then
  log "Full clean requested with --force..."
  "$FLUTTER" clean
  ok "Clean done."
else
  log "Using incremental build (skip clean)"
fi

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
step "Building Windows app  [mode: $MODE]"

if [[ "$MODE" == "debug" ]]; then
  "$FLUTTER" build windows --debug \
    --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
  OUTPUT_DIR="$PROJECT_DIR/build/windows/x64/runner/Debug"
else
  "$FLUTTER" build windows --release \
    --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
  OUTPUT_DIR="$PROJECT_DIR/build/windows/x64/runner/Release"
fi

echo ""
ok "Bundle written to: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR" 2>/dev/null || true

echo ""
echo "Build Summary:"
echo "  Mode     : $MODE"
echo "  Clean    : $(if [[ "$FORCE_CLEAN" == true ]]; then echo "Full (--force)"; else echo "Incremental (fast)"; fi)"
echo ""
echo "Tip: For faster builds, omit --force flag"
echo "     Use --force only when you suspect build issues"

echo ""
ok "All done!"
