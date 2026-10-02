"""
Ativa "Time Sensitive Notifications" no App ID (App Store Connect API).

Sem essa capability no App ID, o perfil App Store gerado pelo fetch-signing-files
nao inclui com.apple.developer.usernotifications.time-sensitive e o archive falha:
  "Provisioning profile ... doesn't include the Time Sensitive Notifications capability".

Ordem de tentativa:
  1. REST /bundleIdCapabilities (capabilityType USERNOTIFICATIONS_TIMESENSITIVE);
  2. CLI app-store-connect bundle-ids enable-capabilities (nomes alternativos).

Se nada funcionar (API key sem permissao, capability indisponivel na conta), o
script REMOVE a chave time-sensitive do Runner.entitlements para o build seguir —
o push continua chegando, so perde a prioridade "time sensitive". Para falhar o
build em vez de remover, exporte IOS_TIME_SENSITIVE_STRICT=1.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from codemagic_asc_api import api_request  # noqa: E402

BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.wisdomapp")
ENTITLEMENTS = Path(
    os.environ.get(
        "IOS_ENTITLEMENTS_PATH",
        str(
            Path(__file__).resolve().parent.parent
            / "ios"
            / "Runner"
            / "Runner.entitlements"
        ),
    )
)
ENTITLEMENT_KEY = "com.apple.developer.usernotifications.time-sensitive"
CAP_TYPE = "USERNOTIFICATIONS_TIMESENSITIVE"
CLI_CANDIDATES = (
    "USERNOTIFICATIONS_TIMESENSITIVE",
    "Time Sensitive Notifications",
    "TIME_SENSITIVE_NOTIFICATIONS",
)
STRICT = os.environ.get("IOS_TIME_SENSITIVE_STRICT", "").strip() in ("1", "true", "yes")


def _run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True)


def _bundle_resource_id() -> str | None:
    # REST primeiro (mesma chave .p8 dos outros passos).
    try:
        listed = api_request(
            "GET",
            f"/bundleIds?filter[identifier]={BUNDLE_ID}&filter[platform]=IOS&limit=10",
        )
        for item in (listed or {}).get("data") or []:
            attrs = item.get("attributes") or {}
            if attrs.get("identifier") == BUNDLE_ID:
                print("Bundle ID", BUNDLE_ID, "-> resource id", item.get("id"), "(REST)")
                return item.get("id")
    except RuntimeError as e:
        print("AVISO GET /bundleIds:", str(e)[:400])

    r = _run(
        [
            "app-store-connect", "bundle-ids", "list",
            "--bundle-id-identifier", BUNDLE_ID,
            "--strict-match-identifier",
            "--platform", "IOS",
            "--json", "-s",
        ]
    )
    if r.returncode != 0:
        print("ERRO bundle-ids list:", (r.stderr or r.stdout)[:600])
        return None
    try:
        j = json.loads((r.stdout or "").strip() or "null")
    except json.JSONDecodeError as e:
        print("ERRO JSON bundle-ids list:", e)
        return None
    data = j.get("data") if isinstance(j, dict) else (j if isinstance(j, list) else [])
    if not data or not isinstance(data[0], dict):
        print("ERRO: Bundle ID nao encontrado:", BUNDLE_ID)
        return None
    print("Bundle ID", BUNDLE_ID, "-> resource id", data[0].get("id"), "(CLI)")
    return data[0].get("id")


def _capability_blob(rid: str) -> str:
    try:
        caps = api_request("GET", f"/bundleIds/{rid}/bundleIdCapabilities?limit=200")
        if caps:
            return json.dumps(caps)
    except RuntimeError as e:
        print("AVISO GET bundleIdCapabilities:", str(e)[:400])
    r = _run(["app-store-connect", "bundle-ids", "capabilities", rid, "--json", "-s"])
    return (r.stdout or "") if r.returncode == 0 else ""


def _has_time_sensitive(blob: str) -> bool:
    return bool(
        re.search(
            r"USERNOTIFICATIONS[_\s-]?TIMESENSITIVE|TIME[_\s-]?SENSITIVE",
            blob or "",
            re.I,
        )
    )


def _enable_via_rest(rid: str) -> bool:
    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": CAP_TYPE},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": rid}}},
        }
    }
    try:
        api_request("POST", "/bundleIdCapabilities", body=body, ok_status=(200, 201))
        print("REST: capability", CAP_TYPE, "ativada no App ID.")
        return True
    except RuntimeError as e:
        low = str(e).lower()
        if any(x in low for x in ("already", "duplicate", "409", "exists", "conflict")):
            print("REST: capability ja estava ativa.")
            return True
        print("AVISO POST bundleIdCapabilities:", str(e)[:600])
        return False


def _enable_via_cli(rid: str) -> bool:
    for cap in CLI_CANDIDATES:
        ec = _run(
            ["app-store-connect", "bundle-ids", "enable-capabilities", rid, "--capability", cap]
        )
        out = ((ec.stderr or "") + (ec.stdout or "")).strip()
        low = out.lower()
        if ec.returncode == 0 or any(
            b in low
            for b in ("already", "duplicate", "exist", "409", "conflict", "not modified", "unchanged")
        ):
            print(f"CLI: Time Sensitive OK com '{cap}'.")
            return True
        print(f"Tentativa CLI '{cap}' falhou: {out[:300]}")
    return False


def _strip_entitlement() -> bool:
    if not ENTITLEMENTS.is_file():
        print("AVISO: entitlements nao encontrado em", ENTITLEMENTS)
        return False
    text = ENTITLEMENTS.read_text(encoding="utf-8")
    if ENTITLEMENT_KEY not in text:
        print("Entitlement time-sensitive ja ausente - nada a remover.")
        return True
    novo = re.sub(
        r"[ \t]*<key>" + re.escape(ENTITLEMENT_KEY) + r"</key>\s*<(true|false)\s*/>\s*\n?",
        "",
        text,
    )
    # Tira tambem o comentario que explicava a chave (senao fica orfao no plist).
    novo = re.sub(r"[ \t]*<!--(?:(?!-->).)*?time-sensitive(?:(?!-->).)*?-->\s*\n?", "", novo, flags=re.S)
    if novo == text:
        print("ERRO: nao consegui remover a chave do plist (formato inesperado).")
        return False
    ENTITLEMENTS.write_text(novo, encoding="utf-8")
    print("Entitlement", ENTITLEMENT_KEY, "removido de", ENTITLEMENTS.name, "(so neste build).")
    return True


def main() -> int:
    print("=== Time Sensitive Notifications no App ID ===")
    print("Bundle:", BUNDLE_ID, "| entitlements:", ENTITLEMENTS)

    if ENTITLEMENTS.is_file() and ENTITLEMENT_KEY not in ENTITLEMENTS.read_text(encoding="utf-8"):
        print("App nao pede time-sensitive nos entitlements - nada a fazer.")
        return 0

    rid = _bundle_resource_id()
    if not rid:
        return 0 if (not STRICT and _strip_entitlement()) else 1

    if _has_time_sensitive(_capability_blob(rid)):
        print("OK: capability Time Sensitive ja ativa no App ID.")
        return 0

    ok = _enable_via_rest(rid) or _enable_via_cli(rid)

    if ok:
        for attempt in (1, 2, 3):
            if _has_time_sensitive(_capability_blob(rid)):
                print("OK: Time Sensitive confirmado na API (tentativa %s)." % attempt)
                return 0
            print("Capability ainda nao listada; aguardando 30s...")
            time.sleep(30)
        # A Apple as vezes demora a listar. O perfil e recriado logo abaixo;
        # se o archive ainda falhar, o proximo build cai no fallback de strip.
        print("AVISO: enable respondeu OK mas a listagem nao confirma - seguindo.")
        return 0

    print("ERRO: nao foi possivel ativar Time Sensitive Notifications via API.")
    print(
        "Ative manualmente: developer.apple.com > Identifiers >",
        BUNDLE_ID,
        "> Time Sensitive Notifications > Save.",
    )
    if STRICT:
        return 1
    print("Fallback: removendo o entitlement para o build nao quebrar.")
    return 0 if _strip_entitlement() else 1


if __name__ == "__main__":
    sys.exit(main())
