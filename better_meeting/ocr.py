"""Етап 6: OCR кадрів і діф нових рядків на екрані."""

import difflib
import re
import subprocess

from .utils import die, log, need


def ocr_vision(path: str, langs: list) -> str:
    try:
        import Vision  # type: ignore
        from Foundation import NSURL  # type: ignore
    except ImportError:
        die("немає pyobjc. `pip install pyobjc-framework-Vision` або --ocr tesseract")
    url = NSURL.fileURLWithPath_(path)
    handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(url, None)
    req = Vision.VNRecognizeTextRequest.alloc().init()
    req.setRecognitionLevel_(0)            # accurate
    req.setUsesLanguageCorrection_(False)  # не «виправляти» команди
    req.setRecognitionLanguages_(langs)
    handler.performRequests_error_([req], None)
    lines = []
    for obs in (req.results() or []):
        cand = obs.topCandidates_(1)
        if cand:
            lines.append(str(cand[0].string()))
    return "\n".join(lines)


def ocr_tesseract(path: str, langs: list) -> str:
    need("tesseract")
    lang = "+".join(l.split("-")[0] for l in langs)
    res = subprocess.run(
        ["tesseract", path, "stdout", "-l", lang, "--psm", "6"],
        capture_output=True, text=True,
    )
    return res.stdout


def norm(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def added_lines(new: str, old: str) -> list:
    old_set = {norm(l) for l in old.splitlines() if norm(l)}
    out = []
    for line in new.splitlines():
        n = norm(line)
        if n and n not in old_set and len(n) > 1:
            out.append(line.rstrip())
    return out


def ocr_frames(frames: list, backend: str, langs: list, sim_threshold: float) -> list:
    log(f"OCR ({backend}) по {len(frames)} кадрах")
    fn = ocr_vision if backend == "vision" else ocr_tesseract
    events, prev_text = [], ""
    for i, fr in enumerate(frames):
        text = fn(fr["path"], langs)
        if prev_text and difflib.SequenceMatcher(None, norm(prev_text), norm(text)).ratio() > sim_threshold:
            continue
        new = added_lines(text, prev_text)
        if new or not prev_text:
            events.append({
                "t": fr["t"],
                "path": fr["path"],
                "added": new,
            })
        prev_text = text
        if (i + 1) % 25 == 0:
            log(f"  {i+1}/{len(frames)}")
    log(f"{len(events)} змістовних подій екрана")
    return events
