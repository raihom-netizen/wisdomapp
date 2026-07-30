# Registra origens JS + redirect URIs no Google Cloud Console.
# Corrige Erro 400: redirect_uri_mismatch / origin_mismatch.
#
# Console: https://console.cloud.google.com/apis/credentials?project=wisdomapp-b9e98
# Guia completo: docs/PROMPT_MESTRE_GOOGLE_CALENDAR_OAUTH.md

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

$redirects = @(
  "https://wisdomapp-b9e98.web.app/google_calendar_oauth.html",
  "https://wisdomapp-b9e98.firebaseapp.com/google_calendar_oauth.html",
  "http://localhost/google_calendar_oauth.html",
  "http://localhost:5000/google_calendar_oauth.html",
  "http://127.0.0.1/google_calendar_oauth.html"
)

Write-Host "=== WISDOMAPP — OAuth Google Calendar (prompt mestre) ===" -ForegroundColor Cyan
Write-Host "Cliente Web: $clientId" -ForegroundColor Yellow
Write-Host ""
Write-Host ">>> OBRIGATORIO no Google Cloud Console <<<" -ForegroundColor Red
Write-Host "Redirect canonico:" -ForegroundColor White
Write-Host "  https://wisdomapp-b9e98.web.app/google_calendar_oauth.html" -ForegroundColor Green
Write-Host ""
Write-Host "Origens JavaScript autorizadas:" -ForegroundColor White
foreach ($o in $origins) { Write-Host "  $o" -ForegroundColor Gray }
Write-Host ""
Write-Host "URIs de redirecionamento autorizados:" -ForegroundColor White
foreach ($r in $redirects) { Write-Host "  $r" -ForegroundColor Gray }
Write-Host ""
Write-Host "Guia: $(Join-Path $root 'docs\PROMPT_MESTRE_GOOGLE_CALENDAR_OAUTH.md')" -ForegroundColor Cyan
Write-Host "Apos salvar no Console, aguarde 2-5 min e rode: .\deploy.ps1 -WebOnly" -ForegroundColor Yellow

$clip = @"
ORIGENS JS:
$($origins -join "`n")

REDIRECT URIs:
$($redirects -join "`n")
"@
Set-Clipboard -Value $clip -ErrorAction SilentlyContinue
Write-Host "Listas copiadas para a area de transferencia." -ForegroundColor Green

Start-Process "https://console.cloud.google.com/apis/credentials/oauthclient/$($clientId -replace ':','%3A')?project=wisdomapp-b9e98"
