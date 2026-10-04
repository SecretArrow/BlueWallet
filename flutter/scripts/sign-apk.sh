#!/usr/bin/env bash
# =============================================================================
# sign-apk.sh — Sign Octra Wallet release APKs with the project keystore
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[sign-apk]${RESET} $*"; }
ok()   { echo -e "${GREEN}[sign-apk] ✔ $*${RESET}"; }
err()  { echo -e "${RED}[sign-apk] ✘ $*${RESET}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Configuration ─────────────────────────────────────────────────────────────
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYSTORE="$SCRIPT_DIR/octra.jks"

[[ -f "$KEYSTORE" ]] || err "Keystore not found: $KEYSTORE"

echo -e "${CYAN}[sign-apk]${RESET} Keystore: ${BOLD}$KEYSTORE${RESET}"
read -r -s -p "$(echo -e "${CYAN}[sign-apk]${RESET} Enter keystore password: ")" KS_PASS
echo  # newline after silent input
[[ -n "$KS_PASS" ]] || err "Password cannot be empty."

# Auto-detect apksigner from ANDROID_HOME or common paths
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
  command -v apksigner 2>/dev/null && return 0
  return 1
}

INPUT_DIR="$PROJECT_DIR/build/app/outputs/flutter-apk"
OUTPUT_DIR="$PROJECT_DIR/release"

# ── Validate prerequisites ────────────────────────────────────────────────────
step "Validating prerequisites"

APKSIGNER="$(_find_apksigner)" || err "apksigner not found. Install Android build-tools or set ANDROID_HOME."
ok "apksigner: $APKSIGNER"
ok "Keystore: $KEYSTORE"

# Collect unsigned APKs
shopt -s nullglob
APK_LIST=("$INPUT_DIR"/*-release.apk)
shopt -u nullglob

[[ ${#APK_LIST[@]} -gt 0 ]] || err "No release APKs found in $INPUT_DIR"
log "Found ${#APK_LIST[@]} APK(s) to sign"

# ── Sign each APK ─────────────────────────────────────────────────────────────
step "Signing APKs"

mkdir -p "$OUTPUT_DIR"
SIGNED_COUNT=0

for apk in "${APK_LIST[@]}"; do
  name="$(basename "$apk")"
  out="$OUTPUT_DIR/$name"

  log "Signing: $name"

  "$APKSIGNER" sign \
    --ks "$KEYSTORE" \
    --ks-pass "pass:$KS_PASS" \
    --out "$out" \
    "$apk"

  # Verify signature
  "$APKSIGNER" verify --verbose "$out" >/dev/null 2>&1 \
    || err "Signature verification failed for $name"

  ok "Verified: $name"
  SIGNED_COUNT=$((SIGNED_COUNT + 1))
done

# ── Summary ────────────────────────────────────────────────────────────────────
step "Summary"

echo ""
echo -e "  ${BOLD}Output directory:${RESET} $OUTPUT_DIR"
echo ""

for apk in "$OUTPUT_DIR"/*.apk; do
  SIZE_BYTES="$(stat --format='%s' "$apk" 2>/dev/null || stat -f '%z' "$apk" 2>/dev/null)"
  SIZE_MB="$(awk "BEGIN { printf \"%.2f\", $SIZE_BYTES / 1048576 }")"
  FULL_PATH="$(realpath "$apk")"
  echo -e "  ${GREEN}✔${RESET} ${FULL_PATH}  (${BOLD}${SIZE_MB} MB${RESET})"
done

echo ""
ok "Signed $SIGNED_COUNT APK(s) successfully!"
