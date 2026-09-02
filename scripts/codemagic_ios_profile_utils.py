"""
Utilitários compartilhados — perfis .mobileprovision iOS (Codemagic).
Match EXATO de bundle ID (evita confundir app com Widget por substring).
"""
from __future__ import annotations

import glob
import os
import plistlib
import subprocess
from pathlib import Path

PROFILE_DIRS = (
    os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
    os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
)


def decode_profile(path: str) -> dict | None:
    r = subprocess.run(
        ["security", "cms", "-D", "-i", path],
        capture_output=True,
    )
    if r.returncode != 0:
        return None
    try:
        return plistlib.loads(r.stdout)
    except Exception:
        return None


def bundle_id_from_entitlement(application_identifier: str) -> str:
    """TEAMID.br.com.foo.app → br.com.foo.app (match exato, sem substring)."""
    raw = (application_identifier or "").strip()
    if not raw:
        return ""
    dot = raw.find(".")
    if dot < 0:
        return raw
    return raw[dot + 1 :]


def iter_profiles() -> list[tuple[str, dict]]:
    out: list[tuple[str, dict]] = []
    for d in PROFILE_DIRS:
        for path in glob.glob(os.path.join(d, "*.mobileprovision")):
            pl = decode_profile(path)
            if pl:
                out.append((path, pl))
    return out


def profile_bundle_id(pl: dict) -> str:
    ent = pl.get("Entitlements") or {}
    return bundle_id_from_entitlement(str(ent.get("application-identifier") or ""))


def find_profile_for_bundle(
    bundle: str,
    *,
    require_app_group: str | None = None,
    require_push: bool = False,
    require_sign_in_apple: bool = False,
) -> tuple[str, str, dict] | None:
    """
    Retorna (profile_name, uuid, plist) para bundle exato.
    """
    best: tuple[str, str, dict, int] | None = None
    for path, pl in iter_profiles():
        suffix = profile_bundle_id(pl)
        if suffix != bundle:
            continue

        ent = pl.get("Entitlements") or {}
        groups = ent.get("com.apple.security.application-groups") or []
        if require_app_group and require_app_group not in groups:
            continue
        if require_push and "aps-environment" not in ent:
            continue
        if require_sign_in_apple and "com.apple.developer.applesignin" not in ent:
            continue

        name = str(pl.get("Name") or "")
        uuid = str(pl.get("UUID") or Path(path).stem)
        score = 0
        if require_app_group and require_app_group in groups:
            score += 20
        if "ios_app_store" in name.lower() or "app store" in name.lower():
            score += 5
        if best is None or score > best[3]:
            best = (name, uuid, pl, score)

    if best is None:
        return None
    return best[0], best[1], best[2]


def find_profile_by_name(name: str) -> tuple[str, dict] | None:
    target = name.strip()
    for path, pl in iter_profiles():
        if str(pl.get("Name") or "").strip() == target:
            return path, pl
    return None
