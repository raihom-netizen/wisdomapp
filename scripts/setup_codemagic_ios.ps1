# Configuração Codemagic para WISDOMAPP iOS — mesma API Apple do Controle Total (ControleTotalAPI1).
# Uso: .\scripts\setup_codemagic_ios.ps1
# Com token: $env:CODEMAGIC_API_TOKEN='...'; .\scripts\setup_codemagic_ios.ps1

param(
    [string]$P8Path = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoUrl = $env:WISDOMAPP_GITHUB_REPO
if ([string]::IsNullOrWhiteSpace($repoUrl)) {
    $repoUrl = "https://github.com/Raihom-Barbosa/wisdomapp.git"
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    Push-Location $root
    try {
        $gitUrl = git remote get-url origin 2>$null
        if ($gitUrl) {
            $repoUrl = $gitUrl
            if (-not $repoUrl.EndsWith('.git')) { $repoUrl = $repoUrl + '.git' }
        }
    } finally { Pop-Location }
}

$token = $env:CODEMAGIC_API_TOKEN
if (-not $token -and $P8Path) {
    $token = Read-Host "Codemagic API Token (Teams > Integrations > Codemagic API)"
}

$headers = @{
    "Content-Type" = "application/json"
    "x-auth-token" = $token
}

$appId = $null
if ($token) {
    try {
        $appsResp = Invoke-RestMethod -Uri "https://api.codemagic.io/apps" -Headers $headers -Method Get
        $app = $appsResp.applications | Where-Object {
            $_.repositoryUrl -like "*wisdomapp*" -or
            $_.appName -like "*wisdom*" -or
            $_.appName -eq "wisdomapp" -or
            $_.appName -eq "WISDOMAPP"
        } | Select-Object -First 1
        if (-not $app) {
            $body = @{ repositoryUrl = $repoUrl } | ConvertTo-Json
            $newApp = Invoke-RestMethod -Uri "https://api.codemagic.io/apps" -Headers $headers -Method Post -Body $body
            $appId = $newApp._id
            if (-not $appId -and $newApp.application) { $appId = $newApp.application._id }
            Write-Host "App WISDOMAPP adicionado ao Codemagic. App ID: $appId" -ForegroundColor Green
        } else {
            $appId = $app._id
            Write-Host "App WISDOMAPP já existe no Codemagic. App ID: $appId" -ForegroundColor Green
        }
    } catch {
        Write-Host "Aviso: API Codemagic: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Adicione manualmente: https://codemagic.io/apps" -ForegroundColor Yellow
    }
}

if ($appId) {
    $envUrl = "https://codemagic.io/app/$appId/settings/environment-variables"
    Write-Host "Abrindo variáveis de ambiente: $envUrl" -ForegroundColor Cyan
    Start-Process $envUrl
} else {
    Write-Host "Abrindo Codemagic Apps..." -ForegroundColor Cyan
    Start-Process "https://codemagic.io/apps"
}

Write-Host ""
Write-Host "WISDOMAPP reutiliza do Controle Total (Team level):" -ForegroundColor Cyan
Write-Host "  - Integração Developer Portal: ControleTotalAPI1" -ForegroundColor White
Write-Host "  - Grupo appstore_credentials: CERTIFICATE_PRIVATE_KEY (secret)" -ForegroundColor White
Write-Host "  - Opcional firebase_ipa_upload: FIREBASE_SERVICE_ACCOUNT_JSON (wisdomapp-b9e98)" -ForegroundColor White
Write-Host ""
Write-Host "No app WISDOMAPP: Workflow Editor > Switch to YAML configuration" -ForegroundColor Cyan
Write-Host "Branch sugerida: codemagic-ios-ready (ou codemagic-{versao}-ready)" -ForegroundColor Cyan

if ($P8Path -and $token -and (Test-Path $P8Path)) {
    Write-Host "Nota: .p8 já está na integração ControleTotalAPI1 — não precisa duplicar por app." -ForegroundColor Gray
}
