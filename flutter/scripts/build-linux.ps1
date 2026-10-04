# =============================================================================
# build-linux.ps1 — Build Octra Wallet Linux Desktop Bundle
# =============================================================================
# Linux desktop builds require Linux (or WSL2) with the required system
# libraries installed.  On a native Windows machine, use WSL2.
#
# Usage:
#   .\build-linux.ps1          Show instructions for building via WSL2
#   .\build-linux.ps1 -Wsl     Attempt to run build-linux.sh inside WSL2
# =============================================================================
[CmdletBinding()]
param([switch]$Wsl)

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-Cmd { param([string]$c) $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }

if ($Wsl) {
    if (-not (Test-Cmd 'wsl')) {
        Write-Host "[build-linux] x WSL2 not found. Enable it with: wsl --install" -ForegroundColor Red
        exit 1
    }
    $wslScriptPath = wsl wslpath -a ($ScriptDir.Replace('\','/'))
    Write-Host "[build-linux] Running build-linux.sh inside WSL2..." -ForegroundColor Cyan
    wsl bash "$wslScriptPath/build-linux.sh"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  Linux desktop builds require Linux      " -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Options:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Use WSL2 (recommended on Windows):" -ForegroundColor Green
Write-Host "       .\build-linux.ps1 -Wsl" -ForegroundColor White
Write-Host "     OR manually:" -ForegroundColor White
Write-Host "       wsl bash scripts/build-linux.sh" -ForegroundColor White
Write-Host ""
Write-Host "  2. Use a Linux machine / VM / CI runner:" -ForegroundColor Green
Write-Host "       bash scripts/build-linux.sh" -ForegroundColor White
Write-Host ""
Write-Host "  3. Enable WSL2 if not already installed:" -ForegroundColor Green
Write-Host "       wsl --install    (run in an elevated PowerShell)" -ForegroundColor White
Write-Host ""
