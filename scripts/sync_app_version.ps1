# Sincroniza pubspec.yaml, Android e web/version.json a partir de lib/constants/app_version.dart.
# Fonte única: AppVersion.current, buildNumber, versionCode (todos iguais entre plataformas).
# Uso: .\scripts\sync_app_version.ps1
#      .\scripts\sync_app_version.ps1 -ValidateOnly

param(
  [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$vf = Join-Path $root "lib\constants\app_version.dart"
$pubspec = Join-Path $root "pubspec.yaml"
$gradle = Join-Path $root "android\app\build.gradle"
$webVj = Join-Path $root "web\version.json"

if (-not (Test-Path $vf)) {
  Write-Error "Nao encontrado: $vf"
}

$raw = Get-Content $vf -Raw -Encoding UTF8
if ($raw -notmatch "current\s*=\s*'([^']+)'") { Write-Error "AppVersion.current ausente em app_version.dart" }
$current = $Matches[1]
if ($raw -notmatch "buildNumber\s*=\s*(\d+)") { Write-Error "buildNumber ausente em app_version.dart" }
$build = [int]$Matches[1]
if ($raw -notmatch "versionCode\s*=\s*(\d+)") { Write-Error "versionCode ausente em app_version.dart" }
$versionCode = [int]$Matches[1]

if ($build -ne $versionCode) {
  Write-Error "buildNumber ($build) e versionCode ($versionCode) devem ser iguais (web/Android/iOS alinhados)."
}

function Get-PubspecMarketing([string]$c) {
  if ($c -match '^\d+\.\d+\.\d+$') { return $c }
  if ($c -match '^\d+\.\d+$') { return "$c.0" }
  return "$c.0.0"
}

$pubMarketing = Get-PubspecMarketing $current
$releaseTag = "$current+$build"
$playUrl = "https://play.google.com/store/apps/details?id=com.wisdomapp.app"
$testFlightUrl = "https://testflight.apple.com/join/qWpWwhnN"

function Test-FileAligned {
  param($Path, $Label, [scriptblock]$Check)
  if (-not (Test-Path $Path)) {
    Write-Host "  AVISO: $Label ausente ($Path)" -ForegroundColor Yellow
    return $true
  }
  $content = Get-Content $Path -Raw -Encoding UTF8
  $ok = & $Check $content
  if (-not $ok) {
    Write-Host "  DESALINHADO: $Label" -ForegroundColor Red
    return $false
  }
  return $true
}

$aligned = $true
$aligned = (Test-FileAligned $pubspec "pubspec.yaml" {
  param($c)
  $c -match "version:\s*([\d.]+)\+(\d+)" -and $Matches[1] -eq $pubMarketing -and [int]$Matches[2] -eq $build
}) -and $aligned

$aligned = (Test-FileAligned $gradle "android/app/build.gradle" {
  param($c)
  $c -match "versionCode\s*=\s*(\d+)" -and [int]$Matches[1] -eq $versionCode -and
    $c -match 'versionName\s*=\s*"([^"]+)"' -and $Matches[1] -eq $current
}) -and $aligned

$aligned = (Test-FileAligned $webVj "web/version.json" {
  param($c)
  $j = $c | ConvertFrom-Json
  $j.version -eq $current -and [int]$j.buildNumber -eq $build -and [int]$j.versionCode -eq $versionCode
}) -and $aligned

if ($ValidateOnly) {
  if ($aligned) {
    Write-Host "OK: versao alinhada $releaseTag (#$versionCode) em todas as plataformas." -ForegroundColor Green
    exit 0
  }
  Write-Host "ERRO: rode .\scripts\sync_app_version.ps1 ou .\scripts\bump_build.ps1" -ForegroundColor Red
  exit 1
}

if ($aligned) {
  Write-Host "Versao ja alinhada: $releaseTag (#$versionCode)" -ForegroundColor Green
  exit 0
}

Write-Host "Sincronizando versao $releaseTag (#$versionCode) ..." -ForegroundColor Cyan

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if (Test-Path $pubspec) {
  $pc = Get-Content $pubspec -Raw -Encoding UTF8
  $pc = $pc -replace "version:\s*[\d.]+\+\d+", "version: ${pubMarketing}+${build}"
  Write-Utf8NoBom $pubspec $pc
}

if (Test-Path $gradle) {
  $gc = Get-Content $gradle -Raw -Encoding UTF8
  $gc = $gc -replace "versionCode\s*=\s*\d+", "versionCode = $versionCode"
  $gc = $gc -replace 'versionName\s*=\s*"[^"]*"', "versionName = `"$current`""
  Write-Utf8NoBom $gradle $gc
}

$json = @{
  version = $current
  buildNumber = $build
  versionCode = $versionCode
  releaseTag = $releaseTag
  apkDownloadUrl = $playUrl
  testFlightUrl = $testFlightUrl
} | ConvertTo-Json -Compress
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($webVj, $json, $utf8)

Write-Host "OK: app_version.dart -> pubspec, build.gradle, web/version.json ($releaseTag)" -ForegroundColor Green
