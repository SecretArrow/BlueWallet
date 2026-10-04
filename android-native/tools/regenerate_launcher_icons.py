#!/usr/bin/env python3
from pathlib import Path

try:
    from PIL import Image, ImageOps
except ImportError as exc:
    raise SystemExit(
        "Pillow is required. Install with: pip install pillow"
    ) from exc

ROOT = Path(__file__).resolve().parents[1]
SRC_ICON = ROOT / "logo-app-octra.png"
RES_DIR = ROOT / "app" / "src" / "main" / "res"

LEGACY_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Adaptive spec target requested:
# 432 canvas with 288 safe zone means foreground scale factor = 288 / 432 = 2/3
SAFE_ZONE_RATIO = 288.0 / 432.0
BG_COLOR_RGBA = (26, 26, 46, 255)  # matches #1A1A2E


def build_legacy_icon(src: Image.Image, size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), BG_COLOR_RGBA)
    fg_size = int(round(size * SAFE_ZONE_RATIO))
    logo = ImageOps.contain(src, (fg_size, fg_size), method=Image.Resampling.LANCZOS)

    x = (size - logo.width) // 2
    y = (size - logo.height) // 2
    canvas.alpha_composite(logo, (x, y))
    return canvas


def main() -> None:
    if not SRC_ICON.exists():
        raise SystemExit(f"Source icon not found: {SRC_ICON}")

    src = Image.open(SRC_ICON).convert("RGBA")

    for folder, size in LEGACY_SIZES.items():
        out_dir = RES_DIR / folder
        out_dir.mkdir(parents=True, exist_ok=True)

        icon = build_legacy_icon(src, size)
        (out_dir / "ic_launcher.png").write_bytes(b"")
        (out_dir / "ic_launcher_round.png").write_bytes(b"")
        icon.save(out_dir / "ic_launcher.png", format="PNG", optimize=True)
        icon.save(out_dir / "ic_launcher_round.png", format="PNG", optimize=True)

    print("Launcher icons regenerated:")
    for folder in LEGACY_SIZES:
        print(f"- {RES_DIR / folder / 'ic_launcher.png'}")
        print(f"- {RES_DIR / folder / 'ic_launcher_round.png'}")


if __name__ == "__main__":
    main()
