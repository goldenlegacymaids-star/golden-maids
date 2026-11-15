"""Generates every app icon and launch image from the Golden Maids logo.

Re-run after any logo change:
    python3 design/tools/generate_app_icons.py
Needs `rsvg-convert` (librsvg) and ImageMagick `convert`.
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BLUE, GOLD, WHITE = "#398FF2", "#F3B642", "#FFFFFF"


def glyph(fg, sparkle):
    """House + door + sparkle, drawn in the 120x120 logo coordinate space."""
    k = 12 * 0.28
    return (
        f'<path d="M28 60 L60 33 L92 60" fill="none" stroke="{fg}" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>'
        f'<path d="M38 54 V86 a4 4 0 0 0 4 4 H78 a4 4 0 0 0 4 -4 V54" fill="none" stroke="{fg}" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>'
        f'<rect x="52" y="66" width="16" height="24" rx="5" fill="{fg}"/>'
        f'<path d="M90 18 Q{90+k} {30-k} 102 30 Q{90+k} {30+k} 90 42 Q{90-k} {30+k} 78 30 Q{90-k} {30-k} 90 18Z" fill="{sparkle}"/>'
    )


def svg(body, size=120):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{body}</svg>'


# Rounded tile (Android legacy, web, launch image) – transparent corners.
TILE = svg(f'<rect width="120" height="120" rx="30" fill="{BLUE}"/>' + glyph(WHITE, GOLD))
# Full-bleed square (iOS – the system rounds the corners itself).
FULL = svg(f'<rect width="120" height="120" fill="{BLUE}"/>' + glyph(WHITE, GOLD))
# Full-bleed with extra padding (web maskable: content inside the 80% safe zone).
MASKABLE = svg(f'<rect width="120" height="120" fill="{BLUE}"/><g transform="translate(60 60) scale(0.78) translate(-60 -60)">' + glyph(WHITE, GOLD) + '</g>')
# Android adaptive icon layers (108dp canvas, content inside the 66dp safe zone).
FOREGROUND = svg('<g transform="translate(54 56) scale(0.66) translate(-62 -56)">' + glyph(WHITE, GOLD) + '</g>', 108)
MONOCHROME = svg('<g transform="translate(54 56) scale(0.66) translate(-62 -56)">' + glyph(WHITE, WHITE) + '</g>', 108)


def render(svg_text, out, px, flatten=False):
    out = pathlib.Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg_text)
    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), f.name, "-o", str(out)], check=True)
    if flatten:  # App Store icons must not have an alpha channel.
        subprocess.run(["convert", str(out), "-background", BLUE, "-alpha", "remove", "-alpha", "off", str(out)], check=True)
    subprocess.run(["convert", str(out), "-strip", str(out)], check=True)


res = ROOT / "android/app/src/main/res"
densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
for name, scale in densities.items():
    render(TILE, res / f"mipmap-{name}/ic_launcher.png", round(48 * scale))
    render(FOREGROUND, res / f"mipmap-{name}/ic_launcher_foreground.png", round(108 * scale))
    render(MONOCHROME, res / f"mipmap-{name}/ic_launcher_monochrome.png", round(108 * scale))
    render(TILE, res / f"drawable-{name}/launch_image.png", round(112 * scale))

ios = ROOT / "ios/Runner/Assets.xcassets"
import json
contents = json.loads((ios / "AppIcon.appiconset/Contents.json").read_text())
for img in contents["images"]:
    pt = float(img["size"].split("x")[0])
    px = round(pt * int(img["scale"].rstrip("x")))
    render(FULL, ios / "AppIcon.appiconset" / img["filename"], px, flatten=True)
for suffix, mult in [("", 1), ("@2x", 2), ("@3x", 3)]:
    render(TILE, ios / f"LaunchImage.imageset/LaunchImage{suffix}.png", 112 * mult)

web = ROOT / "web"
render(TILE, web / "favicon.png", 32)
render(TILE, web / "icons/Icon-192.png", 192)
render(TILE, web / "icons/Icon-512.png", 512)
render(MASKABLE, web / "icons/Icon-maskable-192.png", 192)
render(MASKABLE, web / "icons/Icon-maskable-512.png", 512)

(ROOT / "design/logo/app_icon_full_bleed.svg").write_text(FULL + "\n")
(ROOT / "design/logo/adaptive_foreground.svg").write_text(FOREGROUND + "\n")
(ROOT / "design/logo/adaptive_monochrome.svg").write_text(MONOCHROME + "\n")
print("icons generated")
