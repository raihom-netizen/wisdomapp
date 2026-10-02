"""
Cliente mínimo App Store Connect API (JWT ES256) para CI Codemagic.
Localiza AuthKey_<KEY_ID>.p8 como o CLI app-store-connect (integração Codemagic).
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from typing import Any

API_BASE = "https://api.appstoreconnect.apple.com/v1"


def _normalize_pem(raw: str) -> str:
    text = raw.strip().strip('"').strip("'")
    if "\\n" in text:
        text = text.replace("\\n", "\n")
    return text


def _read_file(path: str) -> str | None:
    if not path or not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        return _normalize_pem(f.read())


def _private_key_pem() -> str:
    key_id = os.environ.get("APP_STORE_CONNECT_KEY_IDENTIFIER", "").strip()

    # Mesmas pastas que o CLI app-store-connect procura (integração Codemagic).
    if key_id:
        fname = f"AuthKey_{key_id}.p8"
        for base in (
            "private_keys",
            os.path.expanduser("~/private_keys"),
            os.path.expanduser("~/.private_keys"),
            os.path.expanduser("~/.appstoreconnect/private_keys"),
            "/Users/builder/private_keys",
            "/Users/builder/.private_keys",
            "/Users/builder/.appstoreconnect/private_keys",
        ):
            path = os.path.join(base, fname)
            content = _read_file(path)
            if content and "BEGIN PRIVATE KEY" in content:
                print(f"ASC JWT: chave .p8 em {path}")
                return content

    raw = (os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY") or "").strip()
    if raw.startswith("@file:"):
        content = _read_file(raw[6:].strip())
        if content:
            return content

    path_env = (os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH") or "").strip()
    content = _read_file(path_env)
    if content:
        return content

    if raw:
        pem = _normalize_pem(raw)
        # Ignora CERTIFICATE_PRIVATE_KEY (RSA) — não é a chave .p8 da API Apple.
        if "BEGIN RSA PRIVATE KEY" in pem:
            pem = ""
        if pem and "BEGIN PRIVATE KEY" in pem:
            return pem

    raise RuntimeError(
        "Chave .p8 App Store Connect não encontrada. "
        "Integração Codemagic (ControleTotalAPI1) ou AuthKey_<KEY_ID>.p8 em ~/.appstoreconnect/private_keys/."
    )


def make_jwt() -> str:
    try:
        import jwt  # PyJWT + cryptography (imagem Codemagic)
    except ImportError as e:
        raise RuntimeError("PyJWT/cryptography ausentes no builder.") from e

    issuer = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "").strip()
    key_id = os.environ.get("APP_STORE_CONNECT_KEY_IDENTIFIER", "").strip()
    if not issuer or not key_id:
        raise RuntimeError("APP_STORE_CONNECT_ISSUER_ID / KEY_IDENTIFIER ausentes.")

    now = int(time.time())
    headers = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, _private_key_pem(), algorithm="ES256", headers=headers)


def api_request(
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    ok_status: tuple[int, ...] = (200, 201),
) -> dict[str, Any] | None:
    url = f"{API_BASE}{path}"
    data = None
    headers = {
        "Authorization": f"Bearer {make_jwt()}",
        "Content-Type": "application/json",
    }
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            raw = resp.read().decode("utf-8")
            if not raw.strip():
                return None
            return json.loads(raw)
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"ASC API {method} {path} → HTTP {e.code}: {err_body[:1200]}") from e
