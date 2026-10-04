# Build Octra Wallet Android APK - Fixed Version
# Run this from android/scripts folder

Write-Host ""
Write-Host "=== Building Octra Wallet (SQLCipher Fix) ===" -ForegroundColor Cyan
Write-Host ""

# Navigate to android directory
$AndroidDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $AndroidDir

try {
    # Clean build
    Write-Host "Cleaning previous build..." -ForegroundColor Yellow
    .\gradlew.bat clean --no-daemon --quiet 2>&1 | Out-Null
    
    # Build debug APK
    Write-Host "Building debug APK..." -ForegroundColor Cyan
    .\gradlew.bat assembleDebug --no-daemon --stacktrace
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "=== Build Successful ===" -ForegroundColor Green
        Write-Host ""
        
        # Find the APK
        $apkPath = Get-ChildItem -Path "app\build\outputs\apk\debug" -Filter "*.apk" | Select-Object -First 1
        if ($apkPath) {
            $sizeMB = [math]::Round($apkPath.Length / 1MB, 2)
            Write-Host "APK: $($apkPath.FullName)" -ForegroundColor Green
            Write-Host "Size: $sizeMB MB" -ForegroundColor Green
        }
    } else {
        Write-Host ""
        Write-Host "=== Build Failed ===" -ForegroundColor Red
        Write-Host "Check the error messages above for details." -ForegroundColor Red
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "To install on device:" -ForegroundColor Cyan
Write-Host "  adb install -r <apk-path>" -ForegroundColor White
Write-Host ""
