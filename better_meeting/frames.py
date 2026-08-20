"""Етапи 3-5: дешеві прев'ю -> відбір кадрів по grid-diff -> повнорозмірні кадри."""

from pathlib import Path

from .utils import log, need, run


def sample_thumbs(video: Path, out_dir: Path, interval: float) -> list:
    need("ffmpeg")
    out_dir.mkdir(parents=True, exist_ok=True)
    log(f"семплю прев'ю раз на {interval}с")
    run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(video),
        "-vf", f"fps=1/{interval},scale=320:-2",
        "-q:v", "6",
        str(out_dir / "%06d.jpg"),
    ])
    files = sorted(out_dir.glob("*.jpg"))
    return [{"t": i * interval, "path": str(p)} for i, p in enumerate(files)]


def grid_signature(path: str, n: int = 16) -> list:
    from PIL import Image
    im = Image.open(path).convert("L").resize((n, n), Image.BILINEAR)
    return list(im.getdata())


def pick_keyframes(thumbs: list, cell_delta: int, min_cells: int, max_gap: float) -> list:
    """Лишаємо кадр, якщо змінилась хоч якась зона екрана (типінг у терміналі — локальна зміна)."""
    log("шукаю кадри, де екран змінився")
    kept, prev_sig, prev_t = [], None, None
    for th in thumbs:
        sig = grid_signature(th["path"])
        if prev_sig is None:
            keep = True
        else:
            diffs = [abs(a - b) for a, b in zip(sig, prev_sig)]
            strong = sum(1 for d in diffs if d > cell_delta)
            keep = strong >= min_cells or max(diffs) > 60 or (th["t"] - prev_t) >= max_gap
        if keep:
            kept.append({"t": th["t"]})
            prev_sig, prev_t = sig, th["t"]
    log(f"{len(kept)} кандидатів з {len(thumbs)}")
    return kept


def extract_full_frames(video: Path, keyframes: list, out_dir: Path, width: int) -> list:
    need("ffmpeg")
    out_dir.mkdir(parents=True, exist_ok=True)
    log(f"витягую {len(keyframes)} повних кадрів")
    out = []
    for i, kf in enumerate(keyframes):
        path = out_dir / f"{i:05d}_{int(kf['t']):06d}.jpg"
        if not path.exists():
            run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-ss", f"{kf['t']:.3f}", "-i", str(video),
                "-frames:v", "1", "-vf", f"scale={width}:-2", "-q:v", "2",
                str(path),
            ])
        out.append({"t": kf["t"], "path": str(path)})
    return out
