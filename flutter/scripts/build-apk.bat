@echo off
:: build-apk.bat — Build Octra Wallet Android APK
:: Delegates to build-apk.ps1 (PowerShell)
::
:: Usage:
::   build-apk.bat                        Build release APK
::   build-apk.bat -Debug                 Build debug APK
::   build-apk.bat -SplitAbi              Build per-ABI release APKs
::   build-apk.bat -TargetAbi arm64-v8a   Build only for arm64-v8a
::   build-apk.bat -TargetAbi armeabi-v7a Build only for armeabi-v7a
::   build-apk.bat -TargetAbi x86_64      Build only for x86_64
::   build-apk.bat -TargetAbi universal   Build universal APK
::   build-apk.bat -Install               Build and install to connected device
::
:: Legacy flags (auto-converted):
::   build-apk.bat --arm64-v8a            Converted to -TargetAbi arm64-v8a
::   build-apk.bat --armeabi-v7a          Converted to -TargetAbi armeabi-v7a
::   build-apk.bat --x86_64               Converted to -TargetAbi x86_64
::   build-apk.bat --universal            Converted to -TargetAbi universal

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%build-apk.ps1"

if not exist "%PS1%" (
    echo [build-apk] ERROR: build-apk.ps1 not found at %PS1%
    exit /b 1
)

:: Convert legacy --abi flags to PowerShell -TargetAbi parameter
set "PS_ARGS="
:parse_args
if "%~1"=="" goto :run
if /i "%~1"=="--arm64-v8a"   ( set "PS_ARGS=%PS_ARGS% -TargetAbi arm64-v8a"   & shift & goto :parse_args )
if /i "%~1"=="--armeabi-v7a" ( set "PS_ARGS=%PS_ARGS% -TargetAbi armeabi-v7a" & shift & goto :parse_args )
if /i "%~1"=="--x86_64"      ( set "PS_ARGS=%PS_ARGS% -TargetAbi x86_64"      & shift & goto :parse_args )
if /i "%~1"=="--universal"   ( set "PS_ARGS=%PS_ARGS% -TargetAbi universal"   & shift & goto :parse_args )
if /i "%~1"=="--split-abi"   ( set "PS_ARGS=%PS_ARGS% -SplitAbi"              & shift & goto :parse_args )
if /i "%~1"=="--install"     ( set "PS_ARGS=%PS_ARGS% -Install"               & shift & goto :parse_args )
if /i "%~1"=="--force"       ( set "PS_ARGS=%PS_ARGS% -Force"                 & shift & goto :parse_args )
if /i "%~1"=="--debug"       ( set "PS_ARGS=%PS_ARGS% -BuildDebug"             & shift & goto :parse_args )
:: Pass through any other arguments as-is
set "PS_ARGS=%PS_ARGS% %~1"
shift
goto :parse_args

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %PS_ARGS%
exit /b %ERRORLEVEL%
