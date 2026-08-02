# Corrige plugins Flutter legados (Gradle 8+ / AGP 8+/9+).
$ErrorActionPreference = "Stop"
$pubCache = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev"
$repoRoot = Split-Path $PSScriptRoot -Parent
$pluginRoots = @()
if (Test-Path $pubCache) {
  $pluginRoots += Get-ChildItem $pubCache -Directory -Filter "device_calendar-*" -ErrorAction SilentlyContinue
  # jni 1.0.1: bloco kotlin {} sem plugin em AGP 9+ → "Could not find method kotlin()"
  foreach ($jniDir in (Get-ChildItem $pubCache -Directory -Filter "jni-*" -ErrorAction SilentlyContinue)) {
    $jniGradle = Join-Path $jniDir.FullName "android\build.gradle"
    if (-not (Test-Path $jniGradle)) { continue }
    $jniRaw = [System.IO.File]::ReadAllText($jniGradle)
    if ($jniRaw -match '(?s)kotlin\s*\{\s*compilerOptions' -and $jniRaw -notmatch 'AGP 9\+: plugin kotlin-android') {
      $jniRaw = $jniRaw -replace '(?s)\r?\nkotlin\s*\{\s*compilerOptions\s*\{\s*jvmTarget\s*=\s*org\.jetbrains\.kotlin\.gradle\.dsl\.JvmTarget\.JVM_17\s*\}\s*\}\s*', @"

// AGP 9+: plugin kotlin-android nao e aplicado acima — bloco kotlin {} quebraria o evaluate.
if (agpMajor < 9) {
    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }
}
"@
      $utf8Jni = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($jniGradle, $jniRaw, $utf8Jni)
      Write-Host "Patch jni: $jniGradle" -ForegroundColor Green
    }
  }
}
$localPlugin = Join-Path $repoRoot "packages\device_calendar"
if (Test-Path $localPlugin) { $pluginRoots += Get-Item $localPlugin }

foreach ($dir in $pluginRoots) {
  $gradle = Join-Path $dir.FullName "android\build.gradle"
  if (-not (Test-Path $gradle)) { continue }
  $raw = [System.IO.File]::ReadAllText($gradle)
  $changed = $false

  if ($raw -match "jcenter\(\)") {
    $raw = $raw -replace "jcenter\(\)", "mavenCentral()"
    $changed = $true
  }

  if ($raw -notmatch "namespace\s") {
    $manifest = Join-Path $dir.FullName "android\src\main\AndroidManifest.xml"
    $ns = "com.builttoroam.devicecalendar"
    if (Test-Path $manifest) {
      $mx = [System.IO.File]::ReadAllText($manifest)
      if ($mx -match 'package="([^"]+)"') { $ns = $Matches[1] }
    }
    $raw = $raw -replace "android\s*\{", "android {`n    namespace = `"$ns`""
    $changed = $true
  }

  if (-not $changed) { continue }
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($gradle, $raw, $utf8)
  Write-Host "Patch: $gradle" -ForegroundColor Green
}
