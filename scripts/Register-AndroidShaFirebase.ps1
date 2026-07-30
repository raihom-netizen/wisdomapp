# Registra SHA-1/SHA-256 do app Android WISDOMAPP no Firebase (Google Sign-In).
# Uso:
#   .\scripts\Register-AndroidShaFirebase.ps1 -List
#   .\scripts\Register-AndroidShaFirebase.ps1 -PlaySha1 "AA:BB:..." -PlaySha256 "CC:DD:..."
#   .\scripts\Register-AndroidShaFirebase.ps1 -FromGradle
#
# Play Console → Integridade do app → Assinatura do app → Certificado da chave de assinatura do app
# Copie SHA-1 e SHA-256 e passe em -PlaySha1 / -PlaySha256 (com ou sem dois-pontos).

param(
  [switch]$List,
  [switch]$FromGradle,
  [string]$PlaySha1 = "",
  [string]$PlaySha256 = ""
)

$ErrorActionPreference = "Stop"
$AppId = "1:766524666378:android:7d110291e6777aa37f25f3"
$Root = Split-Path $PSScriptRoot -Parent

function Normalize-Sha([string]$raw) {
  ($raw -replace "[:\\s]", "").ToLower()
}

function Add-Sha([string]$hash, [string]$label) {
  $norm = Normalize-Sha $hash
  if ($norm.Length -ne 40 -and $norm.Length -ne 64) {
    Write-Host "  Ignorado ($label): tamanho invalido ($($norm.Length))" -ForegroundColor Yellow
    return
  }
  Write-Host "  Registrando $label : $norm" -ForegroundColor Cyan
  firebase apps:android:sha:create $AppId $norm
  if ($LASTEXITCODE -ne 0) { throw "Falha ao registrar $label" }
}

if ($List) {
  firebase apps:android:sha:list $AppId
  exit 0
}

Write-Host "=== WISDOMAPP — SHA Firebase ($AppId) ===" -ForegroundColor Cyan

if ($FromGradle) {
  Push-Location (Join-Path $Root "android")
  $out = .\gradlew signingReport 2>&1 | Out-String
  Pop-Location
  $sha1 = [regex]::Matches($out, "SHA1:\s*([0-9A-Fa-f:]+)") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  $sha256 = [regex]::Matches($out, "SHA-256:\s*([0-9A-Fa-f:]+)") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  foreach ($s in $sha1) { Add-Sha $s "Gradle SHA-1" }
  foreach ($s in $sha256) { Add-Sha $s "Gradle SHA-256" }
}

if ($PlaySha1.Trim()) { Add-Sha $PlaySha1 "Play App Signing SHA-1" }
if ($PlaySha256.Trim()) { Add-Sha $PlaySha256 "Play App Signing SHA-256" }

Write-Host "`nBaixando google-services.json atualizado..." -ForegroundColor Cyan
Push-Location $Root
firebase apps:sdkconfig android $AppId --out android/app/google-services.json
Copy-Item android/app/google-services.json "CONFIGURAÇOES ANDROID/google-services.json" -Force
Pop-Location

Write-Host "`nSHA registrados. Recompile o AAB e publique na Play Store." -ForegroundColor Green
firebase apps:android:sha:list $AppId
