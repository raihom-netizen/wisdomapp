param(
  [switch]$Hosting,
  [switch]$Firestore,
  [switch]$Functions
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

Write-Host "==> WISDOMAPP | DEPLOY" -ForegroundColor Cyan
Write-Host "Projeto: $projectRoot"

$targets = @()
if ($Hosting) { $targets += "hosting" }
if ($Firestore) { $targets += "firestore:rules"; $targets += "firestore:indexes" }
if ($Functions) { $targets += "functions" }

if ($targets.Count -eq 0) {
  Write-Host "Nenhum alvo informado; usando padrao: hosting + firestore:rules + firestore:indexes"
  $targets = @("hosting", "firestore:rules", "firestore:indexes")
}

$onlyArg = $targets -join ","

Write-Host "-> firebase deploy --only $onlyArg"
Invoke-CheckedCommand "firebase" @("deploy", "--only", $onlyArg)

Write-Host "DEPLOY concluido com sucesso." -ForegroundColor Green
