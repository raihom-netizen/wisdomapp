# Corrige GitHub + dispara build CodeMagic (contorna app ARCHIVED na UI).
# Uso: .\scripts\Fix-CodemagicIosCompleto.ps1
# Token (uma vez): Account settings > Personal Account > API token > copie para .codemagic-token na raiz

param(
    [switch]$SkipGitPush,
    [switch]$SkipBuild,
    [string]$ApiToken = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = "https://github.com/raihom-netizen/wisdomapp.git"
$archivedAppId = "6a3fe39cfbfdda27bec38156"
$tokenFile = Join-Path $root ".codemagic-token"
Set-Location $root

function Get-CmToken {
    param([string]$Override)
    if ($Override) { return $Override.Trim() }
    if ($env:CODEMAGIC_API_TOKEN) { return $env:CODEMAGIC_API_TOKEN.Trim() }
    if (Test-Path $tokenFile) { return (Get-Content $tokenFile -Raw).Trim() }
    return $null
}

function Invoke-CmApi {
    param(
        [string]$Token,
        [string]$Method,
        [string]$Uri,
        [object]$Body = $null
    )
    $headers = @{ "Content-Type" = "application/json"; "x-auth-token" = $Token }
    if ($Body) {
        return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method -Body ($Body | ConvertTo-Json -Depth 6)
    }
    return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method
}

Write-Host "=== Fix CodeMagic iOS (automatico) ===" -ForegroundColor Cyan

if (-not $SkipGitPush) {
    git remote set-url origin $repo
    git add codemagic.yaml .gitignore scripts/Fix-CodemagicIosCompleto.ps1 scripts/Push-Codemagic-GitHub.ps1 2>$null | Out-Null
    git add -- lib ios android pubspec.yaml pubspec.lock scripts 2>$null | Out-Null
    if (git diff --cached --name-only) {
        git commit -m "chore(ios): codemagic triggering + fix build archived" 2>$null | Out-Null
    }
    git fetch origin main 2>$null | Out-Null
    git push --force-with-lease origin HEAD:main 2>&1 | ForEach-Object { Write-Host $_ }
    git push origin HEAD:refs/heads/codemagic-10-04-ready 2>$null | Out-Null
    git push origin HEAD:refs/heads/codemagic-ios-ready 2>$null | Out-Null
    Write-Host "GitHub OK: $repo (main + codemagic branches)" -ForegroundColor Green
}

if (-not $SkipBuild) {
    Write-Host "`n[3/3] Disparar build CodeMagic..." -ForegroundColor Cyan
    $nodeScript = Join-Path $root "scripts\trigger-codemagic-build.js"
    if (Test-Path $nodeScript) {
        & node $nodeScript
        if ($LASTEXITCODE -eq 0) { Write-Host "`nConcluido." -ForegroundColor Green; exit 0 }
    }
    $token = Get-CmToken -Override $ApiToken
if (-not $token) {
    Write-Host ""
    Write-Host "API token CodeMagic necessario (uma vez):" -ForegroundColor Yellow
    Write-Host "  1. Abra https://codemagic.io/settings" -ForegroundColor White
    Write-Host "  2. API token > Show > copie" -ForegroundColor White
    Write-Host "  3. Cole abaixo (salvo em .codemagic-token)" -ForegroundColor White
    Start-Process "https://codemagic.io/settings"
    $token = Read-Host "Cole o API token"
    if (-not $token) { throw "Token vazio." }
    Set-Content -Path $tokenFile -Value $token.Trim() -NoNewline -Encoding UTF8
    Write-Host "Token salvo em .codemagic-token" -ForegroundColor Green
}

Write-Host "`nCodeMagic API..." -ForegroundColor Cyan
$apps = (Invoke-CmApi -Token $token -Method Get -Uri "https://api.codemagic.io/apps").applications
$wisdomApps = @($apps | Where-Object {
    $_.repositoryUrl -like "*wisdomapp*" -or $_.appName -like "*wisdom*"
})

$appId = $null
foreach ($a in $wisdomApps) {
    if ($a._id -ne $archivedAppId) {
        $appId = $a._id
        Write-Host "  App ativo: $($a.appName) ($appId)" -ForegroundColor Green
        break
    }
}

if (-not $appId) {
    Write-Host "  wisdomapp ARCHIVED — registrando app novo via API..." -ForegroundColor Yellow
    try {
        $created = Invoke-CmApi -Token $token -Method Post -Uri "https://api.codemagic.io/apps" -Body @{
            repositoryUrl = $repo
        }
        $appId = $created._id
        if (-not $appId -and $created.application) { $appId = $created.application._id }
        if (-not $appId) { throw "Resposta API sem app id." }
        Write-Host "  Novo app criado: $appId" -ForegroundColor Green
        Start-Process "https://codemagic.io/app/$appId/settings"
    } catch {
        Write-Host "  Nao foi possivel criar app via API: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Manual: Applications > Add application > $repo > Flutter" -ForegroundColor Yellow
        Start-Process "https://codemagic.io/apps"
        throw
    }
}

$buildBody = @{
    appId = $appId
    workflowId = "ios-workflow"
    branch = "main"
    environment = @{
        groups = @("appstore_credentials", "firebase_ipa_upload")
    }
}

try {
    $build = Invoke-CmApi -Token $token -Method Post -Uri "https://api.codemagic.io/builds" -Body $buildBody
    $buildId = $build.buildId
    if ($buildId) {
        Write-Host "`nBuild iOS INICIADO via API." -ForegroundColor Green
        Write-Host "  https://codemagic.io/app/$appId/build/$buildId" -ForegroundColor Cyan
        Start-Process "https://codemagic.io/app/$appId/build/$buildId"
    } else {
        Write-Host "Build solicitado: $($build | ConvertTo-Json -Compress)" -ForegroundColor Green
        Start-Process "https://codemagic.io/app/$appId"
    }
} catch {
    Write-Host "  Erro ao iniciar build: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Se app ARCHIVED: delete o antigo em Repository settings ou use o app novo $appId" -ForegroundColor Yellow
    Start-Process "https://codemagic.io/app/$archivedAppId/settings/repository"
    throw
}

Write-Host "`nConcluido." -ForegroundColor Green
