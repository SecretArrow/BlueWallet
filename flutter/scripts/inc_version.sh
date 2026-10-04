#!/usr/bin/env bash
# inc_version.sh — Bump version using 1.x.0+x scheme and push.
# Usage: ./inc_version.sh
#
# Version format in pubspec.yaml:  1.x.0+x
#   version name  = 1.x.0   (shown to users, e.g. "1.16.0")
#   build number  = x     (Android versionCode)
# Both parts share the same counter x, incremented together.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

# ── Read current version ─────────────────────────────────────────────────────
CURRENT=$(grep '^version: ' "$PUBSPEC" | sed 's/^version: //')

# Parse "1.x.0+x" — take the build-number portion (after +) as x
if [[ "$CURRENT" != 1.*+* ]]; then
	echo "Error: Unsupported version format in pubspec.yaml: $CURRENT"
	echo "Expected format: 1.x.0+x (example: 1.15.0+15)"
	exit 1
fi

BUILD_NUM="${CURRENT##*+}"     # e.g. 15
[[ "$BUILD_NUM" =~ ^[0-9]+$ ]] || {
	echo "Error: Invalid build number in version: $CURRENT"
	exit 1
}

# ── Increment x ──────────────────────────────────────────────────────────────
NEW_X=$(( BUILD_NUM + 1 ))
NEW_VERSION="1.${NEW_X}.0+${NEW_X}"

# ── Update pubspec.yaml ──────────────────────────────────────────────────────
sed -i "s/^version: .*/version: ${NEW_VERSION}/" "$PUBSPEC"

echo "Version bumped: $CURRENT  →  $NEW_VERSION"

# ── Git: stage, commit, push ─────────────────────────────────────────────────
cd "$PROJECT_DIR"
git add .
git commit -m "v${NEW_VERSION}"
git push

echo "Done. Version ${NEW_VERSION} pushed."
