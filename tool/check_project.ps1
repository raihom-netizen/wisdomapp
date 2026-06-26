param(
  [switch]$SkipTests,
  [switch]$FixFormat
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

Write-Host "==> WISDOMAPP | CHECK" -ForegroundColor Cyan
Write-Host "Projeto: $projectRoot"

if ($FixFormat) {
  Write-Host "-> Rodando dart format em lib/, test/ e tool/..."
  Invoke-CheckedCommand "dart" @("format", "lib", "test", "tool")
}

Write-Host "-> flutter pub get"
Invoke-CheckedCommand "flutter" @("pub", "get")

Write-Host "-> flutter analyze"
Invoke-CheckedCommand "flutter" @("analyze")

if (-not $SkipTests) {
  Write-Host "-> flutter test"
  Invoke-CheckedCommand "flutter" @("test")
}

Write-Host "CHECK concluido com sucesso." -ForegroundColor Green
