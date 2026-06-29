# Corrige plugins Flutter legados (Gradle 8+ / AGP 8+).
$ErrorActionPreference = "Stop"
$pubCache = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev"
$repoRoot = Split-Path $PSScriptRoot -Parent
$pluginRoots = @()
if (Test-Path $pubCache) {
  $pluginRoots += Get-ChildItem $pubCache -Directory -Filter "device_calendar-*" -ErrorAction SilentlyContinue
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
