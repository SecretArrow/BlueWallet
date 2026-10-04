@echo off
:: =============================================================================
:: sign-apk.bat — Sign Octra Wallet Android release APKs on Windows
:: Delegates to sign-apk.ps1 via PowerShell.
::
:: Usage:
::   scripts\sign-apk.bat
::   sign-apk.bat          (from scripts\ folder)
:: =============================================================================

setlocal

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "PS_SCRIPT=%SCRIPT_DIR%\sign-apk.ps1"

:: Verify PowerShell is available
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell is required but was not found in PATH.
    echo Install it from https://aka.ms/powershell
    exit /b 1
)

echo Running sign-apk.ps1 via PowerShell...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

if errorlevel 1 (
    echo.
    echo ERROR: sign-apk.ps1 exited with an error.
    exit /b 1
)

endlocal
