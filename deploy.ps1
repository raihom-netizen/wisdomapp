param(
  [switch]$WebOnly,
  [switch]$SkipFirebase,
  [switch]$ForceVersionOnline,
  [switch]$Clean,
  [switch]$DryRun,
  [switch]$LegacyCodemagic,
  [switch]$NoCodemagicPush  # compat: o push/Codemagic agora so roda com -LegacyCodemagic
)
# Deploy WISDOMAPP - padrao Controle Total (roteiro completo em WISDOMAPP_MEMORIA_BKP.md, secao
# "Deploy completo (padrao Controle Total)").
# Politica: NAO grava app_config/version nem avisa usuarios automaticamente.
# Apos publicar nas lojas: Painel Admin > "Subir versao e forcar atualizacao" ou .\force_version_online.ps1
#
# Uso: .\deploy.ps1 -WebOnly          -> SO HOSTING (web). Nunca functions/firestore/storage junto.
#      .\deploy.ps1 -WebOnly -DryRun  -> mostra o plano e confere versao/pre-requisitos, sem build e sem publicar
#      .\deploy.ps1                   -> legado "tudo de uma vez" (web + firestore/storage + TODAS as functions + AAB).
#                                        So com pedido explicito do dono; o roteiro padrao e -WebOnly + functions escopadas.
#      .\deploy.ps1 -Clean            -> inclui flutter clean
#      .\deploy.ps1 -ForceVersionOnline  -> tambem grava Firestore (so se quiser forcar agora)
#      .\deploy.ps1 -LegacyCodemagic  -> (completo) tambem gera o ZIP iOS do Codemagic, faz o commit automatico
#                                        e o push para as branches e dispara o Codemagic (fluxo antigo).
# Android: AAB via .\build_aab_release.ps1 -> D:\TEMPORARIOS\WISDOMAPP_<versao>+<build>_<build>_release.aab
# iOS: GitHub Actions "iOS TestFlight (Flutter)" - o dono da o Run workflow. Codemagic = legado.
# IMPORTANTE: nunca "firebase deploy" de hosting sem passar por aqui (build + Validate-HostingPreDeploy).

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

function Get-AppVersionInfo {
  $versionFile = Join-Path $root "lib\constants\app_version.dart"
  $raw = [System.IO.File]::ReadAllText($versionFile)
  $v = [regex]::Match($raw, "static const String current = '([^']+)';").Groups[1].Value
  $pub = [int][regex]::Match($raw, "static const int buildNumber = (\d+);").Groups[1].Value
  $vc = [int][regex]::Match($raw, "static const int versionCode = (\d+);").Groups[1].Value
  return @{ Version = $v; Build = $pub; VersionCode = $vc; Tag = "$v+$pub" }
}

$modo = if ($WebOnly) { "WEB (so hosting)" } else { "COMPLETO legado (web + Firebase + AAB)" }
Write-Host "=== WISDOMAPP deploy: $modo ===" -ForegroundColor Cyan

Write-Host "`n=== 0/7 Versao ===" -ForegroundColor Cyan
if ($DryRun) {
  & (Join-Path $root "scripts\sync_app_version.ps1") -Conferir
} else {
  & (Join-Path $root "scripts\sync_app_version.ps1")
}
if ($LASTEXITCODE -ne 0) { exit 1 }
$ver = Get-AppVersionInfo
Write-Host "Versao: $($ver.Tag) (#$($ver.VersionCode))" -ForegroundColor Yellow

if ($DryRun) {
  Write-Host "`n[DryRun] Plano (nada foi buildado nem publicado):" -ForegroundColor Yellow
  Write-Host "  1/7 flutter pub get $(if ($Clean) { '(+ flutter clean)' })"
  Write-Host "  2/7 flutter build web --release --pwa-strategy=none --no-wasm-dry-run --no-tree-shake-icons"
  Write-Host "      + garantir _flutter.loader.load() em build/web/flutter_bootstrap.js"
  Write-Host "  3/7 build/web/version.json = $($ver.Tag) + Validate-HostingPreDeploy.ps1"
  if ($SkipFirebase) {
    Write-Host "  4/7 Firebase: pulado (-SkipFirebase)"
  } elseif ($WebOnly) {
    Write-Host "  4/7 firebase deploy --only hosting --project wisdomapp-b9e98   (SO hosting)"
  } else {
    Write-Host "  4/7 firebase deploy --only hosting,firestore,storage + --only functions (TODAS) + bootstrap Firestore"
  }
  Write-Host "  5/7 force version: $(if ($ForceVersionOnline) { 'SIM (force_version_online.ps1)' } else { 'nao (manual no Admin)' })"
  Write-Host "  6/7 AAB: $(if ($WebOnly) { 'pulado (-WebOnly)' } else { '.\build_aab_release.ps1' })"
  Write-Host "  7/7 Git/Codemagic: $(if ($LegacyCodemagic -and -not $WebOnly) { 'push-codemagic-ready.ps1 + trigger Codemagic (legado)' } else { 'nada automatico (push manual nas branches de build)' })"
  $tok = Join-Path $root ".firebase-ci-token"
  Write-Host ("  Token Firebase CI: {0}" -f $(if ($env:FIREBASE_TOKEN -or (Test-Path $tok)) { "presente" } else { "AUSENTE (usa o login do firebase CLI)" }))
  $boot = Join-Path $root "web\flutter_bootstrap.js"
  if ((Test-Path $boot) -and ([System.IO.File]::ReadAllText($boot) -match '_flutter\.loader\.load\s*\(')) {
    Write-Host "  web/flutter_bootstrap.js: _flutter.loader.load() presente (OK)" -ForegroundColor Green
  } else {
    Write-Host "  ERRO: web/flutter_bootstrap.js sem _flutter.loader.load() - a web ficaria no splash." -ForegroundColor Red
    exit 1
  }
  exit 0
}

Write-Host "`n=== 1/7 Flutter pub get ===" -ForegroundColor Cyan
& (Join-Path $root "scripts\patch_flutter_plugin_gradle.ps1")
if ($Clean) { flutter clean; if ($LASTEXITCODE -ne 0) { exit 1 } }
flutter pub get
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n=== 2/7 Build Web ===" -ForegroundColor Cyan
$eap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
flutter build web --release --pwa-strategy=none --no-wasm-dry-run --no-tree-shake-icons 2>&1 | ForEach-Object { Write-Host $_ }
$ErrorActionPreference = $eap
if ($LASTEXITCODE -ne 0) { exit 1 }

$publicDir = Join-Path $root "build\web"
$assetBin = Join-Path $publicDir "assets\AssetManifest.bin.json"
$assetJson = Join-Path $publicDir "assets\AssetManifest.json"
if ((Test-Path $assetBin) -and (-not (Test-Path $assetJson))) {
  Copy-Item $assetBin $assetJson -Force
}

$bootstrapPath = Join-Path $publicDir "flutter_bootstrap.js"
if (Test-Path $bootstrapPath) {
  $bc = Get-Content $bootstrapPath -Raw -Encoding UTF8
  # Boot unico: index.html NAO chama load() - so o flutter_bootstrap.js deve chamar.
  # (Versoes antigas do deploy removiam o load() e a web ficava no splash eterno.) NUNCA stripar.
  if ($bc -notmatch '_flutter\.loader\.load\s*\(') {
    if ($bc -match '//\s*load\(\)\s*in index\.html') {
      $inject = @'

_flutter.loader.load({
  serviceWorkerSettings: null,
  config: {
    canvasKitVariant: "full",
    canvasKitBaseUrl: "/canvaskit/"
  }
});
'@
      $bc = $bc -replace '//\s*load\(\)\s*in index\.html[^\r\n]*', $inject.Trim()
      Set-Content -Path $bootstrapPath -Value $bc -NoNewline -Encoding UTF8
      Write-Host '  flutter_bootstrap.js: load() restaurado (CanvasKit local).' -ForegroundColor Yellow
    } else {
      Write-Host '  ERRO: flutter_bootstrap.js sem _flutter.loader.load() - web nao vai abrir.' -ForegroundColor Red
      exit 1
    }
  } else {
    Write-Host '  flutter_bootstrap.js: load() OK.' -ForegroundColor Green
  }
}

# Cache-bust: o index publicado tem de carregar o bootstrap com ?v=<build> (marcador do web/index.html).
$builtIndex = Join-Path $publicDir "index.html"
if (Test-Path $builtIndex) {
  $bi = [System.IO.File]::ReadAllText($builtIndex)
  if ($bi.Contains("flutter_bootstrap.js?v=$($ver.Build)")) {
    Write-Host "  index.html: cache-bust ?v=$($ver.Build) OK." -ForegroundColor Green
  } else {
    Write-Host "  AVISO: build/web/index.html sem flutter_bootstrap.js?v=$($ver.Build) (rode .\scripts\sync_app_version.ps1)." -ForegroundColor Yellow
  }
}

Write-Host "`n=== 3/7 version.json + validacao do boot web ===" -ForegroundColor Cyan
$playUrl = "https://play.google.com/store/apps/details?id=com.wisdomapp.app"
$testFlightUrl = "https://testflight.apple.com/join/qWpWwhnN"
$versionJsonPath = Join-Path $publicDir "version.json"
$json = [ordered]@{
  version = $ver.Version
  buildNumber = $ver.Build
  versionCode = $ver.VersionCode
  releaseTag = $ver.Tag
  apkDownloadUrl = $playUrl
  testFlightUrl = $testFlightUrl
} | ConvertTo-Json -Compress
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($versionJsonPath, $json, $utf8)
Write-Host "  version.json: $($ver.Tag)" -ForegroundColor Green

& (Join-Path $root "scripts\Validate-HostingPreDeploy.ps1") -Root $root
if ($LASTEXITCODE -ne 0) { exit 1 }

if (-not $SkipFirebase) {
  $tokenSrc = Join-Path $root ".firebase-ci-token"
  if (-not (Test-Path $tokenSrc)) {
    $alt = Join-Path $root "dados para copiar do controle total app\.firebase-ci-token"
    if (Test-Path $alt) { Copy-Item $alt $tokenSrc -Force }
  }
  if ($WebOnly) {
    # -WebOnly = SOMENTE hosting. Antes publicava hosting+firestore+storage+TODAS as functions
    # (+ bootstrap do Firestore), o que podia quebrar o app antigo em producao ao subir so a web.
    Write-Host "`n=== 4/7 Firebase: SO hosting ===" -ForegroundColor Cyan
    & (Join-Path $root "scripts\Invoke-FirebaseDeploy.ps1") -Root $root -HostingOnly
    if ($LASTEXITCODE -ne 0) { exit 1 }
  } else {
    Write-Host "`n=== 4/7 Firebase: hosting + firestore + storage + functions (legado completo) ===" -ForegroundColor Cyan
    & (Join-Path $root "scripts\Invoke-FirebaseDeploy.ps1") -Root $root
    if ($LASTEXITCODE -ne 0) { exit 1 }

    Write-Host "`n=== 4b/7 Bootstrap Firestore + Storage ===" -ForegroundColor Cyan
    Push-Location (Join-Path $root "functions")
    $eapBoot = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    node ..\scripts\bootstrap-wisdomapp-firebase.js 2>&1 | ForEach-Object { Write-Host $_ }
    $bootOk = $LASTEXITCODE
    $ErrorActionPreference = $eapBoot
    Pop-Location
    if ($bootOk -ne 0) {
      Write-Host "  Aviso: bootstrap falhou (credencial Admin?). Rode manualmente apos firebase login." -ForegroundColor Yellow
    }
  }
} else {
  Write-Host "`n=== 4/7 Firebase (pulado: -SkipFirebase) ===" -ForegroundColor Yellow
}

if ($ForceVersionOnline) {
  Write-Host "`n=== 5/7 Forcar versao online (opcional) ===" -ForegroundColor Cyan
  & (Join-Path $root "force_version_online.ps1")
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  Aviso: force version falhou - use Admin > Subir versao e forcar atualizacao." -ForegroundColor Yellow
  }
} else {
  Write-Host "`n=== 5/7 Force version (pulado - use Admin quando quiser avisar usuarios) ===" -ForegroundColor Yellow
}

if (-not $WebOnly) {
  Write-Host "`n=== 6/7 AAB (build_aab_release.ps1) ===" -ForegroundColor Cyan
  & (Join-Path $root "build_aab_release.ps1")
  if ($LASTEXITCODE -ne 0) { exit 1 }
  if ($LegacyCodemagic) {
    Write-Host "`n=== 6b/7 ZIP iOS Codemagic (legado) ===" -ForegroundColor Cyan
    & (Join-Path $root "scripts\Export-AabIosTemporarios.ps1")
    if ($LASTEXITCODE -ne 0) { exit 1 }
  }
} else {
  Write-Host "`n=== 6/7 AAB (pulado: -WebOnly) ===" -ForegroundColor Yellow
}

if ($LegacyCodemagic -and -not $WebOnly) {
  Write-Host "`n=== 7/7 Codemagic legado: commit automatico + push + trigger ===" -ForegroundColor Cyan
  git remote set-url origin "https://github.com/raihom-netizen/wisdomapp.git" 2>$null | Out-Null
  & (Join-Path $root "scripts\push-codemagic-ready.ps1") -Root $root
  $trigger = Join-Path $root "scripts\trigger-codemagic-build.js"
  if (Test-Path $trigger) {
    & node $trigger 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  [CodeMagic] App ARCHIVED ou sem API token - rode Fix-CodemagicIos.bat ou desarquive na UI." -ForegroundColor Yellow
    }
  }
} else {
  Write-Host "`n=== 7/7 Git: nada automatico ===" -ForegroundColor Yellow
  Write-Host "  Commit escopado (git add <arquivos>) e push nas branches de build:" -ForegroundColor Yellow
  Write-Host "    git push origin HEAD:refs/heads/codemagic-10-05-ready   (Android/web)" -ForegroundColor Yellow
  Write-Host "    git push origin HEAD:refs/heads/codemagic-ios-ready     (iOS)" -ForegroundColor Yellow
  Write-Host "    git push origin HEAD:refs/heads/main                    (branch padrao)" -ForegroundColor Yellow
}

Write-Host "`n=== Concluido ===" -ForegroundColor Green
Write-Host "  Web: https://wisdomapp.com.br | https://wisdomapp-b9e98.web.app | version.json $($ver.Tag)" -ForegroundColor Cyan
if ($WebOnly) {
  Write-Host "  Firebase: SOMENTE hosting publicado (-WebOnly). Functions/Firestore/Storage NAO tocados." -ForegroundColor Cyan
} else {
  Write-Host "  AAB: D:\TEMPORARIOS\WISDOMAPP_$($ver.Tag)_$($ver.VersionCode)_release.aab (envio manual no Play Console)" -ForegroundColor Cyan
}
Write-Host "  iOS: GitHub > Actions > iOS TestFlight (Flutter) > Run workflow (branch codemagic-ios-ready) - start do dono." -ForegroundColor Cyan
