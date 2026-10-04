#!/usr/bin/env bash
# =============================================================================
# release-apk.sh — Build, Sign, and Publish Octra Wallet APK to GitHub
# =============================================================================
# Usage:
#   ./release-apk.sh                   Auto-detect version from pubspec.yaml
#   ./release-apk.sh --tag v1.2.0      Override the release tag
#   ./release-apk.sh --draft           Create a draft release
#   ./release-apk.sh --prerelease      Mark as pre-release
#   ./release-apk.sh --notes "msg"     Custom release notes
#   ./release-apk.sh --split-abi       Build per-ABI APKs (forwarded to build-apk.sh)
#   ./release-apk.sh --skip-build      Skip build (use existing APK)
#   ./release-apk.sh --skip-sign       Skip signing (use unsigned APK)
#   ./release-apk.sh --dry-run         Do everything except the actual GitHub release
#   ./release-apk.sh --force           Force full clean before build (slower)
#   ./release-apk.sh --no-daemon       Disable daemon (for CI/CD)
#
# Output APKs are placed in: release/  (next to this script)
#
# Environment overrides (optional):
#   GITHUB_TOKEN     — GitHub personal access token (or use `gh auth login`)
#   GITHUB_REPO      — owner/repo (auto-detected from git remote)
#   FLUTTER_BIN      — path to the flutter binary
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[release]${RESET} $*"; }
warn() { echo -e "${YELLOW}[release] ⚠ $*${RESET}"; }
ok()   { echo -e "${GREEN}[release] ✔ $*${RESET}"; }
err()  { echo -e "${RED}[release] ✘ $*${RESET}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Parse Flags ───────────────────────────────────────────────────────────────
TAG_OVERRIDE=""
DRAFT=false
PRERELEASE=false
NOTES_OVERRIDE=""
SKIP_BUILD=false
SKIP_SIGN=false
DRY_RUN=false
FORCE_CLEAN=false
NO_DAEMON=false
BUILD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)        TAG_OVERRIDE="$2"; shift 2 ;;
    --draft)      DRAFT=true; shift ;;
    --prerelease) PRERELEASE=true; shift ;;
    --notes)      NOTES_OVERRIDE="$2"; shift 2 ;;
    --split-abi)  BUILD_ARGS+=("--split-abi"); shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --skip-sign)  SKIP_SIGN=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --force)      FORCE_CLEAN=true; BUILD_ARGS+=("--force"); shift ;;
    --no-daemon)  NO_DAEMON=true; BUILD_ARGS+=("--no-daemon"); shift ;;
    --help|-h)
      sed -n '/^# ====/,/^# ====/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) err "Unknown flag: $1. Use --help for usage." ;;
  esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# 1.  DETERMINE VERSION & TAG
# ═══════════════════════════════════════════════════════════════════════════════
step "Determining release version"

PUBSPEC="$PROJECT_DIR/pubspec.yaml"
[[ -f "$PUBSPEC" ]] || err "pubspec.yaml not found at $PUBSPEC"

# Extract version from pubspec.yaml (e.g., 1.0.0+3)
FULL_VERSION="$(grep '^version:' "$PUBSPEC" | head -1 | awk '{print $2}' | tr -d '[:space:]')"
[[ -n "$FULL_VERSION" ]] || err "Could not parse version from pubspec.yaml"

# Semantic version (before the +)
SEM_VERSION="${FULL_VERSION%%+*}"
# Build number (after the +)
BUILD_NUMBER="${FULL_VERSION#*+}"
[[ "$BUILD_NUMBER" == "$SEM_VERSION" ]] && BUILD_NUMBER=""

if [[ -n "$TAG_OVERRIDE" ]]; then
  RELEASE_TAG="$TAG_OVERRIDE"
else
  RELEASE_TAG="v${SEM_VERSION}"
fi

ok "Version: $FULL_VERSION"
ok "Release tag: $RELEASE_TAG"

# ═══════════════════════════════════════════════════════════════════════════════
# 2.  DETECT GITHUB REPOSITORY
# ═══════════════════════════════════════════════════════════════════════════════
step "Detecting GitHub repository"

if [[ -n "${GITHUB_REPO:-}" ]]; then
  REPO="$GITHUB_REPO"
else
  REMOTE_URL="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
  [[ -n "$REMOTE_URL" ]] || err "No git remote 'origin' found. Set GITHUB_REPO=owner/repo"

  # Extract owner/repo from HTTPS or SSH URL
  REPO="$(echo "$REMOTE_URL" | sed -E 's#^(https?://github\.com/|git@github\.com:)##' | sed 's/\.git$//')"
  [[ "$REPO" == */* ]] || err "Could not parse owner/repo from remote: $REMOTE_URL"
fi

ok "GitHub repo: $REPO"

# ═══════════════════════════════════════════════════════════════════════════════
# 3.  ENSURE GITHUB CLI IS AVAILABLE
# ═══════════════════════════════════════════════════════════════════════════════
step "Checking GitHub CLI (gh)"

_install_gh() {
  log "Installing GitHub CLI..."

  if command -v apt-get &>/dev/null; then
    # Debian / Ubuntu
    (type -p wget >/dev/null || sudo apt-get install -y wget) \
      && sudo mkdir -p -m 755 /etc/apt/keyrings \
      && out=$(mktemp) \
      && wget -nv -O "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      && cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
      && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
      && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
         | sudo tee /etc/apt/sources.list.d/github-cli-stable.list > /dev/null \
      && sudo apt-get update -qq \
      && sudo apt-get install -y gh \
      && rm -f "$out"
  elif command -v brew &>/dev/null; then
    brew install gh
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y gh
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm github-cli
  else
    # Fallback: download binary from GitHub releases
    log "No supported package manager found. Downloading gh binary..."
    GH_VERSION="2.65.0"
    ARCH="$(uname -m)"
    case "$ARCH" in
      x86_64)  GH_ARCH="amd64" ;;
      aarch64) GH_ARCH="arm64" ;;
      armv7l)  GH_ARCH="armv6" ;;
      *) err "Unsupported architecture: $ARCH" ;;
    esac
    GH_TAR="gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz"
    GH_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/${GH_TAR}"
    TMP_DIR="$(mktemp -d)"
    wget -q -O "$TMP_DIR/$GH_TAR" "$GH_URL" || curl -fsSL -o "$TMP_DIR/$GH_TAR" "$GH_URL"
    tar -xzf "$TMP_DIR/$GH_TAR" -C "$TMP_DIR"
    sudo install -m 755 "$TMP_DIR/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /usr/local/bin/gh
    rm -rf "$TMP_DIR"
  fi
}

if ! command -v gh &>/dev/null; then
  _install_gh
  command -v gh &>/dev/null || err "Failed to install GitHub CLI (gh)."
fi

ok "gh: $(gh --version | head -1)"

# ═══════════════════════════════════════════════════════════════════════════════
# 4.  VERIFY GITHUB AUTHENTICATION
# ═══════════════════════════════════════════════════════════════════════════════
step "Verifying GitHub authentication"

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  log "Using GITHUB_TOKEN environment variable"
  export GH_TOKEN="$GITHUB_TOKEN"
fi

if ! gh auth status &>/dev/null; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    log "Authenticating with provided token..."
    echo "$GH_TOKEN" | gh auth login --with-token
  else
    err "Not authenticated with GitHub. Either:\n  1. Run: gh auth login\n  2. Set GITHUB_TOKEN environment variable\n  3. Set GH_TOKEN environment variable"
  fi
fi

ok "GitHub authentication verified"

# ═══════════════════════════════════════════════════════════════════════════════
# 5.  CHECK IF TAG ALREADY EXISTS
# ═══════════════════════════════════════════════════════════════════════════════
step "Checking tag $RELEASE_TAG"

if git -C "$PROJECT_DIR" rev-parse "$RELEASE_TAG" &>/dev/null; then
  warn "Tag $RELEASE_TAG already exists locally."
fi

EXISTING_RELEASE="$(gh release view "$RELEASE_TAG" --repo "$REPO" --json tagName 2>/dev/null || true)"
if [[ -n "$EXISTING_RELEASE" ]]; then
  warn "Release $RELEASE_TAG already exists on GitHub. It will be updated with new assets."
  RELEASE_EXISTS=true
else
  RELEASE_EXISTS=false
  ok "Tag $RELEASE_TAG is new"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 6.  BUILD APK
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$SKIP_BUILD" == false ]]; then
  step "Building APK"

  BUILD_SCRIPT="$SCRIPT_DIR/build-apk.sh"
  [[ -f "$BUILD_SCRIPT" ]] || err "build-apk.sh not found at $BUILD_SCRIPT"
  [[ -x "$BUILD_SCRIPT" ]] || chmod +x "$BUILD_SCRIPT"

  log "Running: ./build-apk.sh ${BUILD_ARGS[*]:-}"
  "$BUILD_SCRIPT" "${BUILD_ARGS[@]:-}" || err "build-apk.sh failed"

  ok "APK build completed"
else
  log "Skipping build (--skip-build)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 7.  SIGN APK
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$SKIP_SIGN" == false ]]; then
  step "Signing APK"

  SIGN_SCRIPT="$SCRIPT_DIR/sign-apk.sh"
  [[ -f "$SIGN_SCRIPT" ]] || err "sign-apk.sh not found at $SIGN_SCRIPT"
  [[ -x "$SIGN_SCRIPT" ]] || chmod +x "$SIGN_SCRIPT"

  log "Running: ./sign-apk.sh"
  "$SIGN_SCRIPT" || err "sign-apk.sh failed"

  ok "APK signing completed"
else
  log "Skipping signing (--skip-sign)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 8.  COLLECT APK FILES FOR UPLOAD
# ═══════════════════════════════════════════════════════════════════════════════
step "Collecting APK files"

SIGNED_DIR="$PROJECT_DIR/release"
UNSIGNED_DIR="$PROJECT_DIR/build/app/outputs/flutter-apk"

APK_FILES=()

# Prefer signed APKs if available
if [[ -d "$SIGNED_DIR" ]] && [[ "$SKIP_SIGN" == false ]]; then
  while IFS= read -r -d '' apk; do
    APK_FILES+=("$apk")
  done < <(find "$SIGNED_DIR" -name '*.apk' -print0 2>/dev/null)
fi

# Fallback to unsigned APKs
if [[ ${#APK_FILES[@]} -eq 0 ]]; then
  while IFS= read -r -d '' apk; do
    APK_FILES+=("$apk")
  done < <(find "$UNSIGNED_DIR" -name '*-release.apk' -print0 2>/dev/null)
fi

[[ ${#APK_FILES[@]} -gt 0 ]] || err "No APK files found to upload."

log "APK files to upload:"
for f in "${APK_FILES[@]}"; do
  SIZE="$(du -h "$f" | cut -f1)"
  echo -e "  ${GREEN}→${RESET} $(basename "$f") ($SIZE)"
done

# ═══════════════════════════════════════════════════════════════════════════════
# 9.  GENERATE RELEASE NOTES
# ═══════════════════════════════════════════════════════════════════════════════
step "Generating release notes"

if [[ -n "$NOTES_OVERRIDE" ]]; then
  RELEASE_NOTES="$NOTES_OVERRIDE"
else
  # Auto-generate from git log since last tag
  PREV_TAG="$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"

  RELEASE_NOTES="## Octra Wallet $RELEASE_TAG

**Build:** $FULL_VERSION
**Date:** $(date -u '+%Y-%m-%d %H:%M UTC')

### Changes
"

  if [[ -n "$PREV_TAG" ]]; then
    COMMITS="$(git -C "$PROJECT_DIR" log "${PREV_TAG}..HEAD" --oneline --no-merges 2>/dev/null || true)"
    if [[ -n "$COMMITS" ]]; then
      while IFS= read -r line; do
        RELEASE_NOTES+="- $line
"
      done <<< "$COMMITS"
    else
      RELEASE_NOTES+="- Maintenance release
"
    fi
  else
    RELEASE_NOTES+="- Initial release
"
  fi

  RELEASE_NOTES+="
### Assets
"
  for f in "${APK_FILES[@]}"; do
    SIZE="$(du -h "$f" | cut -f1)"
    RELEASE_NOTES+="- \`$(basename "$f")\` ($SIZE)
"
  done
fi

echo -e "\n${BOLD}Release Notes:${RESET}"
echo "$RELEASE_NOTES"

# ═══════════════════════════════════════════════════════════════════════════════
# 10. CREATE / UPDATE GITHUB RELEASE
# ═══════════════════════════════════════════════════════════════════════════════
step "Publishing release to GitHub"

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN — skipping actual GitHub release creation"
  log "Would create release: $RELEASE_TAG"
  log "Repo: $REPO"
  log "Draft: $DRAFT"
  log "Prerelease: $PRERELEASE"
  log "APKs: ${#APK_FILES[@]} file(s)"
  echo ""
  ok "Dry run complete. No changes made."
  exit 0
fi

GH_ARGS=()

# Build gh release create/upload command
if [[ "$RELEASE_EXISTS" == true ]]; then
  # Delete existing assets and re-upload
  log "Updating existing release $RELEASE_TAG..."

  # Remove old APK assets from the release
  OLD_ASSETS="$(gh release view "$RELEASE_TAG" --repo "$REPO" --json assets --jq '.assets[].name' 2>/dev/null || true)"
  if [[ -n "$OLD_ASSETS" ]]; then
    while IFS= read -r asset_name; do
      if [[ "$asset_name" == *.apk ]]; then
        log "Removing old asset: $asset_name"
        gh release delete-asset "$RELEASE_TAG" "$asset_name" --repo "$REPO" --yes 2>/dev/null || true
      fi
    done <<< "$OLD_ASSETS"
  fi

  # Upload new APKs
  gh release upload "$RELEASE_TAG" "${APK_FILES[@]}" --repo "$REPO" --clobber

  # Update release notes
  GH_EDIT_ARGS=(--repo "$REPO" --notes "$RELEASE_NOTES")
  [[ "$DRAFT" == true ]]      && GH_EDIT_ARGS+=(--draft)
  [[ "$PRERELEASE" == true ]] && GH_EDIT_ARGS+=(--prerelease)
  gh release edit "$RELEASE_TAG" "${GH_EDIT_ARGS[@]}"

else
  # Create new release
  log "Creating new release $RELEASE_TAG..."

  GH_ARGS=(--repo "$REPO" --title "Octra Wallet $RELEASE_TAG" --notes "$RELEASE_NOTES")
  [[ "$DRAFT" == true ]]      && GH_ARGS+=(--draft)
  [[ "$PRERELEASE" == true ]] && GH_ARGS+=(--prerelease)

  # Create tag if it doesn't exist
  if ! git -C "$PROJECT_DIR" rev-parse "$RELEASE_TAG" &>/dev/null; then
    log "Creating git tag $RELEASE_TAG..."
    git -C "$PROJECT_DIR" tag -a "$RELEASE_TAG" -m "Release $RELEASE_TAG"
    git -C "$PROJECT_DIR" push origin "$RELEASE_TAG"
  fi

  gh release create "$RELEASE_TAG" "${APK_FILES[@]}" "${GH_ARGS[@]}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 11. SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${RESET}"
ok "Release published successfully!"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Tag:${RESET}     $RELEASE_TAG"
echo -e "  ${BOLD}Version:${RESET} $FULL_VERSION"
echo -e "  ${BOLD}Repo:${RESET}    $REPO"
echo -e "  ${BOLD}URL:${RESET}     https://github.com/$REPO/releases/tag/$RELEASE_TAG"
echo ""

for f in "${APK_FILES[@]}"; do
  SIZE="$(du -h "$f" | cut -f1)"
  echo -e "  ${GREEN}✔${RESET} $(basename "$f") ($SIZE)"
done

echo ""
ok "All done!"
