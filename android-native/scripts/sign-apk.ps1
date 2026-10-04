#Requires -Version 5.1
<#
.SYNOPSIS
    Sign Octra Wallet Android release APKs on Windows.
.DESCRIPTION
    Finds every *-release*.apk produced by build-apk.ps1, signs each one with
    the project keystore (octra.jks in the scripts/ folder), and writes signed
    APKs to android\release\.
.EXAMPLE
    .\scripts\sign-apk.ps1          # called by build-apk.ps1 automatically
    .\sign-apk.ps1                  # run from scripts\ folder
#>

[CmdletBinding()]
param(
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Paths
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AndroidDir = Split-Path -Parent $ScriptDir
$Keystore   = Join-Path $ScriptDir 'octra.jks'

# Colour helpers
function Log  { param([string]$M) Write-Host "[sign-apk] $M" -ForegroundColor Cyan }
function Ok   { param([string]$M) Write-Host "[sign-apk] + $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "[sign-apk] * $M" -ForegroundColor Yellow }
function Err  { param([string]$M) Write-Host "[sign-apk] x $M" -ForegroundColor Red; exit 1 }
function Step { param([string]$M) Write-Host "`n== $M ==" -ForegroundColor Cyan }

if ($Help) {
    Get-Content $MyInvocation.MyCommand.Path | Select-String -Pattern '^#' | ForEach-Object { $_.Line -replace '^# ?','' }
    exit 0
}

# Collecting APKs to sign
Step "Collecting APKs to sign"

if (-not (Test-Path $Keystore)) {
    Err "Keystore not found: $Keystore"
}
Log "Keystore: $Keystore"

try {
    $KsPass = Read-Host -Prompt "[sign-apk] Enter keystore password" -AsSecureString
    $KsPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($KsPass))
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($KsPass))
} catch {
    Err "Could not read keystore password: $_"
}

if (-not $KsPassPlain) { Err "Password cannot be empty." }

$GradleOutput = Join-Path $AndroidDir 'app\build\outputs\apk\release'
$InputApks    = @()

try {
    # Only search in Gradle output directory (no duplicates in android root)
    # Match patterns: app-release-unsigned.apk, app-arm64-v8a-release.apk, etc.
    if (Test-Path $GradleOutput) {
        $InputApks = Get-ChildItem -Path $GradleOutput -Filter 'app-*release*.apk' -ErrorAction SilentlyContinue
        # Also match app-release*.apk pattern (for universal APKs)
        $InputApks += Get-ChildItem -Path $GradleOutput -Filter 'app-release*.apk' -ErrorAction SilentlyContinue
        # Deduplicate by filename
        $InputApks = $InputApks | Sort-Object Name -Unique
    }
} catch {
    Warn "Error collecting APKs: $_"
}

if ($InputApks.Count -eq 0) {
    Err "No release APKs found. Run build-apk.ps1 first."
}
Log "Found $($InputApks.Count) APK(s) to sign"

# Locating apksigner
Step "Locating apksigner"

function Find-ApkSigner {
    $sdkHome = $env:ANDROID_HOME
    if (-not $sdkHome) { $sdkHome = $env:ANDROID_SDK_ROOT }
    if (-not $sdkHome) {
        foreach ($c in @("$env:LOCALAPPDATA\Android\Sdk", "$env:USERPROFILE\android-sdk")) {
            if (Test-Path $c) { $sdkHome = $c; break }
        }
    }
    if ($sdkHome) {
        try {
            $found = Get-ChildItem "$sdkHome\build-tools" -Recurse -Filter 'apksigner.bat' -ErrorAction SilentlyContinue |
                     Sort-Object Name | Select-Object -Last 1
            if ($found) { return $found.FullName }
        } catch {
            # Continue to fallback
        }
    }
    # Fallback: PATH
    $cmd = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$ApkSigner = Find-ApkSigner
if (-not $ApkSigner) {
    Err "apksigner not found. Run 'scripts\install.ps1' to install Android SDK build-tools, or ensure ANDROID_HOME is set."
}
Ok "apksigner: $ApkSigner"

# Signing APKs
Step "Signing APKs"

$OutputDir = Join-Path $AndroidDir 'release'
try {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
} catch {
    Warn "Could not create output directory: $_"
}

$SignedCount = 0

foreach ($apk in $InputApks) {
    $name     = $apk.Name
    $stripped = $name -replace '-unsigned',''
    $outName  = [IO.Path]::GetFileNameWithoutExtension($stripped) + '-signed.apk'
    $outPath  = Join-Path $OutputDir $outName

    Log "Signing: $name  ->  release\$outName"

    try {
        & $ApkSigner sign `
            --ks $Keystore `
            --ks-pass "pass:$KsPassPlain" `
            --out $outPath `
            $apk.FullName 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Err "apksigner failed for $name with exit code $LASTEXITCODE"
        }

        # Verify
        & $ApkSigner verify --verbose $outPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Err "Signature verification failed for $outName"
        }

        Ok "Verified: $outName"
        $SignedCount++
    } catch {
        Err "Failed to sign $name`: $_"
    }
}

# Clear plaintext password from memory
$KsPassPlain = $null

# Summary
Step "Summary"

Write-Host ""
Write-Host "  Output directory: $OutputDir" -ForegroundColor Cyan
Write-Host ""

Get-ChildItem $OutputDir -Filter '*.apk' -ErrorAction SilentlyContinue | ForEach-Object {
    $sizeMB = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  + $($_.FullName)  ($sizeMB MB)" -ForegroundColor Green
}

Write-Host ""
Ok "Signed $SignedCount APK(s) successfully!"
