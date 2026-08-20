"""Етап 2: транскрипція з таймкодами (mlx-whisper або faster-whisper)."""

import platform
from pathlib import Path

from .utils import die, log


def transcribe(wav: Path, lang: str, model: str, backend: str) -> list:
    if backend == "auto":
        backend = "mlx" if platform.system() == "Darwin" else "faster"
    if backend == "mlx":
        return _transcribe_mlx(wav, lang, model)
    return _transcribe_faster(wav, lang, model)


def _transcribe_mlx(wav: Path, lang: str, model: str) -> list:
    try:
        import mlx_whisper  # type: ignore
    except ImportError:
        die("немає mlx-whisper. `pip install mlx-whisper` або --asr-backend faster")
    repo = model if "/" in model else f"mlx-community/whisper-{model}"
    log(f"транскрибую (mlx-whisper, {repo})")
    res = mlx_whisper.transcribe(
        str(wav),
        path_or_hf_repo=repo,
        language=None if lang == "auto" else lang,
        condition_on_previous_text=False,
    )
    return [
        {"start": float(s["start"]), "end": float(s["end"]), "text": s["text"].strip()}
        for s in res["segments"] if s["text"].strip()
    ]


def _transcribe_faster(wav: Path, lang: str, model: str) -> list:
    try:
        from faster_whisper import WhisperModel  # type: ignore
    except ImportError:
        die("немає faster-whisper. `pip install faster-whisper`")
    log(f"транскрибую (faster-whisper, {model})")
    m = WhisperModel(model, device="auto", compute_type="int8")
    segs, _ = m.transcribe(
        str(wav),
        language=None if lang == "auto" else lang,
        vad_filter=True,
        condition_on_previous_text=False,
    )
    return [
        {"start": float(s.start), "end": float(s.end), "text": s.text.strip()}
        for s in segs if s.text.strip()
    ]
