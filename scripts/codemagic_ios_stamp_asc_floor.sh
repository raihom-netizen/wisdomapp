#!/usr/bin/env bash
# Grava CFBundleVersion deste build em ios/asc_build_number_floor.txt (próximo build evita 90189).
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
FLOOR_FILE="$ROOT/ios/asc_build_number_floor.txt"
mkdir -p "$(dirname "$FLOOR_FILE")"

BN=""
if [ -f /tmp/cm_ios_build_number ]; then
  BN="$(tr -d '\r\n[:space:]' < /tmp/cm_ios_build_number)"
fi

if [ -z "$BN" ] || [[ ! "$BN" =~ ^[0-9]+$ ]]; then
  echo "AVISO: /tmp/cm_ios_build_number ausente — floor não actualizado."
  exit 0
fi

CURRENT=0
if [ -f "$FLOOR_FILE" ]; then
  CURRENT="$(tr -d '\r\n[:space:]' < "$FLOOR_FILE" 2>/dev/null || echo 0)"
  case "$CURRENT" in
    ''|*[!0-9]*) CURRENT=0 ;;
  esac
fi

if [ "$BN" -gt "$CURRENT" ]; then
  printf '%s\n' "$BN" > "$FLOOR_FILE"
  echo "OK: asc_build_number_floor.txt = $BN (anterior=$CURRENT)"
else
  echo "OK: floor ($CURRENT) já >= CFBundleVersion deste build ($BN)"
fi
