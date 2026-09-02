"""Ativa Push Notifications no App ID via App Store Connect API.

Extraido do codemagic.yaml para rodar igual no GitHub Actions.
"""

import json, os, subprocess, sys, time
bundle = os.environ.get("BUNDLE_ID", "com.wisdomapp")
r = subprocess.run(
    [
        "app-store-connect", "bundle-ids", "list",
        "--bundle-id-identifier", bundle,
        "--strict-match-identifier",
        "--platform", "IOS",
        "--json", "-s",
    ],
    capture_output=True,
    text=True,
)
if r.returncode != 0:
    print("ERRO bundle-ids list:", (r.stderr or r.stdout)[:900])
    sys.exit(1)
j = json.loads((r.stdout or "").strip() or "null")
data = j.get("data") if isinstance(j, dict) else (j if isinstance(j, list) else [])
if not data or not isinstance(data[0], dict):
    print("ERRO: nenhum Bundle ID iOS para", bundle)
    sys.exit(1)
rid = data[0].get("id")
if not rid:
    sys.exit(1)
candidates = ["Push Notifications", "PUSH_NOTIFICATIONS"]
enabled = False
last_out = ""
for cap in candidates:
    ec = subprocess.run(
        [
            "app-store-connect", "bundle-ids", "enable-capabilities", rid,
            "--capability", cap,
        ],
        capture_output=True,
        text=True,
    )
    out = ((ec.stderr or "") + (ec.stdout or "")).strip()
    last_out = out
    low = out.lower()
    if ec.returncode == 0 or any(
        b in low for b in ("already", "duplicate", "exist", "409", "conflict", "not modified", "unchanged")
    ):
        print(f"Push Notifications: OK com '{cap}'.")
        enabled = True
        break
    print(f"Tentativa '{cap}' falhou: {out[:300]}")
if not enabled:
    print("ERRO enable Push Notifications:", (last_out or "")[:900])
    sys.exit(1)
