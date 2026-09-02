#!/usr/bin/env bash
# Envio padrao do IPA ao TestFlight — o mesmo nos quatro apps.
#
# O upload e a parte mais fragil do pipeline: sao ~130 MB para a Apple e uma
# queda de rede no meio derruba um build de 50 minutos. Por isso tenta ate 3x.
#
# Repetir upload tem um risco proprio: se a primeira tentativa chegou a
# registrar o build, a Apple responde 90189 ("build number ja usado"). Isso NAO
# e erro — quer dizer que o binario ja esta la. O script reconhece e sai bem.
#
# Uso:  bash scripts/gha_ios_publish_testflight.sh [pasta-do-projeto]
#
# Variaveis opcionais:
#   GHA_IOS_IPA_PATH    caminho do .ipa (padrao: descobre via codemagic_ios_locate_ipa.sh)
#   GHA_IOS_BETA_GROUP  grupo do TestFlight que recebe o build direto
set -euo pipefail

APP_DIR="${1:-.}"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$APP_DIR"

IPA_FILE="${GHA_IOS_IPA_PATH:-}"
if [ -z "$IPA_FILE" ]; then
  IPA_FILE="$(bash "$SCRIPTS_DIR/codemagic_ios_locate_ipa.sh" .)"
fi
if [ -z "$IPA_FILE" ] || [ ! -f "$IPA_FILE" ]; then
  echo "::error::nenhum .ipa encontrado para enviar"
  exit 1
fi

TAMANHO=$(wc -c < "$IPA_FILE" | tr -d ' ')
if [ "$TAMANHO" -lt 1000000 ]; then
  echo "::error::IPA com $TAMANHO bytes — pequeno demais, build invalido"
  exit 1
fi
echo "Enviando: $IPA_FILE ($(du -h "$IPA_FILE" | cut -f1))"

ARGS=(--path "$IPA_FILE" --testflight)
if [ -n "${GHA_IOS_BETA_GROUP:-}" ]; then
  ARGS+=(--beta-group "$GHA_IOS_BETA_GROUP")
  echo "Grupo TestFlight: $GHA_IOS_BETA_GROUP"
fi

LOG=/tmp/gha_ios_publish.log
for tentativa in 1 2 3; do
  echo "=== Tentativa $tentativa/3 ==="
  set +e
  app-store-connect publish "${ARGS[@]}" 2>&1 | tee "$LOG"
  CODIGO=${PIPESTATUS[0]}
  set -e

  if [ "$CODIGO" -eq 0 ]; then
    echo "IPA enviado. Acompanhe em App Store Connect > TestFlight (o processamento leva alguns minutos)."
    exit 0
  fi

  # 90189: a Apple ja tem esse build number — o binario chegou, nao ha o que repetir.
  if grep -qiE "90189|already been used|already exists|redundant binary" "$LOG"; then
    echo "A Apple respondeu que este build ja esta registrado (90189) — nada a reenviar."
    echo "Se era para ser um build novo, suba o numero de build e gere outro IPA."
    exit 0
  fi

  if [ "$tentativa" -lt 3 ]; then
    echo "Falhou (exit $CODIGO). Nova tentativa em 45s..."
    sleep 45
  fi
done

echo "::error::upload para o TestFlight falhou nas 3 tentativas"
tail -40 "$LOG"
exit 1
