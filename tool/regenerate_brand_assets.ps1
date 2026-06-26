$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

Write-Host "==> WISDOMAPP | Regenerar icones e banners" -ForegroundColor Cyan

python "tool/generate_brand_assets.py"
if ($LASTEXITCODE -ne 0) { throw "Falha ao gerar assets de marca." }

flutter pub run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) { throw "Falha ao gerar launcher icons." }

Write-Host "Icones e banners atualizados com sucesso." -ForegroundColor Green
