# Validacao antes do deploy Firebase Hosting (WISDOMAPP — raiz com build/web).
param([string]$Root = "")

if ($Root -and (Test-Path (Join-Path $Root "firebase.json"))) {
    $repoRoot = $Root
} elseif (Test-Path (Join-Path $PSScriptRoot "..\firebase.json")) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $repoRoot = (Get-Location).Path
}

$ErrorActionPreference = "Stop"
$failed = $false

$firebaseJsonPath = Join-Path $repoRoot "firebase.json"
if (-not (Test-Path $firebaseJsonPath)) {
    Write-Host "[BLINDAGEM] ERRO: firebase.json nao encontrado." -ForegroundColor Red
    exit 1
}
$firebaseContent = Get-Content $firebaseJsonPath -Raw
if (-not ($firebaseContent -match '"public"\s*:\s*"build/web"')) {
    Write-Host "[BLINDAGEM] ERRO: firebase.json deve ter hosting.public = 'build/web'." -ForegroundColor Red
    exit 1
}
Write-Host "[BLINDAGEM] Raiz e firebase.json OK." -ForegroundColor Green

$publicDir = Join-Path $repoRoot "build\web"
$requiredFiles = @("index.html", "flutter_bootstrap.js", "main.dart.js", "version.json")
foreach ($f in $requiredFiles) {
    $path = Join-Path $publicDir $f
    if (-not (Test-Path $path)) {
        Write-Host "[BLINDAGEM] ERRO: Ausente build\web\$f" -ForegroundColor Red
        $failed = $true
    }
}
if ($failed) { exit 1 }
Write-Host "[BLINDAGEM] Arquivos obrigatorios presentes." -ForegroundColor Green

$web404 = Join-Path $repoRoot "web\404.html"
$build404 = Join-Path $publicDir "404.html"
if (Test-Path $web404) {
    Copy-Item $web404 $build404 -Force
}

Write-Host "[BLINDAGEM] Validacao concluida." -ForegroundColor Green
