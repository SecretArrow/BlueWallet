# =============================================================================
# build-ios.ps1 — Build Octra Wallet iOS IPA
# =============================================================================
# iOS builds require macOS with Xcode and CocoaPods installed.
# This script is provided for documentation purposes only.
# To build for iOS, run build-ios.sh on a macOS machine.
# =============================================================================
[CmdletBinding()]
param([switch]$Help)

Write-Host ""
Write-Host "==========================================" -ForegroundColor Yellow
Write-Host "  iOS builds are not supported on Windows" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "iOS builds require macOS with:" -ForegroundColor Cyan
Write-Host "  - Xcode (from the Mac App Store)" -ForegroundColor Cyan
Write-Host "  - CocoaPods: sudo gem install cocoapods" -ForegroundColor Cyan
Write-Host "  - A valid Apple Developer account and signing certificate" -ForegroundColor Cyan
Write-Host ""
Write-Host "On macOS, run:" -ForegroundColor Green
Write-Host "  bash scripts/build-ios.sh" -ForegroundColor Green
Write-Host ""
Write-Host "Alternatively, use a CI service that provides macOS runners" -ForegroundColor Cyan
Write-Host "(GitHub Actions, Bitrise, Codemagic, etc.)" -ForegroundColor Cyan
Write-Host ""
