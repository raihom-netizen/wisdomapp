#!/usr/bin/env bash
# Resolve APP_STORE_APPLE_ID pelo bundle (com.wisdomapp) se não estiver em vars.
# Usa integração Codemagic (app_store_connect) — mesmo auth de fetch-signing-files.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
BUNDLE="${BUNDLE_ID:-com.wisdomapp}"

_export_id() {
  local id="$1"
  export APP_STORE_APPLE_ID="$id"
  echo "APP_STORE_APPLE_ID=$id (bundle $BUNDLE)"
  if [[ -n "${CM_ENV:-}" ]]; then
    echo "APP_STORE_APPLE_ID=$id" >> "$CM_ENV"
  fi
}

if [[ -n "${APP_STORE_APPLE_ID:-}" ]]; then
  echo "APP_STORE_APPLE_ID já definido: $APP_STORE_APPLE_ID"
  exit 0
fi

CACHE_FILE="$ROOT/ios/app_store_apple_id.txt"
if [[ -f "$CACHE_FILE" ]]; then
  CACHED="$(tr -d '\r\n[:space:]' < "$CACHE_FILE")"
  if [[ "$CACHED" =~ ^[0-9]+$ ]]; then
    _export_id "$CACHED"
    exit 0
  fi
fi

if ! command -v app-store-connect >/dev/null 2>&1; then
  python3 -m pip install --user -q "codemagic-cli-tools>=0.52.0"
  export PATH="$(python3 -m site --user-base)/bin:$PATH"
fi

RAW_JSON="$(mktemp)"
trap 'rm -f "$RAW_JSON"' EXIT

_run_apps_list() {
  app-store-connect apps list \
    --bundle-id-identifier "$BUNDLE" \
    --strict-match-identifier \
    --platform IOS \
    --json -s >"$RAW_JSON" 2>/tmp/_asc_apps.err
}

set +e
_run_apps_list
EC=$?
set -e

if [[ $EC -ne 0 || ! -s "$RAW_JSON" ]]; then
  if [[ -f "$ROOT/scripts/codemagic_ios_prepare_api_pem.sh" ]] \
    && bash "$ROOT/scripts/codemagic_ios_prepare_api_pem.sh" 2>/dev/null; then
    set +e
    app-store-connect apps list \
      --bundle-id-identifier "$BUNDLE" \
      --strict-match-identifier \
      --platform IOS \
      --issuer-id "${APP_STORE_CONNECT_ISSUER_ID:-}" \
      --key-id "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" \
      --private-key "@file:/tmp/_asc_ok.pem" \
      --json -s >"$RAW_JSON" 2>/tmp/_asc_apps.err
    EC=$?
    set -e
  fi
fi

if [[ $EC -ne 0 || ! -s "$RAW_JSON" ]]; then
  echo "AVISO: não foi possível resolver APP_STORE_APPLE_ID via API (floor/90189 ainda funcionam)."
  [[ -s /tmp/_asc_apps.err ]] && cat /tmp/_asc_apps.err
  exit 0
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
  echo "AVISO: app iOS com bundle $BUNDLE não encontrado na ASC."
  exit 0
fi

_export_id "$APP_ID"
