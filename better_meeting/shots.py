"""Скріншоти для чату: відбір під ліміт вкладень, підпис таймкоду, склейка в сітки."""

import math
from pathlib import Path


def select_shots(screen: list, duration: float, max_shots: int) -> list:
    """Рівномірно по часу + найінформативніші кадри, щоб влізти в ліміт вкладень чату."""
    candidates = [e for e in screen if e["added"]]
    if not candidates or max_shots <= 0 or len(candidates) <= max_shots:
        return candidates

    duration = duration or (candidates[-1]["t"] + 1)
    buckets = {}
    for ev in candidates:
        idx = min(int(ev["t"] / duration * max_shots), max_shots - 1)
        score = sum(len(l) for l in ev["added"])
        if idx not in buckets or score > buckets[idx][0]:
            buckets[idx] = (score, ev)
    chosen = [v[1] for v in buckets.values()]

    if len(chosen) < max_shots:
        rest = sorted(
            (e for e in candidates if e not in chosen),
            key=lambda e: sum(len(l) for l in e["added"]),
            reverse=True,
        )
        chosen += rest[: max_shots - len(chosen)]
    return sorted(chosen, key=lambda e: e["t"])


def fallback_shots(frames: list, max_shots: int) -> list:
    """Коли OCR вимкнений або не дав тексту (напр. низька роздільність запису):
    рівномірний по часу відбір кадрів, де екран змінювався, — щоб дані з відео
    все одно потрапили в теку, а їх читання лягло на зовнішню модель."""
    if max_shots <= 0 or not frames:
        return []
    if len(frames) <= max_shots:
        picked = frames
    else:
        step = len(frames) / max_shots
        picked = [frames[int(i * step)] for i in range(max_shots)]
    return [{"t": f["t"], "path": f["path"], "added": []} for f in picked]


def _font(size: int):
    from PIL import ImageFont
    for p in [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]:
        if Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()


def write_shot(src: str, dst: Path, label: str, width: int, quality: int, draw_label: bool) -> None:
    from PIL import Image, ImageDraw
    im = Image.open(src).convert("RGB")
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    if draw_label:
        bar = max(24, im.height // 26)
        canvas = Image.new("RGB", (im.width, im.height + bar), (18, 18, 18))
        canvas.paste(im, (0, bar))
        d = ImageDraw.Draw(canvas)
        d.text((8, max(2, bar // 6)), label, fill=(255, 220, 120), font=_font(int(bar * 0.7)))
        im = canvas
    im.save(dst, "JPEG", quality=quality, optimize=True)


def make_sheets(shot_files: list, out_dir: Path, per_sheet: int, width: int, quality: int) -> list:
    """Склеює скріншоти в сітки — коли чат не приймає багато вкладень."""
    from PIL import Image
    out_dir.mkdir(parents=True, exist_ok=True)
    sheets = []
    for n in range(0, len(shot_files), per_sheet):
        group = shot_files[n:n + per_sheet]
        cols = math.ceil(math.sqrt(len(group)))
        rows = math.ceil(len(group) / cols)
        cell_w = width // cols
        imgs = []
        for f in group:
            im = Image.open(f).convert("RGB")
            im = im.resize((cell_w, round(im.height * cell_w / im.width)), Image.LANCZOS)
            imgs.append(im)
        cell_h = max(i.height for i in imgs)
        sheet = Image.new("RGB", (cell_w * cols, cell_h * rows), (18, 18, 18))
        for i, im in enumerate(imgs):
            sheet.paste(im, ((i % cols) * cell_w, (i // cols) * cell_h))
        path = out_dir / f"sheet_{n // per_sheet + 1:02d}.jpg"
        sheet.save(path, "JPEG", quality=quality, optimize=True)
        sheets.append(path.name)
    return sheets
