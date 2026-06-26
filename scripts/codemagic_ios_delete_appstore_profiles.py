"""
Remove perfis IOS_APP_STORE do App Store Connect para o bundle do WISDOMAPP.
Usado no Codemagic antes de fetch-signing-files para forçar recriação com capabilities atuais.
"""
import json
import os
import subprocess
import sys


def main() -> int:
    bundle = os.environ.get("BUNDLE_ID", "com.wisdomapp")
    r = subprocess.run(
        ["app-store-connect", "profiles", "list", "--type", "IOS_APP_STORE", "--json", "-s"],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        print("Aviso: profiles list falhou:", (r.stderr or "")[:400])
        return 0
    try:
        j = json.loads((r.stdout or "").strip() or "null")
    except json.JSONDecodeError as e:
        print("Aviso: JSON invalido em profiles list:", e)
        return 0
    data = j["data"] if isinstance(j, dict) and "data" in j else (j if isinstance(j, list) else [])
    included = {}
    if isinstance(j, dict):
        for inc in j.get("included") or []:
            if inc.get("id") and inc.get("type"):
                included["{}:{}".format(inc.get("type"), inc.get("id"))] = inc

    def bundle_for(item):
        rel = (item.get("relationships") or {}).get("bundleId") or {}
        d = rel.get("data") or {}
        bid, btype = d.get("id"), d.get("type") or "bundleIds"
        if not bid:
            return None
        b = included.get("{}:{}".format(btype, bid))
        if not b:
            return None
        return (b.get("attributes") or {}).get("identifier")

    n = 0
    for item in data or []:
        if not isinstance(item, dict):
            continue
        attrs = item.get("attributes") or {}
        name = str(attrs.get("name") or "")
        pid = item.get("id")
        if not pid:
            continue
        ident = bundle_for(item)
        name_hit = "wisdomapp" in name.lower() or "wisdom" in name.lower()
        if ident != bundle and not (ident is None and name_hit):
            continue
        print("Removendo perfil App Store:", name, pid)
        subprocess.run(
            ["app-store-connect", "profiles", "delete", pid, "--ignore-not-found"],
            check=False,
        )
        n += 1
    print("Perfis removidos (recriacao no passo seguinte):", n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
