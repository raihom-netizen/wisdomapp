#!/usr/bin/env bash
# Maior CFBundleVersion já enviado à App Store Connect (TestFlight / App Store).
set -euo pipefail

APP_ID="${APP_STORE_APPLE_ID:-}"
if [[ -z "$APP_ID" ]]; then
  echo "AVISO: APP_STORE_APPLE_ID vazio." >&2
  echo 0
  exit 1
fi

if [[ ! -f /tmp/_asc_ok.pem ]]; then
  ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
  if [[ -f "$ROOT/scripts/codemagic_ios_prepare_api_pem.sh" ]]; then
    bash "$ROOT/scripts/codemagic_ios_prepare_api_pem.sh" || true
  fi
fi
if [[ ! -f /tmp/_asc_ok.pem ]]; then
  echo "AVISO: /tmp/_asc_ok.pem ausente — não consultar ASC." >&2
  echo 0
  exit 1
fi

if [[ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" || -z "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" ]]; then
  echo "AVISO: credenciais App Store Connect API incompletas." >&2
  echo 0
  exit 1
fi

if ! command -v app-store-connect >/dev/null 2>&1; then
  echo "A instalar codemagic-cli-tools (app-store-connect)..." >&2
  python3 -m pip install --user -q "codemagic-cli-tools>=0.52.0"
  export PATH="$(python3 -m site --user-base)/bin:$PATH"
fi

_asc_query() {
  local subcmd="$1"
  local raw=""
  set +e
  raw="$(app-store-connect "$subcmd" "$APP_ID" \
    --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
    --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
    --private-key "@file:/tmp/_asc_ok.pem" 2>/dev/null | tr -d '\r\n' | head -n 1)"
  local ec=$?
  set -e
  if [[ $ec -ne 0 || -z "$raw" || ! "$raw" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  echo "$raw"
}

_read_floor_from_repo() {
  local ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
  bash "$ROOT/scripts/codemagic_ios_read_asc_floor.sh" 2>/dev/null || echo 0
}

LATEST=0
for attempt in 1 2 3; do
  TF=0
  AS=0
  if TF="$(_asc_query get-latest-testflight-build-number)"; then :; else TF=0; fi
  if AS="$(_asc_query get-latest-app-store-build-number)"; then :; else AS=0; fi
  if [[ "$TF" -gt "$LATEST" ]]; then LATEST="$TF"; fi
  if [[ "$AS" -gt "$LATEST" ]]; then LATEST="$AS"; fi
  if [[ "$LATEST" -gt 0 ]]; then break; fi
  if [[ "$attempt" -lt 3 ]]; then
    echo "ASC: tentativa $attempt sem resposta — retry em 3s..." >&2
    sleep 3
  fi
done

FLOOR="$(_read_floor_from_repo)"
case "$FLOOR" in
  ''|*[!0-9]*) FLOOR=0 ;;
esac

if [[ "$FLOOR" -gt "$LATEST" ]]; then
  echo "ASC: usando floor do repo ($FLOOR) > API ($LATEST)" >&2
  LATEST="$FLOOR"
fi

if [[ "$LATEST" -le 0 ]]; then
  if [[ "$FLOOR" -gt 0 ]]; then
    echo "ASC: API indisponível — fallback floor repo=$FLOOR" >&2
    echo "$FLOOR"
    exit 0
  fi
  echo "AVISO: não foi possível ler último build number na ASC (rede/API)." >&2
  echo 0
  exit 1
fi

echo "ASC: último build conhecido = $LATEST (floor_repo=$FLOOR)" >&2
echo "$LATEST"
