"""Cuts Fer out of the magenta Gemini background for the app screens.

assets_source/mascot/raw/<pose>-<n>.png -> assets/images/mascot/<pose>-<n>.webp

Each pose has a few variants the app rotates through; their counts live in
ferVariants (lib/views/tenvpn/mascot.dart). All frames share one crop (the
union of their bounding boxes) padded to a square, so Fer keeps his scale and
position when the main screen switches pose. The colour key matches tenboost/tools/cut_mascot.py: the background
colour is sampled from the edges and unmixed from the soft fringe so the white
sticker outline keeps no pink halo.

    python -I tool/cut_mascot.py                 every frame in raw/
    python -I tool/cut_mascot.py --src DIR       raw frames from another folder
"""
import argparse
import re
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
RAW = REPO / "assets_source" / "mascot" / "raw"
OUT = REPO / "assets" / "images" / "mascot"
POSES = ["off", "connecting", "on", "error", "welcome"]
FRAME = re.compile(r"^(%s)-(\d+)$" % "|".join(POSES))

# Shown at up to ~290 logical px; 640 covers 2x and keeps the APK small.
SIZE = 640
PAD = 12


def border(shape) -> np.ndarray:
    b = np.zeros(shape, bool)
    b[0, :] = b[-1, :] = b[:, 0] = b[:, -1] = True
    return b


def dilate(mask: np.ndarray, r: int) -> np.ndarray:
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy * dy + dx * dx <= r * r:
                out |= np.roll(np.roll(mask, dy, 0), dx, 1)
    return out


def cut_magenta(rgb: np.ndarray) -> np.ndarray:
    f = rgb.astype(np.float32)
    key = np.median(rgb[border(rgb.shape[:2])], axis=0).astype(np.float32)
    r, g, b = key
    if not (r > 140 and b > 140 and g < 110):
        raise SystemExit(f"background is not magenta: {key}")
    d = np.sqrt(((f - key) ** 2).sum(-1))
    m = np.clip((200 - d) / 150, 0, 1)
    strong = m > 0.9
    # Soft pixels count as background only next to real background, so the
    # pink nose and ears inside the drawing survive.
    m = np.where(strong | (dilate(strong, 3) & (m > 0.05)), m, 0)
    alpha = 1 - m
    safe = np.maximum(alpha, 1e-3)[..., None]
    unmixed = np.clip((f - m[..., None] * key) / safe, 0, 255)
    return np.dstack([unmixed, alpha * 255]).astype(np.uint8)


def bbox(rgba: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.nonzero(rgba[..., 3] > 8)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", type=Path, default=RAW)
    args = parser.parse_args()

    frames = sorted(p.stem for p in args.src.glob("*.png") if FRAME.match(p.stem))
    if not frames:
        raise SystemExit(f"no <pose>-<n>.png frames in {args.src}")
    cut = {}
    for name in frames:
        image = Image.open(args.src / f"{name}.png").convert("RGB")
        if image.size != (1024, 1024):
            image = image.resize((1024, 1024), Image.LANCZOS)
        cut[name] = cut_magenta(np.array(image))

    boxes = np.array([bbox(a) for a in cut.values()])
    x0, y0 = boxes[:, 0].min(), boxes[:, 1].min()
    x1, y1 = boxes[:, 2].max(), boxes[:, 3].max()
    side = max(x1 - x0, y1 - y0) + 2 * PAD
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2

    OUT.mkdir(parents=True, exist_ok=True)
    for stale in OUT.glob("*.webp"):
        stale.unlink()
    for name, rgba in cut.items():
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        frame = Image.fromarray(rgba, "RGBA")
        canvas.paste(frame, (round(side / 2 - cx), round(side / 2 - cy)), frame)
        canvas = canvas.resize((SIZE, SIZE), Image.LANCZOS)
        path = OUT / f"{name}.webp"
        canvas.save(path, "WEBP", quality=88, method=6)
        print(f"{name:14} {SIZE}x{SIZE} {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
