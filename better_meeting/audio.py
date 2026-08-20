"""Етап 1: витягування аудіодоріжки під ASR."""

from pathlib import Path

from .utils import log, need, run


def extract_audio(video: Path, wav: Path,
                  start: float | None = None, duration: float | None = None) -> None:
    need("ffmpeg")
    log("витягую аудіо")
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    if start:
        cmd += ["-ss", f"{start:.3f}"]
    if duration is not None:
        cmd += ["-t", f"{duration:.3f}"]
    cmd += ["-i", str(video), "-vn", "-ac", "1", "-ar", "16000",
            "-c:a", "pcm_s16le", str(wav)]
    run(cmd)
