@echo off
:: install.bat — Install all prerequisites for Octra Wallet Flutter on Windows
:: Delegates to install.ps1 (PowerShell)
::
:: Usage:
::   install.bat              Full setup
::   install.bat -Android     Android toolchain only
::   install.bat -Check       Only check installed tools
::
:: Run this file as Administrator for system-wide installs.

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%install.ps1"

if not exist "%PS1%" (
    echo [install] ERROR: install.ps1 not found at %PS1%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
