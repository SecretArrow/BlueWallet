@echo off
:: =============================================================================
:: build-apk.bat — Build Octra Wallet Android APK on Windows
:: Delegates to build-apk.ps1 via PowerShell.
::
:: Usage:
::   scripts\build-apk.bat [debug|release] [--split-abi] [--arm64-v8a] [--x86_64] [--universal]
::   build-apk.bat [debug|release] [--split-abi] [--arm64-v8a] [--x86_64] [--universal]
::
:: Examples:
::   scripts\build-apk.bat
::   scripts\build-apk.bat release --split-abi
::   scripts\build-apk.bat debug
:: =============================================================================

setlocal

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "PS_SCRIPT=%SCRIPT_DIR%\build-apk.ps1"

:: ── Default argument values ────────────────────────────────────────────────
set "BUILD_TYPE=debug"
set "SPLIT_ABI="
set "TARGET_ABI="
set "FORCE="
set "NO_DAEMON="

:: ── Parse arguments ────────────────────────────────────────────────────────
:parse
if "%~1"=="" goto :run
if /i "%~1"=="debug"       ( set "BUILD_TYPE=debug"   & shift & goto :parse )
if /i "%~1"=="release"     ( set "BUILD_TYPE=release" & shift & goto :parse )
if /i "%~1"=="--split-abi" ( set "SPLIT_ABI=-SplitAbi" & shift & goto :parse )
if /i "%~1"=="--arm64-v8a"  ( set "TARGET_ABI=-TargetAbi arm64-v8a"  & shift & goto :parse )
if /i "%~1"=="--x86_64"     ( set "TARGET_ABI=-TargetAbi x86_64"     & shift & goto :parse )
if /i "%~1"=="--universal"  ( set "TARGET_ABI=-TargetAbi universal"  & shift & goto :parse )
if /i "%~1"=="--force"      ( set "FORCE=-Force"       & shift & goto :parse )
if /i "%~1"=="--no-daemon"  ( set "NO_DAEMON=-NoDaemon" & shift & goto :parse )
echo WARNING: Unknown argument "%~1" — ignoring.
shift
goto :parse

:run
:: Verify PowerShell is available
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell is required but was not found in PATH.
    echo Install it from https://aka.ms/powershell
    exit /b 1
)

echo Running build-apk.ps1 via PowerShell...
echo   BuildType : %BUILD_TYPE%
echo   SplitAbi  : %SPLIT_ABI%
echo   TargetAbi : %TARGET_ABI%
echo   Force     : %FORCE%
echo   NoDaemon  : %NO_DAEMON%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -BuildType %BUILD_TYPE% %SPLIT_ABI% %TARGET_ABI% %FORCE% %NO_DAEMON%

if errorlevel 1 (
    echo.
    echo ERROR: build-apk.ps1 exited with an error.
    exit /b 1
)

endlocal
