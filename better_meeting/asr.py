"""Етап 2: визначення мов(и) запису і транскрипція з таймкодами.

Проблема: whisper з language=None визначає мову ОДИН раз по перших 30 секундах.
Якщо запис починається однією мовою, а продовжується іншою (або мови чергуються),
весь транскрипт їде не туди.

Тому `--lang auto` (дефолт) працює у два кроки:
  1. проби: короткі кліпи рівномірно по всьому запису -> мова кожної проби
  2а. мова одна  -> один прогін із зафіксованою мовою (стабільніше за auto)
  2б. мов кілька -> запис ріжеться на однорідні мовні відрізки, кожен
      транскрибується своєю мовою, сегменти зшиваються по часу

Кожен сегмент транскрипту отримує поле "lang" (код мови whisper: uk/ru/en/...).
"""

import platform
from pathlib import Path

from .utils import log, run, ts

PROBE_LEN = 24.0   # тривалість однієї проби, сек
PROBE_MAX = 12     # скільки проб максимум
MIN_PROBES = 2     # мова «рахується», якщо проб з нею не менше стількох...
MIN_SHARE = 0.2    # ...і їхня частка серед проб з мовленням не менша за цю


def transcribe(wav: Path, lang: str, model: str, backend: str,
               duration: float, work: Path) -> dict:
    """-> {"languages": [...], "probes": [...], "segments": [{start,end,text,lang}]}"""
    if backend == "auto":
        backend = "mlx" if platform.system() == "Darwin" else "faster"

    if lang != "auto":
        return {"languages": [lang], "probes": [],
                "segments": _run(wav, lang, model, backend)}

    probes = _probe_languages(wav, duration, model, backend, work / "lang_probes")
    spans = _language_spans(probes, duration)
    if not spans:
        log("мовлення в пробах не знайдено — прогін з автодетекцією whisper")
        return {"languages": [], "probes": probes,
                "segments": _run(wav, None, model, backend)}

    uniq = []
    for sp in spans:
        if sp["lang"] not in uniq:
            uniq.append(sp["lang"])

    if len(spans) == 1:
        log(f"мова запису: {uniq[0]}")
        return {"languages": uniq, "probes": probes,
                "segments": _run(wav, uniq[0], model, backend)}

    log(f"мови запису: {', '.join(uniq)} — транскрибую {len(spans)} відрізків окремо")
    segments = []
    for i, sp in enumerate(spans):
        log(f"  відрізок {i + 1}/{len(spans)}: {ts(sp['start'])}–{ts(sp['end'])} ({sp['lang']})")
        clip = work / "lang_spans" / f"{i:02d}.wav"
        _cut(wav, sp["start"], sp["end"] - sp["start"], clip)
        for s in _run(clip, sp["lang"], model, backend):
            s["start"] += sp["start"]
            s["end"] += sp["start"]
            segments.append(s)
        clip.unlink()  # відрізки сумарно важать як увесь запис — не кешуємо
    segments.sort(key=lambda s: s["start"])
    return {"languages": uniq, "probes": probes, "segments": segments}


def _probe_languages(wav: Path, duration: float, model: str, backend: str,
                     probes_dir: Path) -> list:
    """Мова коротких кліпів рівномірно по запису. Тиша (порожня транскрипція) -> lang=None."""
    n = 1 if duration <= PROBE_LEN * 2 else min(PROBE_MAX, max(2, int(duration / 180)))
    log(f"визначаю мови: {n} проб по {int(PROBE_LEN)}с")
    probes = []
    for i in range(n):
        t = max(0.0, (i + 0.5) * duration / n - PROBE_LEN / 2)
        clip = probes_dir / f"{int(t):05d}.wav"
        if not clip.exists():
            _cut(wav, t, min(PROBE_LEN, max(1.0, duration - t)), clip)
        segs = _run(clip, None, model, backend)
        lang = segs[0].get("lang") if segs else None
        probes.append({"t": t, "lang": lang})
        log(f"  [{i + 1}/{n}] {ts(t)} -> {lang or 'тиша'}")
    return probes


def _language_spans(probes: list, duration: float) -> list:
    """Проби -> відрізки [{start, end, lang}]. Рідкісні мови (нижче порогів)
    вливаються в сусідній відрізок — одна англійська фраза в українському міті
    не має різати запис."""
    voiced = [p for p in probes if p["lang"]]
    if not voiced:
        return []
    counts = {}
    for p in voiced:
        counts[p["lang"]] = counts.get(p["lang"], 0) + 1
    dominant = max(counts, key=counts.get)
    majors = {l for l, c in counts.items()
              if c >= MIN_PROBES and c / len(voiced) >= MIN_SHARE} or {dominant}

    prev = None
    groups = []
    for p in voiced:
        lang = p["lang"] if p["lang"] in majors else (prev or dominant)
        prev = lang
        if groups and groups[-1]["lang"] == lang:
            groups[-1]["last"] = p["t"]
        else:
            groups.append({"lang": lang, "first": p["t"], "last": p["t"]})

    if len(groups) == 1:
        return [{"start": 0.0, "end": duration, "lang": groups[0]["lang"]}]

    spans = []
    for i, g in enumerate(groups):
        start = 0.0 if i == 0 else spans[-1]["end"]
        end = duration if i == len(groups) - 1 else \
            (g["last"] + groups[i + 1]["first"] + PROBE_LEN) / 2
        spans.append({"start": start, "end": end, "lang": g["lang"]})
    return spans


def _cut(wav: Path, start: float, dur: float, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-ss", f"{start:.3f}", "-t", f"{dur:.3f}", "-i", str(wav),
        "-c", "copy", str(dst),
    ])


def _run(wav: Path, lang, model: str, backend: str) -> list:
    if backend == "mlx":
        return _run_mlx(wav, lang, model)
    return _run_faster(wav, lang, model)


def _run_mlx(wav: Path, lang, model: str) -> list:
    try:
        import mlx_whisper  # type: ignore
    except ImportError:
        from .utils import die
        die("немає mlx-whisper. `pip install mlx-whisper` або --asr-backend faster")
    repo = model if "/" in model else f"mlx-community/whisper-{model}"
    res = mlx_whisper.transcribe(
        str(wav),
        path_or_hf_repo=repo,
        language=lang,
        condition_on_previous_text=False,
    )
    detected = lang or res.get("language")
    return [
        {"start": float(s["start"]), "end": float(s["end"]),
         "text": s["text"].strip(), "lang": detected}
        for s in res["segments"] if s["text"].strip()
    ]


_FASTER_CACHE = {}


def _run_faster(wav: Path, lang, model: str) -> list:
    try:
        from faster_whisper import WhisperModel  # type: ignore
    except ImportError:
        from .utils import die
        die("немає faster-whisper. `pip install faster-whisper`")
    if model not in _FASTER_CACHE:
        _FASTER_CACHE[model] = WhisperModel(model, device="auto", compute_type="int8")
    segs, info = _FASTER_CACHE[model].transcribe(
        str(wav),
        language=lang,
        vad_filter=True,
        condition_on_previous_text=False,
    )
    out = []
    for s in segs:
        if s.text.strip():
            out.append({"start": float(s.start), "end": float(s.end),
                        "text": s.text.strip(), "lang": lang or info.language})
    return out
