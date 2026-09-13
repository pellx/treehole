param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
      [Parameter(Mandatory)][ValidateRange(1,2100000000)][int]$ExpectedBuild,
      [string]$Sdk = 'C:\androidSDK', [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
Push-Location $root
try {
    if ((Get-Content pubspec.yaml -Raw) -notmatch "(?m)^version: $([regex]::Escape($Version))\+$ExpectedBuild\s*$") { throw 'pubspec mismatch' }
    $output = Join-Path $root "build/releases/v$Version"
    if ($DryRun) { Write-Output "flutter build apk --release --split-per-abi; flutter build apk --release; verify -> $output"; return }
    $status = @(git status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $status.Count) { throw 'Package only a clean commit' }
    if (Test-Path -LiteralPath $output) { throw "Output already exists: $output" }
    $buildTools = Get-ChildItem -LiteralPath (Join-Path $Sdk 'build-tools') -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $buildTools) { throw 'Android build-tools missing' }
    $signer = Join-Path $buildTools.FullName 'apksigner.bat'
    $aapt = Join-Path $buildTools.FullName 'aapt.exe'
    & flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw 'Split APK build failed' }
    New-Item -ItemType Directory -Path $output | Out-Null
    foreach ($abi in @('arm64-v8a','armeabi-v7a','x86_64')) {
        Copy-Item -LiteralPath "build/app/outputs/flutter-apk/app-$abi-release.apk" -Destination (Join-Path $output "treehole-v$Version-$abi.apk")
    }
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Universal APK build failed' }
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination (Join-Path $output "treehole-v$Version-all.apk")
    $hashes = foreach ($file in Get-ChildItem -LiteralPath $output -Filter '*.apk') {
        $cert = & $signer verify --print-certs $file.FullName
        if ($LASTEXITCODE -ne 0 -or ($cert -join "`n") -notmatch 'SHA-256 digest: 01360b21890ca7191fabf6ab6ddf74e122568b4d7d5ab07287011baf4027da95') { throw "Signature mismatch: $($file.Name)" }
        $metadata = & $aapt dump badging $file.FullName
        if ($LASTEXITCODE -ne 0 -or ($metadata -join "`n") -notmatch "package: name='com.example.treehole' versionCode='$ExpectedBuild' versionName='$([regex]::Escape($Version))'") { throw "APK metadata mismatch: $($file.Name)" }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($file.Name)"
    }
    $hashes | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS') -Encoding ascii
    git rev-parse HEAD | Set-Content -LiteralPath (Join-Path $output 'SOURCE_COMMIT') -Encoding ascii
    Write-Output $hashes
} finally { Pop-Location }
