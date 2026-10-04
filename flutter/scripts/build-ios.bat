@echo off
:: build-ios.bat — Build Octra Wallet iOS ipa
:: iOS builds require macOS. See build-ios.ps1 for details.
::
:: Usage:
::   build-ios.bat

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%build-ios.ps1"

if not exist "%PS1%" (
    echo [build-ios] ERROR: build-ios.ps1 not found at %PS1%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
