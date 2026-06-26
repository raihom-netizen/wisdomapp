# Atualiza no Git remoto o ramo usado pelo CodeMagic (Start manual na UI).
# Chamado pelo deploy.ps1 e Start-CodemagicIos.ps1.
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Continue"
Push-Location $Root
try {
    if (-not (Test-Path (Join-Path $Root ".git"))) {
        Write-Host "  [Codemagic Git] Sem repositorio .git - rode .\scripts\Start-CodemagicIos.ps1 primeiro." -ForegroundColor Yellow
        exit 0
    }

    $target = $env:CODEMAGIC_READY_BRANCH
    if ([string]::IsNullOrWhiteSpace($target)) { $target = "codemagic-ios-ready" }

    $versionBranch = $null
    $versionFileForCm = Join-Path $Root "lib\constants\app_version.dart"
    if (Test-Path $versionFileForCm) {
        $vRaw = Get-Content $versionFileForCm -Raw
        if ($vRaw -match "current\s*=\s*'([^']+)'") {
            $vMark = $Matches[1]
            $vh = $vMark -replace '\.', '-'
            $versionBranch = "codemagic-$vh-ready"
        }
    }

    $toStage = @(
        "lib/constants/app_version.dart",
        "pubspec.yaml",
        "pubspec.lock",
        "android/app/build.gradle",
        "codemagic.yaml",
        "firestore.indexes.json",
        "firestore.rules",
        "deploy.ps1",
        "scripts/push-codemagic-ready.ps1",
        "scripts/Start-CodemagicIos.ps1",
        "scripts/codemagic_ios_delete_appstore_profiles.py",
        "scripts/upload_ipa_to_storage.js"
    )
    foreach ($rel in $toStage) {
        $p = Join-Path $Root $rel
        if (Test-Path $p) { git add -- $p 2>&1 | Out-Null }
    }

    foreach ($rel in @("lib", "ios", "functions/index.js", "functions/package.json", "functions/package-lock.json")) {
        $p = Join-Path $Root $rel
        if (Test-Path $p) { git add -- $p 2>&1 | Out-Null }
    }

    $stagedNames = git diff --cached --name-only 2>$null
    if ($stagedNames) {
        git commit -m "chore(ios): sync CodeMagic iOS ready [automated]" 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [Codemagic Git] Aviso: commit falhou (git user.name/email?)." -ForegroundColor Yellow
        }
    }

    $pushTargets = @($target)
    if ($versionBranch -and ($versionBranch -ne $target)) { $pushTargets += $versionBranch }

    foreach ($tb in $pushTargets) {
        Write-Host "  [Codemagic Git] Enviando HEAD -> origin/$tb ..." -ForegroundColor Gray
        git push origin "HEAD:refs/heads/$tb" 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [Codemagic Git] Push falhou para '$tb'." -ForegroundColor Yellow
            Write-Host "  Comando manual: git push origin HEAD:refs/heads/$tb" -ForegroundColor Cyan
            exit 0
        }
    }

    Write-Host "  [Codemagic Git] OK - remoto: $($pushTargets -join ', ')." -ForegroundColor Green
    Write-Host "  No CodeMagic: Start new build na branch '$versionBranch' ou '$target'." -ForegroundColor Cyan
}
finally {
    Pop-Location
}
exit 0
