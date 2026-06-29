#!/usr/bin/env bash
# iOS CI: CFBundleVersion = iosBuildNumber (ou buildNumber se iguais). Web/Android ficam no buildNumber.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
cd "$ROOT"

bash "$ROOT/scripts/sync_app_version_from_dart.sh"

VER_FILE="$ROOT/lib/constants/app_version.dart"
PUB="$ROOT/pubspec.yaml"

BUILD_NAME="$(grep "static const String current" "$VER_FILE" | head -1 | sed "s/.*= '\([^']*\)'.*/\1/" | tr -d ' ')"
BN="$(grep "static const int buildNumber" "$VER_FILE" | head -1 | sed 's/.*= \([0-9]*\).*/\1/')"
IOS_BN="$(grep "static const int iosBuildNumber" "$VER_FILE" | head -1 | sed 's/.*= \([0-9]*\).*/\1/' || true)"
if [[ -z "$IOS_BN" || "$IOS_BN" == "$BN" ]]; then
  IOS_BN="$BN"
fi

case "$BUILD_NAME" in
  *.*.*) PUB_MARK="$BUILD_NAME" ;;
  *.*) PUB_MARK="${BUILD_NAME}.0" ;;
  *) PUB_MARK="${BUILD_NAME}.0.0" ;;
esac

case "$BN" in
  ''|*[!0-9]*)
    echo "ERRO: buildNumber invalido em app_version.dart"
    exit 1
    ;;
esac
case "$IOS_BN" in
  ''|*[!0-9]*)
    echo "ERRO: iosBuildNumber invalido em app_version.dart"
    exit 1
    ;;
esac

bash "$ROOT/scripts/codemagic_ios_resolve_app_store_apple_id.sh" 2>/dev/null || true

LATEST=0
FLOOR=0
if FLOOR="$(bash "$ROOT/scripts/codemagic_ios_read_asc_floor.sh" 2>/dev/null)"; then
  case "$FLOOR" in ''|*[!0-9]*) FLOOR=0 ;; esac
else
  FLOOR=0
fi

if LATEST="$(bash "$ROOT/scripts/codemagic_ios_asc_latest_build_number.sh" 2>/dev/null)"; then
  case "$LATEST" in ''|*[!0-9]*) LATEST=0 ;; esac
else
  LATEST=0
fi

BLOCK="$LATEST"
if [[ "$FLOOR" -gt "$BLOCK" && "$LATEST" -le 0 ]]; then
  BLOCK="$FLOOR"
fi

if [[ "$BLOCK" -gt 0 && "$IOS_BN" -le "$BLOCK" ]]; then
  OLD="$IOS_BN"
  IOS_BN=$(( BLOCK + 1 ))
  echo ""
  echo "AVISO 90189 (auto-correção): iosBuildNumber $OLD <= ASC/floor $BLOCK."
  echo "       CFBundleVersion ajustado automaticamente para $IOS_BN (web/Android=$BN)."
  echo ""
  if grep -q "iosBuildNumber" "$VER_FILE"; then
    sed -i.bak "s/iosBuildNumber = [0-9]*/iosBuildNumber = $IOS_BN/" "$VER_FILE" && rm -f "$VER_FILE.bak"
  fi
fi

# pubspec permanece com buildNumber (web/Android); IPA usa --build-number abaixo.
if ! grep -q "+${BN}" "$PUB"; then
  echo "ERRO: pubspec deve manter +${BN} (web/Android); encontrado:"
  grep "^version:" "$PUB" || true
  exit 1
fi

printf '%s' "$PUB_MARK" > /tmp/cm_ios_build_name
printf '%s' "$IOS_BN" > /tmp/cm_ios_build_number

echo "OK: CFBundleVersion iOS=$IOS_BN (marketing $BUILD_NAME) | web/Android build=$BN"
echo "    ASC ultimo=$LATEST floor=$FLOOR"
grep "^version:" "$PUB"
