# Versao unica do WISDOMAPP (padrao Controle Total).
# Fonte: lib/constants/app_version.dart (current, buildNumber, versionCode, iosBuildNumber).
#
# Uso:
#   .\scripts\sync_app_version.ps1                 -> alinha TODOS os pontos a partir do app_version.dart
#   .\scripts\sync_app_version.ps1 -Build 27       -> NOVO RELEASE: buildNumber=versionCode=27,
#                                                     iosBuildNumber = max(ios atual + 1, 27), e alinha tudo
#   .\scripts\sync_app_version.ps1 -Build 27 -Marketing 10.06   -> idem trocando a versao de marketing
#   .\scripts\sync_app_version.ps1 -Conferir       -> so CONFERE: lista cada ponto e onde sobrou numero antigo
#   .\scripts\sync_app_version.ps1 -Conferir -Antigo 25         -> procura o build 25 especificamente
#   .\scripts\sync_app_version.ps1 -ValidateOnly   -> igual -Conferir, exit 1 se algo divergir (compat)
#
# Pontos alinhados (todos com o MESMO build):
#   1. lib/constants/app_version.dart  buildNumber / versionCode / iosBuildNumber
#   2. pubspec.yaml                    version: <marketing>.0+<build>
#   3. android/app/build.gradle        versionCode / versionName (no WISDOMAPP o gradle e FIXO, nao usa flutter.versionCode)
#   4. web/index.html                  flutter_bootstrap.js?v=<build>, main.dart.js?v=<build> (se houver), swVersion = "v=<build>"
#   5. web/firebase-messaging-sw.js    const BANNER_CACHE_V = "<build>"
#   6. web/version.json                version / buildNumber / versionCode / releaseTag
# O deploy.ps1 regrava build/web/version.json a partir do mesmo app_version.dart.

# Atencao: variaveis do PowerShell nao diferenciam maiusculas. O parametro se chama $NovoBuild
# (alias -Build) para nao colidir com a variavel interna $build.
param(
  [Alias("Build")][int]$NovoBuild = 0,
  [string]$Marketing = "",
  [switch]$Conferir,
  [int]$Antigo = 0,
  [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

$paths = [ordered]@{
  dart    = Join-Path $root "lib\constants\app_version.dart"
  pubspec = Join-Path $root "pubspec.yaml"
  gradle  = Join-Path $root "android\app\build.gradle"
  index   = Join-Path $root "web\index.html"
  fcmSw   = Join-Path $root "web\firebase-messaging-sw.js"
  webVj   = Join-Path $root "web\version.json"
}
$playUrl = "https://play.google.com/store/apps/details?id=com.wisdomapp.app"
$testFlightUrl = "https://testflight.apple.com/join/qWpWwhnN"

function Read-Text([string]$Path) { return [System.IO.File]::ReadAllText($Path, $utf8NoBom) }
function Write-Text([string]$Path, [string]$Content) { [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom) }

# Regex case-sensitive (o -match/-replace do PowerShell e case-insensitive: "buildNumber" casaria dentro de "iosBuildNumber").
function Get-Group([string]$Text, [string]$Pattern, [int]$Group = 1) {
  $m = [regex]::Match($Text, $Pattern)
  if ($m.Success) { return $m.Groups[$Group].Value }
  return $null
}
function Set-Pattern([string]$Text, [string]$Pattern, [string]$Replacement) {
  # Replacement literal (sem $1 / $& interpretados).
  $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $Replacement }
  return [regex]::Replace($Text, $Pattern, $evaluator)
}

if (-not (Test-Path $paths.dart)) { Write-Error "Nao encontrado: $($paths.dart)" }

$reCurrent = "static const String current = '([^']+)';"
$reBuild   = "static const int buildNumber = (\d+);"
$reIos     = "static const int iosBuildNumber = (\d+);"
$reVc      = "static const int versionCode = (\d+);"

$dartRaw = Read-Text $paths.dart
$current = Get-Group $dartRaw $reCurrent
$build = [int](Get-Group $dartRaw $reBuild)
$iosRaw = Get-Group $dartRaw $reIos
$ios = if ($iosRaw) { [int]$iosRaw } else { $build }
$vc = [int](Get-Group $dartRaw $reVc)
if (-not $current -or $build -le 0 -or $vc -le 0) { Write-Error "app_version.dart sem current/buildNumber/versionCode no formato esperado." }

$somenteConferir = $Conferir -or $ValidateOnly

# ---------------------------------------------------------------- novo build
if ($NovoBuild -gt 0 -and -not $somenteConferir) {
  if ($NovoBuild -lt $build) { Write-Error "Build $NovoBuild menor que o atual ($build). Build so sobe." }
  $oldTag = "$current+$build (ios $ios)"
  $newIos = [Math]::Max($ios + 1, $NovoBuild)
  $newCurrent = if ($Marketing) { $Marketing } else { $current }
  $dartRaw = Set-Pattern $dartRaw $reCurrent "static const String current = '$newCurrent';"
  $dartRaw = Set-Pattern $dartRaw $reBuild "static const int buildNumber = $NovoBuild;"
  $dartRaw = Set-Pattern $dartRaw $reVc "static const int versionCode = $NovoBuild;"
  if ($iosRaw) { $dartRaw = Set-Pattern $dartRaw $reIos "static const int iosBuildNumber = $newIos;" }
  Write-Text $paths.dart $dartRaw
  if ($Antigo -le 0) { $Antigo = $build }
  $current = $newCurrent; $build = $NovoBuild; $vc = $NovoBuild; $ios = $newIos
  Write-Host "app_version.dart: $oldTag -> $current+$build (ios $ios)" -ForegroundColor Cyan
}

if ($build -ne $vc) { Write-Error "buildNumber ($build) e versionCode ($vc) devem ser iguais (web/Android/iOS alinhados)." }

$pubMarketing = if ($current -match '^\d+\.\d+\.\d+$') { $current } elseif ($current -match '^\d+\.\d+$') { "$current.0" } else { "$current.0.0" }
$releaseTag = "$current+$build"

# ---------------------------------------------------------------- leitura de cada ponto
function Get-Pontos {
  $lista = New-Object System.Collections.ArrayList
  function Add-Ponto($Arquivo, $Campo, $Atual, $Esperado) {
    $ok = ("$Atual" -eq "$Esperado")
    [void]$lista.Add([pscustomobject]@{ Arquivo = $Arquivo; Campo = $Campo; Atual = $(if ($null -eq $Atual) { "(ausente)" } else { $Atual }); Esperado = $Esperado; OK = $ok })
  }
  $d = Read-Text $paths.dart
  Add-Ponto "app_version.dart" "buildNumber" (Get-Group $d $reBuild) $build
  Add-Ponto "app_version.dart" "versionCode" (Get-Group $d $reVc) $build
  $iosAtual = Get-Group $d $reIos
  [void]$lista.Add([pscustomobject]@{ Arquivo = "app_version.dart"; Campo = "iosBuildNumber"; Atual = $iosAtual; Esperado = ">= $build"; OK = ([int]$iosAtual -ge $build) })
  if (Test-Path $paths.pubspec) {
    $p = Read-Text $paths.pubspec
    Add-Ponto "pubspec.yaml" "version" (Get-Group $p '(?m)^version:\s*(\S+)') "$pubMarketing+$build"
  }
  if (Test-Path $paths.gradle) {
    $g = Read-Text $paths.gradle
    Add-Ponto "android/app/build.gradle" "versionCode" (Get-Group $g 'versionCode\s*=\s*(\d+)') $build
    Add-Ponto "android/app/build.gradle" "versionName" (Get-Group $g 'versionName\s*=\s*"([^"]*)"') $current
  }
  if (Test-Path $paths.index) {
    $i = Read-Text $paths.index
    Add-Ponto "web/index.html" "flutter_bootstrap.js?v=" (Get-Group $i 'flutter_bootstrap\.js\?v=(\d+)') $build
    $md = Get-Group $i 'main\.dart\.js\?v=(\d+)'
    if ($md) { Add-Ponto "web/index.html" "main.dart.js?v=" $md $build }
    Add-Ponto "web/index.html" "swVersion" (Get-Group $i 'swVersion = "v=(\d+)"') $build
  }
  if (Test-Path $paths.fcmSw) {
    $s = Read-Text $paths.fcmSw
    Add-Ponto "web/firebase-messaging-sw.js" "BANNER_CACHE_V" (Get-Group $s 'const BANNER_CACHE_V = "(\d+)"') $build
  }
  if (Test-Path $paths.webVj) {
    $j = (Read-Text $paths.webVj) | ConvertFrom-Json
    Add-Ponto "web/version.json" "version" $j.version $current
    Add-Ponto "web/version.json" "buildNumber" $j.buildNumber $build
    Add-Ponto "web/version.json" "versionCode" $j.versionCode $build
    Add-Ponto "web/version.json" "releaseTag" $j.releaseTag $releaseTag
  }
  return $lista
}

function Show-Conferencia {
  $pontos = Get-Pontos
  Write-Host "`n=== Conferencia de versao: $releaseTag (#$vc) | iOS $ios ===" -ForegroundColor Cyan
  $pontos | Format-Table Arquivo, Campo, Atual, Esperado, OK -AutoSize | Out-String | Write-Host

  $floorFile = Join-Path $root "ios\asc_build_number_floor.txt"
  if (Test-Path $floorFile) {
    $floor = 0; [int]::TryParse((Read-Text $floorFile).Trim(), [ref]$floor) | Out-Null
    if ($ios -le $floor) {
      Write-Host "  AVISO iOS: iosBuildNumber $ios <= piso App Store ($floor em ios/asc_build_number_floor.txt) -> o CI sobe sozinho (anti-90189)." -ForegroundColor Yellow
    }
  }

  $procurar = if ($Antigo -gt 0) { $Antigo } else { $build - 1 }
  if ($procurar -gt 0) {
    Write-Host "Procurando o build antigo '$procurar' nos pontos de versao:" -ForegroundColor Cyan
    $achou = $false
    $re = "(?<![\d.])$procurar(?![\d.])"
    foreach ($k in $paths.Keys) {
      $f = $paths[$k]
      if (-not (Test-Path $f)) { continue }
      $n = 0
      foreach ($linha in [System.IO.File]::ReadAllLines($f, $utf8NoBom)) {
        $n++
        if ([regex]::IsMatch($linha, $re) -and [regex]::IsMatch($linha, '(?i)version|build|\?v=|swVersion|CACHE_V|releaseTag')) {
          $rel = $f.Substring($root.Length + 1)
          Write-Host ("  {0}:{1}: {2}" -f $rel, $n, $linha.Trim()) -ForegroundColor Yellow
          $achou = $true
        }
      }
    }
    if (-not $achou) { Write-Host "  Nenhum resto do build $procurar." -ForegroundColor Green }
  }

  $divergentes = @($pontos | Where-Object { -not $_.OK })
  if ($divergentes.Count -eq 0) {
    Write-Host "OK: versao alinhada $releaseTag (#$vc) em todos os pontos." -ForegroundColor Green
    return $true
  }
  Write-Host "DIVERGENTE: $($divergentes.Count) ponto(s). Rode .\scripts\sync_app_version.ps1 (ou -Build <novo>)." -ForegroundColor Red
  return $false
}

if ($somenteConferir) {
  $ok = Show-Conferencia
  if ($ok) { exit 0 } else { exit 1 }
}

# ---------------------------------------------------------------- alinhar
Write-Host "Alinhando versao $releaseTag (#$vc) | iOS $ios ..." -ForegroundColor Cyan

if (Test-Path $paths.pubspec) {
  $t = Read-Text $paths.pubspec
  $t = Set-Pattern $t '(?m)^version:[ \t]*\S+' "version: $pubMarketing+$build"
  Write-Text $paths.pubspec $t
}
if (Test-Path $paths.gradle) {
  $t = Read-Text $paths.gradle
  $t = Set-Pattern $t 'versionCode\s*=\s*\d+' "versionCode = $build"
  $t = Set-Pattern $t 'versionName\s*=\s*"[^"]*"' "versionName = `"$current`""
  Write-Text $paths.gradle $t
}
if (Test-Path $paths.index) {
  # So os marcadores de versao. Nada mais do index.html e tocado.
  $t = Read-Text $paths.index
  $novo = Set-Pattern $t 'flutter_bootstrap\.js\?v=\d+' "flutter_bootstrap.js?v=$build"
  $novo = Set-Pattern $novo 'main\.dart\.js\?v=\d+' "main.dart.js?v=$build"
  $novo = Set-Pattern $novo 'swVersion = "v=\d+"' "swVersion = `"v=$build`""
  if ($novo -ne $t) { Write-Text $paths.index $novo }
}
if (Test-Path $paths.fcmSw) {
  $t = Read-Text $paths.fcmSw
  $novo = Set-Pattern $t 'const BANNER_CACHE_V = "\d+"' "const BANNER_CACHE_V = `"$build`""
  if ($novo -ne $t) { Write-Text $paths.fcmSw $novo }
}
$json = [ordered]@{
  version = $current
  buildNumber = $build
  versionCode = $vc
  releaseTag = $releaseTag
  apkDownloadUrl = $playUrl
  testFlightUrl = $testFlightUrl
} | ConvertTo-Json -Compress
Write-Text $paths.webVj $json

$ok = Show-Conferencia
if (-not $ok) { exit 1 }
exit 0
