#!/usr/bin/env bash
# Gera /tmp/_asc_ok.pem a partir de APP_STORE_CONNECT_PRIVATE_KEY.
set -euo pipefail

_secret_to_text_file() {
  local val="$1"
  local out="$2"
  printf '%b' "$val" \
    | tr -d '\r' \
    | perl -0777 -pe 's/^\xEF\xBB\xBF//; s/\A"(.*)"\z/$1/s; s/\A'\''(.*)'\''\z/$1/s; s/\A```[^\n]*\n//s; s/\n```\z//s' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$out"
}

_looks_like_pem_api() {
  local f="$1"
  grep -qE '^-----BEGIN (EC )?PRIVATE KEY-----$' "$f" && grep -qE '^-----END (EC )?PRIVATE KEY-----$' "$f"
}

_maybe_load_from_path_reference() {
  local raw_file="$1"
  local out_file="$2"
  local ref
  ref="$(tr -d '\n' < "$raw_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ "$ref" =~ ^AuthKey_[A-Z0-9]+\.p8$ ]] || [[ "$ref" =~ \.p8$ ]]; then
    for cand in "$ref" "$PWD/$ref" "${CM_BUILD_DIR:-$PWD}/$ref" "${CM_BUILD_DIR:-$PWD}/IOS/$ref"; do
      if [ -f "$cand" ]; then
        cp -f "$cand" "$out_file"
        return 0
      fi
    done
  fi
  return 1
}

_fail_with_help() {
  echo "ERRO: APP_STORE_CONNECT_PRIVATE_KEY nao e PEM .p8 valido nem Base64 de PEM."
  echo "Dica: no secret, cole o CONTEUDO do ficheiro AuthKey_*.p8 (incluindo BEGIN/END)."
  [ -s /tmp/_asc_b64.err ] && cat /tmp/_asc_b64.err
  exit 1
}

if [ -f /tmp/_asc_ok.pem ] && _looks_like_pem_api /tmp/_asc_ok.pem; then
  echo "OK: /tmp/_asc_ok.pem já existe."
  exit 0
fi

_norm_api() {
  _secret_to_text_file "${APP_STORE_CONNECT_PRIVATE_KEY:-}" /tmp/_asc_raw.pem
  if [ ! -s /tmp/_asc_raw.pem ]; then
    echo "AVISO: APP_STORE_CONNECT_PRIVATE_KEY ausente — integração Codemagic será usada nos comandos app-store-connect."
    return 0
  fi

  if _looks_like_pem_api /tmp/_asc_raw.pem; then
    cp -f /tmp/_asc_raw.pem /tmp/_asc_ok.pem
  elif base64 -D < /tmp/_asc_raw.pem > /tmp/_asc_dec.pem 2>/tmp/_asc_b64.err && [ -s /tmp/_asc_dec.pem ] && _looks_like_pem_api /tmp/_asc_dec.pem; then
    cp -f /tmp/_asc_dec.pem /tmp/_asc_ok.pem
  elif _maybe_load_from_path_reference /tmp/_asc_raw.pem /tmp/_asc_path.pem && _looks_like_pem_api /tmp/_asc_path.pem; then
    cp -f /tmp/_asc_path.pem /tmp/_asc_ok.pem
  else
    _fail_with_help
  fi

  unset APP_STORE_CONNECT_PRIVATE_KEY || true
}

_norm_api
if [ -f /tmp/_asc_ok.pem ] && _looks_like_pem_api /tmp/_asc_ok.pem; then
  echo "OK: /tmp/_asc_ok.pem ($(wc -c < /tmp/_asc_ok.pem | tr -d ' ') bytes)"
fi
