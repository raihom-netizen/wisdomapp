# Incrementa buildNumber + versionCode (mesmo valor) e iosBuildNumber (+1) - web, Android e iOS alinhados.
# Atalho para: .\scripts\sync_app_version.ps1 -Build <atual + Increment>
# Uso: .\scripts\bump_build.ps1
#      .\scripts\bump_build.ps1 -Increment 2

param(
  [int]$Increment = 1
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$vf = Join-Path $root "lib\constants\app_version.dart"

if (-not (Test-Path $vf)) { Write-Error "Nao encontrado: $vf" }

$raw = [System.IO.File]::ReadAllText($vf)
$m = [regex]::Match($raw, "static const int buildNumber = (\d+);")
if (-not $m.Success) { Write-Error "buildNumber ausente" }
$old = [int]$m.Groups[1].Value
$new = $old + $Increment

& (Join-Path $root "scripts\sync_app_version.ps1") -Build $new
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Build incrementado: $old -> $new (web + Android + iOS alinhados)" -ForegroundColor Green
