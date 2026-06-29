# Incrementa só iosBuildNumber (CFBundleVersion). Web/Android permanecem em buildNumber.
# Uso: .\scripts\bump_ios_build.ps1
#      .\scripts\bump_ios_build.ps1 -Increment 2

param(
  [int]$Increment = 1
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$vf = Join-Path $root "lib\constants\app_version.dart"

if (-not (Test-Path $vf)) { Write-Error "Nao encontrado: $vf" }

$raw = Get-Content $vf -Raw -Encoding UTF8
if ($raw -notmatch "iosBuildNumber\s*=\s*(\d+)") {
  if ($raw -notmatch "buildNumber\s*=\s*(\d+)") { Write-Error "buildNumber/iosBuildNumber ausente" }
  $base = [int]$Matches[1]
  $new = $base + $Increment
  $raw = $raw -replace "(static const int buildNumber = \d+;)", "`$1`n`n  /// CFBundleVersion iOS (App Store / TestFlight). Pode ficar à frente de [buildNumber] (hotfix só Apple).`n  static const int iosBuildNumber = $new;"
} else {
  $old = [int]$Matches[1]
  $new = $old + $Increment
  $raw = $raw -replace "iosBuildNumber\s*=\s*\d+", "iosBuildNumber = $new"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($vf, $raw, $utf8NoBom)

Write-Host "iOS build incrementado -> iosBuildNumber = $new (web/Android inalterados)" -ForegroundColor Green
Write-Host "Codemagic ajusta automaticamente se ASC estiver à frente." -ForegroundColor Gray
