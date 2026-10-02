# Build AAB release do WISDOMAPP (padrao Controle Total) + copia em D:\TEMPORARIOS.
#
# Uso:
#   .\build_aab_release.ps1                 -> confere versao, flutter analyze (falha so em error),
#                                              flutter build appbundle --release, 16 KB, copia e confere o AAB
#   .\build_aab_release.ps1 -DryRun         -> so mostra o plano e confere versao/pre-requisitos (nao builda)
#   .\build_aab_release.ps1 -SkipAnalyze    -> pula o preflight (use so se o analyze ja rodou na sessao)
#   .\build_aab_release.ps1 -Strings "Texto novo 1","Texto novo 2"   -> confere essas strings no AAB gerado
#
# Saida: D:\TEMPORARIOS\WISDOMAPP_<marketing>+<build>_<versionCode>_release.aab
#        + alias D:\TEMPORARIOS\WISDOMAPP_ultimo_release.aab
# A versao vem SO de lib/constants/app_version.dart (alinhe antes com .\scripts\sync_app_version.ps1 -Build <n>).
# Pode levar 10-20 min. Nao publica nada: o envio ao Play Console e manual (dono).
param(
  [switch]$DryRun,
  [switch]$SkipAnalyze,
  [string[]]$Strings = @()
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root
$versionFile = Join-Path $root "lib\constants\app_version.dart"
$destDir = "D:\TEMPORARIOS"

function Get-Ver {
  $raw = [System.IO.File]::ReadAllText($versionFile)
  $c = [regex]::Match($raw, "static const String current = '([^']+)';").Groups[1].Value
  $b = [regex]::Match($raw, "static const int buildNumber = (\d+);").Groups[1].Value
  $v = [regex]::Match($raw, "static const int versionCode = (\d+);").Groups[1].Value
  if (-not $c -or -not $b -or -not $v) { throw "app_version.dart sem current/buildNumber/versionCode." }
  return @{ Marketing = $c; Build = [int]$b; VersionCode = [int]$v }
}

Write-Host "=== 1/6 Versao (app_version.dart -> pubspec/gradle/web) ===" -ForegroundColor Cyan
& (Join-Path $root "scripts\sync_app_version.ps1") -Conferir
if ($LASTEXITCODE -ne 0) {
  Write-Host "ERRO: versao desalinhada. Rode .\scripts\sync_app_version.ps1 (ou -Build <novo>) antes do AAB." -ForegroundColor Red
  exit 1
}
$ver = Get-Ver
$destAab = Join-Path $destDir ("WISDOMAPP_{0}+{1}_{2}_release.aab" -f $ver.Marketing, $ver.Build, $ver.VersionCode)
$aabBuilt = Join-Path $root "build\app\outputs\bundle\release\app-release.aab"

$proguard = Join-Path $root "android\app\proguard-rules.pro"
if (Test-Path $proguard) {
  # Regra geral do dono (R8): nada de -keep do pacote inteiro de biblioteca. So avisa; quem enxuga e o dono/sessao propria.
  # "Amplo" = pacote de ate 3 niveis com .** { *; } (ex.: com.google.**, com.google.firebase.**, io.flutter.plugins.**),
  # fora o proprio app (com.wisdomapp). Keeps estreitos (ex.: io.flutter.plugins.firebase.firestore.**) nao contam.
  $amplos = Select-String -Path $proguard -CaseSensitive -Pattern '^\s*-keep(classmembers|names)?\s+(class|interface)\s+(?!com\.wisdomapp)[a-z0-9_]+(\.[a-z0-9_]+){0,2}\.\*\*\s*\{\s*\*;\s*\}'
  if ($amplos) {
    Write-Host "  AVISO R8: keep(s) amplo(s) em proguard-rules.pro (baixa taxa de otimizacao no Play):" -ForegroundColor Yellow
    $amplos | ForEach-Object { Write-Host ("    linha {0}: {1}" -f $_.LineNumber, $_.Line.Trim()) -ForegroundColor Yellow }
  } else {
    Write-Host "  proguard-rules.pro: sem keep amplo de biblioteca." -ForegroundColor Green
  }
}
$manifest = Join-Path $root "android\app\src\main\AndroidManifest.xml"
if ((Test-Path $manifest) -and (Select-String -Path $manifest -Pattern 'android.permission.READ_CONTACTS' -Quiet)) {
  Write-Host "  ATENCAO: AndroidManifest pede READ_CONTACTS -> declaracao no Play Console (prazo 27/01/2027)." -ForegroundColor Yellow
}

if ($DryRun) {
  Write-Host "`n[DryRun] Plano (nada foi buildado):" -ForegroundColor Yellow
  Write-Host "  2/6 flutter analyze --no-fatal-infos --no-fatal-warnings $(if ($SkipAnalyze) { '(pulado)' })"
  Write-Host "  3/6 flutter pub get + flutter build appbundle --release --no-tree-shake-icons"
  Write-Host "  4/6 .\scripts\Validate-Aab16Kb.ps1 -AabPath $aabBuilt"
  Write-Host "  5/6 copia -> $destAab (+ WISDOMAPP_ultimo_release.aab)"
  Write-Host "  6/6 .\scripts\Conferir-Aab.ps1 (versionCode $($ver.VersionCode) + strings)"
  $keyProps = Join-Path $root "android\key.properties"
  Write-Host ("  key.properties (assinatura release): {0}" -f $(if (Test-Path $keyProps) { "presente" } else { "AUSENTE - o AAB sairia assinado com debug!" }))
  Write-Host ("  D:\TEMPORARIOS: {0}" -f $(if (Test-Path $destDir) { "existe" } else { "sera criado" }))
  exit 0
}

if (-not (Test-Path (Join-Path $root "android\key.properties"))) {
  Write-Host "ERRO: android\key.properties ausente - o AAB sairia assinado com a chave debug (Play recusa)." -ForegroundColor Red
  exit 1
}

if (-not $SkipAnalyze) {
  Write-Host "`n=== 2/6 Preflight: flutter analyze (falha so em error) ===" -ForegroundColor Cyan
  $eap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  # So o codigo do app (lib/ e test/): a raiz tem pastas de backup (ex.: «dados para copiar do controle total app») com erros que nao entram no build.
  $analyzeOut = flutter analyze lib test --no-fatal-infos --no-fatal-warnings 2>&1 | ForEach-Object { "$_" }
  $ErrorActionPreference = $eap
  $erros = @($analyzeOut | Where-Object { $_ -match '^\s*error\s' })
  if ($erros.Count -gt 0) {
    $erros | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host "ERRO: flutter analyze encontrou $($erros.Count) error(s). Corrija antes do AAB." -ForegroundColor Red
    exit 1
  }
  $resumo = $analyzeOut | Select-Object -Last 1
  Write-Host "  analyze OK (sem error). $resumo" -ForegroundColor Green
} else {
  Write-Host "`n=== 2/6 Preflight analyze (pulado: -SkipAnalyze) ===" -ForegroundColor Yellow
}

Write-Host "`n=== 3/6 Build AAB $($ver.Marketing)+$($ver.Build) (#$($ver.VersionCode)) ===" -ForegroundColor Cyan
$patch = Join-Path $root "scripts\patch_flutter_plugin_gradle.ps1"
if (Test-Path $patch) { & $patch }
flutter pub get
if ($LASTEXITCODE -ne 0) { exit 1 }
$eap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
flutter build appbundle --release --no-tree-shake-icons 2>&1 | ForEach-Object { Write-Host $_ }
$code = $LASTEXITCODE
$ErrorActionPreference = $eap
if ($code -ne 0) {
  Write-Host "ERRO: build AAB falhou ($code). 'Tag mismatch' = antivirus/proxy no HTTPS do Gradle." -ForegroundColor Red
  exit 1
}
if (-not (Test-Path $aabBuilt)) { Write-Host "ERRO: AAB nao encontrado em $aabBuilt" -ForegroundColor Red; exit 1 }

Write-Host "`n=== 4/6 Blindagem 16 KB ===" -ForegroundColor Cyan
& (Join-Path $root "scripts\Validate-Aab16Kb.ps1") -AabPath $aabBuilt

Write-Host "`n=== 5/6 Copia D:\TEMPORARIOS ===" -ForegroundColor Cyan
if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
Copy-Item $aabBuilt $destAab -Force
Copy-Item $aabBuilt (Join-Path $destDir "WISDOMAPP_ultimo_release.aab") -Force
Write-Host "  $destAab" -ForegroundColor Green

Write-Host "`n=== 6/6 Conferencia do AAB ===" -ForegroundColor Cyan
& (Join-Path $root "scripts\Conferir-Aab.ps1") -AabPath $destAab -EsperadoVersionCode $ver.VersionCode -Strings $Strings
$conf = $LASTEXITCODE
Write-Host ""
if ($conf -ne 0) {
  Write-Host "AAB gerado, mas a conferencia apontou divergencia (ver acima). NAO envie ao Play antes de entender." -ForegroundColor Red
  exit 1
}
Write-Host "AAB pronto para o Play Console (envio manual): $destAab" -ForegroundColor Green
exit 0
