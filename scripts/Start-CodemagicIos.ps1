# WISDOMAPP - configuracao iOS CodeMagic em um clique (Git + push branch + registro Codemagic).
# Mesma certificação Apple do Controle Total App (ControleTotalAPI1 / appstore_credentials).
#
# Uso:
#   .\scripts\Start-CodemagicIos.ps1
#   $env:CODEMAGIC_API_TOKEN='...'; .\scripts\Start-CodemagicIos.ps1
#   $env:WISDOMAPP_GITHUB_REPO='https://github.com/SEU_USER/wisdomapp.git'; .\scripts\Start-CodemagicIos.ps1
#
# Depois: no Codemagic - Start new build - workflow iOS - branch codemagic-*-ready

param(
    [switch]$SkipGitInit,
    [switch]$SkipCodemagicApi,
    [switch]$SkipPush,
    [string]$GitHubRepo = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

if ([string]::IsNullOrWhiteSpace($GitHubRepo)) {
    $GitHubRepo = $env:WISDOMAPP_GITHUB_REPO
}
if ([string]::IsNullOrWhiteSpace($GitHubRepo)) {
    $GitHubRepo = "https://github.com/ralhom-netizen/wisdomapp.git"
}

function Add-CodemagicGitFiles {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $paths = @(
        ".gitignore",
        "codemagic.yaml",
        "pubspec.yaml",
        "pubspec.lock",
        "analysis_options.yaml",
        "lib",
        "ios",
        "android",
        "assets",
        "web",
        "test",
        "tool",
        "scripts",
        "deploy.ps1",
        "firestore.rules",
        "firestore.indexes.json",
        "firebase.json",
        "storage.rules",
        "functions/index.js",
        "functions/package.json",
        "functions/package-lock.json"
    )
    foreach ($rel in $paths) {
        $p = Join-Path $root $rel
        if (Test-Path $p) {
            git add -- $p 2>&1 | Out-Null
        }
    }
    $ErrorActionPreference = $eap
}

function Get-VersionBranch {
    $vf = Join-Path $root "lib\constants\app_version.dart"
    if (-not (Test-Path $vf)) { return "codemagic-ios-ready" }
    $raw = Get-Content $vf -Raw
    if ($raw -match "current\s*=\s*'([^']+)'") {
        return "codemagic-$($Matches[1] -replace '\.', '-')-ready"
    }
    return "codemagic-ios-ready"
}

Write-Host "=== WISDOMAPP - Setup iOS CodeMagic (um clique) ===" -ForegroundColor Cyan
Write-Host "Bundle: com.wisdomapp | API Apple: wisdomapp (4UMWWALR3U)" -ForegroundColor Yellow
$versionBranch = Get-VersionBranch
Write-Host "Branch CodeMagic: $versionBranch + codemagic-ios-ready" -ForegroundColor Yellow

# --- 1) Git init + primeiro commit se necessário ---
if (-not $SkipGitInit) {
    Write-Host "`n[1/4] Git..." -ForegroundColor Cyan
    $needsInitialCommit = $false
    if (-not (Test-Path (Join-Path $root ".git"))) {
        git init
        if ($LASTEXITCODE -ne 0) { throw "git init falhou" }
        $needsInitialCommit = $true

        $gitUser = git config user.name 2>$null
        $gitEmail = git config user.email 2>$null
        if (-not $gitUser) { git config user.name "WISDOMAPP Deploy" }
        if (-not $gitEmail) { git config user.email "raihom@gmail.com" }
    } else {
        $needsInitialCommit = $true
        $eapGit = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        git rev-parse HEAD 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $needsInitialCommit = $false }
        $ErrorActionPreference = $eapGit
        if ($needsInitialCommit) { Write-Host "  .git existe sem commits - criando commit inicial..." -ForegroundColor Gray }
        else { Write-Host "  .git ja existe." -ForegroundColor Gray }
    }

    if ($needsInitialCommit) {
        Add-CodemagicGitFiles
        git commit -m "chore: initial WISDOMAPP iOS CodeMagic ready"
        if ($LASTEXITCODE -ne 0) { throw "git commit inicial falhou" }
        Write-Host "  Repositorio Git inicializado e commit criado." -ForegroundColor Green
    }

    $hasOrigin = $false
    try {
        $null = git remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0) { $hasOrigin = $true }
    } catch { }

    if (-not $hasOrigin) {
        git remote add origin $GitHubRepo
        Write-Host "  Remote origin: $GitHubRepo" -ForegroundColor Green

        if (Get-Command gh -ErrorAction SilentlyContinue) {
            $repoName = ($GitHubRepo -replace '\.git$', '' -split '/')[-1]
            $owner = ($GitHubRepo -replace 'https://github.com/', '' -replace '\.git$', '' -split '/')[0]
            Write-Host "  Criando repositorio GitHub ($owner/$repoName) se nao existir..." -ForegroundColor Gray
            gh repo view "$owner/$repoName" 2>$null
            if ($LASTEXITCODE -ne 0) {
                gh repo create "$owner/$repoName" --private --source=. --remote=origin --push 2>&1 | ForEach-Object { Write-Host $_ }
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  Repositorio GitHub criado e push inicial feito." -ForegroundColor Green
                    $hasOrigin = $true
                }
            }
        }
    } else {
        $url = git remote get-url origin
        Write-Host "  Origin existente: $url" -ForegroundColor Gray
    }
}

# --- 2) Push branches CodeMagic ---
if (-not $SkipPush) {
    Write-Host "`n[2/4] Push branches CodeMagic..." -ForegroundColor Cyan
    & (Join-Path $root "scripts\push-codemagic-ready.ps1") -Root $root
}

# --- 3) Registrar app no Codemagic ---
if (-not $SkipCodemagicApi) {
    Write-Host "`n[3/4] Codemagic (registrar app + abrir config)..." -ForegroundColor Cyan
    & (Join-Path $root "scripts\setup_codemagic_ios.ps1")
}

# --- 4) Resumo ---
Write-Host "`n[4/4] Proximos passos ===" -ForegroundColor Green
Write-Host '  1. Codemagic: app WISDOMAPP, Settings, Workflow Editor, Switch to YAML' -ForegroundColor White
Write-Host '  2. Integracao Team wisdomapp + appstore_credentials (CERTIFICATE_PRIVATE_KEY)' -ForegroundColor White
Write-Host ('  3. Start new build: workflow iOS, branch ' + $versionBranch) -ForegroundColor White
Write-Host '  4. IPA e TestFlight automaticos apos o build.' -ForegroundColor White
Write-Host ''
Write-Host 'Concluido. Clique Start no CodeMagic apos ativar YAML.' -ForegroundColor Green
