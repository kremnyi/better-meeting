"""Дрібні хелпери, якими користуються всі етапи."""

import json
import shutil
import subprocess
import sys
from pathlib import Path


def ts(seconds: float) -> str:
    s = int(round(seconds))
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{sec:02d}" if h else f"{m:02d}:{sec:02d}"


def ts_file(seconds: float) -> str:
    s = int(round(seconds))
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return f"{h:02d}-{m:02d}-{sec:02d}"


def log(msg: str) -> None:
    print(f"[bm] {msg}", file=sys.stderr, flush=True)


def die(msg: str) -> None:
    print(f"[bm] ПОМИЛКА: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def need(binary: str) -> None:
    if shutil.which(binary) is None:
        die(f"не знайдено `{binary}` у PATH")


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def save(path: Path, data) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def probe_duration(video: Path) -> float:
    need("ffprobe")
    res = run([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(video),
    ])
    try:
        return float(res.stdout.strip())
    except ValueError:
        return 0.0
