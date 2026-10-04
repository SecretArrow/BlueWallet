# =============================================================================
# sign-apk.ps1 — Sign Octra Wallet release APKs with the project keystore
# =============================================================================
# Usage:
#   .\sign-apk.ps1
#
# Reads APKs from:   ..\build\app\outputs\flutter-apk\*-release.apk
# Writes signed to:  ..\release\
#
# Requirements:
#   - Android build-tools with apksigner.bat
#   - octra.jks keystore file in the same folder as this script (scripts\)
# =============================================================================
[CmdletBinding()]
param([switch]$Help)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

function Log  { param([string]$m) Write-Host "[sign-apk] $m" -ForegroundColor Cyan }
function Ok   { param([string]$m) Write-Host "[sign-apk] + $m" -ForegroundColor Green }
function Err  { param([string]$m) Write-Host "[sign-apk] x $m" -ForegroundColor Red; exit 1 }
function Step { param([string]$m) Write-Host "`n== $m ==" -ForegroundColor Cyan }

if ($Help) { Get-Content $MyInvocation.MyCommand.Path | Where-Object { $_ -match '^#' } | ForEach-Object { $_ -replace '^# ?','' }; exit 0 }

# Configuration
$Keystore  = "$ScriptDir\octra.jks"
$InputDir  = "$ProjectDir\build\app\outputs\flutter-apk"
$OutputDir = "$ProjectDir\release"

if (-not (Test-Path $Keystore)) { Err "Keystore not found: $Keystore" }
Log "Keystore: $Keystore"

$KsPass = Read-Host -AsSecureString "[sign-apk] Enter keystore password"
$BSTR   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($KsPass)
$KsPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
if (-not $KsPassPlain) { Err "Password cannot be empty." }

# Find apksigner
$ApkSigner = $null
if ($env:ANDROID_HOME) {
    $found = Get-ChildItem "$env:ANDROID_HOME\build-tools" -Recurse -Filter 'apksigner.bat' -ErrorAction SilentlyContinue |
             Sort-Object FullName | Select-Object -Last 1
    if ($found) { $ApkSigner = $found.FullName }
}
if (-not $ApkSigner) {
    $candidates = @(
        "$env:USERPROFILE\android-sdk\build-tools\35.0.0\apksigner.bat",
        "$env:USERPROFILE\android-sdk\build-tools\34.0.0\apksigner.bat",
        "$env:USERPROFILE\Android\Sdk\build-tools\35.0.0\apksigner.bat",
        "$env:USERPROFILE\Android\Sdk\build-tools\34.0.0\apksigner.bat"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $ApkSigner = $c; break } }
}
if (-not $ApkSigner) { Err "apksigner not found. Set env:ANDROID_HOME or run install.ps1 first." }

# Validate prerequisites
Step "Validating prerequisites"
Ok "apksigner: $ApkSigner"
Ok "Keystore: $Keystore"

if (-not (Test-Path $InputDir)) { Err "APK input directory not found: $InputDir" }
$ApkList = Get-ChildItem "$InputDir\*-release.apk" -ErrorAction SilentlyContinue
if ($ApkList.Count -eq 0) { Err "No release APKs found in $InputDir" }
Log "Found $($ApkList.Count) APK(s) to sign"

# Sign each APK
Step "Signing APKs"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$SignedCount = 0

foreach ($apk in $ApkList) {
    $name = $apk.Name
    $out  = "$OutputDir\$name"
    Log "Signing: $name"

    & $ApkSigner sign `
        --ks $Keystore `
        --ks-pass "pass:$KsPassPlain" `
        --out $out `
        $apk.FullName 2>&1 | Out-Null

    # Verify
    $verifyResult = & $ApkSigner verify --verbose $out 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Err "Signature verification failed for $name" }
    Ok "Verified: $name"
    $SignedCount++
}

$KsPassPlain = $null  # Clear plaintext password from memory

# Summary
Step "Summary"
Write-Host ""
Write-Host "  Output directory: $OutputDir" -ForegroundColor White
Write-Host ""

Get-ChildItem "$OutputDir\*.apk" | ForEach-Object {
    $sizeMB = "{0:N2}" -f ($_.Length / 1MB)
    Write-Host "  + $($_.FullName)  ($sizeMB MB)" -ForegroundColor Green
}

Write-Host ""
Ok "Signed $SignedCount APK(s) successfully!"
