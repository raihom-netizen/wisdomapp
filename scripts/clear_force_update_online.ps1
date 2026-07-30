# Desativa aviso obrigatorio (forceUpdate: false) sem apagar versao no Firestore.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$versionFile = Join-Path $root "lib\constants\app_version.dart"
$version = "10.04"
$build = 12
$vc = 12
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
  Write-Host "Token nao encontrado. Use Admin > Desativar aviso obrigatorio." -ForegroundColor Yellow
  exit 1
}

$url = "https://us-central1-wisdomapp-b9e98.cloudfunctions.net/ctSyncAppVersion?version=$version&buildNumber=$build&versionCode=$vc&forceUpdate=0&token=$token"
try {
  $r = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
  if ($r.ok) {
    Write-Host "OK: forceUpdate=false em app_config/version ($version+$build)" -ForegroundColor Green
    exit 0
  }
  Write-Host "Erro: $($r.error)" -ForegroundColor Red
  exit 1
} catch {
  Write-Host "Erro ctSyncAppVersion: $_" -ForegroundColor Red
  exit 1
}
