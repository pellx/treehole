param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
      [switch]$Offline)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
Push-Location $root
try {
    $problems = [Collections.Generic.List[string]]::new()
    $pub = Get-Content pubspec.yaml -Raw
    if ($pub -notmatch "(?m)^version: $([regex]::Escape($Version))\+(\d+)\s*$") { throw 'pubspec version mismatch' }
    $build = $Matches[1]
    if ((Get-Content lib/models/version_info.dart -Raw) -notmatch "currentVersion = '$([regex]::Escape($Version))'") { throw 'Client version mismatch' }
    $status = @(git status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'git status failed' }
    if ($status.Count) { $problems.Add('Commit audited changes before packaging') }
    foreach ($tool in @('flutter','ssh','git','gh')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { $problems.Add("Missing tool: $tool") }
    }
    if (-not (Select-String -LiteralPath .github/workflows/ios.yml -SimpleMatch -Pattern 'RELEASE_VERSION:')) { $problems.Add('Missing workflow version validation') }
    if (-not $Offline) {
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            gh auth status
            if ($LASTEXITCODE -ne 0) { $problems.Add('GitHub login required') }
        }
        ssh -o BatchMode=yes -o ConnectTimeout=10 -p 400 pell@www.leisure.xin "test -d /var/www/img/flutter_app_version && test ! -e /var/www/img/flutter_app_version/v$Version"
        if ($LASTEXITCODE -ne 0) { $problems.Add('SSH/directory check failed or version already exists') }
        foreach ($abi in @('arm64-v8a','armeabi-v7a','x86_64','all')) {
            $url = "https://www.leisure.xin:33433/flutter_app_version/v$Version/treehole-v$Version-$abi.apk"
            try { $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 15; $problems.Add("Target already served: $url ($($response.StatusCode))") }
            catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { Write-Output "Available target: $url" } else { $problems.Add("Unable to verify target: $url") } }
        }
    }
    Write-Output "Version: $Version ($build); root: $root"
    Write-Output 'Before release verify old APK certificate, build code, real-device upgrade and App Store Connect build availability (see checklist).'
    if ($problems.Count) { throw ($problems -join "`n") }
} finally { Pop-Location }
