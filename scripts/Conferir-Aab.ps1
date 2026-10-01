# Confere um AAB do WISDOMAPP: versionCode/versionName reais (manifest do bundle) e, opcionalmente,
# strings que PRECISAM estar no codigo Dart compilado (libapp.so) - prova de que a melhoria entrou.
#
# Uso:
#   .\scripts\Conferir-Aab.ps1                                   -> AAB mais novo em D:\TEMPORARIOS (WISDOMAPP_*_release.aab)
#   .\scripts\Conferir-Aab.ps1 -AabPath D:\TEMPORARIOS\WISDOMAPP_10.05+27_27_release.aab
#   .\scripts\Conferir-Aab.ps1 -Strings "Enviar video rapido","Acesso rapido"
#   .\scripts\Conferir-Aab.ps1 -StringsArquivo .\scratch\strings.txt    (uma por linha, UTF-8 - use para textos com acento)
#
# Regras (aprendidas no Controle Total):
# - O snapshot AOT do Dart guarda texto em Latin-1 (1 byte/char) OU UTF-16; so UTF-8 da FALSO NEGATIVO
#   com acento. Aqui cada string e procurada em utf-8, latin-1 e utf-16-le.
# - Dois controles automaticos: uma string que TEM de existir ("WISDOMAPP") e uma que NAO pode
#   ("zzz_nao_existe_zzz"). Se os controles falharem, o metodo esta quebrado - nao confie no resultado.
# - Texto com acento: nao passe pela linha de comando do Git Bash (chega corrompido); use -StringsArquivo.
# - O versionCode real e o do manifest dentro do AAB (nao a mensagem do log do Gradle).
param(
  [string]$AabPath = "",
  [string[]]$Strings = @(),
  [string]$StringsArquivo = "",
  [int]$EsperadoVersionCode = 0
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

if (-not $AabPath) {
  $ultimo = Get-ChildItem "D:\TEMPORARIOS" -Filter "WISDOMAPP_*_release.aab" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "WISDOMAPP_ultimo_release.aab" } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $ultimo) { throw "Nenhum WISDOMAPP_*_release.aab em D:\TEMPORARIOS. Informe -AabPath." }
  $AabPath = $ultimo.FullName
}
if (-not (Test-Path $AabPath)) { throw "AAB nao encontrado: $AabPath" }
$AabPath = (Resolve-Path $AabPath).Path

if ($EsperadoVersionCode -le 0) {
  $vf = Join-Path $root "lib\constants\app_version.dart"
  if (Test-Path $vf) {
    $m = [regex]::Match([System.IO.File]::ReadAllText($vf), "static const int versionCode = (\d+);")
    if ($m.Success) { $EsperadoVersionCode = [int]$m.Groups[1].Value }
  }
}

if ($StringsArquivo) {
  $Strings += [System.IO.File]::ReadAllLines((Resolve-Path $StringsArquivo).Path, (New-Object System.Text.UTF8Encoding $false)) |
    Where-Object { $_.Trim() -ne "" }
}

$latin1 = [System.Text.Encoding]::GetEncoding(28591)
function Read-EntryBytes($zip, [string]$name) {
  $e = $zip.GetEntry($name)
  if (-not $e) { return $null }
  $s = $e.Open()
  try {
    $ms = New-Object System.IO.MemoryStream
    $s.CopyTo($ms)
    return $ms.ToArray()
  } finally { $s.Dispose() }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($AabPath)
$falhou = $false
try {
  $info = Get-Item $AabPath
  Write-Host "=== Conferencia do AAB ===" -ForegroundColor Cyan
  Write-Host ("  Arquivo : {0}" -f $info.FullName)
  Write-Host ("  Tamanho : {0:N0} bytes | {1}" -f $info.Length, $info.LastWriteTime)
  Write-Host ("  SHA-256 : {0}" -f (Get-FileHash $AabPath -Algorithm SHA256).Hash)

  # Manifest em protobuf: os atributos guardam o valor tambem como texto ASCII
  # ("versionCode" \x1a <len> "27"), entao da para ler sem bundletool.
  $mf = Read-EntryBytes $zip "base/manifest/AndroidManifest.xml"
  if (-not $mf) { throw "base/manifest/AndroidManifest.xml ausente no AAB." }
  $mfText = $latin1.GetString($mf)
  $vcM = [regex]::Match($mfText, "(?s)versionCode\x1a.(\d+)")
  $vnM = [regex]::Match($mfText, "(?s)versionName\x1a.([0-9][0-9A-Za-z.\-+]*)")
  $pkM = [regex]::Match($mfText, "(?s)package\x1a.([a-z][a-z0-9_.]+)")
  $vcAab = if ($vcM.Success) { [int]$vcM.Groups[1].Value } else { -1 }
  Write-Host ("  package     : {0}" -f $(if ($pkM.Success) { $pkM.Groups[1].Value } else { "?" }))
  Write-Host ("  versionName : {0}" -f $(if ($vnM.Success) { $vnM.Groups[1].Value } else { "?" }))
  if ($EsperadoVersionCode -gt 0 -and $vcAab -ne $EsperadoVersionCode) {
    Write-Host ("  versionCode : {0}  (ESPERADO {1} - DIVERGENTE)" -f $vcAab, $EsperadoVersionCode) -ForegroundColor Red
    $falhou = $true
  } else {
    Write-Host ("  versionCode : {0}  OK" -f $vcAab) -ForegroundColor Green
  }

  # Permissoes sensiveis para o Play (regra geral do dono: READ_CONTACTS).
  foreach ($perm in @("android.permission.READ_CONTACTS", "android.permission.WRITE_CONTACTS")) {
    if ($mfText.Contains($perm)) {
      Write-Host "  ATENCAO: o AAB pede $perm -> exige declaracao no Play Console (prazo 27/01/2027)." -ForegroundColor Yellow
    } else {
      Write-Host "  $perm : nao pede (OK)" -ForegroundColor Green
    }
  }

  $libapp = Read-EntryBytes $zip "base/lib/arm64-v8a/libapp.so"
  if (-not $libapp) {
    Write-Host "  AVISO: base/lib/arm64-v8a/libapp.so ausente - nao da para conferir strings." -ForegroundColor Yellow
  } else {
    $hay = $latin1.GetString($libapp)
    function Test-Texto([string]$t) {
      $achados = @()
      foreach ($enc in @(@{ n = "utf-8"; e = (New-Object System.Text.UTF8Encoding $false) }, @{ n = "latin-1"; e = $latin1 }, @{ n = "utf-16-le"; e = [System.Text.Encoding]::Unicode })) {
        $needle = $latin1.GetString($enc.e.GetBytes($t))
        if ($hay.IndexOf($needle, [System.StringComparison]::Ordinal) -ge 0) { $achados += $enc.n }
      }
      return , $achados
    }
    $ctrlSim = Test-Texto "WISDOMAPP"
    $ctrlNao = Test-Texto "zzz_nao_existe_zzz"
    if ($ctrlSim.Count -eq 0 -or $ctrlNao.Count -gt 0) {
      Write-Host "  ERRO: controles falharam (metodo de busca quebrado) - nao confie nas strings." -ForegroundColor Red
      $falhou = $true
    } else {
      Write-Host '  Controles OK ("WISDOMAPP" achado; "zzz_nao_existe_zzz" ausente).' -ForegroundColor Green
    }
    foreach ($t in $Strings) {
      $r = Test-Texto $t
      if ($r.Count -gt 0) {
        Write-Host ("  [OK]    {0}  ({1})" -f $t, ($r -join ", ")) -ForegroundColor Green
      } else {
        Write-Host ("  [FALTA] {0}" -f $t) -ForegroundColor Red
        $falhou = $true
      }
    }
  }
}
finally { $zip.Dispose() }

if ($falhou) { exit 1 }
exit 0
