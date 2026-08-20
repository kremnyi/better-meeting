"""Етап 7: збирання самодостатньої теки artifacts/."""

import shutil
from pathlib import Path

from .ocr import norm
from .prompts import HOWTO, PROMPT
from .render import render_timeline, render_transcript
from .shots import fallback_shots, make_sheets, select_shots, write_shot
from .utils import log, ts, ts_file


def write_bundle(
    art: Path,
    transcript: list,
    screen: list,
    frames: list,
    duration: float,
    *,
    max_shots: int,
    shot_width: int,
    shot_quality: int,
    draw_label: bool,
    sheet: int,
    pause: float,
) -> None:
    if art.exists():
        shutil.rmtree(art)
    (art / "screens").mkdir(parents=True, exist_ok=True)

    shots = select_shots(screen, duration, max_shots)
    if not shots:
        shots = fallback_shots(frames, max_shots)
        if shots:
            log("OCR-тексту немає — беру кадри рівномірно по часу")
    log(f"відібрано {len(shots)} скріншотів")

    shots_by_t, shot_files, index_rows = {}, [], []
    for i, ev in enumerate(shots, 1):
        name = f"{i:03d}_{ts_file(ev['t'])}.jpg"
        dst = art / "screens" / name
        write_shot(ev["path"], dst, ts(ev["t"]), shot_width, shot_quality, draw_label)
        shots_by_t[round(ev["t"], 3)] = f"screens/{name}"
        shot_files.append(dst)
        preview = " / ".join(norm(l) for l in ev["added"][:3])[:160]
        index_rows.append(f"| {ts(ev['t'])} | `screens/{name}` | {preview} |")

    sheets = []
    if sheet:
        sheets = make_sheets(shot_files, art / "sheets", sheet, shot_width, shot_quality)
        log(f"склеєно {len(sheets)} сіток")

    (art / "transcript.md").write_text(render_transcript(transcript), encoding="utf-8")
    timeline = render_timeline(transcript, screen, shots_by_t, pause)
    (art / "timeline.md").write_text(timeline, encoding="utf-8")

    (art / "screens_index.md").write_text(
        "# Скріншоти\n\n| Таймкод | Файл | Що з'явилось на екрані |\n|---|---|---|\n"
        + "\n".join(index_rows) + "\n",
        encoding="utf-8",
    )
    (art / "PROMPT.md").write_text(PROMPT, encoding="utf-8")

    stats = "\n".join([
        f"- тривалість запису: {ts(duration)}",
        f"- сегментів мови: {len(transcript)}",
        f"- подій екрана: {len(screen)}",
        f"- скріншотів у теці: {len(shot_files)}",
        f"- розмір timeline.md: {len(timeline)} символів",
    ])
    sheets_note = "\n   - або, якщо вкладень забагато, — зображення з `sheets/`" if sheets else ""
    (art / "HOW-TO.md").write_text(
        HOWTO.format(stats=stats, sheets_note=sheets_note), encoding="utf-8")

    log(f"готово: {art}")
