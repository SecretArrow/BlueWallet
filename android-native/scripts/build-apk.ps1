#Requires -Version 5.1
<#
.SYNOPSIS
    Build Octra Wallet Android APK on Windows (Fast Build).
.DESCRIPTION
    Wraps gradlew.bat to build debug or release APKs with incremental build support.
    Uses Gradle daemon for faster subsequent builds.
    Only cleans when -Force parameter is specified.
.PARAMETER BuildType
    'debug' or 'release' (default: debug)
.PARAMETER SplitAbi
    If set, passes -PsplitAbi=true to Gradle to produce per-ABI APKs.
.PARAMETER Force
    If set, performs full clean before build (slower).
.PARAMETER NoDaemon
    If set, disables Gradle daemon (useful for CI/CD).
.PARAMETER TargetAbi
    Target a specific CPU architecture: 'arm64-v8a', 'x86_64', or 'universal'.
.EXAMPLE
    .\scripts\build-apk.ps1 -BuildType release -SplitAbi
    .\scripts\build-apk.ps1 debug
    .\scripts\build-apk.ps1 release -Force
    .\scripts\build-apk.ps1 -BuildType release -TargetAbi arm64-v8a
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('debug', 'release')]
    [string]$BuildType = 'debug',

    [switch]$SplitAbi,
    [switch]$Force,
    [switch]$NoDaemon,
    [ValidateSet('', 'arm64-v8a', 'x86_64', 'universal')]
    [string]$TargetAbi = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Paths
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AndroidDir = Split-Path -Parent $ScriptDir
$GradlewBat = Join-Path $AndroidDir 'gradlew.bat'
$LogDir     = Join-Path $AndroidDir 'build-logs'
$Timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile    = Join-Path $LogDir "build-${BuildType}-${Timestamp}.log"
$ReleaseDir = Join-Path $AndroidDir 'app\build\outputs\apk\release'
$DebugDir   = Join-Path $AndroidDir 'app\build\outputs\apk\debug'

# Versions
$SdkPlatform   = 'android-35'
$SdkBuildTools = '35.0.0'
$SdkNdk        = '27.3.13750724'

# Colour helpers
function Log  { param([string]$M) Write-Host "[build-apk] $M" -ForegroundColor Cyan }
function Ok   { param([string]$M) Write-Host "[build-apk] + $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "[build-apk] * $M" -ForegroundColor Yellow }
function Err  { param([string]$M) Write-Host "[build-apk] x $M" -ForegroundColor Red; exit 1 }

# Logging
try {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    "Build started: $(Get-Date)" | Out-File $LogFile -Encoding UTF8
} catch {
    Warn "Could not create log directory or file: $_"
}

# Auto-increment version (only for release builds)
function Increment-Version {
    if ($BuildType -ne 'release') { return }
    
    $PropsFile = Join-Path $AndroidDir 'version.properties'
    if (-not (Test-Path $PropsFile)) {
        Warn "version.properties not found, skipping version increment"
        return
    }

    try {
        $lines = Get-Content $PropsFile -Raw -Encoding UTF8
        $codeStr = ($lines | Select-String -Pattern '^VERSION_CODE=' -SimpleMatch) -replace '^VERSION_CODE=','' -replace '\s',''
        $nameStr = ($lines | Select-String -Pattern '^VERSION_NAME=' -SimpleMatch) -replace '^VERSION_NAME=','' -replace '\s',''

        if (-not $codeStr -or -not $nameStr) {
            Warn "Could not parse version.properties"
            return
        }

        $newCode = [int]$codeStr + 1

        # Bump patch in VERSION_NAME (e.g. 1.2.3-alpha -> 1.2.4-alpha)
        if ($nameStr -match '^(\d+\.\d+\.)(\d+)(-.+)?$') {
            $newPatch = [int]$Matches[2] + 1
            $newName  = "$($Matches[1])${newPatch}$($Matches[3])"
        } else {
            $newName = $nameStr
        }

        "VERSION_CODE=$newCode`nVERSION_NAME=$newName" | Set-Content $PropsFile -NoNewline -Encoding UTF8
        Log "Version bumped: $nameStr ($codeStr) -> $newName ($newCode)"
    } catch {
        Warn "Failed to increment version: $_"
    }
}

# Selective clean - only remove app/build, not .gradle cache
function Selective-Clean {
    param([switch]$Full)
    
    if ($Full) {
        Log "Running full clean (this will be slow)..."
        Push-Location $AndroidDir
        try {
            & $GradlewBat clean --no-daemon --quiet 2>&1 | Out-Null
        } catch {
            Warn "gradlew clean failed, continuing anyway"
        }
        Pop-Location

        $cachePaths = @(
            (Join-Path $AndroidDir '.gradle'),
            (Join-Path $AndroidDir 'app\build')
        )
        foreach ($p in $cachePaths) {
            if (Test-Path $p) {
                try {
                    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                } catch {
                    Warn "Could not remove $p"
                }
            }
        }
        Ok "Full clean complete"
    } else {
        # Only clean app/build for incremental build
        $appBuildDir = Join-Path $AndroidDir 'app\build'
        if (Test-Path $appBuildDir) {
            Log "Cleaning only app/build (incremental)..."
            try {
                Remove-Item $appBuildDir -Recurse -Force -ErrorAction SilentlyContinue
                Ok "Incremental clean done"
            } catch {
                Warn "Could not clean app/build: $_"
            }
        } else {
            Log "No previous build found, skipping clean"
        }
    }
}

# SDK / Java checks
$SdkDir = $env:ANDROID_HOME
if (-not $SdkDir) { $SdkDir = $env:ANDROID_SDK_ROOT }
if (-not $SdkDir) {
    foreach ($c in @("$env:LOCALAPPDATA\Android\Sdk", "$env:USERPROFILE\android-sdk")) {
        if (Test-Path $c) { $SdkDir = $c; break }
    }
}
if (-not $SdkDir -or -not (Test-Path $SdkDir)) {
    Err "Android SDK not found. Run 'scripts\install.ps1' first."
}
$env:ANDROID_HOME     = $SdkDir
$env:ANDROID_SDK_ROOT = $SdkDir

if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Err "Java not found. Run 'scripts\install.ps1' first."
}

if (-not (Test-Path $GradlewBat)) {
    Err "gradlew.bat not found at $GradlewBat. Run 'scripts\install.ps1' first."
}

# Update local.properties
$PropsFile = Join-Path $AndroidDir 'local.properties'
$SdkPath   = $SdkDir.Replace('\', '/')
if (-not (Test-Path $PropsFile)) {
    "sdk.dir=$SdkPath" | Set-Content $PropsFile -NoNewline -Encoding UTF8
    Log "Created local.properties"
} else {
    $content = Get-Content $PropsFile -Raw -Encoding UTF8
    if ($content -match 'sdk\.dir=') {
        $content = $content -replace 'sdk\.dir=.*', "sdk.dir=$SdkPath"
    } else {
        $content += "`nsdk.dir=$SdkPath"
    }
    Set-Content $PropsFile -Value $content -NoNewline -Encoding UTF8
    Log "Updated local.properties"
}

# Header
Write-Host ""
Write-Host "=== Octra Wallet Android Build Script (Fast) ===" -ForegroundColor Cyan
Write-Host "Build type : $BuildType" -ForegroundColor Cyan
Write-Host "Split ABI  : $SplitAbi" -ForegroundColor Cyan
Write-Host "Force clean: $Force" -ForegroundColor Cyan
Write-Host "No daemon  : $NoDaemon" -ForegroundColor Cyan
Write-Host "Target ABI : $(if ($TargetAbi) { $TargetAbi } else { 'all' })" -ForegroundColor Cyan
Write-Host "Build log  : $LogFile" -ForegroundColor Cyan
Write-Host "Android SDK: $SdkDir" -ForegroundColor Cyan
Write-Host ""

# Increment version only for release
Increment-Version

# Selective clean (default: incremental)
Selective-Clean -Full:$Force

# Gradle build
$GradleTask = if ($BuildType -eq 'release') { 'assembleRelease' } else { 'assembleDebug' }

# Use daemon by default for faster builds (unless NoDaemon is specified)
$GradleArgs = @($GradleTask, '--stacktrace')
if ($NoDaemon) {
    $GradleArgs += '--no-daemon'
} else {
    $GradleArgs += '--daemon'
    Log "Using Gradle daemon for faster builds"
}

# Validate mutually exclusive flags
if ($TargetAbi -and $SplitAbi) {
    Err "-TargetAbi cannot be used with -SplitAbi"
}

if ($SplitAbi) { $GradleArgs += '-PsplitAbi=true' }
if ($TargetAbi -and $TargetAbi -ne 'universal') { $GradleArgs += "-PabiFilters=$TargetAbi" }

Log "Running: gradlew.bat $($GradleArgs -join ' ')"
Push-Location $AndroidDir
try {
    $OldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $GradlewBat $GradleArgs 2>&1 | Out-File $LogFile -Append -Encoding UTF8
    } finally {
        $ErrorActionPreference = $OldEAP
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed with exit code $LASTEXITCODE"
    }
} catch {
    Pop-Location
    Write-Host ""
    Write-Host "=== Build Failed ===" -ForegroundColor Red
    Write-Host "Error: $_"
    Write-Host "See log: $LogFile"
    Write-Host ""
    Write-Host "=== Error Summary ===" -ForegroundColor Red
    if (Test-Path $LogFile) {
        Select-String -Path $LogFile -Pattern 'error:|FAILED|Execution failed' -CaseSensitive:$false |
            Select-Object -First 20 | ForEach-Object { Write-Host $_.Line }
    }
    exit 1
}
Pop-Location

# Verify APKs were built
$FoundApks = @()

if ($BuildType -eq 'release') {
    if ($TargetAbi) {
        if ($TargetAbi -eq 'universal') {
            foreach ($c in @('app-release.apk','app-release-unsigned.apk')) {
                $s = Join-Path $ReleaseDir $c
                if (Test-Path $s) { $FoundApks += $s; break }
            }
        } else {
            $src = Join-Path $ReleaseDir "app-${TargetAbi}-release.apk"
            if (-not (Test-Path $src)) { $src = Join-Path $ReleaseDir "app-${TargetAbi}-release-unsigned.apk" }
            if (Test-Path $src) { $FoundApks += $src }
        }
    } elseif ($SplitAbi) {
        foreach ($abi in @('arm64-v8a', 'x86_64')) {
            $src = Join-Path $ReleaseDir "app-${abi}-release.apk"
            if (-not (Test-Path $src)) { $src = Join-Path $ReleaseDir "app-${abi}-release-unsigned.apk" }
            if (Test-Path $src) {
                $FoundApks += $src
            }
        }
        # Universal fallback
        foreach ($c in @('app-universal-release.apk','app-release.apk','app-release-unsigned.apk')) {
            $s = Join-Path $ReleaseDir $c
            if (Test-Path $s) {
                $FoundApks += $s
                break
            }
        }
    } else {
        foreach ($c in @('app-release.apk','app-release-unsigned.apk')) {
            $s = Join-Path $ReleaseDir $c
            if (Test-Path $s) {
                $FoundApks += $s
                break
            }
        }
    }
} else {
    if ($TargetAbi) {
        if ($TargetAbi -ne 'universal') {
            $s = Join-Path $DebugDir "app-${TargetAbi}-debug.apk"
            if (Test-Path $s) { $FoundApks += $s }
        } else {
            $s = Join-Path $DebugDir 'app-debug.apk'
            if (Test-Path $s) { $FoundApks += $s }
        }
    } elseif ($SplitAbi) {
        foreach ($abi in @('arm64-v8a', 'x86_64')) {
            $s = Join-Path $DebugDir "app-${abi}-debug.apk"
            if (Test-Path $s) {
                $FoundApks += $s
            }
        }
    } else {
        $s = Join-Path $DebugDir 'app-debug.apk'
        if (Test-Path $s) {
            $FoundApks += $s
        }
    }
}

if ($FoundApks.Count -eq 0) {
    Write-Host ""
    Write-Host "=== Build Failed ===" -ForegroundColor Red
    Write-Host "No APKs found in output directories."
    Write-Host "Release dir: $ReleaseDir"
    Write-Host "Debug dir: $DebugDir"
    exit 1
}

Write-Host ""
Write-Host "=== Build Successful ===" -ForegroundColor Green
foreach ($apk in $FoundApks) {
    $size = [math]::Round((Get-Item $apk).Length / 1MB, 2)
    Write-Host "  APK: $apk  ($size MB)" -ForegroundColor Green
}

# Auto-sign release APKs
if ($BuildType -eq 'release') {
    $SignScript = Join-Path $ScriptDir 'sign-apk.ps1'
    if (Test-Path $SignScript) {
        Write-Host ""
        Write-Host "=== Auto-signing release APKs ===" -ForegroundColor Cyan
        try {
            & $SignScript
        } catch {
            Warn "sign-apk.ps1 failed: $_"
        }
    } else {
        Warn "sign-apk.ps1 not found at $SignScript - skipping auto-sign"
    }
}

Write-Host ""
Write-Host "Build log: $LogFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tip: For even faster builds, run without -Force flag" -ForegroundColor Yellow
Write-Host "     Use -Force only when you suspect build cache issues" -ForegroundColor Yellow
