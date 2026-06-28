#!/usr/bin/env bash
# Sincroniza pubspec.yaml a partir de lib/constants/app_version.dart (mesmo build web/Android/iOS).
# Uso: bash scripts/sync_app_version_from_dart.sh
#      bash scripts/sync_app_version_from_dart.sh --validate
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
cd "$ROOT"

VALIDATE_ONLY=0
if [[ "${1:-}" == "--validate" ]]; then
  VALIDATE_ONLY=1
fi

VER_FILE="$ROOT/lib/constants/app_version.dart"
PUB="$ROOT/pubspec.yaml"
GRADLE="$ROOT/android/app/build.gradle"
WEB_VJ="$ROOT/web/version.json"

CURRENT="$(grep "static const String current" "$VER_FILE" | head -1 | sed "s/.*= '\([^']*\)'.*/\1/" | tr -d ' ')"
BUILD="$(grep "static const int buildNumber" "$VER_FILE" | head -1 | sed 's/.*= \([0-9]*\).*/\1/')"
VC="$(grep "static const int versionCode" "$VER_FILE" | head -1 | sed 's/.*= \([0-9]*\).*/\1/')"

if [[ -z "$CURRENT" || -z "$BUILD" || -z "$VC" ]]; then
  echo "ERRO: AppVersion.current/buildNumber/versionCode ausente em $VER_FILE"
  exit 1
fi

if [[ "$BUILD" != "$VC" ]]; then
  echo "ERRO: buildNumber ($BUILD) != versionCode ($VC) — web/Android/iOS devem ser iguais."
  exit 1
fi

case "$CURRENT" in
  *.*.*) PUB_MARK="$CURRENT" ;;
  *.*) PUB_MARK="${CURRENT}.0" ;;
  *) PUB_MARK="${CURRENT}.0.0" ;;
esac

EXPECTED_PUB="${PUB_MARK}+${BUILD}"
TAG="${CURRENT}+${BUILD}"

_check() {
  local aligned=1
  if [[ -f "$PUB" ]]; then
    local line bn
    line="$(grep '^version:' "$PUB" | head -1 | sed 's/^version:[[:space:]]*//;s/[[:space:]]*$//')"
    bn="${line##*+}"
    if [[ "$line" != "$EXPECTED_PUB" ]]; then
      echo "DESALINHADO pubspec: $line (esperado $EXPECTED_PUB)"
      aligned=0
    fi
  fi
  if [[ -f "$GRADLE" ]]; then
    local gvc gvn
    gvc="$(grep 'versionCode' "$GRADLE" | head -1 | sed 's/.*= \([0-9]*\).*/\1/')"
    gvn="$(grep 'versionName' "$GRADLE" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')"
    if [[ "$gvc" != "$VC" || "$gvn" != "$CURRENT" ]]; then
      echo "DESALINHADO build.gradle: versionCode=$gvc versionName=$gvn (esperado $VC / $CURRENT)"
      aligned=0
    fi
  fi
  if [[ -f "$WEB_VJ" ]]; then
    if ! python3 - "$WEB_VJ" "$CURRENT" "$BUILD" "$VC" <<'PY'
import json, sys
path, cur, bn, vc = sys.argv[1:5]
with open(path, encoding="utf-8") as f:
    j = json.load(f)
ok = str(j.get("version")) == cur and int(j.get("buildNumber", -1)) == int(bn) and int(j.get("versionCode", -1)) == int(vc)
sys.exit(0 if ok else 1)
PY
    then
      echo "DESALINHADO web/version.json (esperado $TAG)"
      aligned=0
    fi
  fi
  if [[ "$aligned" -eq 1 ]]; then
    return 0
  fi
  return 1
}

if [[ "$VALIDATE_ONLY" -eq 1 ]]; then
  if _check; then
    echo "OK: versao alinhada $TAG (#$VC) — web / Android / iOS"
    exit 0
  fi
  echo "ERRO: rode sync no repo (.\scripts\sync_app_version.ps1 ou bump_build.ps1) e push antes do build."
  exit 1
fi

if _check; then
  echo "Versao ja alinhada: $TAG"
else
  sed -i.bak "s/^version: .*/version: ${EXPECTED_PUB}/" "$PUB" && rm -f "$PUB.bak"
  if [[ -f "$GRADLE" ]]; then
    sed -i.bak \
      -e "s/versionCode = [0-9]*/versionCode = ${VC}/" \
      -e "s/versionName = \"[^\"]*\"/versionName = \"${CURRENT}\"/" \
      "$GRADLE" && rm -f "$GRADLE.bak"
  fi
  if [[ -f "$WEB_VJ" ]]; then
    python3 - "$WEB_VJ" "$CURRENT" "$BUILD" "$VC" "$TAG" <<'PY'
import json, sys
path, cur, bn, vc, tag = sys.argv[1:6]
data = {
    "version": cur,
    "buildNumber": int(bn),
    "versionCode": int(vc),
    "releaseTag": tag,
    "apkDownloadUrl": "https://play.google.com/store/apps/details?id=com.wisdomapp.app",
    "testFlightUrl": "https://testflight.apple.com/join/qWpWwhnN",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
PY
  fi
  echo "OK: sincronizado $TAG (#$VC) -> pubspec + gradle + web/version.json"
fi

printf '%s' "$PUB_MARK" > /tmp/cm_ios_build_name
printf '%s' "$BUILD" > /tmp/cm_ios_build_number
