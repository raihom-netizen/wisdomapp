#!/usr/bin/env bash
# Valida WISDOMAPP.ipa antes do upload TestFlight — evita 90189 e binário inválido.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
IPA="${1:-}"

if [[ -z "$IPA" ]]; then
  for cand in \
    "$ROOT/build/ios/ipa/WISDOMAPP.ipa" \
    "$ROOT/build/ios/ipa/"*.ipa; do
    if [[ -f "$cand" ]]; then
      IPA="$cand"
      break
    fi
  done
fi

if [[ -z "$IPA" ]] || [[ ! -f "$IPA" ]]; then
  IPA="$(find "$ROOT/build/ios" -name "*.ipa" -type f 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$IPA" ]] || [[ ! -f "$IPA" ]]; then
  echo "ERRO: nenhum .ipa para validar."
  exit 1
fi

echo "=== Validar IPA antes do upload ASC ==="
echo "IPA: $IPA"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"

APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [[ -z "$APP" ]] || [[ ! -d "$APP" ]]; then
  echo "ERRO: Payload/*.app ausente no IPA."
  exit 1
fi

PLIST="$APP/Info.plist"
if [[ ! -f "$PLIST" ]]; then
  echo "ERRO: Info.plist ausente em $APP"
  exit 1
fi

if /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" 2>/dev/null | grep -q remote-notification; then
  ENT="$(mktemp)"
  codesign -d --entitlements :- "$APP" 2>/dev/null >"$ENT" || true
  if ! grep -q 'aps-environment' "$ENT" 2>/dev/null; then
    echo ""
    echo "ERRO: UIBackgroundModes remote-notification sem aps-environment no binário assinado."
    exit 1
  fi
  echo "OK: remote-notification + aps-environment presentes."
else
  echo "OK: Info.plist sem remote-notification."
fi

if /usr/libexec/PlistBuddy -c "Print :LSApplicationQueriesSchemes" "$PLIST" &>/dev/null; then
  _idx=0
  while true; do
    _scheme="$(/usr/libexec/PlistBuddy -c "Print :LSApplicationQueriesSchemes:${_idx}" "$PLIST" 2>/dev/null)" || break
    case "$_scheme" in
      http|https)
        echo "ERRO: LSApplicationQueriesSchemes não pode incluir http/https (ITMS-90048)."
        exit 1
        ;;
    esac
    _idx=$((_idx + 1))
  done
fi
echo "OK: LSApplicationQueriesSchemes sem http/https."

ENT_FILE="$(mktemp)"
codesign -d --entitlements :- "$APP" 2>/dev/null >"$ENT_FILE" || true
REPO_ENT="$ROOT/ios/Runner/Runner.entitlements"
if [[ -f "$REPO_ENT" ]] && grep -q 'com.apple.developer.applesignin' "$REPO_ENT" 2>/dev/null; then
  if ! grep -q 'com.apple.developer.applesignin' "$ENT_FILE" 2>/dev/null; then
    echo "ERRO: Sign In with Apple pedido no repo mas ausente no IPA assinado."
    exit 1
  fi
  echo "OK: Sign In with Apple no IPA."
fi

IPA_MARKETING="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"
IPA_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || true)"
case "$IPA_BUILD" in
  ''|*[!0-9]*) IPA_BUILD="" ;;
esac

bash "$ROOT/scripts/codemagic_ios_resolve_app_store_apple_id.sh" 2>/dev/null || true

if [[ -n "$IPA_BUILD" ]]; then
  LATEST_ASC=0
  if LATEST_ASC="$(bash "$ROOT/scripts/codemagic_ios_asc_latest_build_number.sh" 2>/dev/null)"; then
    case "$LATEST_ASC" in
      ''|*[!0-9]*) LATEST_ASC=0 ;;
    esac
    BLOCK=0
    if [[ "$LATEST_ASC" -gt 0 && "$IPA_BUILD" -le "$LATEST_ASC" ]]; then
      BLOCK=1
    elif [[ "$LATEST_ASC" -le 0 ]]; then
      FLOOR_ASC=0
      if FLOOR_ASC="$(bash "$ROOT/scripts/codemagic_ios_read_asc_floor.sh" 2>/dev/null)"; then
        case "$FLOOR_ASC" in
          ''|*[!0-9]*) FLOOR_ASC=0 ;;
        esac
      fi
      if [[ "$FLOOR_ASC" -gt 0 && "$IPA_BUILD" -le "$FLOOR_ASC" ]]; then
        BLOCK=1
        LATEST_ASC="$FLOOR_ASC"
      fi
    fi
    if [[ "$BLOCK" -eq 1 ]]; then
      echo ""
      echo "ERRO 90189 (evitado): CFBundleVersion=$IPA_BUILD ($IPA_MARKETING), ASC/floor >= $LATEST_ASC."
      echo "       Start new build (workflow completo). NÃO Retry só em Publishing."
      exit 1
    fi
    EXPECTED=""
    if [[ -f /tmp/cm_ios_build_number ]]; then
      EXPECTED="$(tr -d '\r\n' < /tmp/cm_ios_build_number)"
    fi
    if [[ -n "$EXPECTED" && "$EXPECTED" != "$IPA_BUILD" ]]; then
      echo "ERRO: CFBundleVersion no IPA ($IPA_BUILD) ≠ esperado pelo CI ($EXPECTED)."
      exit 1
    fi
    echo "OK: CFBundleVersion $IPA_BUILD > ASC último $LATEST_ASC."
  else
    FLOOR_ASC=0
    if FLOOR_ASC="$(bash "$ROOT/scripts/codemagic_ios_read_asc_floor.sh" 2>/dev/null)"; then
      case "$FLOOR_ASC" in
        ''|*[!0-9]*) FLOOR_ASC=0 ;;
      esac
    fi
    if [[ "$FLOOR_ASC" -gt 0 && "$IPA_BUILD" -le "$FLOOR_ASC" ]]; then
      echo "ERRO 90189 (evitado): CFBundleVersion=$IPA_BUILD ≤ floor repo ($FLOOR_ASC)."
      exit 1
    fi
    echo "AVISO: ASC indisponível — validação 90189 só com floor."
  fi
else
  echo "AVISO: CFBundleVersion ausente no IPA."
fi

echo "=== Validação IPA concluída — seguro para upload TestFlight ==="
