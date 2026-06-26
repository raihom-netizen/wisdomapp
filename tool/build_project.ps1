param(
  [ValidateSet("web", "apk", "appbundle", "ios", "all")]
  [string]$Target = "web"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

function Invoke-CheckedCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Command,
    [Parameter(Mandatory = $false)]
    [string[]]$Arguments = @()
  )
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Falha ao executar: $Command $($Arguments -join ' ') (exit_code=$LASTEXITCODE)"
  }
}

Write-Host "==> WISDOMAPP | BUILD ($Target)" -ForegroundColor Cyan
Write-Host "Projeto: $projectRoot"

Write-Host "-> flutter pub get"
Invoke-CheckedCommand "flutter" @("pub", "get")

switch ($Target) {
  "web" {
    Write-Host "-> flutter build web --release"
    Invoke-CheckedCommand "flutter" @("build", "web", "--release")
  }
  "apk" {
    Write-Host "-> flutter build apk --release"
    Invoke-CheckedCommand "flutter" @("build", "apk", "--release")
  }
  "appbundle" {
    Write-Host "-> flutter build appbundle --release"
    Invoke-CheckedCommand "flutter" @("build", "appbundle", "--release")
  }
  "ios" {
    Write-Host "-> flutter build ios --release"
    Invoke-CheckedCommand "flutter" @("build", "ios", "--release")
  }
  "all" {
    Write-Host "-> flutter build web --release"
    Invoke-CheckedCommand "flutter" @("build", "web", "--release")
    Write-Host "-> flutter build appbundle --release"
    Invoke-CheckedCommand "flutter" @("build", "appbundle", "--release")
  }
}

Write-Host "BUILD concluido com sucesso." -ForegroundColor Green
