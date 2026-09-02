#!/usr/bin/env bash
# Localiza .ipa após flutter build ipa e normaliza em build/ios/ipa/ (working dir = flutter_app).
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

mkdir -p build/ios/ipa

summarize_build_ios() {
  echo "--- build/ios (resumo) ---" >&2
  ls -la build/ios 2>/dev/null || true
  echo "Arquivos .ipa:" >&2
  find build/ios -name "*.ipa" -type f 2>/dev/null || true
  echo "Archives .xcarchive:" >&2
  find build/ios -name "*.xcarchive" -type d 2>/dev/null || true
  echo "ExportOptions.plist:" >&2
  find build/ios -name "ExportOptions.plist" -type f 2>/dev/null || true
}

try_export_from_archive() {
  local archive export_plist
  archive="$(find build/ios/archive -name "*.xcarchive" -type d 2>/dev/null | head -1 || true)"
  if [ -z "$archive" ]; then
    return 1
  fi
  export_plist="ios/ExportOptions.plist"
  if [ ! -f "$export_plist" ]; then
    export_plist="$(find build/ios -name "ExportOptions.plist" -type f 2>/dev/null | head -1 || true)"
  fi
  if [ -z "$export_plist" ] || [ ! -f "$export_plist" ]; then
    echo "AVISO: archive existe mas ExportOptions.plist não — export manual indisponível." >&2
    return 1
  fi
  echo "Tentando exportar IPA de: $archive (plist: $export_plist)" >&2
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath build/ios/ipa \
    -exportOptionsPlist "$export_plist" \
    -allowProvisioningUpdates 2>&1 || return 1
  return 0
}

find_ipa() {
  find build/ios -name "*.ipa" -type f 2>/dev/null | head -1
}

IPA="$(find_ipa || true)"

if [ -z "$IPA" ]; then
  IPA="$(find build -name "*.ipa" -type f 2>/dev/null | head -1 || true)"
fi

if [ -z "$IPA" ]; then
  IPA="$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "*.ipa" -type f 2>/dev/null | head -1 || true)"
fi

if [ -z "$IPA" ]; then
  try_export_from_archive || true
  IPA="$(find_ipa || true)"
fi

if [ -z "$IPA" ]; then
  echo "ERRO: nenhum .ipa encontrado após o build." >&2
  summarize_build_ios
  if [ -f /tmp/flutter_ipa_build.log ]; then
    echo "--- últimos erros flutter build ipa ---" >&2
    grep -E "error:|Error:|failed|FAILED|Encountered error" /tmp/flutter_ipa_build.log 2>/dev/null | tail -30 >&2 \
      || tail -40 /tmp/flutter_ipa_build.log >&2
  fi
  exit 1
fi

DEST="build/ios/ipa/$(basename "$IPA")"
if [ "$IPA" != "$DEST" ]; then
  cp -f "$IPA" "$DEST"
fi

echo "$DEST"
