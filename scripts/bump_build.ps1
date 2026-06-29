# Incrementa buildNumber + versionCode (mesmo valor) — web, Android e iOS ficam alinhados.
# Uso: .\scripts\bump_build.ps1
#      .\scripts\bump_build.ps1 -Increment 2

param(
  [int]$Increment = 1
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$vf = Join-Path $root "lib\constants\app_version.dart"

if (-not (Test-Path $vf)) { Write-Error "Nao encontrado: $vf" }

$raw = Get-Content $vf -Raw -Encoding UTF8
if ($raw -notmatch "buildNumber\s*=\s*(\d+)") { Write-Error "buildNumber ausente" }
$old = [int]$Matches[1]
$new = $old + $Increment

$raw = $raw -replace "buildNumber\s*=\s*\d+", "buildNumber = $new"
$raw = $raw -replace "versionCode\s*=\s*\d+", "versionCode = $new"
if ($raw -match "iosBuildNumber\s*=\s*\d+") {
  $raw = $raw -replace "iosBuildNumber\s*=\s*\d+", "iosBuildNumber = $new"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($vf, $raw, $utf8NoBom)

& (Join-Path $root "scripts\sync_app_version.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Build incrementado: $old -> $new (web + Android + iOS alinhados)" -ForegroundColor Green
