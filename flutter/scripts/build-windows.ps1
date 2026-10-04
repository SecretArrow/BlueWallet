# =============================================================================
# build-windows.ps1 — Build Octra Wallet Windows Desktop App
# =============================================================================
# Usage:
#   .\build-windows.ps1          Build release Windows bundle
#   .\build-windows.ps1 -Debug   Build debug Windows bundle
#
# Requirements:
#   - Flutter SDK
#   - Visual Studio 2022 (Desktop development with C++ workload)
#     OR MSYS2 with mingw-w64-x86_64-gcc
#   - CMake 3.14+
#
# Output:
#   build\windows\x64\runner\Release\   (release)
#   build\windows\x64\runner\Debug\     (debug)
#
# Environment overrides (optional):
#   $env:FLUTTER_BIN     — path to flutter.bat
#   $env:FLUTTER_CHANNEL — Flutter channel if auto-installing (default: stable)
#   $env:FLUTTER_VERSION — specific Flutter version tag (e.g. 3.24.3)
# =============================================================================
[CmdletBinding()]
param(
    [switch]$Debug,
    [switch]$Force,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

$FlutterChannel = if ($env:FLUTTER_CHANNEL) { $env:FLUTTER_CHANNEL } else { 'stable' }
$FlutterVersion = if ($env:FLUTTER_VERSION) { $env:FLUTTER_VERSION } else { '' }
$Mode = if ($Debug) { 'debug' } else { 'release' }

function Log  { param([string]$m) Write-Host "[build-windows] $m" -ForegroundColor Cyan }
function Warn { param([string]$m) Write-Host "[build-windows] * $m" -ForegroundColor Yellow }
function Ok   { param([string]$m) Write-Host "[build-windows] + $m" -ForegroundColor Green }
function Err  { param([string]$m) Write-Host "[build-windows] x $m" -ForegroundColor Red; exit 1 }
function Step { param([string]$m) Write-Host "`n== $m ==" -ForegroundColor Cyan }
function Test-Cmd { param([string]$c) $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }

if ($Help) { Get-Content $MyInvocation.MyCommand.Path | Where-Object { $_ -match '^#' } | ForEach-Object { $_ -replace '^# ?','' }; exit 0 }

# Platform guard
if ($env:OS -ne 'Windows_NT') { Err "Windows builds must be run on Windows." }

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

# CMake / C++ compiler check
Step "Checking build tools"
if (-not (Test-Cmd 'cmake')) { Err "CMake not found. Install from https://cmake.org or: winget install Kitware.CMake" }
Ok "CMake: $(cmake --version | Select-Object -First 1)"

if (Test-Cmd 'cl') {
    Ok "MSVC compiler found."
} elseif (Test-Cmd 'g++') {
    Ok "MinGW g++ found: $(g++ --version | Select-Object -First 1)"
} else {
    Warn "No C++ compiler detected. Install Visual Studio 2022 (C++ workload) or MSYS2 mingw64."
}

# Flutter precache
Step "Flutter precache (Windows)"
& $FlutterExe precache --windows 2>&1 | Out-Null
Ok "Precache done."

# Project dependencies (incremental by default)
Step "Project dependencies"
Log "Project: $ProjectDir"
Push-Location $ProjectDir
try {
    if ($Force) {
        Log "Full clean requested..."
        & $FlutterExe clean 2>&1 | Out-Null
        Ok "Clean done."
    } else {
        Log "Using incremental build (skip clean)"
    }
    
    Log "Running flutter pub get..."
    & $FlutterExe pub get 2>&1 | Out-Null
    Ok "Dependencies resolved."
} finally {
    Pop-Location
}

# Read and bump version
Step "Version bump"
$Pubspec    = "$ProjectDir\pubspec.yaml"
$content    = Get-Content $Pubspec -Raw
$verLine    = (Get-Content $Pubspec | Where-Object { $_ -match '^version:' } | Select-Object -First 1)
$fullVer    = ($verLine -replace 'version:\s*','').Trim()
$BuildName  = $fullVer.Split('+')[0]
$oldBuild   = [int]$fullVer.Split('+')[1]
$BuildNum   = $oldBuild + 1

$content    = $content -replace '(?m)^version:.*', "version: $BuildName+$BuildNum"
Set-Content -Path $Pubspec -Value $content -NoNewline
Ok "Version: $BuildName+$BuildNum  (was +$oldBuild)"

# Build
Step "Building Windows app  [mode: $Mode]"
Push-Location $ProjectDir
try {
    if ($Debug) {
        & $FlutterExe build windows --debug --build-name $BuildName --build-number $BuildNum 2>&1 | Out-Null
        $OutputDir = "$ProjectDir\build\windows\x64\runner\Debug"
    } else {
        & $FlutterExe build windows --release --build-name $BuildName --build-number $BuildNum 2>&1 | Out-Null
        $OutputDir = "$ProjectDir\build\windows\x64\runner\Release"
    }
} finally {
    Pop-Location
}

Write-Host ""
Ok "Bundle written to: $OutputDir"
if (Test-Path $OutputDir) {
    Get-ChildItem $OutputDir | Format-Table Name,@{n='Size';e={if ($_.PSIsContainer) {'<dir>'} else {"{0:N2} MB" -f ($_.Length/1MB)}}}
}

Write-Host ""
Ok "All done!"
Write-Host ""
Write-Host "Build Summary:" -ForegroundColor Cyan
Write-Host "  Mode     : $Mode" -ForegroundColor Cyan
Write-Host "  Clean    : $(if ($Force) { 'Full' } else { 'Incremental (fast)' })" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tip: For faster builds, omit -Force flag" -ForegroundColor Yellow
Write-Host "     Use -Force only when you suspect build issues" -ForegroundColor Yellow
