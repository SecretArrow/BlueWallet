@echo off
:: release-apk.bat — Build, Sign, and Publish Octra Wallet APK to GitHub
:: Delegates to release-apk.ps1 (PowerShell)
::
:: Usage:
::   release-apk.bat                   Auto-detect version
::   release-apk.bat -Tag v1.2.0       Override release tag
::   release-apk.bat -Draft            Create a draft release
::   release-apk.bat -Prerelease       Mark as pre-release
::   release-apk.bat -Notes "msg"      Custom release notes
::   release-apk.bat -SplitAbi         Build per-ABI APKs
::   release-apk.bat -SkipBuild        Skip build (use existing APK)
::   release-apk.bat -SkipSign         Skip signing
::   release-apk.bat -DryRun           Do everything except GitHub release
::
:: Environment: set GITHUB_TOKEN=<token>  for non-interactive auth

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%release-apk.ps1"

if not exist "%PS1%" (
    echo [release-apk] ERROR: release-apk.ps1 not found at %PS1%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
