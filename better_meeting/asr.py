"""Етап 2: транскрипція з таймкодами (mlx-whisper або faster-whisper).

--lang uk        -> один прогін цією мовою.
--lang auto      -> повний прогін КОЖНОЮ з мов --langs (дефолт uk,ru,en),
                    потім злиття: таймлайн покривається сегментами тієї мови,
                    якій whisper дав кращу впевненість (avg_logprob) на цій
                    ділянці. Працює для будь-якого чергування мов у записі —
                    аж до перемикання мови між сусідніми репліками.

Кожен прогін кешується окремо (pass_<lang>.json у робочій теці) — падіння на
другій мові не змушує переганяти першу. Кожен сегмент має поле "lang".
"""

import platform
from pathlib import Path

from .utils import load, log, save


def transcribe(wav: Path, lang: str, langs: list, model: str, backend: str,
               work: Path) -> list:
    """-> [{start, end, text, lang}], відсортовані по часу."""
    if backend == "auto":
        backend = "mlx" if platform.system() == "Darwin" else "faster"

    if lang != "auto":
        return [_public(s) for s in _run(wav, lang, model, backend)]

    passes = []
    for l in langs:
        cache = work / f"pass_{l}.json"
        if cache.exists():
            segs = load(cache)
            log(f"прогін [{l}]: з кешу, {len(segs)} сегментів")
        else:
            log(f"прогін [{l}]")
            segs = _run(wav, l, model, backend)
            save(cache, segs)
        passes.append(segs)

    merged = _merge(passes)
    shares = {}
    for s in merged:
        shares[s["lang"]] = shares.get(s["lang"], 0) + 1
    log("злито: " + ", ".join(f"{l}: {n}" for l, n in
                              sorted(shares.items(), key=lambda kv: -kv[1])))
    return [_public(s) for s in merged]


def _public(s: dict) -> dict:
    return {"start": s["start"], "end": s["end"], "text": s["text"], "lang": s["lang"]}


def _merge(passes: list) -> list:
    """Жадібне покриття таймлайну: у кожній точці беремо сегмент з найкращим
    avg_logprob серед тих, що її накривають. Сегменти-галюцинації (стандартна
    whisper-евристика: високий no_speech і низький logprob) відкидаються."""
    segs = [s for p in passes for s in p
            if not (s["nospeech"] > 0.6 and s["score"] < -1.0)]
    if not segs:
        return []
    segs.sort(key=lambda s: s["start"])

    out = []
    cursor = segs[0]["start"]
    while True:
        cands = [s for s in segs
                 if s["end"] > cursor + 0.2 and s["start"] <= cursor + 2.0]
        if not cands:
            rest = [s["start"] for s in segs if s["start"] > cursor]
            if not rest:
                break
            cursor = min(rest)
            continue
        best = max(cands, key=lambda s: s["score"])
        out.append(best)
        cursor = best["end"]
    return out


def _run(wav: Path, lang: str, model: str, backend: str) -> list:
    if backend == "mlx":
        return _run_mlx(wav, lang, model)
    return _run_faster(wav, lang, model)


def _run_mlx(wav: Path, lang: str, model: str) -> list:
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
    return [
        {"start": float(s["start"]), "end": float(s["end"]),
         "text": s["text"].strip(), "lang": lang,
         "score": float(s.get("avg_logprob", 0.0)),
         "nospeech": float(s.get("no_speech_prob", 0.0))}
        for s in res["segments"] if s["text"].strip()
    ]


_FASTER_CACHE = {}


def _run_faster(wav: Path, lang: str, model: str) -> list:
    try:
        from faster_whisper import WhisperModel  # type: ignore
    except ImportError:
        from .utils import die
        die("немає faster-whisper. `pip install faster-whisper`")
    if model not in _FASTER_CACHE:
        _FASTER_CACHE[model] = WhisperModel(model, device="auto", compute_type="int8")
    segs, _ = _FASTER_CACHE[model].transcribe(
        str(wav),
        language=lang,
        vad_filter=True,
        condition_on_previous_text=False,
    )
    return [
        {"start": float(s.start), "end": float(s.end),
         "text": s.text.strip(), "lang": lang,
         "score": float(s.avg_logprob), "nospeech": float(s.no_speech_prob)}
        for s in segs if s.text.strip()
    ]
