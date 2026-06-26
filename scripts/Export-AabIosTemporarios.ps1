# Gera AAB em D:\TEMPORARIOS + ZIP iOS/CodeMagic.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$destDir = "D:\TEMPORARIOS"
$versionFile = Join-Path $root "lib\constants\app_version.dart"

if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

$v = "10.02"; $pub = 2; $vc = 2
if (Test-Path $versionFile) {
  $raw = Get-Content $versionFile -Raw
  if ($raw -match "current\s*=\s*'([^']+)'") { $v = $Matches[1] }
  if ($raw -match "buildNumber\s*=\s*(\d+)") { $pub = [int]$Matches[1] }
  if ($raw -match "versionCode\s*=\s*(\d+)") { $vc = [int]$Matches[1] }
}

Write-Host "=== Build AAB WISDOMAPP ($v+$pub / #$vc) ===" -ForegroundColor Cyan
Set-Location $root
flutter pub get | Out-Null
$eap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
flutter build appbundle --release --no-tree-shake-icons 2>&1 | ForEach-Object { Write-Host $_ }
$ErrorActionPreference = $eap
if ($LASTEXITCODE -ne 0) { throw "Build AAB falhou." }

$aabBuilt = Join-Path $root "build\app\outputs\bundle\release\app-release.aab"
if (-not (Test-Path $aabBuilt)) { throw "AAB nao encontrado." }

$destAab = Join-Path $destDir "WISDOMAPP_${v}+${pub}_${vc}_release.aab"
Copy-Item $aabBuilt $destAab -Force
Copy-Item $aabBuilt (Join-Path $destDir "WISDOMAPP_ultimo_release.aab") -Force
Write-Host "AAB: $destAab" -ForegroundColor Green

Write-Host "=== Pacote iOS / CodeMagic ===" -ForegroundColor Cyan
$tag = "${v}+${pub}"
$staging = Join-Path $destDir "WISDOMAPP_ios_codemagic_staging_${tag}_${vc}"
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

@("codemagic.yaml", "pubspec.yaml", "pubspec.lock") | ForEach-Object {
  $p = Join-Path $root $_
  if (Test-Path $p) { Copy-Item $p (Join-Path $staging $_) -Force }
}
Copy-Item $versionFile (Join-Path $staging "app_version.dart") -Force
Copy-Item (Join-Path $root "android\app\build.gradle") (Join-Path $staging "android_build.gradle") -Force

$iosDst = Join-Path $staging "ios"
$iosSrc = Join-Path $root "ios"
if (Test-Path $iosSrc) {
  & robocopy $iosSrc $iosDst /E /XD Pods .symlinks DerivedData build /NFL /NDL /NJH /NJS | Out-Null
  if ($LASTEXITCODE -ge 8) { Write-Host "Aviso robocopy ios: $LASTEXITCODE" -ForegroundColor Yellow }
  $global:LASTEXITCODE = 0
}

$zip = Join-Path $destDir "WISDOMAPP_ios_codemagic_${tag}_${vc}.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $staging -DestinationPath $zip -Force
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "ZIP iOS: $zip" -ForegroundColor Green

$readme = @"
WISDOMAPP — export $tag (#$vc)
AAB: $destAab
ZIP iOS: $zip
Branch CodeMagic sugerida: codemagic-10-02-ready
"@
Set-Content -Path (Join-Path $destDir "WISDOMAPP_EXPORT_${tag}_${vc}.txt") -Value $readme -Encoding UTF8
Write-Host "Concluido." -ForegroundColor Green
