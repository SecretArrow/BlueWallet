#!/usr/bin/env bash
# =============================================================================
# install.sh — Bootstrap all build requirements for Octra Wallet (Android)
# =============================================================================
# Installs / verifies:
#   • Java 17 (OpenJDK)
#   • Android command-line tools
#   • Android SDK components: platform-tools, android-35, build-tools 35.0.0,
#     cmake 3.22.1, NDK 27.3.13750724
#   • Gradle wrapper (gradlew) in the android/ project root
#   • local.properties (sdk.dir)
#
# Usage:
#   bash scripts/install.sh          # from android/ root
#   bash install.sh                  # from scripts/ folder
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Versions / constants ──────────────────────────────────────────────────────
SDK_PLATFORM="android-35"
SDK_BUILD_TOOLS="35.0.0"
SDK_NDK="27.3.13750724"
CMAKE_VERSION="3.22.1"
CMDLINE_TOOLS_VERSION="13114758"
GRADLE_WRAPPER_VERSION="8.10.2"
JAVA_MIN_VERSION=17

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[install]${RESET} $*"; }
ok()   { echo -e "${GREEN}[install] ✔ $*${RESET}"; }
warn() { echo -e "${YELLOW}[install] ⚠  $*${RESET}"; }
err()  { echo -e "${RED}[install] ✘  $*${RESET}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Privilege helper ──────────────────────────────────────────────────────────
_sudo() {
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        "$@"
    fi
}

# ── apt helper ────────────────────────────────────────────────────────────────
apt_install() {
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get not available. Please install $* manually."
        return 1
    fi
    _sudo apt-get update -qq
    _sudo apt-get install -y "$@"
}

# ── download helper ───────────────────────────────────────────────────────────
download() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$url" -O "$out"
    else
        err "Neither curl nor wget is available."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
step "1 / 6  —  System utilities"
# ─────────────────────────────────────────────────────────────────────────────

NEED_PKGS=()
for tool in curl unzip git; do
    command -v "$tool" >/dev/null 2>&1 || NEED_PKGS+=("$tool")
done
if [ ${#NEED_PKGS[@]} -gt 0 ]; then
    log "Installing missing utilities: ${NEED_PKGS[*]}"
    apt_install "${NEED_PKGS[@]}"
fi
ok "curl, unzip, git present"

# ─────────────────────────────────────────────────────────────────────────────
step "2 / 6  —  Java $JAVA_MIN_VERSION"
# ─────────────────────────────────────────────────────────────────────────────

_java_major() {
    local v
    v="$(java -version 2>&1 | head -1 | sed 's/.*version "\([^"]*\)".*/\1/')"
    # Handle "1.8.0_xyz" (Java 8) and "17.0.x" (Java 17+)
    if [[ "$v" == 1.* ]]; then
        echo "${v#1.}" | cut -d. -f1   # e.g. 1.8 → 8
    else
        echo "$v" | cut -d. -f1
    fi
}

if command -v java >/dev/null 2>&1; then
    JAVA_VER="$(_java_major)"
    if [ "${JAVA_VER:-0}" -ge "$JAVA_MIN_VERSION" ] 2>/dev/null; then
        ok "Java $JAVA_VER already installed"
    else
        warn "Java $JAVA_VER < $JAVA_MIN_VERSION — installing OpenJDK $JAVA_MIN_VERSION"
        apt_install "openjdk-${JAVA_MIN_VERSION}-jdk"
    fi
else
    log "Java not found. Installing OpenJDK $JAVA_MIN_VERSION..."
    if command -v apt-get >/dev/null 2>&1; then
        apt_install "openjdk-${JAVA_MIN_VERSION}-jdk"
    else
        err "Java $JAVA_MIN_VERSION is required. Please install it manually:\n  https://adoptium.net/"
    fi
fi

# Set JAVA_HOME if not already set
if [ -z "${JAVA_HOME:-}" ]; then
    JAVA_BIN="$(readlink -f "$(command -v java)" 2>/dev/null || true)"
    if [ -n "$JAVA_BIN" ]; then
        JAVA_HOME="$(dirname "$(dirname "$JAVA_BIN")")"
        export JAVA_HOME
    fi
fi
ok "JAVA_HOME=$JAVA_HOME"

# ─────────────────────────────────────────────────────────────────────────────
step "3 / 6  —  Android SDK"
# ─────────────────────────────────────────────────────────────────────────────

SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

if [ -z "$SDK_DIR" ]; then
    for candidate in "$HOME/Android/Sdk" "$HOME/android-sdk" "/opt/android-sdk"; do
        [ -d "$candidate" ] && { SDK_DIR="$candidate"; break; }
    done
fi

if [ -z "$SDK_DIR" ] || [ ! -d "$SDK_DIR" ]; then
    SDK_DIR="$HOME/android-sdk"
    PINNED_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
    LEGACY_URL="https://dl.google.com/android/repository/commandlinetools-linux-latest.zip"
    TOOLS_ZIP="$SDK_DIR/cmdline-tools.zip"
    TOOLS_DIR="$SDK_DIR/cmdline-tools"

    log "Downloading Android command-line tools → $SDK_DIR"
    mkdir -p "$SDK_DIR"
    if ! download "$PINNED_URL" "$TOOLS_ZIP" 2>/dev/null; then
        download "$LEGACY_URL" "$TOOLS_ZIP"
    fi
    rm -rf "$TOOLS_DIR"
    mkdir -p "$TOOLS_DIR"
    unzip -q "$TOOLS_ZIP" -d "$TOOLS_DIR"
    rm -f "$TOOLS_ZIP"
    # Normalize directory layout expected by sdkmanager
    [ -d "$TOOLS_DIR/cmdline-tools" ] && mv "$TOOLS_DIR/cmdline-tools" "$TOOLS_DIR/latest"
    ok "Command-line tools installed at $SDK_DIR/cmdline-tools/latest"
else
    ok "Android SDK found at $SDK_DIR"
fi

export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"

# ─────────────────────────────────────────────────────────────────────────────
step "4 / 6  —  SDK components"
# ─────────────────────────────────────────────────────────────────────────────

SDKMANAGER=""
for candidate in \
    "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" \
    "$SDK_DIR/tools/bin/sdkmanager"; do
    [ -x "$candidate" ] && { SDKMANAGER="$candidate"; break; }
done

if [ -z "$SDKMANAGER" ]; then
    warn "sdkmanager not found — skipping automatic SDK component installation."
    warn "Please install these components manually:"
    warn "  platform-tools  platforms;$SDK_PLATFORM  build-tools;$SDK_BUILD_TOOLS"
    warn "  cmake;$CMAKE_VERSION  ndk;$SDK_NDK"
else
    log "Accepting Android SDK licenses..."
    set +o pipefail
    yes | "$SDKMANAGER" --sdk_root="$SDK_DIR" --licenses >/dev/null 2>&1 || true
    set -o pipefail

    log "Installing SDK components (this may take a few minutes)..."
    "$SDKMANAGER" --sdk_root="$SDK_DIR" \
        "platform-tools" \
        "platforms;$SDK_PLATFORM" \
        "build-tools;$SDK_BUILD_TOOLS" \
        "cmake;$CMAKE_VERSION" \
        "ndk;$SDK_NDK"
    ok "SDK components installed"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "5 / 6  —  Gradle wrapper"
# ─────────────────────────────────────────────────────────────────────────────

if [ -f "$ANDROID_DIR/gradlew" ]; then
    ok "gradlew already present"
else
    log "Creating Gradle wrapper (version $GRADLE_WRAPPER_VERSION)..."
    if command -v gradle >/dev/null 2>&1; then
        (cd "$ANDROID_DIR" && gradle wrapper --gradle-version "$GRADLE_WRAPPER_VERSION")
        ok "gradlew created"
    else
        err "Gradle is not installed.\n  Install it from https://gradle.org/install/ then re-run this script,\n  OR add the gradlew file manually."
    fi
fi
chmod +x "$ANDROID_DIR/gradlew"

# ─────────────────────────────────────────────────────────────────────────────
step "6 / 6  —  local.properties"
# ─────────────────────────────────────────────────────────────────────────────

PROPS="$ANDROID_DIR/local.properties"
if [ -f "$PROPS" ]; then
    # Update sdk.dir if it doesn't match the current SDK_DIR
    if grep -q "^sdk.dir=" "$PROPS"; then
        CURRENT_SDK="$(grep '^sdk.dir=' "$PROPS" | cut -d= -f2-)"
        if [ "$CURRENT_SDK" != "$SDK_DIR" ]; then
            sed -i "s|^sdk.dir=.*|sdk.dir=$SDK_DIR|" "$PROPS"
            log "Updated sdk.dir in local.properties"
        fi
    else
        echo "sdk.dir=$SDK_DIR" >> "$PROPS"
        log "Appended sdk.dir to local.properties"
    fi
    ok "local.properties OK"
else
    echo "sdk.dir=$SDK_DIR" > "$PROPS"
    if [ -n "${JAVA_HOME:-}" ]; then
        echo "# JAVA_HOME is set in your environment: $JAVA_HOME" >> "$PROPS"
    fi
    ok "Created local.properties"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Setup complete"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "  ${BOLD}JAVA_HOME${RESET}      = ${JAVA_HOME:-<not set>}"
echo -e "  ${BOLD}ANDROID_HOME${RESET}   = $SDK_DIR"
echo -e "  ${BOLD}gradlew${RESET}        = $ANDROID_DIR/gradlew"
echo -e "  ${BOLD}local.properties${RESET} = $PROPS"
echo ""
echo -e "${GREEN}${BOLD}All requirements installed. You can now run:${RESET}"
echo -e "  ${CYAN}bash scripts/build-apk.sh release --split-abi${RESET}"
echo ""
