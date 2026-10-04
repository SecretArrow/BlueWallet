# =============================================================================
# release-apk.ps1 — Build, Sign, and Publish Octra Wallet APK to GitHub
# =============================================================================
# Usage:
#   .\release-apk.ps1
#   .\release-apk.ps1 -Tag v1.2.0         Override the release tag
#   .\release-apk.ps1 -Draft              Create a draft release
#   .\release-apk.ps1 -Prerelease         Mark as pre-release
#   .\release-apk.ps1 -Notes "msg"        Custom release notes
#   .\release-apk.ps1 -SplitAbi           Build per-ABI APKs
#   .\release-apk.ps1 -SkipBuild          Skip build (use existing APK)
#   .\release-apk.ps1 -SkipSign           Skip signing (use unsigned APK)
#   .\release-apk.ps1 -DryRun             Do everything except GitHub release
#   .\release-apk.ps1 -Force              Force full clean before build (slower)
#   .\release-apk.ps1 -NoDaemon           Disable daemon (for CI/CD)
#
# Environment overrides (optional):
#   $env:GITHUB_TOKEN   — GitHub personal access token
#   $env:GITHUB_REPO    — owner/repo (auto-detected from git remote)
#   $env:FLUTTER_BIN    — path to flutter.bat
# =============================================================================
[CmdletBinding()]
param(
    [string]$Tag        = '',
    [switch]$Draft,
    [switch]$Prerelease,
    [string]$Notes      = '',
    [switch]$SplitAbi,
    [switch]$SkipBuild,
    [switch]$SkipSign,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoDaemon,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

function Log  { param([string]$m) Write-Host "[release] $m" -ForegroundColor Cyan }
function Warn { param([string]$m) Write-Host "[release] * $m" -ForegroundColor Yellow }
function Ok   { param([string]$m) Write-Host "[release] + $m" -ForegroundColor Green }
function Err  { param([string]$m) Write-Host "[release] x $m" -ForegroundColor Red; exit 1 }
function Step { param([string]$m) Write-Host "`n== $m ==" -ForegroundColor Cyan }
function Test-Cmd { param([string]$c) $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }

if ($Help) { Get-Content $MyInvocation.MyCommand.Path | Where-Object { $_ -match '^#' } | ForEach-Object { $_ -replace '^# ?','' }; exit 0 }

Push-Location $ProjectDir

# 1. DETERMINE VERSION & TAG
Step "Determining release version"
$Pubspec = "$ProjectDir\pubspec.yaml"
if (-not (Test-Path $Pubspec)) { Err "pubspec.yaml not found at $Pubspec" }

$verLine   = Get-Content $Pubspec | Where-Object { $_ -match '^version:' } | Select-Object -First 1
$FullVer   = ($verLine -replace 'version:\s*','').Trim()
if (-not $FullVer) { Err "Could not parse version from pubspec.yaml" }

$SemVer     = $FullVer.Split('+')[0]
$BuildNum   = if ($FullVer -match '\+') { $FullVer.Split('+')[1] } else { '' }
$ReleaseTag = if ($Tag) { $Tag } else { "v$SemVer" }

Ok "Version: $FullVer"
Ok "Release tag: $ReleaseTag"

# 2. DETECT GITHUB REPOSITORY
Step "Detecting GitHub repository"
$Repo = ''
if ($env:GITHUB_REPO) {
    $Repo = $env:GITHUB_REPO
} else {
    if (-not (Test-Cmd 'git')) { Err "git not found." }
    $remoteUrl = git -C $ProjectDir remote get-url origin 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $remoteUrl) { Err "No git remote 'origin'. Set env:GITHUB_REPO=owner/repo" }
    $Repo = $remoteUrl -replace '^https?://github\.com/','' -replace '^git@github\.com:','' -replace '\.git$',''
}
if ($Repo -notmatch '.+/.+') { Err "Could not parse owner/repo from remote." }
Ok "GitHub repo: $Repo"

# 3. ENSURE GITHUB CLI
Step "Checking GitHub CLI (gh)"
if (-not (Test-Cmd 'gh')) {
    Log "Installing GitHub CLI via winget..."
    try {
        winget install --id GitHub.cli --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        Ok "GitHub CLI installed"
    } catch {
        Warn "winget install failed"
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
}
if (-not (Test-Cmd 'gh')) { Err "GitHub CLI not found. Install from https://cli.github.com/" }
Ok "gh: $(gh --version | Select-Object -First 1)"

# 4. VERIFY GITHUB AUTHENTICATION
Step "Verifying GitHub authentication"
if ($env:GITHUB_TOKEN) {
    $env:GH_TOKEN = $env:GITHUB_TOKEN
    Log "Using GITHUB_TOKEN environment variable."
}
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    if ($env:GH_TOKEN) {
        $env:GH_TOKEN | gh auth login --with-token 2>&1 | Out-Null
    } else {
        Err "Not authenticated with GitHub.`n  1. Run: gh auth login`n  2. Or set env:GITHUB_TOKEN"
    }
}
Ok "GitHub authentication verified."

# 5. CHECK TAG
Step "Checking tag $ReleaseTag"
$existingRelease = gh release view $ReleaseTag --repo $Repo --json tagName 2>&1
$ReleaseExists = $LASTEXITCODE -eq 0 -and $existingRelease
if ($ReleaseExists) {
    Warn "Release $ReleaseTag already exists on GitHub. It will be updated."
} else {
    Ok "Tag $ReleaseTag is new"
}

# 6. BUILD APK
if (-not $SkipBuild) {
    Step "Building APK"
    $BuildScript = "$ScriptDir\build-apk.ps1"
    if (-not (Test-Path $BuildScript)) { Err "build-apk.ps1 not found at $BuildScript" }
    $buildArgs = @{}
    if ($SplitAbi) { $buildArgs['SplitAbi'] = $true }
    if ($Force) { $buildArgs['Force'] = $true }
    if ($NoDaemon) { $buildArgs['NoDaemon'] = $true }
    & $BuildScript @buildArgs
    if ($LASTEXITCODE -ne 0) { Err "build-apk.ps1 failed" }
    Ok "APK build completed"
} else {
    Log "Skipping build (-SkipBuild)"
}

# 7. SIGN APK
if (-not $SkipSign) {
    Step "Signing APK"
    $SignScript = "$ScriptDir\sign-apk.ps1"
    if (-not (Test-Path $SignScript)) { Err "sign-apk.ps1 not found at $SignScript" }
    & $SignScript
    if ($LASTEXITCODE -ne 0) { Err "sign-apk.ps1 failed" }
    Ok "APK signing completed"
} else {
    Log "Skipping signing (-SkipSign)"
}

# 8. COLLECT APK FILES
Step "Collecting APK files"
$SignedDir   = "$ProjectDir\release"
$UnsignedDir = "$ProjectDir\build\app\outputs\flutter-apk"
$ApkFiles = @()

if ((Test-Path $SignedDir) -and -not $SkipSign) {
    $ApkFiles = @(Get-ChildItem "$SignedDir\*.apk" -ErrorAction SilentlyContinue)
}
if ($ApkFiles.Count -eq 0) {
    $ApkFiles = @(Get-ChildItem "$UnsignedDir\*-release.apk" -ErrorAction SilentlyContinue)
}
if ($ApkFiles.Count -eq 0) { Err "No APK files found to upload." }

Log "APK files to upload:"
foreach ($f in $ApkFiles) {
    $sz = "{0:N2} MB" -f ($f.Length/1MB)
    Write-Host "  -> $($f.Name) ($sz)" -ForegroundColor Green
}

# 9. GENERATE RELEASE NOTES
Step "Generating release notes"

if ($Notes) {
    $ReleaseNotes = $Notes
} else {
    $prevTag = git -C $ProjectDir describe --tags --abbrev=0 2>&1
    if ($LASTEXITCODE -ne 0) { $prevTag = '' }
    $ReleaseNotes = "## Octra Wallet $ReleaseTag`n`n**Build:** $FullVer`n**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC`n`n### Changes`n"
    if ($prevTag) {
        $commits = git -C $ProjectDir log "${prevTag}..HEAD" --oneline --no-merges 2>&1
        if ($commits) { foreach ($c in ($commits -split "`n")) { $ReleaseNotes += "- $c`n" } }
        else { $ReleaseNotes += "- Maintenance release`n" }
    } else { $ReleaseNotes += "- Initial release`n" }
    $ReleaseNotes += "`n### Assets`n"
    foreach ($f in $ApkFiles) { $ReleaseNotes += "- ``$($f.Name)`` ($("{0:N2}" -f ($f.Length/1MB)) MB)`n" }
}
Write-Host "`nRelease Notes:" -ForegroundColor White
Write-Host $ReleaseNotes

# 10. CREATE / UPDATE GITHUB RELEASE
Step "Publishing release to GitHub"

if ($DryRun) {
    Warn "DRY RUN - no actual GitHub release will be created."
    Log "Would create: $ReleaseTag for $Repo with $($ApkFiles.Count) APK(s)"
    Ok "Dry run complete."
    Pop-Location
    exit 0
}

$apkPaths = $ApkFiles | ForEach-Object { $_.FullName }

if ($ReleaseExists) {
    Log "Updating existing release $ReleaseTag ..."
    $oldAssets = gh release view $ReleaseTag --repo $Repo --json assets --jq '.assets[].name' 2>&1
    foreach ($a in ($oldAssets -split "`n")) {
        if ($a -match '\.apk$') {
            gh release delete-asset $ReleaseTag $a --repo $Repo --yes 2>&1 | Out-Null
        }
    }
    gh release upload $ReleaseTag @apkPaths --repo $Repo --clobber
    $editArgs = @('--repo', $Repo, '--notes', $ReleaseNotes)
    if ($Draft)      { $editArgs += '--draft' }
    if ($Prerelease) { $editArgs += '--prerelease' }
    gh release edit $ReleaseTag @editArgs
} else {
    Log "Creating new release $ReleaseTag ..."
    $existingTag = git -C $ProjectDir rev-parse $ReleaseTag 2>&1
    if ($LASTEXITCODE -ne 0) {
        git -C $ProjectDir tag -a $ReleaseTag -m "Release $ReleaseTag"
        git -C $ProjectDir push origin $ReleaseTag
    }
    $ghArgs = @('--repo', $Repo, '--title', "Octra Wallet $ReleaseTag", '--notes', $ReleaseNotes)
    if ($Draft)      { $ghArgs += '--draft' }
    if ($Prerelease) { $ghArgs += '--prerelease' }
    gh release create $ReleaseTag @apkPaths @ghArgs
}

# 11. SUMMARY
Pop-Location
Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Ok "Release published successfully!"
Write-Host "===========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Tag    : $ReleaseTag"
Write-Host "  Version: $FullVer"
Write-Host "  Repo   : $Repo"
Write-Host "  URL    : https://github.com/$Repo/releases/tag/$ReleaseTag"
Write-Host ""
foreach ($f in $ApkFiles) {
    Write-Host "  + $($f.Name) ($("{0:N2}" -f ($f.Length/1MB)) MB)" -ForegroundColor Green
}
Write-Host ""
Ok "All done!"
