#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap all build requirements for Octra Wallet Android on Windows.
.DESCRIPTION
    Installs / verifies:
      - Java 17 (Microsoft Build of OpenJDK via winget, or prompts for manual install)
      - Android command-line tools
      - Android SDK components: platform-tools, android-35, build-tools 35.0.0,
        cmake 3.22.1, NDK 27.3.13750724
      - Gradle wrapper in the android/ project root
      - local.properties (sdk.dir)
.EXAMPLE
    .\scripts\install.ps1        # run from android\ root
    .\install.ps1                # run from scripts\ folder
#>

[CmdletBinding()]
param(
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Paths
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AndroidDir = Split-Path -Parent $ScriptDir

# Versions
$SdkPlatform          = 'android-35'
$SdkBuildTools        = '35.0.0'
$SdkNdk               = '27.3.13750724'
$CmakeVersion         = '3.22.1'
$CmdlineToolsVersion  = '13114758'
$GradleWrapperVersion = '8.10.2'
$JavaMinVersion       = 17

# Colour helpers
function Log  { param([string]$Msg) Write-Host "[install] $Msg" -ForegroundColor Cyan }
function Ok   { param([string]$Msg) Write-Host "[install] + $Msg" -ForegroundColor Green }
function Warn { param([string]$Msg) Write-Host "[install] * $Msg" -ForegroundColor Yellow }
function Err  { param([string]$Msg) Write-Host "[install] x $Msg" -ForegroundColor Red; exit 1 }
function Step { param([string]$Msg) Write-Host "`n== $Msg ==" -ForegroundColor Cyan }

# Download helper
function Download-File {
    param([string]$Url, [string]$OutPath)
    Log "Downloading: $Url"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing
    } catch {
        # Fallback to WebClient
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Url, $OutPath)
        $wc.Dispose()
    }
}

if ($Help) {
    Get-Content $MyInvocation.MyCommand.Path | Select-String -Pattern '^#' | ForEach-Object { $_.Line -replace '^# ?','' }
    exit 0
}

# 1 / 6 - Java
Step "1 / 6 - Java $JavaMinVersion"

$JavaOk = $false
$javaCmd = Get-Command java -ErrorAction SilentlyContinue
if ($javaCmd) {
    try {
        $verLine = & java -version 2>&1 | Select-Object -First 1
        if ($verLine -match '"([\d.]+)"') {
            $verStr = $Matches[1]
            $major  = if ($verStr -match '^1\.') { [int]($verStr.Split('.')[1]) } else { [int]($verStr.Split('.')[0]) }
            if ($major -ge $JavaMinVersion) {
                Ok "Java $major already installed"
                $JavaOk = $true
            } else {
                Warn "Java $major < $JavaMinVersion"
            }
        }
    } catch {
        Warn "Could not determine Java version"
    }
}

if (-not $JavaOk) {
    Log "Attempting to install Microsoft OpenJDK $JavaMinVersion via winget..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            & winget install --id Microsoft.OpenJDK.17 --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            Ok "Java $JavaMinVersion installed via winget"
            $JavaOk = $true
        } catch {
            Warn "winget install failed"
        }
    } else {
        Warn "winget not available."
    }

    if (-not $JavaOk) {
        Write-Host ""
        Write-Host "  Please install Java $JavaMinVersion manually:" -ForegroundColor Yellow
        Write-Host "    https://adoptium.net/  or  https://learn.microsoft.com/en-us/java/openjdk/download" -ForegroundColor Yellow
        Write-Host "  Then re-run this script." -ForegroundColor Yellow
        Write-Host ""
        Err "Java $JavaMinVersion required."
    }
}

# Set JAVA_HOME
if (-not $env:JAVA_HOME) {
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmd) {
        $javaPath = $javaCmd.Source
        try {
            $env:JAVA_HOME = Split-Path (Split-Path $javaPath -Parent) -Parent
        } catch {
            Warn "Could not set JAVA_HOME"
        }
    }
}
Ok "JAVA_HOME = $env:JAVA_HOME"

# 2 / 6 - Android SDK
Step "2 / 6 - Android SDK"

$SdkDir = $env:ANDROID_HOME
if (-not $SdkDir) { $SdkDir = $env:ANDROID_SDK_ROOT }
if (-not $SdkDir) {
    foreach ($c in @("$env:LOCALAPPDATA\Android\Sdk", "$env:USERPROFILE\android-sdk")) {
        if (Test-Path $c) { $SdkDir = $c; break }
    }
}

if (-not $SdkDir -or -not (Test-Path $SdkDir)) {
    $SdkDir   = "$env:USERPROFILE\android-sdk"
    $ToolsZip = "$SdkDir\cmdline-tools.zip"
    $ToolsDir = "$SdkDir\cmdline-tools"
    $PinnedUrl = "https://dl.google.com/android/repository/commandlinetools-win-${CmdlineToolsVersion}_latest.zip"
    $LegacyUrl = "https://dl.google.com/android/repository/commandlinetools-win-latest.zip"

    try {
        New-Item -ItemType Directory -Force -Path $SdkDir | Out-Null
        try {
            Download-File $PinnedUrl $ToolsZip
        } catch {
            Log "Primary download failed, trying legacy URL..."
            Download-File $LegacyUrl $ToolsZip
        }

        if (Test-Path $ToolsDir) { Remove-Item $ToolsDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
        Expand-Archive -Path $ToolsZip -DestinationPath $ToolsDir -Force
        Remove-Item $ToolsZip -ErrorAction SilentlyContinue

        # Normalize layout
        $nested = Join-Path $ToolsDir 'cmdline-tools'
        if (Test-Path $nested) {
            Rename-Item $nested 'latest' -ErrorAction SilentlyContinue
        }
        Ok "Command-line tools installed at $SdkDir"
    } catch {
        Err "Failed to download/install Android SDK: $_"
    }
} else {
    Ok "Android SDK found at $SdkDir"
}

$env:ANDROID_HOME      = $SdkDir
$env:ANDROID_SDK_ROOT  = $SdkDir

# 3 / 6 - SDK components
Step "3 / 6 - SDK components"

$SdkMgr = $null
foreach ($c in @("$SdkDir\cmdline-tools\latest\bin\sdkmanager.bat",
                  "$SdkDir\tools\bin\sdkmanager.bat")) {
    if (Test-Path $c) { $SdkMgr = $c; break }
}

if (-not $SdkMgr) {
    Warn "sdkmanager not found - please install components manually."
} else {
    Log "Accepting Android SDK licenses..."
    try {
        'y','y','y','y','y','y','y' | & $SdkMgr --sdk_root="$SdkDir" --licenses 2>$null | Out-Null
    } catch {
        Warn "Could not auto-accept licenses"
    }

    Log "Installing SDK components (this may take a few minutes)..."
    try {
        & $SdkMgr --sdk_root="$SdkDir" `
            "platform-tools" `
            "platforms;$SdkPlatform" `
            "build-tools;$SdkBuildTools" `
            "cmake;$CmakeVersion" `
            "ndk;$SdkNdk" 2>&1 | Out-Null
        Ok "SDK components installed"
    } catch {
        Warn "SDK component installation encountered issues: $_"
    }
}

# 4 / 6 - Gradle wrapper
Step "4 / 6 - Gradle wrapper"

$GradlewBat = Join-Path $AndroidDir 'gradlew.bat'
if (Test-Path $GradlewBat) {
    Ok "gradlew.bat already present"
} else {
    $gradle = Get-Command gradle -ErrorAction SilentlyContinue
    if ($gradle) {
        try {
            Push-Location $AndroidDir
            & gradle wrapper --gradle-version $GradleWrapperVersion 2>&1 | Out-Null
            Pop-Location
            Ok "gradlew.bat created"
        } catch {
            Warn "Gradle wrapper creation failed: $_"
        }
    } else {
        Warn "Gradle not found. Please add gradlew.bat manually or install Gradle."
        Write-Host "  https://gradle.org/install/" -ForegroundColor Yellow
    }
}

# 5 / 6 - local.properties
Step "5 / 6 - local.properties"

$Props    = Join-Path $AndroidDir 'local.properties'
$SdkPath  = $SdkDir.Replace('\', '/')

if (Test-Path $Props) {
    try {
        $content = Get-Content $Props -Raw -Encoding UTF8
        if ($content -match 'sdk\.dir=') {
            $content = $content -replace 'sdk\.dir=.*', "sdk.dir=$SdkPath"
        } else {
            $content += "`nsdk.dir=$SdkPath"
        }
        Set-Content $Props $content -NoNewline -Encoding UTF8
        Log "Updated sdk.dir in local.properties"
    } catch {
        Warn "Could not update local.properties: $_"
    }
} else {
    try {
        "sdk.dir=$SdkPath" | Set-Content $Props -NoNewline -Encoding UTF8
    } catch {
        Warn "Could not create local.properties: $_"
    }
}
Ok "local.properties OK"

# 6 / 6 - PATH hint
Step "6 / 6 - PATH hint"

# Add sdk platform-tools to current session PATH
$PlatformTools = Join-Path $SdkDir 'platform-tools'
if ((Test-Path $PlatformTools) -and $env:PATH -notlike "*$PlatformTools*") {
    $env:PATH += ";$PlatformTools"
    Log "Added $PlatformTools to session PATH"
}

# Summary
Write-Host ""
Write-Host "  JAVA_HOME      = $env:JAVA_HOME" -ForegroundColor Cyan
Write-Host "  ANDROID_HOME   = $SdkDir"        -ForegroundColor Cyan
Write-Host "  gradlew.bat    = $GradlewBat"    -ForegroundColor Cyan
Write-Host "  local.properties = $Props"       -ForegroundColor Cyan
Write-Host ""
Write-Host "All requirements installed. You can now run:" -ForegroundColor Green
Write-Host "  .\scripts\build-apk.ps1 -BuildType release -SplitAbi" -ForegroundColor Cyan
Write-Host ""
