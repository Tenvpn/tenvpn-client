#!/usr/bin/env python3
"""Render every TENVPN app icon from the Fer mascot in assets_source/images/brand/.

Usage: python tool/generate_brand_icons.py           (needs Pillow)
       python tool/generate_brand_icons.py --vector  (also needs scikit-image)

fer.png is the mascot bust on transparency; the launcher puts it on lime with the
hoodie running off the bottom edge, so a circular or squircle mask only trims the
shoulders. fer-glyph.png is the white head silhouette with the eye mask cut out:
Android draws status-bar, Quick Settings and themed icons from shape alone, and a
shield there read as a bank logo. --vector rewrites the two 24dp vector drawables
from that silhouette.
"""
import base64
import io
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageOps

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / 'assets_source/images/brand'
LIME = (182, 227, 46)
DARK = (29, 37, 33)
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
TRAY_ICO_SIZES = [16, 20, 24, 32, 40, 48, 64]


def bust(fer: Image.Image, size: int, height: float, bg=LIME) -> Image.Image:
    canvas = Image.new('RGBA', (size, size), bg + (255,) if bg else (0, 0, 0, 0))
    h = round(size * height)
    w = round(fer.width * h / fer.height)
    canvas.alpha_composite(fer.resize((w, h), Image.LANCZOS), ((size - w) // 2, size - h))
    return canvas


def glyph(mask: Image.Image, size: int, fraction: float) -> Image.Image:
    canvas = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    s = round(size * fraction)
    alpha = Image.new('L', (size, size), 0)
    alpha.paste(mask.resize((s, s), Image.LANCZOS), ((size - s) // 2, (size - s) // 2))
    canvas.putalpha(alpha)
    return canvas


def rounded(img: Image.Image, radius: float = 0.22) -> Image.Image:
    return _masked(img, lambda d, w, h: d.rounded_rectangle((0, 0, w - 1, h - 1), round(w * radius), fill=255))


def round_mask(img: Image.Image) -> Image.Image:
    return _masked(img, lambda d, w, h: d.ellipse((0, 0, w - 1, h - 1), fill=255))


def _masked(img: Image.Image, draw) -> Image.Image:
    mask = Image.new('L', (img.width * 4, img.height * 4), 0)
    draw(ImageDraw.Draw(mask), mask.width, mask.height)
    out = img.copy()
    out.putalpha(ImageChops.multiply(out.getchannel('A'), mask.resize(img.size, Image.LANCZOS)))
    return out


def dim(img: Image.Image) -> Image.Image:
    grey = ImageOps.grayscale(img.convert('RGB')).convert('RGBA')
    grey.putalpha(img.getchannel('A'))
    return grey


def widget_off(fer: Image.Image, size: int) -> Image.Image:
    face = ImageEnhance.Brightness(dim(fer)).enhance(0.75)
    return round_mask(bust(face, size, 0.78, bg=DARK))


def save_ico(img: Image.Image, path: Path, sizes):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format='ICO', sizes=[(s, s) for s in sizes])


def svg_with_png(img: Image.Image, path: Path):
    buf = io.BytesIO()
    img.save(buf, format='PNG', optimize=True)
    data = base64.b64encode(buf.getvalue()).decode()
    path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'width="{img.width}" height="{img.height}" viewBox="0 0 {img.width} {img.height}">'
        f'<image width="{img.width}" height="{img.height}" '
        f'xlink:href="data:image/png;base64,{data}"/></svg>\n',
        encoding='utf-8',
    )


def vector_drawable(mask: Image.Image) -> str:
    import numpy as np
    from skimage import measure

    grid = 192
    a = np.asarray(mask.resize((grid, grid), Image.LANCZOS), dtype=float) / 255
    a = np.pad(a, 1)
    paths = []
    for contour in measure.find_contours(a, 0.5):
        points = measure.approximate_polygon(contour, tolerance=0.7)
        if len(points) < 4:
            continue
        coords = [f'{(x - 1) * 24 / grid:.2f},{(y - 1) * 24 / grid:.2f}' for y, x in points]
        paths.append('M' + 'L'.join(coords) + 'Z')
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="24dp"\n'
        '    android:height="24dp"\n'
        '    android:viewportWidth="24"\n'
        '    android:viewportHeight="24">\n'
        '  <path\n'
        '      android:fillColor="#FFFFFFFF"\n'
        '      android:fillType="evenOdd"\n'
        f'      android:pathData="{"".join(paths)}" />\n'
        '</vector>\n'
    )


def main():
    fer = Image.open(BRAND / 'fer.png').convert('RGBA')
    mask = Image.open(BRAND / 'fer-glyph.png').convert('L')
    res = ROOT / 'android/app/src/main/res'
    for name, k in DENSITIES.items():
        d = res / f'mipmap-{name}'
        d.mkdir(exist_ok=True)
        bust(fer, round(48 * k), 0.84).save(d / 'ic_launcher.webp', lossless=True)
        round_mask(bust(fer, round(48 * k), 0.78)).save(d / 'ic_launcher_round.webp', lossless=True)
        bust(fer, round(108 * k), 0.58, bg=None).save(d / 'ic_launcher_foreground.png')
        glyph(mask, round(108 * k), 0.5).save(d / 'ic_launcher_monochrome.png')
        tv = res / f'mipmap-television-{name}'
        if tv.exists():
            bust(fer, round(80 * k), 0.84).save(tv / 'ic_launcher.webp', lossless=True)
    banner = Image.new('RGBA', (320, 180), LIME + (255,))
    face = fer.resize((round(fer.width * 170 / fer.height), 170), Image.LANCZOS)
    banner.alpha_composite(face, ((320 - face.width) // 2, 10))
    banner.save(res / 'mipmap-xhdpi/ic_banner.png')
    (res / 'values/ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#B6E32E</color>\n</resources>\n',
        encoding='utf-8',
    )

    widgets = res / 'drawable-nodpi'
    widgets.mkdir(exist_ok=True)
    round_mask(bust(fer, 288, 0.78)).save(widgets / 'widget_toggle_on.png', optimize=True)
    widget_off(fer, 288).save(widgets / 'widget_toggle_off.png', optimize=True)
    if '--vector' in sys.argv:
        drawable = vector_drawable(mask)
        for name in ('ic.xml', 'ic_service.xml'):
            (ROOT / 'android/service/src/main/res/drawable' / name).write_text(drawable, encoding='utf-8')

    master = rounded(bust(fer, 1024, 0.84))
    save_ico(master, ROOT / 'windows/runner/resources/app_icon.ico', ICO_SIZES)
    tray = rounded(bust(fer, 256, 0.84))
    save_ico(dim(tray), ROOT / 'assets/images/tray/windows/status_1.ico', TRAY_ICO_SIZES)
    save_ico(tray, ROOT / 'assets/images/tray/windows/status_2.ico', TRAY_ICO_SIZES)
    save_ico(tray, ROOT / 'assets/images/tray/windows/status_3.ico', TRAY_ICO_SIZES)
    unix = ROOT / 'assets/images/tray/unix'
    for scale, sub in ((1, ''), (2, '2.0x'), (3, '3.0x'), (4, '4.0x')):
        d = unix / sub if sub else unix
        if d.exists():
            s = 18 * scale
            small = rounded(bust(fer, s, 0.84))
            dim(small).save(d / 'status_1.png')
            small.save(d / 'status_2.png')
            small.save(d / 'status_3.png')

    svg_with_png(rounded(bust(fer, 256, 0.84)), ROOT / 'assets/images/icon.svg')
    master.save(ROOT / 'assets/images/icon.png')
    save_ico(master, ROOT / 'assets/images/icon.ico', ICO_SIZES)

    composer = ROOT / 'ios/Runner/AppIcon.icon'
    svg_with_png(bust(fer, 1024, 0.84), composer / 'Assets/icon.svg')
    spec = json.loads((composer / 'icon.json').read_text(encoding='utf-8'))
    spec['fill'] = {'solid': 'srgb:0.71373,0.89020,0.18039,1.00000'}
    for group in spec.get('groups', []):
        for layer in group.get('layers', []):
            layer['position'] = {'scale': 1.0, 'translation-in-points': [0, 0]}
    (composer / 'icon.json').write_text(json.dumps(spec, indent=2) + '\n', encoding='utf-8')

    widget = ROOT / 'ios/Widget/Assets.xcassets/AppIcon.appiconset'
    bust(fer, 1024, 0.84).convert('RGB').save(widget / 'AppIcon-1024.png')
    contents = json.loads((widget / 'Contents.json').read_text(encoding='utf-8'))
    contents['images'][0]['filename'] = 'AppIcon-1024.png'
    (widget / 'Contents.json').write_text(json.dumps(contents, indent=2) + '\n', encoding='utf-8')

    launch = ROOT / 'ios/Runner/Assets.xcassets/LaunchLogo.imageset'
    for suffix, k in (('', 1), ('@2x', 2), ('@3x', 3)):
        logo = round_mask(bust(fer, 288 * k, 0.78))
        logo.save(launch / f'LaunchLogo{suffix}.png')
        logo.save(launch / f'LaunchLogoDark{suffix}.png')
    print('icons written')


if __name__ == '__main__':
    main()
