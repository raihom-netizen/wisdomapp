#!/usr/bin/env bash
# Resolve APP_STORE_APPLE_ID pelo bundle (com.wisdomapp) se não estiver em vars.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
BUNDLE="${BUNDLE_ID:-com.wisdomapp}"

if [[ -n "${APP_STORE_APPLE_ID:-}" ]]; then
  echo "APP_STORE_APPLE_ID já definido: $APP_STORE_APPLE_ID"
  exit 0
fi

bash "$ROOT/scripts/codemagic_ios_prepare_api_pem.sh"

if ! command -v app-store-connect >/dev/null 2>&1; then
  python3 -m pip install --user -q "codemagic-cli-tools>=0.52.0"
  export PATH="$(python3 -m site --user-base)/bin:$PATH"
fi

RAW_JSON="$(mktemp)"
trap 'rm -f "$RAW_JSON"' EXIT

set +e
app-store-connect apps list \
  --bundle-id-identifier "$BUNDLE" \
  --strict-match-identifier \
  --platform IOS \
  --issuer-id "${APP_STORE_CONNECT_ISSUER_ID}" \
  --key-id "${APP_STORE_CONNECT_KEY_IDENTIFIER}" \
  --private-key "@file:/tmp/_asc_ok.pem" \
  --json -s >"$RAW_JSON" 2>/tmp/_asc_apps.err
EC=$?
set -e

if [[ $EC -ne 0 || ! -s "$RAW_JSON" ]]; then
  echo "ERRO: não foi possível listar apps ASC para bundle $BUNDLE."
  [[ -s /tmp/_asc_apps.err ]] && cat /tmp/_asc_apps.err
  echo "Defina APP_STORE_APPLE_ID nas vars do workflow (App Store Connect → App → Informações gerais → ID Apple)."
  exit 1
fi

APP_ID="$(python3 - "$RAW_JSON" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    raw = f.read().strip()
if not raw:
    sys.exit(1)
data = json.loads(raw)
items = data.get("data", data) if isinstance(data, dict) else data
if isinstance(items, dict):
    items = [items]
for item in items or []:
    iid = str(item.get("id", "")).strip()
    if iid.isdigit():
        print(iid)
        sys.exit(0)
sys.exit(1)
PY
)" || true

if [[ -z "$APP_ID" || ! "$APP_ID" =~ ^[0-9]+$ ]]; then
  echo "ERRO: app iOS com bundle $BUNDLE não encontrado na ASC."
  echo "Crie o app em App Store Connect ou defina APP_STORE_APPLE_ID manualmente."
  exit 1
fi

export APP_STORE_APPLE_ID="$APP_ID"
echo "APP_STORE_APPLE_ID=$APP_ID (bundle $BUNDLE)"

if [[ -n "${CM_ENV:-}" ]]; then
  {
    echo "APP_STORE_APPLE_ID=$APP_ID"
  } >> "$CM_ENV"
fi
