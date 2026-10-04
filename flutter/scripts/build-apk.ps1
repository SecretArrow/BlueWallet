# =============================================================================
# build-apk.ps1 — Build Octra Wallet Android APK (Fast Build)
# =============================================================================
# Usage:
#   .\build-apk.ps1              Build release APK (incremental)
#   .\build-apk.ps1 -Debug       Build debug APK (incremental)
#   .\build-apk.ps1 -SplitAbi    Build per-ABI release APKs
#   .\build-apk.ps1 -Install     Build release APK and install to device
#   .\build-apk.ps1 -Force       Force full clean before build (slower)
#   .\build-apk.ps1 -NoDaemon    Disable Flutter daemon (for CI/CD)
#   .\build-apk.ps1 -TargetAbi arm64-v8a   Build only for arm64-v8a
#   .\build-apk.ps1 -TargetAbi armeabi-v7a Build only for armeabi-v7a
#   .\build-apk.ps1 -TargetAbi x86_64      Build only for x86_64
#   .\build-apk.ps1 -TargetAbi universal   Build universal APK
#
# Environment overrides (optional):
#   $env:FLUTTER_BIN     — path to flutter.bat
#   $env:ANDROID_HOME    — path to Android SDK root
#   $env:FLUTTER_CHANNEL — Flutter channel if auto-installing (default: stable)
#   $env:FLUTTER_VERSION — specific Flutter version tag (e.g. 3.24.3)
#
# Output: build\app\outputs\flutter-apk\
# =============================================================================
[CmdletBinding()]
param(
    [switch]$BuildDebug,
    [switch]$SplitAbi,
    [switch]$Install,
    [switch]$Force,
    [switch]$NoDaemon,
    [ValidateSet('', 'arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal')]
    [string]$TargetAbi = '',
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

$FlutterChannel = if ($env:FLUTTER_CHANNEL) { $env:FLUTTER_CHANNEL } else { 'stable' }
$FlutterVersion = if ($env:FLUTTER_VERSION) { $env:FLUTTER_VERSION } else { '' }
$Mode = if ($BuildDebug) { 'debug' } else { 'release' }

# Validate mutually exclusive flags
if ($TargetAbi -and $SplitAbi) { Err "-TargetAbi cannot be used with -SplitAbi" }

# Map ABI to Flutter target-platform
function Get-TargetPlatform {
    param([string]$abi)
    switch ($abi) {
        'arm64-v8a'   { 'android-arm64' }
        'armeabi-v7a' { 'android-arm' }
        'x86_64'      { 'android-x64' }
        default       { '' }
    }
}

function Log  { param([string]$m) Write-Host "[build-apk] $m" -ForegroundColor Cyan }
function Warn { param([string]$m) Write-Host "[build-apk] * $m" -ForegroundColor Yellow }
function Ok   { param([string]$m) Write-Host "[build-apk] + $m" -ForegroundColor Green }
function Err  { param([string]$m) Write-Host "[build-apk] x $m" -ForegroundColor Red; exit 1 }
function Step { param([string]$m) Write-Host "`n== $m ==" -ForegroundColor Cyan }
function Test-Cmd { param([string]$c) $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }

if ($Help) {
    Get-Content $MyInvocation.MyCommand.Path | Select-String -Pattern '^#' | ForEach-Object { $_.Line -replace '^# ?','' }
    exit 0
}

# Locate Flutter
Step "Locating Flutter"
$FlutterExe = $null
if ($env:FLUTTER_BIN -and (Test-Path $env:FLUTTER_BIN)) { $FlutterExe = $env:FLUTTER_BIN }
if (-not $FlutterExe -and (Test-Cmd 'flutter')) { $FlutterExe = 'flutter' }
$candidates = @(
    "$env:USERPROFILE\flutter\bin\flutter.bat",
    "$env:USERPROFILE\development\flutter\bin\flutter.bat",
    "C:\flutter\bin\flutter.bat",
    "C:\src\flutter\bin\flutter.bat",
    "$env:LOCALAPPDATA\flutter\bin\flutter.bat"
)
foreach ($c in $candidates) { if (-not $FlutterExe -and (Test-Path $c)) { $FlutterExe = $c } }

if (-not $FlutterExe) {
    Step "Flutter not found - auto-installing"
    $fdir = "$env:USERPROFILE\flutter"
    $branch = if ($FlutterVersion) { $FlutterVersion } else { $FlutterChannel }
    if (-not (Test-Path $fdir)) {
        if (-not (Test-Cmd 'git')) { Err "git not found. Install from https://git-scm.com" }
        git clone --depth 1 --branch $branch https://github.com/flutter/flutter.git $fdir
    }
    $FlutterExe = "$fdir\bin\flutter.bat"
    $env:Path += ";$fdir\bin"
}
if (-not (Test-Path $FlutterExe) -and -not (Test-Cmd $FlutterExe)) { Err "Flutter not found at: $FlutterExe" }
Ok "Flutter: $FlutterExe"
& $FlutterExe --version 2>&1 | Select-Object -First 1

# Locate Android SDK
Step "Configuring Android SDK"
$AndroidSdk = $null
foreach ($c in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:USERPROFILE\android-sdk",
                  "$env:USERPROFILE\Android\Sdk", "$env:LOCALAPPDATA\Android\Sdk")) {
    if ($c -and (Test-Path "$c\platform-tools")) { $AndroidSdk = $c; break }
}
if (-not $AndroidSdk) { Err "Android SDK not found. Set env:ANDROID_HOME or run install.ps1 first." }
$env:ANDROID_HOME     = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:Path += ";$AndroidSdk\platform-tools;$AndroidSdk\cmdline-tools\latest\bin"
Ok "Android SDK: $AndroidSdk"

# Java check
Step "Checking Java"
if (-not (Test-Cmd 'java')) { Err "Java not found. Run install.ps1 first." }
$JavaVer = "Found"
try {
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $JavaVer = & java -version 2>&1 | Select-Object -First 1
    $ErrorActionPreference = $oldEAP
} catch {
    $JavaVer = "Found (version check failed to print)"
}
Ok "java: $JavaVer"

# Project dependencies (NO CLEAN by default)
Step "Project dependencies"
Log "Project: $ProjectDir"
Push-Location $ProjectDir
try {
    # Only clean if -Force is specified
    if ($Force) {
        Log "Full clean requested with -Force..."
        & $FlutterExe clean 2>&1 | Out-Null
        if (Test-Path "$ProjectDir\android\.gradle") { Remove-Item -Recurse -Force "$ProjectDir\android\.gradle" -ErrorAction SilentlyContinue }
        if (Test-Path "$ProjectDir\android\build") { Remove-Item -Recurse -Force "$ProjectDir\android\build" -ErrorAction SilentlyContinue }
        Ok "Full clean done"
    } else {
        Log "Using incremental build (skip clean)"
        # Only run pub get to ensure dependencies
        Log "Running flutter pub get..."
        & $FlutterExe pub get 2>&1 | Out-Null
        Ok "Dependencies resolved"
    }
} finally {
    Pop-Location
}

# Read version
Step "Version"
$Pubspec    = "$ProjectDir\pubspec.yaml"
$VerLine    = (Get-Content $Pubspec | Where-Object { $_ -match '^version:' } | Select-Object -First 1)
$FullVer    = ($VerLine -replace 'version:\s*','').Trim()
$BuildName  = $FullVer.Split('+')[0]
$BuildNum   = $FullVer.Split('+')[1]
Ok "Version: $BuildName+$BuildNum"

# Build APK
Step "Building APK  [mode: $Mode, target: $(if ($TargetAbi) { $TargetAbi } else { 'all' })]"
$OutputDir = "$ProjectDir\build\app\outputs\flutter-apk"

# Build arguments
$BuildArgs = @('build', 'apk')
if ($BuildDebug) {
    $BuildArgs += '--debug'
} else {
    $BuildArgs += '--release'
}

if ($NoDaemon) {
    $BuildArgs += '--no-pub'
}

$BuildArgs += '--build-name', $BuildName
$BuildArgs += '--build-number', $BuildNum

if ($SplitAbi) {
    # For split-ABI, we need to build each platform separately
    $abiMatrix = @(
        @{ Platform='android-arm';   Abi='armeabi-v7a' },
        @{ Platform='android-arm64'; Abi='arm64-v8a'   },
        @{ Platform='android-x64';   Abi='x86_64'      }
    )
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    foreach ($e in $abiMatrix) {
        Log "Building $($e.Abi) ..."
        Push-Location $ProjectDir
        try {
            $specificArgs = $BuildArgs + @('--target-platform', $e.Platform)
            & $FlutterExe $specificArgs 2>&1 | Out-Null
        } finally {
            Pop-Location
        }
        $src = "$OutputDir\app-release.apk"
        $dst = "$OutputDir\app-$($e.Abi)-release.apk"
        if (-not (Test-Path $src)) { Err "Expected APK not found: $src" }
        Copy-Item $src $dst -Force
        Ok "Created $(Split-Path $dst -Leaf)"
    }
} elseif ($TargetAbi -and $TargetAbi -ne 'universal') {
    $platform = Get-TargetPlatform $TargetAbi
    if (-not $platform) { Err "Unknown ABI: $TargetAbi" }
    Log "Building $TargetAbi APK (target-platform: $platform)..."
    $specificArgs = $BuildArgs + @('--target-platform', $platform)
    Push-Location $ProjectDir
    try {
        & $FlutterExe $specificArgs 2>&1 | Out-Null
    } finally {
        Pop-Location
    }
    $srcApk = if ($BuildDebug) { "$OutputDir\app-debug.apk" } else { "$OutputDir\app-release.apk" }
    $dstApk = "$OutputDir\app-${TargetAbi}-${Mode}.apk"
    if (Test-Path $srcApk) {
        Copy-Item $srcApk $dstApk -Force
        Ok "Created $(Split-Path $dstApk -Leaf)"
    }
} else {
    Push-Location $ProjectDir
    try {
        & $FlutterExe $BuildArgs 2>&1 | Out-Null
    } finally {
        Pop-Location
    }
}

Write-Host ""
Ok "APK(s) written to: $OutputDir"
Get-ChildItem "$OutputDir\*.apk" -ErrorAction SilentlyContinue | Format-Table Name,@{n='Size';e={"{0:N2} MB" -f ($_.Length/1MB)}}

# Optional install
if ($Install) {
    Step "Installing to device"
    $adbOutput = adb devices 2>&1
    if ($adbOutput -match 'device$') {
        Push-Location $ProjectDir
        try {
            & $FlutterExe install 2>&1 | Out-Null
        } finally {
            Pop-Location
        }
        Ok "Installed to device."
    } else {
        Warn "No device connected via adb."
    }
}

Write-Host ""
Ok "All done!"
Write-Host ""
Write-Host "Build Summary:" -ForegroundColor Cyan
Write-Host "  Mode     : $Mode" -ForegroundColor Cyan
Write-Host "  Clean    : $(if ($Force) { 'Full' } else { 'Incremental (fast)' })" -ForegroundColor Cyan
Write-Host "  SplitAbi : $SplitAbi" -ForegroundColor Cyan
Write-Host "  Target   : $(if ($TargetAbi) { $TargetAbi } else { 'all' })" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tip: For faster builds, omit -Force flag" -ForegroundColor Yellow
Write-Host "     Use -Force only when you suspect build issues" -ForegroundColor Yellow
