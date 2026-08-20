"""Склейка етапів. Кожен етап кешується в --out, --force перезробить."""

import shutil

from .asr import transcribe
from .audio import extract_audio
from .bundle import write_bundle
from .frames import extract_full_frames, pick_keyframes, sample_thumbs
from .ocr import ocr_frames
from .utils import die, load, log, probe_duration, save


def run_pipeline(a) -> None:
    if not a.video.exists():
        die(f"немає файлу {a.video}")
    a.out.mkdir(parents=True, exist_ok=True)
    log(f"робоча тека: {a.out}")

    wav = a.out / "audio.wav"
    f_transcript = a.out / "transcript.json"
    f_keyframes = a.out / "keyframes.json"
    f_screen = a.out / "screen.json"
    d_thumbs = a.out / "thumbs"
    d_frames = a.out / "frames"
    art = a.out / "artifacts"

    if a.force or not wav.exists():
        extract_audio(a.video, wav)
    if a.only == "audio":
        return

    if a.force or not f_transcript.exists():
        save(f_transcript, transcribe(wav, a.lang, a.asr_model, a.asr_backend))
    transcript = load(f_transcript)
    log(f"транскрипт: {len(transcript)} сегментів")
    if a.only == "transcribe":
        return

    if a.force or not f_keyframes.exists():
        if a.force and d_thumbs.exists():
            shutil.rmtree(d_thumbs)
        save(f_keyframes, pick_keyframes(
            sample_thumbs(a.video, d_thumbs, a.frame_interval),
            a.cell_delta, a.min_cells, a.max_gap))
    frames = extract_full_frames(a.video, load(f_keyframes), d_frames, a.frame_width)
    if a.only == "frames":
        return

    if a.ocr == "none":
        screen = []
    else:
        if a.force or not f_screen.exists():
            save(f_screen, ocr_frames(frames, a.ocr, a.ocr_lang.split(","), a.ocr_sim))
        screen = load(f_screen)
    if a.only == "ocr":
        return

    write_bundle(
        art, transcript, screen, frames, probe_duration(a.video),
        max_shots=a.max_shots,
        shot_width=a.shot_width,
        shot_quality=a.shot_quality,
        draw_label=not a.no_label,
        sheet=a.sheet,
        pause=a.pause,
    )
