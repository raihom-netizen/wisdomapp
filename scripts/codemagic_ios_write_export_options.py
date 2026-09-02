"""
Gera ExportOptions.plist com perfis explícitos (app + Widget) para exportArchive.
Match EXATO de bundle — evita usar perfil Widget no app principal.
"""
from __future__ import annotations

import argparse
import os
import plistlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from codemagic_ios_profile_utils import (  # noqa: E402
    find_profile_for_bundle,
    profile_bundle_id,
)

BUNDLE_ID = os.environ.get("BUNDLE_ID", "br.com.controletotalapp1.app")
WIDGET_BUNDLE_ID = os.environ.get(
    "WIDGET_BUNDLE_ID", "br.com.controletotalapp1.app.ControleTotalWidget"
)
APP_GROUP = os.environ.get("APP_GROUP_ID", "group.br.com.controletotalapp1.widget")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-o",
        "--output",
        default="ios/ExportOptions.plist",
        help="Caminho do ExportOptions.plist (relativo ao flutter_app)",
    )
    args = parser.parse_args()

    main_hit = find_profile_for_bundle(
        BUNDLE_ID,
        require_push=True,
        require_sign_in_apple=True,
    )
    if main_hit is None:
        # Fallback: perfil do app sem exigir Push/SiWA no decode (alguns perfis usam chaves diferentes).
        main_hit = find_profile_for_bundle(BUNDLE_ID)
    # App sem extensao de widget (WIDGET_BUNDLE_ID vazio): exporta so o app.
    widget_hit = None
    if WIDGET_BUNDLE_ID:
        widget_hit = find_profile_for_bundle(
            WIDGET_BUNDLE_ID,
            require_app_group=APP_GROUP,
        )

    if main_hit is None:
        print(f"ERRO: perfil App Store não encontrado para {BUNDLE_ID} (match exato).")
        return 1
    if WIDGET_BUNDLE_ID and widget_hit is None:
        print(
            f"ERRO: perfil Widget com App Group {APP_GROUP} não encontrado para "
            f"{WIDGET_BUNDLE_ID} (match exato)."
        )
        return 1

    main_name, main_uuid, main_pl = main_hit

    main_suffix = profile_bundle_id(main_pl)
    if main_suffix != BUNDLE_ID:
        print(f"ERRO: perfil app aponta para {main_suffix}, esperado {BUNDLE_ID}")
        return 1

    print(f"Perfil app: {main_name}")
    print(f"  bundle: {main_suffix} | uuid: {main_uuid}")

    perfis = {BUNDLE_ID: main_name}

    if widget_hit is not None:
        widget_name, widget_uuid, widget_pl = widget_hit
        if main_name == widget_name or main_uuid == widget_uuid:
            print("ERRO: mesmo perfil atribuído ao app e ao Widget — abortando export.")
            return 1
        widget_suffix = profile_bundle_id(widget_pl)
        if widget_suffix != WIDGET_BUNDLE_ID:
            print(f"ERRO: perfil widget aponta para {widget_suffix}, esperado {WIDGET_BUNDLE_ID}")
            return 1
        print(f"Perfil widget: {widget_name}")
        print(f"  bundle: {widget_suffix} | uuid: {widget_uuid}")
        perfis[WIDGET_BUNDLE_ID] = widget_name
    else:
        print("App sem extensao de widget — ExportOptions so com o app.")

    export_plist = {
        "method": "app-store",
        "signingStyle": "manual",
        "uploadSymbols": True,
        "compileBitcode": False,
        "provisioningProfiles": perfis,
    }

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "wb") as f:
        plistlib.dump(export_plist, f)
    print(f"ExportOptions.plist gravado: {out_path.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
