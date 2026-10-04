@echo off
:: inc_version.bat — Bump version in pubspec.yaml and push
:: Delegates to inc_version.ps1 (PowerShell)
::
:: Usage:
::   inc_version.bat

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%inc_version.ps1"

if not exist "%PS1%" (
    echo [inc_version] ERROR: inc_version.ps1 not found at %PS1%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
