@echo off
:: build-windows.bat — Build Octra Wallet Windows Desktop Application
:: Delegates to build-windows.ps1 (PowerShell)
::
:: Usage:
::   build-windows.bat          Build release Windows bundle
::   build-windows.bat -Debug   Build debug Windows bundle
::
:: Requirements: Flutter SDK, Visual Studio 2022 (C++ workload), CMake

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%build-windows.ps1"

if not exist "%PS1%" (
    echo [build-windows] ERROR: build-windows.ps1 not found at %PS1%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
