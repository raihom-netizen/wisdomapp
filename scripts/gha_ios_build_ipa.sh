#!/usr/bin/env bash
# Processo padrao de gerar o IPA — o mesmo nos quatro apps (Controle Total, WISDOMAPP,
# MOOVAUP, Gestao YAHWEH). Nasceu no Controle Total e virou script para nao divergir.
#
# Por que nao "flutter build ipa": o flutter monta o ExportOptions dele e o .ipa acaba
# saindo em lugares diferentes conforme o layout do repo. Aqui o archive e o export sao
# explicitos, com o ExportOptions gerado a partir dos perfis que estao no keychain.
#
# Uso:  bash scripts/gha_ios_build_ipa.sh <pasta-do-projeto-flutter>
#
# Variaveis opcionais:
#   GHA_IOS_BUILD_NAME    passa --build-name para o flutter (ex.: 49.57.0)
#   GHA_IOS_BUILD_NUMBER  passa --build-number
#   GHA_IOS_EXTRA_ARGS    argumentos extras do app (ex.: --dart-define=X=1)
#   GHA_IOS_SCHEME        scheme do Xcode (padrao: Runner)
set -euo pipefail

APP_DIR="${1:-.}"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME="${GHA_IOS_SCHEME:-Runner}"

cd "$APP_DIR"
APP_PATH="$(pwd)"
echo "=== Build iOS IPA — projeto: $APP_PATH"

bash "$SCRIPTS_DIR/codemagic_ios_prebuild_check.sh" .
python3 "$SCRIPTS_DIR/codemagic_ios_write_export_options.py" -o ios/ExportOptions.plist
python3 "$SCRIPTS_DIR/codemagic_ios_validate_export_options.py"

# O xcodebuild precisa saber onde esta o Flutter; o wrapper do Xcode le essas duas.
if [ -n "${FLUTTER_ROOT:-}" ] && [ -d "$FLUTTER_ROOT/packages/flutter_tools" ]; then
  FLUTTER_SDK="$FLUTTER_ROOT"
else
  FLUTTER_BIN="$(command -v flutter)"
  while [ -L "$FLUTTER_BIN" ]; do FLUTTER_BIN="$(readlink "$FLUTTER_BIN")"; done
  FLUTTER_SDK="$(dirname "$(dirname "$FLUTTER_BIN")")"
fi
export FLUTTER_ROOT="$FLUTTER_SDK"
export FLUTTER_APPLICATION_PATH="$APP_PATH"
echo "FLUTTER_ROOT=$FLUTTER_SDK"

# SPM desligado: o CocoaPods resolve as dependencias sem o conflito do Swift Package Manager.
export FLUTTER_SWIFT_PACKAGE_MANAGER=false

ARGS=(--release --no-codesign)
[ -n "${GHA_IOS_BUILD_NAME:-}" ] && ARGS+=(--build-name="$GHA_IOS_BUILD_NAME")
[ -n "${GHA_IOS_BUILD_NUMBER:-}" ] && ARGS+=(--build-number="$GHA_IOS_BUILD_NUMBER")
if [ -n "${GHA_IOS_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  ARGS+=(${GHA_IOS_EXTRA_ARGS})
fi

echo "=== flutter build ios ${ARGS[*]} ==="
set -o pipefail
flutter build ios "${ARGS[@]}" 2>&1 | tee /tmp/flutter_build_ios.log
FLUTTER_EXIT=${PIPESTATUS[0]}
if [ "$FLUTTER_EXIT" -ne 0 ]; then
  echo "::error::flutter build ios falhou (exit $FLUTTER_EXIT)"
  tail -100 /tmp/flutter_build_ios.log
  exit 1
fi

python3 "$SCRIPTS_DIR/codemagic_ios_strip_spm.py" ios

echo "=== xcodebuild archive ==="
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath build/ios/Runner.xcarchive \
  archive \
  FLUTTER_ROOT="$FLUTTER_SDK" \
  FLUTTER_APPLICATION_PATH="$APP_PATH" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -disableAutomaticPackageResolution \
  2>&1 | tee /tmp/xcodebuild_archive.log | tail -40
if [ ! -d build/ios/Runner.xcarchive ]; then
  echo "::error::archive nao gerado"
  tail -120 /tmp/xcodebuild_archive.log
  exit 1
fi

echo "=== xcodebuild -exportArchive ==="
xcodebuild -exportArchive \
  -archivePath build/ios/Runner.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist ios/ExportOptions.plist \
  2>&1 | tee /tmp/xcodebuild_export.log

bash "$SCRIPTS_DIR/codemagic_ios_locate_ipa.sh" .
