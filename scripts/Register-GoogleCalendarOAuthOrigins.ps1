# Registra origens JS + redirect URIs no cliente OAuth Web (Google Calendar).
# Corrige Erro 400: origin_mismatch na web.
#
# Console: https://console.cloud.google.com/apis/credentials?project=wisdomapp-b9e98
# Cliente OAuth 2.0 Web → Editar → Origens JavaScript + URIs de redirecionamento
#
# Uso: .\scripts\Register-GoogleCalendarOAuthOrigins.ps1

$ErrorActionPreference = "Stop"
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

Write-Host "=== WISDOMAPP — OAuth Google Calendar ===" -ForegroundColor Cyan
Write-Host "Cliente Web: $clientId" -ForegroundColor Yellow
Write-Host ""
Write-Host "Origens JavaScript autorizadas:" -ForegroundColor White
foreach ($o in $origins) { Write-Host "  - $o" -ForegroundColor Gray }
Write-Host ""
Write-Host "URIs de redirecionamento autorizados:" -ForegroundColor White
foreach ($r in $redirects) { Write-Host "  - $r" -ForegroundColor Gray }
Write-Host ""
Write-Host "Adicione manualmente no Console Google Cloud (link acima)." -ForegroundColor Green
