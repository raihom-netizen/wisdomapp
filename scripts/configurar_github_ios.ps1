# Configura os secrets do build iOS no GitHub Actions.
# Depois disso basta: Actions > "iOS TestFlight (Flutter)" > Run workflow.
#
# Uso:  .\scripts\configurar_github_ios.ps1
#       .\scripts\configurar_github_ios.ps1 -KeyId 4UMWWALR3U    # escolher a chave .p8
#       .\scripts\configurar_github_ios.ps1 -DispararBuild       # ja dispara o build no fim
#
# Os valores sao lidos do disco e enviados direto ao GitHub pelo "gh secret set";
# nada e impresso na tela nem gravado em log.
#
# A conta Apple e a mesma do Controle Total (Issuer 77a1debb-...), entao as chaves
# em C:\Controletotalapp_Independente\ios_keys servem aqui — inclusive a chave RSA,
# que deve ser a MESMA em todos os apps para nao estourar o limite de 3 certificados
# Apple Distribution da conta.

[CmdletBinding()]
param(
    [string]$Repo = "raihom-netizen/wisdomapp",
    [string]$KeyId,
    [string]$IssuerId,
    [string]$ChavesCompartilhadas = "C:\Controletotalapp_Independente\ios_keys",
    [switch]$DispararBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$iosKeys = Join-Path $root "ios_keys"

function Escrever($msg, $cor = "White") { Write-Host $msg -ForegroundColor $cor }

Escrever "`n=== Configurar build iOS no GitHub Actions ===" Cyan
Escrever "Repositorio: $Repo`n"

# --- 1. GitHub CLI ---------------------------------------------------------
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Escrever "GitHub CLI (gh) nao encontrado. Instalando via winget..." Yellow
    winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Escrever "Instalei o gh mas ele ainda nao esta no PATH desta janela." Red
        Escrever "Feche e abra o PowerShell e rode este script de novo." Yellow
        exit 1
    }
}
Escrever "GitHub CLI: OK" Green

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Escrever "`nVoce ainda nao esta logado no gh. Abrindo o login (escolha GitHub.com > HTTPS > browser)..." Yellow
    gh auth login
    if ($LASTEXITCODE -ne 0) { Escrever "Login nao concluido." Red; exit 1 }
}
Escrever "Login GitHub: OK" Green

# --- 2. Chave .p8 da App Store Connect API ---------------------------------
# Procura no projeto e, se nao achar, nas chaves compartilhadas do Controle Total.
$pastasP8 = @($iosKeys, (Join-Path $root "ios"), (Join-Path $root "IOS"), (Join-Path $root "keys"), $root, $ChavesCompartilhadas) |
    Where-Object { $_ -and (Test-Path $_) }

$p8Files = @()
foreach ($pasta in $pastasP8) {
    $p8Files += Get-ChildItem $pasta -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^(AuthKey|ApiKey)_[A-Z0-9]+\.p8$" }
}
$p8Files = $p8Files | Sort-Object LastWriteTime -Descending

if ($p8Files.Count -eq 0) {
    Escrever "`nNenhum AuthKey_*.p8 encontrado em:" Red
    $pastasP8 | ForEach-Object { Escrever "  $_" Gray }
    Escrever "Baixe em App Store Connect > Users and Access > Integrations > App Store Connect API" Yellow
    Escrever "e salve o arquivo AuthKey_XXXX.p8 em ios_keys\ (a chave precisa de papel Admin ou App Manager)." Yellow
    exit 1
}

if ($KeyId) {
    $p8 = $p8Files | Where-Object { $_.Name -match [regex]::Escape($KeyId) } | Select-Object -First 1
    if (-not $p8) { Escrever "Nao achei .p8 da chave $KeyId." Red; exit 1 }
} elseif ($p8Files.Count -eq 1) {
    $p8 = $p8Files[0]
} else {
    Escrever "`nMais de uma chave .p8 encontrada:" Cyan
    for ($i = 0; $i -lt $p8Files.Count; $i++) {
        $kid = $p8Files[$i].Name -replace "^(AuthKey|ApiKey)_", "" -replace "\.p8$", ""
        Escrever ("  [{0}] {1}   (Key ID {2}, {3})" -f $i, $p8Files[$i].FullName, $kid, $p8Files[$i].LastWriteTime.ToString("dd/MM/yyyy"))
    }
    $escolha = Read-Host "Qual usar? (numero, Enter = 0)"
    if ([string]::IsNullOrWhiteSpace($escolha)) { $escolha = "0" }
    $p8 = $p8Files[[int]$escolha]
}

$keyIdFinal = $p8.Name -replace "^(AuthKey|ApiKey)_", "" -replace "\.p8$", ""
Escrever "`nChave da API: $($p8.FullName)  (Key ID $keyIdFinal)" Green

# A chave precisa de papel Admin ou App Manager para criar certificado/perfil.
$codemagicYaml = Join-Path $root "codemagic.yaml"
if (Test-Path $codemagicYaml) {
    $m = Select-String -Path $codemagicYaml -Pattern 'APP_STORE_CONNECT_KEY_IDENTIFIER:\s*"?([A-Z0-9]+)"?' | Select-Object -First 1
    if ($m) {
        $keyNoCodemagic = $m.Matches.Groups[1].Value
        if ($keyNoCodemagic -ne $keyIdFinal) {
            Escrever "AVISO: o Codemagic usava a chave $keyNoCodemagic e voce vai usar $keyIdFinal." Yellow
            Escrever "       Tudo bem, desde que $keyIdFinal tenha papel Admin ou App Manager na App Store Connect." Yellow
        }
    }
}

# --- 3. Issuer ID ----------------------------------------------------------
if (-not $IssuerId) {
    foreach ($f in @((Join-Path $iosKeys "issuer_id.txt"), (Join-Path $ChavesCompartilhadas "issuer_id.txt"))) {
        if (Test-Path $f) { $IssuerId = (Get-Content $f -Raw).Trim(); break }
    }
}
if (-not $IssuerId -and (Test-Path $codemagicYaml)) {
    $m = Select-String -Path $codemagicYaml -Pattern 'APP_STORE_CONNECT_ISSUER_ID:\s*"?([0-9a-fA-F-]{36})"?' | Select-Object -First 1
    if ($m) { $IssuerId = $m.Matches.Groups[1].Value }
}
if (-not $IssuerId) {
    $IssuerId = Read-Host "Issuer ID (App Store Connect > Integrations > App Store Connect API)"
}
if ($IssuerId -notmatch '^[0-9a-fA-F-]{36}$') {
    Escrever "AVISO: '$IssuerId' nao parece um Issuer ID (UUID de 36 caracteres)." Yellow
    $ok = Read-Host "Continuar assim mesmo? (s/N)"
    if ($ok -ne "s") { exit 1 }
}
Escrever "Issuer ID: $IssuerId" Green

# --- 4. Chave RSA do certificado (CERTIFICATE_PRIVATE_KEY) -----------------
# O CI usa essa chave para buscar ou CRIAR o certificado Apple Distribution.
# Usar a MESMA chave em todos os apps da conta evita estourar o limite de 3
# certificados de distribuicao da Apple.
$rsaPath = Join-Path $iosKeys "ios_distribution_private_key.pem"
$rsaCompartilhada = Join-Path $ChavesCompartilhadas "ios_distribution_private_key.pem"

if (-not (Test-Path $rsaPath) -and (Test-Path $rsaCompartilhada)) {
    Escrever "`nUsando a chave RSA compartilhada da conta Apple:" Green
    Escrever "  $rsaCompartilhada" Gray
    Escrever "  (mesmo certificado Apple Distribution dos outros apps — e o que evita o limite de 3)" Gray
    $rsaPath = $rsaCompartilhada
} elseif (-not (Test-Path $rsaPath)) {
    Escrever "`nChave RSA do certificado nao existe ainda. Gerando..." Yellow
    if (-not (Test-Path $iosKeys)) { New-Item -ItemType Directory $iosKeys | Out-Null }
    $sshKeygen = Get-Command ssh-keygen -ErrorAction SilentlyContinue
    $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    if ($sshKeygen) {
        $tmp = Join-Path $iosKeys "ios_distribution_private_key"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        if (Test-Path "$tmp.pub") { Remove-Item "$tmp.pub" -Force }
        & ssh-keygen -t rsa -b 2048 -m PEM -f $tmp -q -N '""' | Out-Null
        if (-not (Test-Path $tmp)) { & ssh-keygen -t rsa -b 2048 -m PEM -f $tmp -q -N "" | Out-Null }
        if (Test-Path $tmp) { Move-Item $tmp $rsaPath -Force }
        if (Test-Path "$tmp.pub") { Remove-Item "$tmp.pub" -Force }
    } elseif ($openssl) {
        & openssl genrsa -out $rsaPath 2048 2>$null
    }
    if (-not (Test-Path $rsaPath)) {
        Escrever "Nao consegui gerar a chave RSA (precisa de ssh-keygen ou openssl no PATH)." Red
        Escrever "Gere manualmente e salve em: $rsaPath" Yellow
        exit 1
    }
    Escrever "Chave RSA gerada: $rsaPath" Green
    Escrever "GUARDE esse arquivo — e ele que amarra o certificado Apple da conta." Yellow
} else {
    Escrever "`nChave RSA do certificado: reaproveitando $rsaPath" Green
}

# --- 5. Enviar os secrets --------------------------------------------------
Escrever "`n=== Gravando os secrets em $Repo ===" Cyan

function DefinirSecret($nome, $valorArquivo) {
    # PowerShell nao tem redirecionamento de entrada com '<' — o valor vai pelo pipe.
    Get-Content -Raw $valorArquivo | gh secret set $nome --repo $Repo
    if ($LASTEXITCODE -ne 0) { throw "Falha ao gravar o secret $nome" }
    Escrever "  $nome  OK" Green
}
function DefinirSecretTexto($nome, $valor) {
    $valor | gh secret set $nome --repo $Repo
    if ($LASTEXITCODE -ne 0) { throw "Falha ao gravar o secret $nome" }
    Escrever "  $nome  OK" Green
}

DefinirSecret "APP_STORE_CONNECT_PRIVATE_KEY" $p8.FullName
DefinirSecret "CERTIFICATE_PRIVATE_KEY" $rsaPath
DefinirSecretTexto "APP_STORE_CONNECT_KEY_IDENTIFIER" $keyIdFinal
DefinirSecretTexto "APP_STORE_CONNECT_ISSUER_ID" $IssuerId

# Opcional: service account do Firebase, para publicar o .ipa no site.
$firebaseCandidatos = @(
    (Join-Path $root "firebase-service-account.json"),
    (Join-Path $root "scripts\firebase-service-account.json"),
    (Join-Path $root "wisdomapp-service-account.json")
) | Where-Object { Test-Path $_ }

if ($firebaseCandidatos.Count -gt 0) {
    DefinirSecret "FIREBASE_SERVICE_ACCOUNT_JSON" $firebaseCandidatos[0]
    Escrever "  (IPA tambem sera publicado no site de divulgacao)" Gray
} else {
    Escrever "  FIREBASE_SERVICE_ACCOUNT_JSON  nao configurado (opcional)" Gray
    Escrever "  Sem ele o build ainda gera o IPA e envia ao TestFlight; so nao atualiza o link do site." Gray
}

# --- 6. Pronto -------------------------------------------------------------
Escrever "`n=== Tudo configurado ===" Cyan
Escrever "Agora e so:" White
Escrever "  https://github.com/$Repo/actions/workflows/ios_testflight.yml" Cyan
Escrever "  > Run workflow" White
Escrever "`nNo primeiro build deixe 'Ativar capabilities' marcado." Yellow
Escrever "Nos proximos, desmarque: economiza alguns minutos de espera por build." Yellow

if ($DispararBuild) {
    $branch = git -C $root rev-parse --abbrev-ref HEAD
    Escrever "`nDisparando o build na branch $branch..." Cyan
    gh workflow run ios_testflight.yml --repo $Repo --ref $branch
    if ($LASTEXITCODE -eq 0) {
        Escrever "Build disparado. Acompanhe em:" Green
        Escrever "  https://github.com/$Repo/actions" Cyan
    }
}
