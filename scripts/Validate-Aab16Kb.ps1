# Blindagem 16 KB (Play / Android 15+): toda lib .so 64-bit do AAB precisa de alinhamento LOAD >= 0x4000.
# Porte do Controle Total. Le as libs direto do zip (o AAB e um zip), sem extrair o resto.
# Uso: .\scripts\Validate-Aab16Kb.ps1 -AabPath build\app\outputs\bundle\release\app-release.aab
param(
  [Parameter(Mandatory = $true)]
  [string]$AabPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $AabPath)) { throw "AAB nao encontrado: $AabPath" }
$AabPath = (Resolve-Path $AabPath).Path

$sdkFromLocal = $null
$localProps = Join-Path (Split-Path $PSScriptRoot -Parent) "android\local.properties"
if (Test-Path $localProps) {
  $line = Get-Content $localProps | Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
  if ($line) { $sdkFromLocal = ($line -replace '^sdk\.dir=', '') -replace '\\\\', '\' -replace '\\:', ':' }
}

$ndkCandidates = @(
  $(if ($sdkFromLocal) { Join-Path $sdkFromLocal "ndk" }),
  $(if ($env:ANDROID_SDK_ROOT) { Join-Path $env:ANDROID_SDK_ROOT "ndk" }),
  $(if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME "ndk" }),
  "C:\dev\gestao-yahweh-toolchain\android-sdk\ndk",
  "$env:LOCALAPPDATA\Android\sdk\ndk"
) | Where-Object { $_ -and (Test-Path $_) }
$ndkRoot = $ndkCandidates | Select-Object -First 1
if (-not $ndkRoot) {
  Write-Warning "NDK nao encontrado. Pulando validacao 16 KB (o AAB segue gerado)."
  exit 0
}

$readelf = $null
foreach ($d in (Get-ChildItem $ndkRoot -Directory | Sort-Object Name -Descending)) {
  $candidate = Join-Path $d.FullName "toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe"
  if (Test-Path $candidate) { $readelf = $candidate; break }
}
if (-not $readelf) { throw "llvm-readelf.exe nao encontrado no NDK ($ndkRoot). Nao e possivel validar 16 KB." }

$tmpRoot = Join-Path $env:TEMP ("wisdom_aab_16kb_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($AabPath)
try {
  $violations = @()
  $checked = 0
  foreach ($entry in $zip.Entries) {
    if ($entry.FullName -notmatch '^base/lib/(arm64-v8a|x86_64)/[^/]+\.so$') { continue }
    $arch = $Matches[1]
    $out = Join-Path $tmpRoot ($arch + "_" + $entry.Name)
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $out, $true)
    $checked++
    $loadLines = & $readelf -l $out | Select-String "^\s*LOAD\s+"
    foreach ($line in $loadLines) {
      $tokens = ($line.ToString() -replace '\s+', ' ').Trim().Split(' ')
      if ($tokens.Count -lt 8) { continue }
      $alignHex = $tokens[$tokens.Count - 1]
      try { $align = [Convert]::ToInt64($alignHex, 16) } catch { continue }
      if ($align -lt 0x4000) { $violations += "$($entry.Name) [$arch] alinhamento $alignHex (< 0x4000)" }
    }
  }
  if ($violations.Count -gt 0) {
    throw ("AAB reprovado na blindagem 16 KB: " + ($violations -join "; "))
  }
  Write-Host "  Blindagem 16 KB: OK ($checked libs 64-bit com alinhamento >= 0x4000)." -ForegroundColor Green
}
finally {
  $zip.Dispose()
  Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
