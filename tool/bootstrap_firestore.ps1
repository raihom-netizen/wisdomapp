# Bootstrap Firestore + Storage WISDOMAPP via Cloud Function (nao precisa service account local).
param(
  [switch]$Force,
  [string]$Version = "10.02",
  [int]$BuildNumber = 2,
  [int]$VersionCode = 2
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$tokenFile = Join-Path $root ".deploy-token"
if (-not (Test-Path $tokenFile)) {
  throw "Arquivo .deploy-token nao encontrado na raiz do projeto."
}
$secret = (Get-Content $tokenFile -Raw).Trim()

Write-Host "=== Deploy funcao ctBootstrapWisdomappFirestore ===" -ForegroundColor Cyan
$ciTokenFile = Join-Path $root ".firebase-ci-token"
$env:FIREBASE_TOKEN = (Get-Content $ciTokenFile -Raw).Trim()
firebase deploy --only "functions:ctBootstrapWisdomappFirestore" --project wisdomapp-b9e98

$forceParam = if ($Force) { "1" } else { "0" }
$url = "https://us-central1-wisdomapp-b9e98.cloudfunctions.net/ctBootstrapWisdomappFirestore" +
  "?token=$secret&force=$forceParam&version=$Version&buildNumber=$BuildNumber&versionCode=$VersionCode"

Write-Host "=== Executando bootstrap remoto ===" -ForegroundColor Cyan
Write-Host $url.Replace($secret, "****")

$response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 120
$response | ConvertTo-Json -Depth 8

if (-not $response.ok) {
  throw "Bootstrap falhou: $($response.error)"
}

Write-Host "`nBootstrap Firestore concluido." -ForegroundColor Green
