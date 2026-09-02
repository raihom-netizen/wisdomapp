"""Ativa Sign In with Apple no App ID via App Store Connect API.

Extraido do codemagic.yaml para rodar igual no GitHub Actions.
Usa o CLI app-store-connect (codemagic-cli-tools) com as variaveis
APP_STORE_CONNECT_* do ambiente.
"""

import json, os, re, subprocess, sys, time
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
try:
    j = json.loads((r.stdout or "").strip() or "null")
except json.JSONDecodeError as e:
    print("ERRO JSON bundle-ids list:", e)
    sys.exit(1)
# O CLI pode retornar {"data":[...]} ou apenas [...]
if isinstance(j, dict):
    data = j.get("data") or []
elif isinstance(j, list):
    data = j
else:
    data = []
if not data or not isinstance(data[0], dict):
    print("ERRO: nenhum Bundle ID iOS para", bundle)
    sys.exit(1)
rid = data[0].get("id")
if not rid:
    sys.exit(1)
print("Bundle ID resource id:", rid)
# Alguns ambientes aceitam nomes diferentes para a mesma capability.
candidates = [
    "Sign In with Apple",
    "APPLE_ID_AUTH",
    "SIGN_IN_WITH_APPLE",
]
last_out = ""
enabled = False
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
    if ec.returncode == 0:
        print(f"Sign In with Apple: capability ativada com '{cap}'.")
        enabled = True
        break
    if any(b in low for b in ("already", "duplicate", "exist", "409", "conflict", "not modified", "unchanged")):
        print(f"Sign In with Apple: capability ja ativa (resposta ao tentar '{cap}').")
        enabled = True
        break
    print(f"Tentativa capability '{cap}' falhou: {out[:300]}")

if not enabled:
    print("ERRO enable-capabilities — nao foi possivel ativar Sign In with Apple no App ID.")
    print("Detalhe:", (last_out or "")[:900])
    print("Confirme permissao da API key (Admin/App Manager) e capability ativa no Apple Developer.")
    sys.exit(1)
# Fonte de verdade: listagem oficial (inspecionar .mobileprovision no CI deu falso negativo vs Xcode).

def caps_has_sign_in(txt):
    try:
        jc = json.loads((txt or "").strip() or "{}")
    except json.JSONDecodeError:
        return False
    blob = json.dumps(jc)
    return bool(
        re.search(
            r"SIGN_IN_WITH_APPLE|APPLE_ID_AUTH|Sign[\s_]?In[\s_]?with[\s_]?Apple|SignInWithApple|com\.apple\.developer\.applesignin",
            blob,
            re.I | re.DOTALL,
        )
    )

for attempt in (1, 2):
    caps = subprocess.run(
        ["app-store-connect", "bundle-ids", "capabilities", rid, "--json", "-s"],
        capture_output=True,
        text=True,
    )
    caps_out = caps.stdout or ""
    caps_err = caps.stderr or ""
    print("--- bundle-ids capabilities (trecho, tentativa %s) ---" % attempt)
    print(caps_out[:12000])
    if caps.returncode != 0:
        print("ERRO bundle-ids capabilities:", caps_err[:900])
        sys.exit(1)
    if caps_has_sign_in(caps_out):
        print("OK: Sign In with Apple confirmado na API (bundle-ids capabilities).")
        break
    if attempt == 1:
        print("AVISO: Sign In ainda nao aparece na listagem; aguardando 60s e relendo...")
        time.sleep(60)
    else:
        print("ERRO: Sign In with Apple nao consta em bundle-ids capabilities apos enable + espera.")
        print("Corrija no portal: developer.apple.com > Identifiers >", bundle, "> Sign In with Apple (Primary App ID) > Save.")
        sys.exit(1)
