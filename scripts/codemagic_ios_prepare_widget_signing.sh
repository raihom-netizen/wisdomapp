#!/usr/bin/env bash
set -uo pipefail

MAIN_BUNDLE="${BUNDLE_ID:-com.wisdomapp}"
WIDGET_BUNDLE="${WIDGET_BUNDLE_ID:-com.wisdomapp.WisdomappWidget}"
APP_GROUP="${APP_GROUP_ID:-group.com.wisdomapp.widget}"
PROJECT_FILE="ios/Runner.xcodeproj/project.pbxproj"
RUNNER_ENTITLEMENTS="ios/Runner/Runner.entitlements"

fallback_without_widget() {
  echo "AVISO: App Group nao configurado pela API Apple; gerando IPA sem o Widget nesta execucao."
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" \
    "$RUNNER_ENTITLEMENTS" 2>/dev/null || true
  python3 - "$PROJECT_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
for line in (
    "\t\t\t\tWW01011CF9000F007C011A /* Embed Foundation Extensions */,\n",
    "\t\t\t\tWW01017CF9000F007C017A /* PBXTargetDependency */,\n",
):
    text = text.replace(line, "")
path.write_text(text)
PY
  if [[ -n "${CM_ENV:-}" ]]; then
    echo "WISDOMAPP_WIDGET_ENABLED=false" >> "$CM_ENV"
  fi
  exit 0
}

bundle_resource_id() {
  local identifier="$1"
  app-store-connect bundle-ids list \
    --bundle-id-identifier "$identifier" \
    --strict-match-identifier \
    --platform IOS \
    --json -s 2>/dev/null |
    python3 -c '
import json, sys
obj = json.load(sys.stdin)
data = obj.get("data", []) if isinstance(obj, dict) else obj
if data and isinstance(data[0], dict):
    print(data[0].get("id", ""))
'
}

configure_app_group() {
  local resource_id="$1"
  local capabilities capability_id settings
  settings="[{\"key\":\"APP_GROUP_IDS\",\"options\":[{\"key\":\"$APP_GROUP\",\"enabled\":true}]}]"
  capabilities="$(asc bundle-ids capabilities list --bundle "$resource_id" --output json 2>/dev/null)" || return 1
  capability_id="$(
    printf '%s' "$capabilities" | python3 -c '
import json, sys
obj = json.load(sys.stdin)
data = obj.get("data", []) if isinstance(obj, dict) else obj
for item in data or []:
    attrs = item.get("attributes", {}) if isinstance(item, dict) else {}
    capability = attrs.get("capabilityType") or item.get("capabilityType")
    if capability == "APP_GROUPS":
        print(item.get("id", ""))
        break
'
  )"
  if [[ -n "$capability_id" ]]; then
    asc bundle-ids capabilities update --id "$capability_id" --settings "$settings"
  else
    asc bundle-ids capabilities add \
      --bundle "$resource_id" \
      --capability APP_GROUPS \
      --settings "$settings"
  fi
}

main_id="$(bundle_resource_id "$MAIN_BUNDLE")"
if [[ -z "$main_id" ]]; then
  echo "ERRO: Bundle ID principal nao encontrado: $MAIN_BUNDLE"
  fallback_without_widget
fi

widget_id="$(bundle_resource_id "$WIDGET_BUNDLE")"
if [[ -z "$widget_id" ]]; then
  echo "Registrando Bundle ID do Widget: $WIDGET_BUNDLE"
  app-store-connect bundle-ids create \
    --identifier "$WIDGET_BUNDLE" \
    --name "WISDOMAPP Widget" \
    --platform IOS >/dev/null 2>&1 || true
  widget_id="$(bundle_resource_id "$WIDGET_BUNDLE")"
fi
if [[ -z "$widget_id" ]]; then
  echo "ERRO: nao foi possivel registrar o Bundle ID do Widget."
  fallback_without_widget
fi

export ASC_KEY_ID="${APP_STORE_CONNECT_KEY_IDENTIFIER:-}"
export ASC_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"
export ASC_PRIVATE_KEY="${APP_STORE_CONNECT_PRIVATE_KEY:-}"
export ASC_BYPASS_KEYCHAIN=1
export PATH="$HOME/.local/bin:$PATH"

if ! command -v asc >/dev/null 2>&1; then
  echo "Instalando asc para configurar o App Group..."
  INSTALL_DIR="$HOME/.local/bin" curl -fsSL https://asccli.sh/install | bash >/dev/null 2>&1 || fallback_without_widget
fi

if configure_app_group "$main_id" && configure_app_group "$widget_id"; then
  echo "OK: App Group $APP_GROUP associado ao app e ao Widget."
  if [[ -n "${CM_ENV:-}" ]]; then
    echo "WISDOMAPP_WIDGET_ENABLED=true" >> "$CM_ENV"
  fi
else
  fallback_without_widget
fi
