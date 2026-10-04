#!/usr/bin/env bash
# =============================================================================
# install.sh — Install & configure all prerequisites for Octra Wallet Flutter
# =============================================================================
# This script installs and configures everything needed to run the build,
# sign, and release scripts in this directory:
#
#   • Git
#   • Java (OpenJDK 17)
#   • Flutter SDK (stable channel)
#   • Android SDK command-line tools  (cmdline-tools, platform-tools,
#     build-tools 35.0.0, platforms;android-35)
#   • apksigner  (bundled with Android build-tools)
#   • GitHub CLI  (gh)
#   • Linux desktop build deps  (cmake, ninja, GTK3, libsecret, etc.)
#
# Usage:
#   ./install.sh              Full setup (Flutter + Android + Linux deps)
#   ./install.sh --android    Android / APK toolchain only
#   ./install.sh --linux      Linux desktop deps only
#   ./install.sh --ios        iOS checks / reminders only
#   ./install.sh --check      Only check what is already installed
#
# Environment overrides (optional):
#   FLUTTER_CHANNEL   — Flutter channel to clone  (default: stable)
#   FLUTTER_VERSION   — specific Flutter version tag  (e.g. 3.24.3)
#   ANDROID_HOME      — existing Android SDK path (skips SDK download)
#   JAVA_HOME         — existing JDK path (skips JDK install)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_VERSION="${FLUTTER_VERSION:-}"
FLUTTER_INSTALL_DIR="${FLUTTER_INSTALL_DIR:-$HOME/flutter}"

ANDROID_SDK_DIR="${ANDROID_HOME:-$HOME/android-sdk}"
CMDLINE_TOOLS_VERSION="11076708"   # latest at time of writing; update if needed
BUILD_TOOLS_VERSION="35.0.0"
ANDROID_PLATFORM="android-35"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[install]${RESET} $*"; }
warn() { echo -e "${YELLOW}[install] ⚠ $*${RESET}"; }
ok()   { echo -e "${GREEN}[install] ✔ $*${RESET}"; }
err()  { echo -e "${RED}[install] ✘ $*${RESET}" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Parse flags ───────────────────────────────────────────────────────────────
DO_FLUTTER=true
DO_ANDROID=true
DO_LINUX=true
DO_IOS=false
CHECK_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --android)  DO_FLUTTER=true; DO_ANDROID=true; DO_LINUX=false ;;
    --linux)    DO_FLUTTER=true; DO_ANDROID=false; DO_LINUX=true ;;
    --ios)      DO_FLUTTER=true; DO_ANDROID=false; DO_LINUX=false; DO_IOS=true ;;
    --check)    CHECK_ONLY=true ;;
    --help|-h)
      sed -n '/^# ====/,/^# ====/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) err "Unknown flag: $arg. Use --android | --linux | --ios | --check" ;;
  esac
done

# ── OS detection ──────────────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Linux)  PKG_MGR="apt-get" ;;
  Darwin) PKG_MGR="brew" ;;
  *)      PKG_MGR="" ;;
esac

_apt_install() {
  if command -v apt-get &>/dev/null; then
    log "apt-get install -y $*"
    sudo apt-get install -y "$@" 2>/dev/null
  elif command -v brew &>/dev/null; then
    brew install "$@" 2>/dev/null || true
  else
    warn "Cannot auto-install: $*. Please install manually."
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# CHECK MODE — print current tool versions and exit
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$CHECK_ONLY" == true ]]; then
  step "Checking installed tools"
  _check() {
    local name="$1" cmd="$2"
    if command -v "$cmd" &>/dev/null; then
      local ver
      ver="$( "$cmd" --version 2>&1 | head -1 || true )"
      ok "$name: $ver"
    else
      warn "$name: NOT FOUND"
    fi
  }
  _check "git"       "git"
  _check "java"      "java"
  _check "flutter"   "flutter"
  _check "sdkmanager" "sdkmanager"  || true
  _check "apksigner" "apksigner"    || true
  _check "gh"        "gh"
  [[ -d "${ANDROID_HOME:-}" ]] && ok "ANDROID_HOME: ${ANDROID_HOME}" \
    || warn "ANDROID_HOME: not set / not found"
  exit 0
fi

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║    Octra Wallet — Development Setup              ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
log "Project root : $PROJECT_DIR"
log "Scripts dir  : $SCRIPT_DIR"
log "OS           : $OS ($ARCH)"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# 1.  GIT
# ══════════════════════════════════════════════════════════════════════════════
step "Git"
if ! command -v git &>/dev/null; then
  log "Installing git..."
  _apt_install git
fi
ok "git: $(git --version)"

# ══════════════════════════════════════════════════════════════════════════════
# 2.  JAVA (JDK 17)
# ══════════════════════════════════════════════════════════════════════════════
step "Java (JDK 17)"
if [[ -n "${JAVA_HOME:-}" ]] && [[ -x "${JAVA_HOME}/bin/java" ]]; then
  ok "JAVA_HOME already set: $JAVA_HOME"
elif command -v java &>/dev/null; then
  ok "java: $(java -version 2>&1 | head -1)"
else
  log "Installing OpenJDK 17..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y openjdk-17-jdk
  elif command -v brew &>/dev/null; then
    brew install --cask temurin@17
  else
    err "Cannot install Java automatically. Install JDK 17 and re-run."
  fi
  ok "java: $(java -version 2>&1 | head -1)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 3.  FLUTTER SDK
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$DO_FLUTTER" == true ]]; then
step "Flutter SDK"

_find_flutter() {
  [[ -n "${FLUTTER_BIN:-}" ]] && [[ -x "${FLUTTER_BIN}" ]] && { echo "$FLUTTER_BIN"; return 0; }
  command -v flutter &>/dev/null && { command -v flutter; return 0; }
  local c; for c in \
    "$HOME/flutter/bin/flutter" \
    "$HOME/development/flutter/bin/flutter" \
    "$HOME/snap/flutter/common/flutter/bin/flutter" \
    "/opt/flutter/bin/flutter" \
    "/usr/local/flutter/bin/flutter" \
    "/flutter/bin/flutter"; do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

FLUTTER="$(_find_flutter 2>/dev/null || true)"

if [[ -z "$FLUTTER" ]]; then
  log "Flutter not found — cloning into $FLUTTER_INSTALL_DIR ..."
  if [[ -d "$FLUTTER_INSTALL_DIR" ]] && [[ ! -x "$FLUTTER_INSTALL_DIR/bin/flutter" ]]; then
    warn "Removing broken Flutter directory and re-cloning..."
    rm -rf "$FLUTTER_INSTALL_DIR"
  fi
  if [[ ! -d "$FLUTTER_INSTALL_DIR" ]]; then
    if [[ -n "$FLUTTER_VERSION" ]]; then
      git clone --depth 1 --branch "$FLUTTER_VERSION" \
        https://github.com/flutter/flutter.git "$FLUTTER_INSTALL_DIR"
    else
      git clone --depth 1 --branch "$FLUTTER_CHANNEL" \
        https://github.com/flutter/flutter.git "$FLUTTER_INSTALL_DIR"
    fi
  fi
  FLUTTER="$FLUTTER_INSTALL_DIR/bin/flutter"
  FLUTTER_ROOT="$(dirname "$(dirname "$FLUTTER")")"
  export PATH="$FLUTTER_ROOT/bin:$PATH"

  log "Adding Flutter to PATH in ~/.bashrc / ~/.zshrc ..."
  EXPORT_LINE="export PATH=\"$FLUTTER_ROOT/bin:\$PATH\""
  grep -qF "$FLUTTER_ROOT/bin" "$HOME/.bashrc" 2>/dev/null || echo "$EXPORT_LINE" >> "$HOME/.bashrc"
  if [[ -f "$HOME/.zshrc" ]]; then
    grep -qF "$FLUTTER_ROOT/bin" "$HOME/.zshrc" 2>/dev/null || echo "$EXPORT_LINE" >> "$HOME/.zshrc"
  fi
fi

FLUTTER_ROOT="$(dirname "$(dirname "$FLUTTER")")"
export PATH="$FLUTTER_ROOT/bin:$PATH"
ok "Flutter: $FLUTTER"
"$FLUTTER" --version 2>&1 | head -1 || true
fi # DO_FLUTTER

# ══════════════════════════════════════════════════════════════════════════════
# 4.  ANDROID SDK
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$DO_ANDROID" == true ]]; then
step "Android SDK"

_find_android_sdk() {
  local c; for c in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
    "$HOME/android-sdk" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" \
    "/opt/android-sdk" "/usr/lib/android-sdk"; do
    [[ -n "$c" ]] && [[ -d "$c/platform-tools" ]] && { echo "$c"; return 0; }
  done
  return 1
}

ANDROID_SDK="$(_find_android_sdk 2>/dev/null || true)"

if [[ -z "$ANDROID_SDK" ]]; then
  log "Android SDK not found — installing command-line tools to $ANDROID_SDK_DIR ..."
  mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"

  CMDLINE_ZIP="commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
  case "$OS" in
    Darwin) CMDLINE_ZIP="commandlinetools-mac-${CMDLINE_TOOLS_VERSION}_latest.zip" ;;
  esac
  CMDLINE_URL="https://dl.google.com/android/repository/${CMDLINE_ZIP}"
  TMP_ZIP="/tmp/${CMDLINE_ZIP}"

  log "Downloading: $CMDLINE_URL"
  if command -v wget &>/dev/null; then
    wget -q -O "$TMP_ZIP" "$CMDLINE_URL"
  elif command -v curl &>/dev/null; then
    curl -fsSL -o "$TMP_ZIP" "$CMDLINE_URL"
  else
    _apt_install wget
    wget -q -O "$TMP_ZIP" "$CMDLINE_URL"
  fi

  log "Extracting command-line tools..."
  TMP_EXTRACT="/tmp/cmdline-tools-extract"
  rm -rf "$TMP_EXTRACT"
  unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT"
  # Google ships the zip with a 'cmdline-tools' folder inside
  mv "$TMP_EXTRACT/cmdline-tools" "$ANDROID_SDK_DIR/cmdline-tools/latest"
  rm -rf "$TMP_EXTRACT" "$TMP_ZIP"

  ANDROID_SDK="$ANDROID_SDK_DIR"
fi

export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_SDK_ROOT="$ANDROID_SDK"
SDKMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
export PATH="$ANDROID_SDK/platform-tools:$ANDROID_SDK/cmdline-tools/latest/bin:$PATH"
ok "Android SDK: $ANDROID_SDK"

# Install required SDK packages
log "Installing platform-tools, build-tools $BUILD_TOOLS_VERSION, $ANDROID_PLATFORM ..."
yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK" \
  "platform-tools" \
  "build-tools;${BUILD_TOOLS_VERSION}" \
  "platforms;${ANDROID_PLATFORM}" 2>/dev/null || \
  warn "sdkmanager install encountered warnings — some packages may need manual acceptance."

# Accept licenses
log "Accepting Android SDK licenses..."
yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK" --licenses 2>/dev/null || true
ok "Android SDK packages installed."

# Add to shell profile
EXPORT_ANDROID="export ANDROID_HOME=\"$ANDROID_SDK\"\nexport PATH=\"\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH\""
grep -qF "ANDROID_HOME" "$HOME/.bashrc" 2>/dev/null || printf "\n%b\n" "$EXPORT_ANDROID" >> "$HOME/.bashrc"
if [[ -f "$HOME/.zshrc" ]]; then
  grep -qF "ANDROID_HOME" "$HOME/.zshrc" 2>/dev/null || printf "\n%b\n" "$EXPORT_ANDROID" >> "$HOME/.zshrc"
fi
ok "ANDROID_HOME set in shell profile."

# Flutter Android config
if command -v flutter &>/dev/null || [[ -x "${FLUTTER:-}" ]]; then
  step "Flutter doctor (Android)"
  "${FLUTTER:-flutter}" config --android-sdk "$ANDROID_SDK" 2>/dev/null || true
  yes | "${FLUTTER:-flutter}" doctor --android-licenses 2>/dev/null || true
fi
fi # DO_ANDROID

# ══════════════════════════════════════════════════════════════════════════════
# 5.  LINUX DESKTOP DEPENDENCIES
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$DO_LINUX" == true ]] && [[ "$OS" == "Linux" ]]; then
step "Linux desktop build dependencies"

MISSING=()
for pkg in cmake ninja-build clang lld pkg-config; do
  command -v "$pkg" &>/dev/null || MISSING+=("$pkg")
done
pkg-config --exists gtk+-3.0   2>/dev/null || MISSING+=("libgtk-3-dev")
pkg-config --exists openssl    2>/dev/null || MISSING+=("libssl-dev")
pkg-config --exists libsecret-1 2>/dev/null || MISSING+=("libsecret-1-dev")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  log "Installing: ${MISSING[*]}"
  sudo apt-get install -y clang lld cmake ninja-build pkg-config \
    libgtk-3-dev libssl-dev libblkid-dev liblzma-dev \
    libsecret-1-dev libjsoncpp-dev libsqlite3-dev 2>/dev/null || \
    warn "apt-get install encountered issues. Install manually: ${MISSING[*]}"
else
  ok "All Linux desktop dependencies already satisfied."
fi
fi # DO_LINUX

# ══════════════════════════════════════════════════════════════════════════════
# 6.  IOS REMINDERS (macOS only)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$DO_IOS" == true ]]; then
step "iOS prerequisites"
if [[ "$OS" != "Darwin" ]]; then
  warn "iOS builds require macOS. These steps are only informational on $OS."
fi
log "Required for iOS builds:"
log "  1. Xcode (from the Mac App Store)"
log "  2. sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
log "  3. sudo xcodebuild -runFirstLaunch"
log "  4. CocoaPods: sudo gem install cocoapods"
log "  5. flutter pub get && cd ios && pod install"
if command -v xcodebuild &>/dev/null; then
  ok "Xcode: $(xcodebuild -version 2>&1 | head -1)"
else
  warn "Xcode not found."
fi
if command -v pod &>/dev/null; then
  ok "CocoaPods: $(pod --version)"
else
  warn "CocoaPods not found."
fi
fi # DO_IOS

# ══════════════════════════════════════════════════════════════════════════════
# 7.  GITHUB CLI (gh)
# ══════════════════════════════════════════════════════════════════════════════
step "GitHub CLI (gh)"
if ! command -v gh &>/dev/null; then
  log "Installing GitHub CLI..."
  if command -v apt-get &>/dev/null; then
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
      && rm -f "$out" || warn "Could not install gh via apt."
  elif command -v brew &>/dev/null; then
    brew install gh
  else
    GH_VER="2.65.0"
    case "$ARCH" in x86_64) GH_ARCH="amd64";; aarch64) GH_ARCH="arm64";; *) GH_ARCH="amd64";; esac
    GH_TAR="gh_${GH_VER}_linux_${GH_ARCH}.tar.gz"
    TMP_DIR="$(mktemp -d)"
    wget -q -O "$TMP_DIR/$GH_TAR" "https://github.com/cli/cli/releases/download/v${GH_VER}/${GH_TAR}" \
      || curl -fsSL -o "$TMP_DIR/$GH_TAR" "https://github.com/cli/cli/releases/download/v${GH_VER}/${GH_TAR}"
    tar -xzf "$TMP_DIR/$GH_TAR" -C "$TMP_DIR"
    sudo install -m 755 "$TMP_DIR/gh_${GH_VER}_linux_${GH_ARCH}/bin/gh" /usr/local/bin/gh
    rm -rf "$TMP_DIR"
  fi
fi
if command -v gh &>/dev/null; then
  ok "gh: $(gh --version | head -1)"
else
  warn "GitHub CLI not installed. Install from https://cli.github.com/ to use release-apk.sh"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 8.  MAKE SCRIPTS EXECUTABLE
# ══════════════════════════════════════════════════════════════════════════════
step "Setting script permissions"
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null && ok "All .sh scripts in $SCRIPT_DIR are now executable."

# ══════════════════════════════════════════════════════════════════════════════
# 9.  FLUTTER DOCTOR SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
step "Flutter doctor"
if command -v flutter &>/dev/null; then
  flutter doctor 2>&1 || true
elif [[ -n "${FLUTTER:-}" ]] && [[ -x "$FLUTTER" ]]; then
  "$FLUTTER" doctor 2>&1 || true
else
  warn "flutter not in PATH yet. Open a new terminal (or run: source ~/.bashrc) and then run: flutter doctor"
fi

# ══════════════════════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║  Setup complete!                                 ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
log "Available scripts in $SCRIPT_DIR :"
log "  build-apk.sh     — Build Android APK"
log "  build-ios.sh     — Build iOS IPA"
log "  build-linux.sh   — Build Linux desktop bundle"
log "  build-windows.sh — Build Windows desktop bundle"
log "  sign-apk.sh      — Sign release APKs"
log "  release-apk.sh   — Build + sign + publish to GitHub"
log "  inc_version.sh   — Bump version in pubspec.yaml"
echo ""
warn "If flutter/android tools were just installed, open a new terminal or run:"
warn "  source ~/.bashrc    (or ~/.zshrc)"
echo ""
