@echo off
:: build-linux.bat — Build Octra Wallet Linux desktop bundle
:: Linux builds require Linux or WSL2. Delegates to build-linux.ps1.
::
:: Usage:
::   build-linux.bat        Show instructions
::   build-linux.bat -Wsl   Run build-linux.sh inside WSL2

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%build-linux.ps1"

if not exist "%PS1%" (
    echo [build-linux] ERROR: build-linux.ps1 not found at %PS1%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
