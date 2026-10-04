#!/usr/bin/env bash
# =============================================================================
# sign-apk.sh — Sign Octra Wallet Android APKs (debug or release)
# =============================================================================
# Signs every APK produced by build-apk.sh (universal and split-ABI).
# Defaults to release; falls back to debug automatically if no release APKs
# are present. The signed APKs are written to the release/ folder.
#
# Usage:
#   ./sign-apk.sh                        # auto-detect build type
#   ./sign-apk.sh --build-type release   # force release
#   ./sign-apk.sh --build-type debug     # force debug
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ANDROID_DIR is the android/ project root — one level above this scripts/ folder
ANDROID_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ANDROID_DIR"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[sign-apk]${RESET} $*"; }
ok()   { echo -e "${GREEN}[sign-apk] ✔ $*${RESET}"; }
warn() { echo -e "${YELLOW}[sign-apk] ⚠ $*${RESET}"; }
err()  { echo -e "${RED}[sign-apk] ✘ $*${RESET}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
BUILD_TYPE="auto"   # auto | release | debug

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-type)
      [[ -n "${2:-}" ]] || err "--build-type requires a value (debug|release|auto)"
      BUILD_TYPE="$2"; shift 2 ;;
    --build-type=*)
      BUILD_TYPE="${1#*=}"; shift ;;
    -h|--help)
      echo "Usage: $0 [--build-type debug|release|auto]"; exit 0 ;;
    *)
      warn "Unknown argument: $1 (ignored)"; shift ;;
  esac
done

case "$BUILD_TYPE" in
  auto|release|debug) ;;
  *) err "Invalid --build-type '$BUILD_TYPE'. Valid values: auto, release, debug" ;;
esac

# ── Keystore ──────────────────────────────────────────────────────────────────
KEYSTORE="$SCRIPT_DIR/octra.jks"

[[ -f "$KEYSTORE" ]] || err "Keystore not found: $KEYSTORE"

echo -e "${CYAN}[sign-apk]${RESET} Keystore: ${BOLD}$KEYSTORE${RESET}"
read -r -s -p "$(echo -e "${CYAN}[sign-apk]${RESET} Enter keystore password: ")" KS_PASS
echo  # newline after silent input
[[ -n "$KS_PASS" ]] || err "Password cannot be empty."

# ── Auto-detect apksigner ─────────────────────────────────────────────────────
_find_apksigner() {
  if [[ -n "${ANDROID_HOME:-}" ]]; then
    local found
    found="$(find "$ANDROID_HOME/build-tools" -name apksigner -type f 2>/dev/null | sort -V | tail -1)"
    [[ -n "$found" ]] && { echo "$found"; return 0; }
  fi
  local candidates=(
    "$HOME/android-sdk/build-tools/35.0.0/apksigner"
    "$HOME/android-sdk/build-tools/34.0.0/apksigner"
    "$HOME/Android/Sdk/build-tools/35.0.0/apksigner"
    "$HOME/Android/Sdk/build-tools/34.0.0/apksigner"
  )
  for c in "${candidates[@]}"; do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  command -v apksigner 2>/dev/null && echo "apksigner" && return 0
  return 1
}

step "Collecting APKs to sign"

# ── Resolve actual build type for glob patterns ────────────────────────────
# Pick up APKs from:
#   1. split-ABI / universal outputs placed directly in ANDROID_DIR by build-apk.sh
#   2. raw Gradle output dir (fallback)

_collect_apks() {
  local btype="$1"
  local gradle_out="$ANDROID_DIR/app/build/outputs/apk/$btype"
  shopt -s nullglob
  local found=()
  local seen=()
  # Only search in Gradle output directory (no duplicates in android root)
  # Match various APK naming patterns: app-release-unsigned.apk, app-arm64-v8a-release.apk, etc.
  for apk in "$gradle_out"/app-*"${btype}"*.apk "$gradle_out"/app-"${btype}"*.apk; do
    [[ -f "$apk" ]] || continue
    # Skip duplicates (same basename already collected)
    local base
    base="$(basename "$apk")"
    local is_dup=false
    for s in "${seen[@]}"; do
      [[ "$s" == "$base" ]] && { is_dup=true; break; }
    done
    if [[ "$is_dup" == "false" ]]; then
      found+=("$apk")
      seen+=("$base")
    fi
  done
  shopt -u nullglob
  [[ ${#found[@]} -gt 0 ]] && printf '%s\n' "${found[@]}"
}

INPUT_APKS=()

if [[ "$BUILD_TYPE" == "auto" ]]; then
  # Try release first; fall back to debug
  mapfile -t INPUT_APKS < <(_collect_apks release)
  if [[ ${#INPUT_APKS[@]} -eq 0 ]]; then
    warn "No release APKs found — trying debug build..."
    mapfile -t INPUT_APKS < <(_collect_apks debug)
    [[ ${#INPUT_APKS[@]} -gt 0 ]] && BUILD_TYPE="debug" || true
  else
    BUILD_TYPE="release"
  fi
else
  mapfile -t INPUT_APKS < <(_collect_apks "$BUILD_TYPE")
fi

[[ ${#INPUT_APKS[@]} -gt 0 ]] || err "No ${BUILD_TYPE} APKs found. Run build-apk.sh first."
log "Build type : ${BOLD}${BUILD_TYPE}${RESET}"
log "Found ${#INPUT_APKS[@]} APK(s) to sign"

step "Validating prerequisites"

APKSIGNER="$(_find_apksigner)" || err "apksigner not found. Install Android build-tools or set ANDROID_HOME."
ok "apksigner: $APKSIGNER"
ok "Keystore: $KEYSTORE"

step "Signing APKs"

OUTPUT_DIR="$ANDROID_DIR/release"
mkdir -p "$OUTPUT_DIR"
SIGNED_COUNT=0

for apk in "${INPUT_APKS[@]}"; do
  name="$(basename "$apk")"
  # Strip -unsigned suffix if present, then append -signed before .apk
  # e.g. octra_wallet-arm64-v8a-release.apk  → octra_wallet-arm64-v8a-release-signed.apk
  # e.g. app-x86_64-release-unsigned.apk     → app-x86_64-release-signed.apk
  stripped="${name/-unsigned/}"
  out_name="${stripped%.apk}-signed.apk"
  out="$OUTPUT_DIR/$out_name"

  log "Signing: $name  →  release/$out_name"

  "$APKSIGNER" sign \
    --ks "$KEYSTORE" \
    --ks-pass "pass:$KS_PASS" \
    --out "$out" \
    "$apk"

  "$APKSIGNER" verify --verbose "$out" >/dev/null 2>&1 \
    || err "Signature verification failed for $out_name"

  ok "Verified: $out_name"
  SIGNED_COUNT=$(( SIGNED_COUNT + 1 ))
done

step "Summary"

echo ""
echo -e "  ${BOLD}Output directory:${RESET} $(realpath "$OUTPUT_DIR")"
echo ""

for apk in "$OUTPUT_DIR"/*.apk; do
  [[ -f "$apk" ]] || continue
  SIZE_BYTES="$(stat --format='%s' "$apk" 2>/dev/null || stat -f '%z' "$apk" 2>/dev/null)"
  SIZE_MB="$(awk "BEGIN { printf \"%.2f\", $SIZE_BYTES / 1048576 }")"
  FULL_PATH="$(realpath "$apk")"
  echo -e "  ${GREEN}✔${RESET} ${FULL_PATH}  (${BOLD}${SIZE_MB} MB${RESET})"
done

echo ""
ok "Signed $SIGNED_COUNT APK(s) successfully!"
