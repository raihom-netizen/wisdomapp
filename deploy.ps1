param(
  [switch]$WebOnly,
  [switch]$SkipFirebase,
  [switch]$ForceVersionOnline,
  [switch]$Clean,
  [switch]$NoCodemagicPush
)
# Deploy WISDOMAPP: web + Firebase + AAB (D:\TEMPORARIOS) + pacote iOS/CodeMagic.
# Politica: NAO grava app_config/version nem avisa usuarios automaticamente.
# Apos deploy, use Painel Admin > "Subir versao e forcar atualizacao" ou .\force_version_online.ps1
# Uso: .\deploy.ps1
#      .\deploy.ps1 -ForceVersionOnline  -> tambem grava Firestore (so se quiser forcar agora)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

function Get-AppVersionInfo {
  $versionFile = Join-Path $root "lib\constants\app_version.dart"
  $v = "10.02"; $pub = 2; $vc = 2
  if (Test-Path $versionFile) {
    $raw = Get-Content $versionFile -Raw
    if ($raw -match "current\s*=\s*'([^']+)'") { $v = $Matches[1] }
    if ($raw -match "buildNumber\s*=\s*(\d+)") { $pub = [int]$Matches[1] }
    if ($raw -match "versionCode\s*=\s*(\d+)") { $vc = [int]$Matches[1] }
  }
  return @{ Version = $v; Build = $pub; VersionCode = $vc; Tag = "$v+$pub" }
}

Write-Host "=== WISDOMAPP Deploy completo ===" -ForegroundColor Cyan
$ver = Get-AppVersionInfo
Write-Host "Versao: $($ver.Tag) (#$($ver.VersionCode))" -ForegroundColor Yellow

Write-Host "`n=== 1/7 Flutter pub get ===" -ForegroundColor Cyan
if ($Clean) { flutter clean; if ($LASTEXITCODE -ne 0) { exit 1 } }
flutter pub get
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n=== 2/7 Build Web ===" -ForegroundColor Cyan
$eap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
flutter build web --release --pwa-strategy=none --no-wasm-dry-run --no-tree-shake-icons 2>&1 | ForEach-Object { Write-Host $_ }
$ErrorActionPreference = $eap
if ($LASTEXITCODE -ne 0) { exit 1 }

$publicDir = Join-Path $root "build\web"
$assetBin = Join-Path $publicDir "assets\AssetManifest.bin.json"
$assetJson = Join-Path $publicDir "assets\AssetManifest.json"
if ((Test-Path $assetBin) -and (-not (Test-Path $assetJson))) {
  Copy-Item $assetBin $assetJson -Force
}

$bootstrapPath = Join-Path $publicDir "flutter_bootstrap.js"
if (Test-Path $bootstrapPath) {
  $bc = Get-Content $bootstrapPath -Raw -Encoding UTF8
  # Evita double-load: index.html chama load() com CanvasKit local (/canvaskit/) — Safari iOS.
  if ($bc -match '_flutter\.loader\.load\s*\(') {
    $bc = $bc -replace '_flutter\.loader\.load\s*\([^)]*\)\s*;', '// load() in index.html (Safari iOS + local CanvasKit)'
    Set-Content -Path $bootstrapPath -Value $bc -NoNewline -Encoding UTF8
  }
}

Write-Host "`n=== 3/7 version.json ===" -ForegroundColor Cyan
$playUrl = "https://play.google.com/store/apps/details?id=com.wisdomapp.app"
$versionJsonPath = Join-Path $publicDir "version.json"
$json = @{
  version = $ver.Version
  buildNumber = $ver.Build
  versionCode = $ver.VersionCode
  releaseTag = $ver.Tag
  apkDownloadUrl = $playUrl
} | ConvertTo-Json -Compress
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($versionJsonPath, $json, $utf8)
Write-Host "  version.json: $($ver.Tag)" -ForegroundColor Green

& (Join-Path $root "scripts\Validate-HostingPreDeploy.ps1") -Root $root
if ($LASTEXITCODE -ne 0) { exit 1 }

if (-not $SkipFirebase) {
  Write-Host "`n=== 4/7 Firebase deploy ===" -ForegroundColor Cyan
  $tokenSrc = Join-Path $root ".firebase-ci-token"
  if (-not (Test-Path $tokenSrc)) {
    $alt = Join-Path $root "dados para copiar do controle total app\.firebase-ci-token"
    if (Test-Path $alt) { Copy-Item $alt $tokenSrc -Force }
  }
  & (Join-Path $root "scripts\Invoke-FirebaseDeploy.ps1") -Root $root
  if ($LASTEXITCODE -ne 0) { exit 1 }

  Write-Host "`n=== 4b/7 Bootstrap Firestore + Storage ===" -ForegroundColor Cyan
  Push-Location (Join-Path $root "functions")
  $eapBoot = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  node ..\scripts\bootstrap-wisdomapp-firebase.js 2>&1 | ForEach-Object { Write-Host $_ }
  $bootOk = $LASTEXITCODE
  $ErrorActionPreference = $eapBoot
  Pop-Location
  if ($bootOk -ne 0) {
    Write-Host "  Aviso: bootstrap falhou (credencial Admin?). Rode manualmente apos firebase login." -ForegroundColor Yellow
  }
} else {
  Write-Host "`n=== 4/7 Firebase (pulado: -SkipFirebase) ===" -ForegroundColor Yellow
}

if ($ForceVersionOnline) {
  Write-Host "`n=== 5/7 Forcar versao online (opcional) ===" -ForegroundColor Cyan
  & (Join-Path $root "force_version_online.ps1")
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  Aviso: force version falhou - use Admin > Subir versao e forcar atualizacao." -ForegroundColor Yellow
  }
} else {
  Write-Host "`n=== 5/7 Force version (pulado - use Admin quando quiser avisar usuarios) ===" -ForegroundColor Yellow
}

if (-not $WebOnly) {
  Write-Host "`n=== 6/7 AAB + iOS export ===" -ForegroundColor Cyan
  & (Join-Path $root "scripts\Export-AabIosTemporarios.ps1")
  if ($LASTEXITCODE -ne 0) { exit 1 }
} else {
  Write-Host "`n=== 6/7 AAB/iOS (pulado: -WebOnly) ===" -ForegroundColor Yellow
}

if (-not $NoCodemagicPush -and -not $WebOnly) {
  Write-Host "`n=== 7/8 CodeMagic Git (branch iOS) ===" -ForegroundColor Cyan
  & (Join-Path $root "scripts\push-codemagic-ready.ps1") -Root $root
}

Write-Host "`n=== $(if ($NoCodemagicPush -or $WebOnly) { '7/7' } else { '8/8' }) Concluido ===" -ForegroundColor Green
Write-Host "  Web: https://wisdomapp-b9e98.web.app" -ForegroundColor Cyan
Write-Host "  AAB/iOS: D:\TEMPORARIOS\WISDOMAPP_*" -ForegroundColor Cyan
$cmBranch = "codemagic-ios-ready"
$vf = Join-Path $root "lib\constants\app_version.dart"
if (Test-Path $vf) {
  $vr = Get-Content $vf -Raw
  if ($vr -match "current\s*=\s*'([^']+)'") {
    $cmBranch = "codemagic-$($Matches[1] -replace '\.', '-')-ready"
  }
}
Write-Host "  CodeMagic: Start build na branch $cmBranch (ou .\scripts\Start-CodemagicIos.ps1 na 1a vez)" -ForegroundColor Cyan
