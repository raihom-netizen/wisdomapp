# Deploy Firebase (projeto wisdomapp-b9e98).
#   -HostingOnly   -> so hosting (usado pelo deploy.ps1 -WebOnly)
#   -FunctionsOnly -> todas as functions (prefira o deploy escopado: firebase deploy --only functions:<nome>)
#   sem switch     -> hosting + firestore + storage + TODAS as functions (legado completo)
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [switch]$HostingOnly,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = "Stop"
$firebaseCmd = & (Join-Path $PSScriptRoot "Resolve-FirebaseCli.ps1") -Root $Root
if (-not $firebaseCmd) {
    throw "Firebase CLI nao encontrado. Instale: npm i -g firebase-tools"
}

$tokenFile = Join-Path $Root ".firebase-ci-token"
if (-not $env:FIREBASE_TOKEN -and (Test-Path $tokenFile)) {
    $env:FIREBASE_TOKEN = (Get-Content $tokenFile -Raw).Trim()
}

Set-Location $Root
$eap = $ErrorActionPreference
$ErrorActionPreference = "Continue"

# Projeto explicito: nunca depender do "firebase use" da maquina (o CLI pode estar apontando para o Controle Total).
$fbArgs = @("--project", "wisdomapp-b9e98")
if ($env:FIREBASE_TOKEN) { $fbArgs += @("--token", $env:FIREBASE_TOKEN) }

if ($FunctionsOnly) {
    Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS -ErrorAction SilentlyContinue
    if (-not $env:FUNCTIONS_DISCOVERY_TIMEOUT) { $env:FUNCTIONS_DISCOVERY_TIMEOUT = "90" }
    & $firebaseCmd deploy --only functions @fbArgs
    $code = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if ($code -ne 0) { throw "firebase deploy functions falhou ($code)" }
    return
}

if ($HostingOnly) {
    & $firebaseCmd deploy --only hosting @fbArgs
    $code = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if ($code -ne 0) { throw "firebase deploy hosting falhou ($code)" }
    return
}

& $firebaseCmd deploy --only "hosting,firestore,storage" @fbArgs
if ($LASTEXITCODE -ne 0) {
    $ErrorActionPreference = $eap
    throw "firebase deploy hosting/firestore/storage falhou ($LASTEXITCODE)"
}

Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS -ErrorAction SilentlyContinue
if (-not $env:FUNCTIONS_DISCOVERY_TIMEOUT) { $env:FUNCTIONS_DISCOVERY_TIMEOUT = "90" }
& $firebaseCmd deploy --only functions @fbArgs
$code = $LASTEXITCODE
$ErrorActionPreference = $eap
if ($code -ne 0) { throw "firebase deploy functions falhou ($code)" }
