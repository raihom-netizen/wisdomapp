# Forca gravacao da versao atual no Firestore app_config/version (WISDOMAPP).
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$versionFile = Join-Path $root "lib\constants\app_version.dart"
$version = "10.02"
$build = 2
$vc = 2
if (Test-Path $versionFile) {
  $content = Get-Content $versionFile -Raw
  if ($content -match "current\s*=\s*'([^']+)'") { $version = $Matches[1] }
  if ($content -match "buildNumber\s*=\s*(\d+)") { $build = [int]$Matches[1] }
  if ($content -match "versionCode\s*=\s*(\d+)") { $vc = [int]$Matches[1] }
}

$token = $env:APP_VERSION_SECRET
if (-not $token -and (Test-Path (Join-Path $root ".deploy-token"))) {
  $token = (Get-Content (Join-Path $root ".deploy-token") -Raw).Trim()
}
if (-not $token) {
  $alt = Join-Path $root "dados para copiar do controle total app\.deploy-token"
  if (Test-Path $alt) { $token = (Get-Content $alt -Raw).Trim() }
}

if (-not $token) {
  Write-Host "Token nao encontrado (.deploy-token ou APP_VERSION_SECRET)." -ForegroundColor Yellow
  Write-Host "Use Admin > Subir versao e forcar atualizacao." -ForegroundColor Gray
  exit 1
}

$url = "https://us-central1-wisdomapp-b9e98.cloudfunctions.net/ctSyncAppVersion?version=$version&buildNumber=$build&versionCode=$vc&testFlightUrl=$([uri]::EscapeDataString('https://testflight.apple.com/join/qWpWwhnN'))&token=$token"
try {
  $r = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
  if ($r.ok) {
    Write-Host "OK: app_config/version = $version+$build forceUpdate=true" -ForegroundColor Green
    exit 0
  }
  Write-Host "Erro: $($r.error)" -ForegroundColor Red
  exit 1
} catch {
  Write-Host "Erro ctSyncAppVersion: $_" -ForegroundColor Red
  exit 1
}
