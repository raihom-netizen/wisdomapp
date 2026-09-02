#!/usr/bin/env bash
# Validações rápidas antes do archive — falha cedo com mensagem clara (evita 4 min de Xcode).
# Serve a qualquer app: descobre o widget sozinho e, se o app não tiver extensão, só pula.
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
ERR=0

echo "=== Prebuild iOS (widget + deployment target) ==="

# Widget: primeira pasta ios/<Algo>Widget*/ que tenha .swift dentro.
WIDGET_DIR=""
for cand in ios/*Widget*/; do
  if compgen -G "${cand}*.swift" > /dev/null 2>&1; then WIDGET_DIR="${cand%/}"; break; fi
done

if [ -z "$WIDGET_DIR" ]; then
  echo "Sem extensão de widget neste app — nada a validar aqui."
else
  echo "Widget: $WIDGET_DIR"
  # APIs iOS 17+ proibidas nos fontes do widget — usar widgetFullBleedBackground no helper,
  # que e o unico arquivo autorizado a chamar essas APIs (ele tem o fallback para 15.5).
  FORBIDDEN_PATTERNS=(
    '\.containerBackground'
    '\.contentMargins\('
    'invalidatableContent\('
  )
  # contentMarginsDisabled() no WidgetConfiguration é permitido (iOS 17+, noop em 15.5).
  for arquivo in "$WIDGET_DIR"/*.swift; do
    [ -f "$arquivo" ] || continue
    case "$(basename "$arquivo")" in WidgetFullBleedBackground.swift) continue ;; esac
    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
      if grep -vE '^\s*//' "$arquivo" | grep -qE "$pattern"; then
        echo "ERRO: $arquivo usa API iOS 17+ ($pattern). Use widgetFullBleedBackground." >&2
        ERR=1
      fi
    done
  done
  if [ -f "$WIDGET_DIR/WidgetFullBleedBackground.swift" ]; then
    echo "WidgetFullBleedBackground.swift: helper full-bleed (iOS 17+ com fallback 15.5)."
  fi
fi

if [ -f "$PBXPROJ" ]; then
  if python3 - <<'PY' "$PBXPROJ"
import re, sys
from collections import Counter
text = open(sys.argv[1], encoding="utf-8").read()
ids = re.findall(r"^\t\t(\w{23,24}) /\*[^*]+\*/ = \{", text, re.M)
dups = [k for k, v in Counter(ids).items() if v > 1]
if dups:
    print("ERRO: IDs duplicados em project.pbxproj:", ", ".join(dups))
    sys.exit(1)
print("project.pbxproj: sem IDs duplicados.")
PY
  then
    :
  else
    ERR=1
  fi
  # Nome do target da extensão sai do próprio projeto (ex.: ControleTotalWidgetExtension).
  WIDGET_TARGET="$(grep -oE '[A-Za-z0-9_]+WidgetExtension' "$PBXPROJ" 2>/dev/null | head -1 || true)"
  if [ -n "$WIDGET_TARGET" ]; then
    if grep -A2 "$WIDGET_TARGET" "$PBXPROJ" | grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 1[0-6]\.'; then
      echo "ERRO: deployment target do Widget < 15.5 em project.pbxproj." >&2
      ERR=1
    fi
  fi
  if ! grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 15.5' "$PBXPROJ"; then
    echo "AVISO: IPHONEOS_DEPLOYMENT_TARGET 15.5 não encontrado em project.pbxproj." >&2
  fi
fi

if [ "$ERR" -ne 0 ]; then
  echo "Prebuild iOS falhou — corrija o widget antes do archive." >&2
  exit 1
fi

echo "Prebuild iOS OK."
