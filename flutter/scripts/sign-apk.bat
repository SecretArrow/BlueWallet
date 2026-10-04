@echo off
:: sign-apk.bat — Sign Octra Wallet release APKs
:: Delegates to sign-apk.ps1 (PowerShell)
::
:: Usage:
::   sign-apk.bat
::
:: Requirements: Android build-tools (apksigner), octra.jks in this folder

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%sign-apk.ps1"

if not exist "%PS1%" (
    echo [sign-apk] ERROR: sign-apk.ps1 not found at %PS1%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
