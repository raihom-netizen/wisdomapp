"""
Valida ExportOptions.plist antes do flutter build ipa (blindagem exportArchive).
"""
from __future__ import annotations

import os
import plistlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from codemagic_ios_profile_utils import find_profile_by_name, profile_bundle_id  # noqa: E402

BUNDLE_ID = os.environ.get("BUNDLE_ID", "br.com.controletotalapp1.app")
WIDGET_BUNDLE_ID = os.environ.get(
    "WIDGET_BUNDLE_ID", "br.com.controletotalapp1.app.ControleTotalWidget"
)


def main() -> int:
    plist_path = Path(
        os.environ.get("EXPORT_OPTIONS_PATH", "ios/ExportOptions.plist")
    )
    if not plist_path.is_file():
        print(f"ERRO: {plist_path} não encontrado.")
        return 1

    with open(plist_path, "rb") as f:
        data = plistlib.load(f)

    profiles = data.get("provisioningProfiles") or {}
    if not isinstance(profiles, dict):
        print("ERRO: provisioningProfiles inválido no ExportOptions.plist")
        return 1

    # App sem extensao de widget (WIDGET_BUNDLE_ID vazio): valida so o app.
    tem_widget = bool(WIDGET_BUNDLE_ID)
    required = {BUNDLE_ID, WIDGET_BUNDLE_ID} if tem_widget else {BUNDLE_ID}
    missing = required - set(profiles.keys())
    if missing:
        print(f"ERRO: ExportOptions sem bundles: {sorted(missing)}")
        return 1

    main_name = str(profiles[BUNDLE_ID])
    widget_name = str(profiles[WIDGET_BUNDLE_ID]) if tem_widget else ""
    if tem_widget and main_name == widget_name:
        print("ERRO: app e Widget com o mesmo nome de perfil no ExportOptions.")
        return 1

    main_found = find_profile_by_name(main_name)
    if not main_found:
        print(f"ERRO: perfil app '{main_name}' não encontrado no keychain.")
        return 1
    widget_found = find_profile_by_name(widget_name) if tem_widget else None
    if tem_widget and not widget_found:
        print(f"ERRO: perfil widget '{widget_name}' não encontrado no keychain.")
        return 1

    _, main_pl = main_found
    widget_pl = widget_found[1] if widget_found else {}
    main_bundle = profile_bundle_id(main_pl)
    widget_bundle = profile_bundle_id(widget_pl) if widget_found else ""

    if main_bundle != BUNDLE_ID:
        print(
            f"ERRO: perfil '{main_name}' é bundle {main_bundle}, "
            f"mas ExportOptions mapeia para {BUNDLE_ID}"
        )
        return 1
    if tem_widget and widget_bundle != WIDGET_BUNDLE_ID:
        print(
            f"ERRO: perfil '{widget_name}' é bundle {widget_bundle}, "
            f"mas ExportOptions mapeia para {WIDGET_BUNDLE_ID}"
        )
        return 1

    main_ent = main_pl.get("Entitlements") or {}
    if "aps-environment" not in main_ent:
        print(f"AVISO: perfil app sem aps-environment (Push).")
    if "com.apple.developer.applesignin" not in main_ent:
        print(f"AVISO: perfil app sem Sign In with Apple.")

    if tem_widget:
        widget_groups = (widget_pl.get("Entitlements") or {}).get(
            "com.apple.security.application-groups"
        ) or []
        if not widget_groups:
            print(f"ERRO: perfil widget sem application-groups.")
            return 1
        print("OK: ExportOptions.plist validado (app + Widget, bundles distintos).")
    else:
        print("OK: ExportOptions.plist validado (app sem extensao de widget).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
