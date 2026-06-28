#!/usr/bin/env bash
# iOS CI: usa o MESMO buildNumber do repo (web/Android/iOS alinhados).
# Bloqueia 90189 se buildNumber <= último upload ASC — exige bump_build.ps1 + push antes.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
cd "$ROOT"

bash "$ROOT/scripts/sync_app_version_from_dart.sh"

VER_FILE="$ROOT/lib/constants/app_version.dart"
PUB="$ROOT/pubspec.yaml"

BUILD_NAME="$(grep "static const String current" "$VER_FILE" | head -1 | sed "s/.*= '\([^']*\)'.*/\1/" | tr -d ' ')"
BN="$(grep "static const int buildNumber" "$VER_FILE" | head -1 | sed 's/.*= \([0-9]*\).*/\1/')"

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
if [[ "$FLOOR" -gt "$BLOCK" ]]; then BLOCK="$FLOOR"; fi

if [[ "$BLOCK" -gt 0 && "$BN" -le "$BLOCK" ]]; then
  NEED=$(( BLOCK + 1 ))
  echo ""
  echo "ERRO 90189 (evitado): buildNumber no repo = $BN, mas App Store Connect/floor = $BLOCK."
  echo "       CFBundleVersion precisa ser >= $NEED."
  echo ""
  echo "       Web, Android e iOS usam o MESMO numero — alinhe antes do build:"
  echo "         .\\scripts\\bump_build.ps1"
  echo "         git add lib/constants/app_version.dart pubspec.yaml android/app/build.gradle web/version.json"
  echo "         git commit && git push"
  echo "       Depois: Start new build (nao Retry so em Publishing)."
  echo ""
  exit 1
fi

sed -i.bak "s/^version: .*/version: ${PUB_MARK}+${BN}/" "$PUB" && rm -f "$PUB.bak"
if ! grep -q "+${BN}" "$PUB"; then
  echo "ERRO: build +${BN} nao aplicado em pubspec.yaml"
  exit 1
fi

printf '%s' "$PUB_MARK" > /tmp/cm_ios_build_name
printf '%s' "$BN" > /tmp/cm_ios_build_number

echo "OK: CFBundleVersion=$BN (marketing $BUILD_NAME) — alinhado web/Android/iOS"
echo "    ASC ultimo=$LATEST floor=$FLOOR"
grep "^version:" "$PUB"
