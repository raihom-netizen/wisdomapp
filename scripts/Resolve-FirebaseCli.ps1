# Resolve caminho do Firebase CLI (npm global ou PATH).
param([string]$Root = (Split-Path $PSScriptRoot -Parent))

$candidates = @(
    (Join-Path $env:APPDATA "npm\firebase.cmd"),
    "C:\dev\gestao-yahweh-toolchain\node\firebase.cmd"
)
foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
}
$cmd = Get-Command firebase.cmd -ErrorAction SilentlyContinue
if ($cmd) { return $cmd.Source }
$cmd = Get-Command firebase -ErrorAction SilentlyContinue
if ($cmd) { return $cmd.Source }
return $null
