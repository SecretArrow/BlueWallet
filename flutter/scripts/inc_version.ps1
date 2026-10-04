# =============================================================================
# inc_version.ps1 — Bump version using 1.x.0+x scheme and push
# =============================================================================
# Version format in pubspec.yaml:  1.x.0+x
#   version name  = 1.x.0   (shown to users, e.g. "1.16.0")
#   build number  = x       (Android versionCode)
# Both parts share the same counter x, incremented together.
#
# Usage:
#   .\inc_version.ps1
# =============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$Pubspec    = "$ProjectDir\pubspec.yaml"

function Ok  { param([string]$m) Write-Host "+ $m" -ForegroundColor Green }
function Err { param([string]$m) Write-Host "x $m" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $Pubspec)) { Err "pubspec.yaml not found at: $Pubspec" }

# Read current version
$verLine = Get-Content $Pubspec | Where-Object { $_ -match '^version: ' } | Select-Object -First 1
if (-not $verLine) { Err "Could not find 'version:' line in pubspec.yaml" }

$current = ($verLine -replace '^version: ','').Trim()

if ($current -notmatch '^1\.\d+\.\d+\+\d+$') {
    Err "Unsupported version format: '$current'. Expected: 1.x.0+x (e.g. 1.15.0+15)"
}

$buildNum = [int]($current -split '\+')[1]
$newX     = $buildNum + 1
$newVer   = "1.${newX}.0+${newX}"

# Update pubspec.yaml
$content = Get-Content $Pubspec -Raw
$content = $content -replace '(?m)^version: .*', "version: $newVer"
Set-Content -Path $Pubspec -Value $content -NoNewline

Write-Host "Version bumped: $current  ->  $newVer" -ForegroundColor Green

# Git: stage, commit, push
Push-Location $ProjectDir
try {
    git add .
    git commit -m "v$newVer"
    git push
} finally {
    Pop-Location
}

Ok "Done. Version $newVer pushed."
