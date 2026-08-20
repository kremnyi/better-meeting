"""Етап 1: витягування аудіодоріжки під ASR."""

from pathlib import Path

from .utils import log, need, run


def extract_audio(video: Path, wav: Path) -> None:
    need("ffmpeg")
    log("витягую аудіо")
    run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(video),
        "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
        str(wav),
    ])
