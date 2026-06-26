"""Gera ícones WISDOMAPP a partir de assets/images/logo_divulgacao.png.

Uso:
  python tool/generate_brand_assets.py
  flutter pub run flutter_launcher_icons

Saídas: icon_no_bg, adaptive foreground, web/icons (PWA + splash), push banners.
"""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "images"
SRC_CANDIDATES = [
    ASSETS / "logo_divulgacao.png",
    ASSETS / "logo_divulgacao" / "logo.png",
    ASSETS / "logo_divulgacao" / "logo_divulgacao.png",
    ASSETS / "icon.png",
]
OUT_ICON = ASSETS / "icon_no_bg.png"
OUT_ADAPTIVE = ASSETS / "icon_adaptive_foreground.png"
OUT_MASTER = ASSETS / "icon.png"
PUSH_DIR = ASSETS / "images" / "push_banners"
WEB_ICONS = ROOT / "web" / "icons"

PUSH_THEMES = {
    "financeiro": (13, 148, 136),
    "compromisso": (37, 99, 235),
    "escala": (234, 88, 12),
    "audiencia": (91, 33, 182),
    "folga": (124, 58, 237),
}

WEB_BG = (10, 31, 86, 255)  # #0A1F56


def resolve_source() -> Path:
    for p in SRC_CANDIDATES:
        if p.is_file():
            return p
    raise FileNotFoundError(
        "Coloque logo_divulgacao.png em assets/images/ — candidatos: "
        + ", ".join(str(c) for c in SRC_CANDIDATES)
    )


def is_removable_background(r: int, g: int, b: int, a: int) -> bool:
    if a < 8:
        return True
    mx = max(r, g, b)
    mn = min(r, g, b)
    sat = mx - mn
    # Preto sólido externo (fundo da arte ChatGPT / PNG).
    if mx <= 32 and sat <= 24:
        return True
    # Cinza escuro uniforme nas bordas.
    if mx < 52 and sat < 38:
        return True
    # Branco / quase branco.
    if mn > 238 and sat < 18:
        return True
    if mn > 225 and sat < 28 and abs(r - g) < 12 and abs(g - b) < 12:
        return True
    return False


def remove_border_background(src: Image.Image) -> Image.Image:
    img = src.convert("RGBA")
    w, h = img.size
    px = img.load()
    visited = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()

    def try_enqueue(x: int, y: int) -> None:
        if x < 0 or y < 0 or x >= w or y >= h:
            return
        idx = y * w + x
        if visited[idx]:
            return
        visited[idx] = 1
        r, g, b, a = px[x, y]
        if is_removable_background(r, g, b, a):
            q.append((x, y))

    for x in range(w):
        try_enqueue(x, 0)
        try_enqueue(x, h - 1)
    for y in range(h):
        try_enqueue(0, y)
        try_enqueue(w - 1, y)

    while q:
        x, y = q.popleft()
        r, g, b, _a = px[x, y]
        px[x, y] = (r, g, b, 0)
        try_enqueue(x + 1, y)
        try_enqueue(x - 1, y)
        try_enqueue(x, y + 1)
        try_enqueue(x, y - 1)

    alpha = img.getchannel("A").filter(ImageFilter.GaussianBlur(radius=0.6))
    img.putalpha(alpha)
    return img


def fit_on_transparent_canvas(
    img: Image.Image,
    scale: float,
    size: int = 1024,
    vertical_bias: float = 0.0,
) -> Image.Image:
    alpha = img.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        raise RuntimeError("Não foi possível extrair o escudo do logo (alpha vazio).")

    cropped = img.crop(bbox)
    target = int(size * scale)
    fitted = cropped.copy()
    fitted.thumbnail((target, target), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2 + int(size * vertical_bias)
    canvas.alpha_composite(fitted, (x, y))
    return canvas


def composite_on_background(foreground: Image.Image, bg_rgba: tuple[int, int, int, int]) -> Image.Image:
    base = Image.new("RGBA", foreground.size, bg_rgba)
    base.alpha_composite(foreground)
    return base


def save_web_png(img: Image.Image, path: Path, size: int, *, maskable: bool = False) -> None:
    scale = 0.72 if maskable else 0.88
    fitted = fit_on_transparent_canvas(img, scale=scale, size=size)
    if maskable:
        out = composite_on_background(fitted, WEB_BG)
    else:
        out = composite_on_background(fitted, WEB_BG)
    out.save(path, "PNG", optimize=True)


def _lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def make_push_banner(logo: Image.Image, base_rgb: tuple[int, int, int], size=(600, 300)) -> Image.Image:
    w, h = size
    banner = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(banner)
    dark = tuple(max(0, c - 35) for c in base_rgb)
    light = tuple(min(255, c + 40) for c in base_rgb)
    for y in range(h):
        t = y / max(h - 1, 1)
        row = (_lerp(dark[0], light[0], t), _lerp(dark[1], light[1], t), _lerp(dark[2], light[2], t))
        draw.line([(0, y), (w, y)], fill=row + (255,))

    emblem = fit_on_transparent_canvas(logo, scale=0.55, size=min(w, h))
    emblem.thumbnail((int(h * 0.78), int(h * 0.78)), Image.Resampling.LANCZOS)
    x = (w - emblem.width) // 2
    y = (h - emblem.height) // 2
    banner.alpha_composite(emblem, (x, y))
    return banner


def main() -> None:
    src_path = resolve_source()
    print(f"Origem: {src_path}")

    src = Image.open(src_path).convert("RGBA")
    no_bg = remove_border_background(src)

    final_icon = fit_on_transparent_canvas(no_bg, scale=0.86)
    adaptive_fg = fit_on_transparent_canvas(no_bg, scale=0.76)

    ASSETS.mkdir(parents=True, exist_ok=True)
    final_icon.save(OUT_ICON, "PNG", optimize=True)
    adaptive_fg.save(OUT_ADAPTIVE, "PNG", optimize=True)
    final_icon.save(OUT_MASTER, "PNG", optimize=True)
    print(f"Gerado: {OUT_ICON}")
    print(f"Gerado: {OUT_ADAPTIVE}")
    print(f"Gerado: {OUT_MASTER}")

    WEB_ICONS.mkdir(parents=True, exist_ok=True)
    emblem_path = WEB_ICONS / "wisdomapp_emblem.png"
    final_icon.save(emblem_path, "PNG", optimize=True)
    print(f"Gerado: {emblem_path}")

    for size, name in [(192, "Icon-192.png"), (512, "Icon-512.png")]:
        save_web_png(no_bg, WEB_ICONS / name, size, maskable=False)
        print(f"Gerado: {WEB_ICONS / name}")

    for size, name in [(192, "Icon-maskable-192.png"), (512, "Icon-maskable-512.png")]:
        save_web_png(no_bg, WEB_ICONS / name, size, maskable=True)
        print(f"Gerado: {WEB_ICONS / name}")

    favicon = ROOT / "web" / "favicon.png"
    save_web_png(no_bg, favicon, 48, maskable=False)
    print(f"Gerado: {favicon}")

    push_dir = ROOT / "assets" / "images" / "push_banners"
    push_dir.mkdir(parents=True, exist_ok=True)
    for kind, rgb in PUSH_THEMES.items():
        banner = make_push_banner(no_bg, rgb)
        asset_path = push_dir / f"push-banner-{kind}.png"
        web_path = WEB_ICONS / f"push-banner-{kind}.png"
        banner.save(asset_path, "PNG", optimize=True)
        banner.save(web_path, "PNG", optimize=True)
        print(f"Gerado: {asset_path}")


if __name__ == "__main__":
    main()
