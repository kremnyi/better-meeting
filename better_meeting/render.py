"""Рендер текстових артефактів: transcript.md і timeline.md."""

from .utils import ts


def _is_multilang(transcript: list) -> bool:
    return len({s.get("lang") for s in transcript if s.get("lang")}) > 1


def render_transcript(transcript: list) -> str:
    multi = _is_multilang(transcript)
    lines = ["# Транскрипт", ""]
    if multi:
        lines[0] += "\n\nЗапис багатомовний — код мови вказано в кожному рядку."
    for seg in transcript:
        tag = f" [{seg['lang']}]" if multi and seg.get("lang") else ""
        lines.append(f"[{ts(seg['start'])}]{tag} {seg['text']}")
    return "\n".join(lines) + "\n"


def render_timeline(transcript: list, screen: list, shots_by_t: dict,
                    pause_threshold: float, stats: str = "") -> str:
    multi = _is_multilang(transcript)
    items, prev_end = [], None
    for seg in transcript:
        if prev_end is not None and seg["start"] - prev_end >= pause_threshold:
            items.append((prev_end, "PAUSE",
                          f"[тиша {int(seg['start'] - prev_end)}с]"))
        tag = f"[{seg['lang']}] " if multi and seg.get("lang") else ""
        items.append((seg["start"], "SPEECH", tag + seg["text"]))
        prev_end = seg["end"]

    for ev in screen:
        body = "\n".join("    " + l for l in ev["added"][:40]) if ev["added"] \
            else "    (екран змінився, тексту не розпізнано)"
        shot = shots_by_t.get(round(ev["t"], 3))
        items.append((ev["t"], "SCREEN", (body, shot)))

    items.sort(key=lambda x: x[0])
    out = ["# Таймлайн", ""]
    if stats:
        out += [stats, ""]
    out += ["МОВА — транскрипція. ЕКРАН — тільки НОВІ рядки, що з'явились на екрані (OCR).",
            "Посилання на скріншот стоїть там, де він є у теці screens/.", ""]
    for t, kind, body in items:
        if kind == "SPEECH":
            out.append(f"[{ts(t)}] МОВА: {body}")
        elif kind == "PAUSE":
            out.append(f"[{ts(t)}] {body}")
        else:
            text, shot = body
            head = f"[{ts(t)}] ЕКРАН"
            if shot:
                head += f" (скріншот: {shot})"
            out.append(f"{head}:\n{text}")
    return "\n".join(out) + "\n"
