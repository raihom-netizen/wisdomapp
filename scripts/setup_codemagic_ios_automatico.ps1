# Gera chave RSA para CERTIFICATE_PRIVATE_KEY (só se ainda não existir no Team Codemagic).
# WISDOMAPP reutiliza o mesmo secret do Controle Total — normalmente NÃO precisa rodar isto.
# Uso: .\scripts\setup_codemagic_ios_automatico.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$nodeScript = Join-Path $root "scripts\generate_ios_certificate_key.js"
$keyFile = "D:\TEMPORARIOS\codemagic_ios_distribution_key.pem"

if (-not (Test-Path $nodeScript)) {
    Write-Host "Script não encontrado: $nodeScript"
    exit 1
}

New-Item -ItemType Directory -Path "D:\TEMPORARIOS" -Force | Out-Null
Set-Location $root
& node $nodeScript
if (-not (Test-Path $keyFile)) {
    Write-Host "Chave não foi gerada."
    exit 1
}
Get-Content $keyFile -Raw | Set-Clipboard
Write-Host ""
Write-Host ">>> Chave copiada (só use se o Team ainda não tiver CERTIFICATE_PRIVATE_KEY)." -ForegroundColor Green
Write-Host ">>> Codemagic Team → appstore_credentials → CERTIFICATE_PRIVATE_KEY (Secret)" -ForegroundColor Cyan
