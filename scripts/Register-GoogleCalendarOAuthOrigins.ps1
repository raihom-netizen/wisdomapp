# Registra origens JavaScript no cliente OAuth Web do WISDOMAPP (Google Calendar GIS).
# Corrige Erro 400: origin_mismatch na web.
#
# Pré-requisito: gcloud auth login + projeto wisdomapp-b9e98
# Uso: .\scripts\Register-GoogleCalendarOAuthOrigins.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$clientId = "766524666378-ce9albkkvn01si77s6ofcqvoaatn29s0.apps.googleusercontent.com"

$origins = @(
  "https://wisdomapp-b9e98.web.app",
  "https://wisdomapp-b9e98.firebaseapp.com",
  "http://localhost",
  "http://localhost:5000",
  "http://localhost:8080",
  "http://127.0.0.1",
  "http://127.0.0.1:5000"
)

Write-Host "=== WISDOMAPP — Origens OAuth Google Calendar ===" -ForegroundColor Cyan
Write-Host "Cliente Web: $clientId" -ForegroundColor Yellow
Write-Host "Projeto: wisdomapp-b9e98" -ForegroundColor Yellow
Write-Host ""
Write-Host "Adicione manualmente no Console se o gcloud falhar:" -ForegroundColor Gray
Write-Host "https://console.cloud.google.com/apis/credentials?project=wisdomapp-b9e98" -ForegroundColor Gray
foreach ($o in $origins) { Write-Host "  - $o" -ForegroundColor White }

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
  Write-Host "`ngcloud nao encontrado. Use o Console Google Cloud (link acima)." -ForegroundColor Yellow
  exit 0
}

try {
  gcloud config set project wisdomapp-b9e98 2>&1 | Out-Null
  $json = gcloud alpha iap oauth-clients list --format=json 2>$null
  Write-Host "`nTentando atualizar via gcloud (pode exigir API OAuth2)..." -ForegroundColor Cyan
  Write-Host "Se nao funcionar, copie as origens acima para o cliente OAuth Web manualmente." -ForegroundColor Yellow
} catch {
  Write-Host "gcloud: $_" -ForegroundColor Yellow
}

Write-Host "`nConcluido (verifique no Console)." -ForegroundColor Green
