"""
Checa, ANTES do archive, se o perfil App Store do app traz o entitlement
com.apple.developer.usernotifications.time-sensitive.

Se o Runner.entitlements pede time-sensitive e o perfil nao tem, o xcodebuild
falharia depois de ~10 min ("Provisioning profile ... doesn't include the Time
Sensitive Notifications capability"). Aqui o problema aparece em segundos:
  - modo padrao: remove o entitlement e o build segue (push normal continua);
  - IOS_TIME_SENSITIVE_STRICT=1: falha o build para corrigir no portal Apple.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from codemagic_ios_profile_utils import find_profile_for_bundle  # noqa: E402

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
STRICT = os.environ.get("IOS_TIME_SENSITIVE_STRICT", "").strip() in ("1", "true", "yes")


def _strip_entitlement() -> bool:
    text = ENTITLEMENTS.read_text(encoding="utf-8")
    novo = re.sub(
        r"[ \t]*<key>" + re.escape(ENTITLEMENT_KEY) + r"</key>\s*<(true|false)\s*/>\s*\n?",
        "",
        text,
    )
    novo = re.sub(r"[ \t]*<!--(?:(?!-->).)*?time-sensitive(?:(?!-->).)*?-->\s*\n?", "", novo, flags=re.S)
    if novo == text:
        print("ERRO: nao consegui remover a chave time-sensitive do plist.")
        return False
    ENTITLEMENTS.write_text(novo, encoding="utf-8")
    print("Entitlement time-sensitive removido de", ENTITLEMENTS.name, "(so neste build).")
    return True


def main() -> int:
    print("=== Perfil x entitlement Time Sensitive ===")
    if not ENTITLEMENTS.is_file():
        print("AVISO: entitlements nao encontrado em", ENTITLEMENTS, "- pulando.")
        return 0
    if ENTITLEMENT_KEY not in ENTITLEMENTS.read_text(encoding="utf-8"):
        print("App nao pede time-sensitive - nada a validar.")
        return 0

    found = find_profile_for_bundle(BUNDLE_ID)
    if not found:
        # WisdomApp: sem perfil para conferir, nao arrisca o archive — tira o
        # entitlement so neste build (push normal continua).
        print("AVISO: nenhum perfil instalado para", BUNDLE_ID, "- removendo time-sensitive neste build.")
        if STRICT:
            return 1
        return 0 if _strip_entitlement() else 1

    name, uuid, plist = found
    ent = plist.get("Entitlements") or {}
    print("Perfil:", name, "| UUID:", uuid)
    if ent.get(ENTITLEMENT_KEY):
        print("OK: perfil inclui Time Sensitive Notifications.")
        return 0

    print("PROBLEMA: o perfil NAO inclui", ENTITLEMENT_KEY)
    print(
        "Ative no portal: developer.apple.com > Identifiers >",
        BUNDLE_ID,
        "> Time Sensitive Notifications > Save (e refaca o build).",
    )
    if STRICT:
        return 1
    return 0 if _strip_entitlement() else 1


if __name__ == "__main__":
    sys.exit(main())
