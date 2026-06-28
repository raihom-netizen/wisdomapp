#!/usr/bin/env bash
# Último CFBundleVersion conhecido já enviado à App Store Connect (evita 90189).
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
FLOOR_FILE="$ROOT/ios/asc_build_number_floor.txt"
if [[ ! -f "$FLOOR_FILE" ]]; then
  echo 0
  exit 0
fi
FLOOR="$(tr -d '\r\n[:space:]' < "$FLOOR_FILE")"
case "$FLOOR" in
  ''|*[!0-9]*) echo 0 ;;
  *) echo "$FLOOR" ;;
esac
