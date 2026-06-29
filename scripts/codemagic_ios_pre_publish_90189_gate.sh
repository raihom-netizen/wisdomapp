#!/usr/bin/env bash
# Última barreira antes do upload ASC — bloqueia 90189 Redundant Binary Upload.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"

echo "══════════════════════════════════════════════════════════════"
echo " Gate anti-90189 — validação final antes do App Store Connect"
echo " Se falhar: Start new build (workflow completo). NÃO Retry Publishing."
echo "══════════════════════════════════════════════════════════════"

bash "$ROOT/scripts/codemagic_ios_validate_ipa_before_upload.sh"

BN=""
if [[ -f /tmp/cm_ios_build_number ]]; then
  BN="$(tr -d '\r\n[:space:]' < /tmp/cm_ios_build_number)"
fi
LATEST=0
if LATEST="$(bash "$ROOT/scripts/codemagic_ios_asc_latest_build_number.sh" 2>/dev/null)"; then
  case "$LATEST" in
    ''|*[!0-9]*) LATEST=0 ;;
  esac
fi

if [[ -n "$BN" && "$LATEST" -gt 0 && "$BN" -le "$LATEST" ]]; then
  echo "ERRO: CFBundleVersion planeado ($BN) ≤ ASC ($LATEST). Abortar upload."
  echo "       (Reinicie workflow completo — o passo Versão iOS deve auto-corrigir.)"
  exit 1
fi

echo "OK: pronto para Publishing (CFBundleVersion=${BN:-?} > ASC=${LATEST:-0})."
