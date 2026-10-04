# =============================================================================
# install.ps1 — Install & configure all prerequisites for Octra Wallet Flutter
# =============================================================================
# Usage (run from the scripts\ folder in PowerShell as Administrator):
#   .\install.ps1              Full setup
#   .\install.ps1 -Android     Android / APK toolchain only
#   .\install.ps1 -Linux       Reminder: Linux deps need WSL2
#   .\install.ps1 -Check       Only check what is installed
#
# Requirements: PowerShell 5.1+ or PowerShell 7+
#               Run as Administrator for system-wide installs.
# =============================================================================
[CmdletBinding()]
param(
    [switch]$Android,
    [switch]$Linux,
    [switch]$Check,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir  = Split-Path -Parent $ScriptDir

$FlutterChannel = if ($env:FLUTTER_CHANNEL) { $env:FLUTTER_CHANNEL } else { 'stable' }
$FlutterVersion = if ($env:FLUTTER_VERSION) { $env:FLUTTER_VERSION } else { '' }
$FlutterInstallDir = if ($env:FLUTTER_INSTALL_DIR) { $env:FLUTTER_INSTALL_DIR } else { "$env:USERPROFILE\flutter" }

$AndroidSdkDir          = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:USERPROFILE\android-sdk" }
$CmdlineToolsVersion    = '11076708'
$BuildToolsVersion      = '35.0.0'
$AndroidPlatform        = 'android-35'

# Helpers
function Log  { param([string]$msg) Write-Host "[install] $msg" -ForegroundColor Cyan }
function Ok   { param([string]$msg) Write-Host "[install] + $msg" -ForegroundColor Green }
function Warn { param([string]$msg) Write-Host "[install] * $msg" -ForegroundColor Yellow }
function Err  { param([string]$msg) Write-Host "[install] x $msg" -ForegroundColor Red; exit 1 }
function Step { param([string]$msg) Write-Host "`n== $msg ==" -ForegroundColor Cyan }
function Test-Cmd { param([string]$cmd) $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue) }

function Install-WinGet {
    param([string]$id, [string]$name)
    if (Test-Cmd 'winget') {
        Log "Installing $name via winget..."
        try {
            winget install --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            Ok "$name installed via winget"
        } catch {
            Warn "winget install failed for $name"
        }
    } else {
        Warn "winget not available. Install $name manually: $id"
    }
}

if ($Help) {
    Get-Content $MyInvocation.MyCommand.Path | Where-Object { $_ -match '^#' } | ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

# Check mode
if ($Check) {
    Step "Checking installed tools"
    foreach ($cmd in @('git','java','flutter','gh')) {
        if (Test-Cmd $cmd) {
            $ver = & $cmd --version 2>&1 | Select-Object -First 1
            Ok "${cmd}: $ver"
        } else {
            Warn "${cmd}: NOT FOUND"
        }
    }
    if ($env:ANDROID_HOME -and (Test-Path $env:ANDROID_HOME)) {
        Ok "ANDROID_HOME: $env:ANDROID_HOME"
    } else {
        Warn "ANDROID_HOME: not set / not found"
    }
    exit 0
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    Octra Wallet - Windows Dev Setup  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Log "Project root : $ProjectDir"
Log "Scripts dir  : $ScriptDir"
Write-Host ""

# 1. GIT
Step "Git"
if (-not (Test-Cmd 'git')) {
    Install-WinGet 'Git.Git' 'Git'
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
}
if (Test-Cmd 'git') { Ok "git: $(git --version)" } else { Warn "git not found after install attempt." }

# 2. JAVA (JDK 17)
Step "Java (JDK 17)"
if (-not (Test-Cmd 'java')) {
    Install-WinGet 'EclipseAdoptium.Temurin.17.JDK' 'Temurin JDK 17'
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
}
if (Test-Cmd 'java') {
    Ok "java: $(java -version 2>&1 | Select-Object -First 1)"
} else {
    Warn "Java not found. Install JDK 17 from https://adoptium.net/ and re-run."
}

# 3. FLUTTER SDK
Step "Flutter SDK"
$FlutterExe = $null

# Search for existing Flutter
$FlutterCandidates = @(
    "$env:USERPROFILE\flutter\bin\flutter.bat",
    "$env:USERPROFILE\development\flutter\bin\flutter.bat",
    "C:\flutter\bin\flutter.bat",
    "C:\src\flutter\bin\flutter.bat"
)
foreach ($c in $FlutterCandidates) {
    if (Test-Path $c) { $FlutterExe = $c; break }
}
if (-not $FlutterExe -and (Test-Cmd 'flutter')) { $FlutterExe = 'flutter' }

if (-not $FlutterExe) {
    Log "Flutter not found - cloning into $FlutterInstallDir ..."
    if (-not (Test-Path $FlutterInstallDir)) {
        $branch = if ($FlutterVersion) { $FlutterVersion } else { $FlutterChannel }
        if (-not (Test-Cmd 'git')) { Err "git not found. Install from https://git-scm.com" }
        git clone --depth 1 --branch $branch https://github.com/flutter/flutter.git $FlutterInstallDir
    }
    $FlutterExe = "$FlutterInstallDir\bin\flutter.bat"
    $flutterBin = "$FlutterInstallDir\bin"
    $currentUser = [System.Environment]::GetEnvironmentVariable('Path','User')
    if ($currentUser -notlike "*$flutterBin*") {
        [System.Environment]::SetEnvironmentVariable('Path', "$currentUser;$flutterBin", 'User')
        Log "Added $flutterBin to user PATH."
    }
    $env:Path += ";$flutterBin"
}

Ok "Flutter found: $FlutterExe"
& $FlutterExe --version 2>&1 | Select-Object -First 1

# 4. ANDROID SDK
if ($Android -or (-not $Linux)) {
Step "Android SDK"

$AndroidSdk = $null
$AndroidCandidates = @(
    $env:ANDROID_HOME,
    $env:ANDROID_SDK_ROOT,
    "$env:USERPROFILE\android-sdk",
    "$env:USERPROFILE\Android\Sdk",
    "$env:LOCALAPPDATA\Android\Sdk"
)
foreach ($c in $AndroidCandidates) {
    if ($c -and (Test-Path "$c\platform-tools")) { $AndroidSdk = $c; break }
}

if (-not $AndroidSdk) {
    Log "Android SDK not found - downloading command-line tools to $AndroidSdkDir ..."
    New-Item -ItemType Directory -Force -Path "$AndroidSdkDir\cmdline-tools" | Out-Null
    $CmdlineZip = "commandlinetools-win-${CmdlineToolsVersion}_latest.zip"
    $CmdlineUrl = "https://dl.google.com/android/repository/$CmdlineZip"
    $TmpZip     = "$env:TEMP\$CmdlineZip"
    Log "Downloading: $CmdlineUrl"
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest -Uri $CmdlineUrl -OutFile $TmpZip -UseBasicParsing
    } catch {
        # Fallback to WebClient
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($CmdlineUrl, $TmpZip)
        $wc.Dispose()
    }
    
    Log "Extracting..."
    Expand-Archive -Path $TmpZip -DestinationPath "$env:TEMP\cmdline-tools-extract" -Force
    Remove-Item "$env:TEMP\cmdline-tools-extract\cmdline-tools" -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item "$env:TEMP\cmdline-tools-extract\cmdline-tools" "$AndroidSdkDir\cmdline-tools\latest" -Force
    Remove-Item "$env:TEMP\cmdline-tools-extract" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $TmpZip -Force -ErrorAction SilentlyContinue
    $AndroidSdk = $AndroidSdkDir
}

$env:ANDROID_HOME     = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$SdkManager = "$AndroidSdk\cmdline-tools\latest\bin\sdkmanager.bat"
$env:Path += ";$AndroidSdk\platform-tools;$AndroidSdk\cmdline-tools\latest\bin"
Ok "Android SDK: $AndroidSdk"

Log "Installing SDK packages (platform-tools, build-tools, platform)..."
$packages = "platform-tools", "build-tools;$BuildToolsVersion", "platforms;$AndroidPlatform"
foreach ($pkg in $packages) {
    try {
        & $SdkManager --sdk_root="$AndroidSdk" $pkg 2>&1 | Out-Null
    } catch {
        Warn "Failed to install $pkg"
    }
}

Log "Accepting licenses..."
$yesInput = , "y" * 10
$yesInput | & $SdkManager --sdk_root="$AndroidSdk" --licenses 2>&1 | Out-Null
Ok "Android SDK packages installed."

# Persist environment variables
[System.Environment]::SetEnvironmentVariable('ANDROID_HOME', $AndroidSdk, 'User')
[System.Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $AndroidSdk, 'User')
$userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
if ($userPath -notlike "*$AndroidSdk\platform-tools*") {
    [System.Environment]::SetEnvironmentVariable('Path', "$userPath;$AndroidSdk\platform-tools;$AndroidSdk\cmdline-tools\latest\bin", 'User')
}
Ok "ANDROID_HOME persisted to user environment."

# Flutter Android config
if ($FlutterExe) {
    & $FlutterExe config --android-sdk $AndroidSdk 2>&1 | Out-Null
    $yesInput = , "y" * 10
    $yesInput | & $FlutterExe doctor --android-licenses 2>&1 | Out-Null
}
} # Android

# 5. VISUAL STUDIO BUILD TOOLS (Windows desktop builds)
if (-not $Android -and -not $Linux) {
Step "Visual Studio Build Tools (Windows desktop)"
if (-not (Test-Cmd 'cl') -and -not (Test-Cmd 'g++')) {
    Warn "No C++ compiler detected."
    Log "For Windows desktop builds, install Visual Studio 2022 with 'Desktop development with C++'"
    Log "  winget install Microsoft.VisualStudio.2022.Community"
    Log "  OR install MinGW via MSYS2: https://www.msys2.org/"
} else {
    Ok "C++ compiler available."
}
if (-not (Test-Cmd 'cmake')) {
    Log "Installing CMake..."
    Install-WinGet 'Kitware.CMake' 'CMake'
}
if (Test-Cmd 'cmake') { Ok "CMake: $(cmake --version | Select-Object -First 1)" }
} # Windows desktop

# 6. GITHUB CLI
Step "GitHub CLI (gh)"
if (-not (Test-Cmd 'gh')) {
    Install-WinGet 'GitHub.cli' 'GitHub CLI'
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
}
if (Test-Cmd 'gh') { Ok "gh: $(gh --version | Select-Object -First 1)" } else { Warn "gh not found. Install from https://cli.github.com/" }

# 7. FLUTTER DOCTOR SUMMARY
Step "Flutter doctor"
if ($FlutterExe) {
    & $FlutterExe doctor 2>&1
} elseif (Test-Cmd 'flutter') {
    flutter doctor 2>&1
}

# DONE
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Setup complete!                     " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Log "Available scripts in $ScriptDir :"
Log "  build-apk.ps1     - Build Android APK"
Log "  build-windows.ps1 - Build Windows desktop app"
Log "  sign-apk.ps1      - Sign release APKs"
Log "  release-apk.ps1   - Build + sign + publish to GitHub"
Log "  inc_version.ps1   - Bump version in pubspec.yaml"
Write-Host ""
Warn "Open a new PowerShell window so the updated PATH takes effect."
Write-Host ""
