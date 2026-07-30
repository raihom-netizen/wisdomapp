# Envia o projeto ao GitHub que o CodeMagic usa (raihom-netizen/wisdomapp).
# Rode: .\scripts\Push-Codemagic-GitHub.ps1  (ou Fix-CodemagicIosCompleto.ps1)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = "https://github.com/raihom-netizen/wisdomapp.git"
Set-Location $root

Write-Host "=== Push GitHub para CodeMagic ===" -ForegroundColor Cyan
Write-Host "Repo: $repo" -ForegroundColor Yellow
Write-Host "Branch remota: main (+ codemagic-10-04-ready)" -ForegroundColor Yellow

git remote set-url origin $repo

$paths = @(
    "codemagic.yaml", "pubspec.yaml", "pubspec.lock", "analysis_options.yaml",
    "lib", "ios", "android", "assets", "web", "test", "tool", "scripts",
    "firestore.rules", "firestore.indexes.json", "firebase.json", "storage.rules",
    "functions/index.js", "functions/package.json", "functions/package-lock.json",
    ".gitignore"
)
foreach ($rel in $paths) {
    $p = Join-Path $root $rel
    if (Test-Path $p) { git add -- $p 2>$null | Out-Null }
}

$staged = git diff --cached --name-only
if ($staged) {
    git commit -m "chore: sync CodeMagic iOS build $(Get-Date -Format yyyy-MM-dd)"
}

Write-Host "`nEnviando para origin/main ..." -ForegroundColor Cyan
git push -u origin HEAD:main
if ($LASTEXITCODE -ne 0) {
    Write-Host "`nFalhou. Abra GitHub Desktop ou faca login:" -ForegroundColor Red
    Write-Host "  https://github.com/login" -ForegroundColor White
    Write-Host "Depois rode este script de novo." -ForegroundColor Yellow
    exit 1
}

git push origin HEAD:refs/heads/codemagic-10-04-ready 2>$null
Write-Host "`nOK. No CodeMagic: Start new build, branch main, workflow ios-workflow" -ForegroundColor Green
