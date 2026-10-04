@echo off
:: =============================================================================
:: install.bat — Bootstrap all build requirements for Octra Wallet (Android)
:: Delegates to install.ps1 via PowerShell.
:: Run from the android\ root:   scripts\install.bat
:: Run from scripts\ folder:     install.bat
:: =============================================================================

setlocal

:: Resolve this script's directory so it can be called from anywhere
set "SCRIPT_DIR=%~dp0"
:: Strip trailing backslash
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "PS_SCRIPT=%SCRIPT_DIR%\install.ps1"

:: Verify PowerShell is available
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell is required but was not found in PATH.
    echo Install it from https://aka.ms/powershell
    exit /b 1
)

echo Running install.ps1 via PowerShell...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

if errorlevel 1 (
    echo.
    echo ERROR: install.ps1 exited with an error.
    exit /b 1
)

echo.
echo Setup complete.
endlocal
