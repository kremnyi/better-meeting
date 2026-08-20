# better-meeting

**Talk to your meeting recordings.** better-meeting is a pure extractor: it pulls *everything* out of a video — timestamped speech transcript, text that appeared on screen, key screenshots — into one self-contained folder. Hand that folder to any LLM as context, and ask it anything about the meeting.

**There is no LLM inside the tool.** It never summarizes, never interprets. Extraction is local and deterministic; the understanding is done by whatever model *you* connect — a chatbot you paste files into, or an agent that picks the folder up as a plugin.

Works for any kind of recording: a daily standup that's all talk, a technical demo full of screen changes, a workshop, a plain call.

```bash
bm meeting.mp4
# -> runs/meeting/artifacts/  (transcript.md, timeline.md, screens/, PROMPT.md, HOW-TO.md)
```

## What it extracts

The pipeline runs in cached stages — each writes into the video's working folder, and re-running skips finished stages (`--force` redoes them):

| # | Stage      | What happens                                                       |
|---|------------|--------------------------------------------------------------------|
| 1 | `audio`    | `ffmpeg` extracts a 16 kHz mono WAV                                 |
| 2 | `transcribe` | language detection across the whole recording, then Whisper (mlx on macOS / faster-whisper elsewhere) with timecodes |
| 3 | `frames`   | sample thumbnails, keep only keyframes where the screen changed    |
| 4 | `ocr`      | macOS Vision / tesseract reads each keyframe, diffs new on-screen text |
| 5 | `bundle`   | assembles `artifacts/`: transcript, timeline, screenshots, prompt  |

If OCR finds no readable text (low-res recording, or `--ocr none`), screenshots are still selected — evenly across the moments the screen changed — so a multimodal model can read them itself.

### Multilingual meetings

Whisper's built-in auto-detect samples only the **first 30 seconds** — useless for meetings that mix languages (a Ukrainian standup with English terms and Russian asides is an everyday case). `bm` doesn't guess:

When no language is pinned, it transcribes the whole recording **once per language** in `--langs` (default `uk,ru,en`), then merges: the timeline is covered by the segments from whichever pass Whisper was most confident about (`avg_logprob`) at that point. This survives *any* language mixing — down to the language switching between neighboring sentences — because every stretch of audio was decoded in every candidate language and the best decode wins locally. Hallucinated segments (Whisper's classic silence artifacts) are filtered by the standard `no_speech`/`logprob` heuristic.

The cost is proportional: 3 languages = 3 transcription passes. Each pass is cached separately (`pass_uk.json`, …), so an interrupted run resumes without redoing finished passes. If you know the meeting's language, pin it — `--lang uk` — for a single pass. Adjust the candidate set with `--langs uk,en` etc.

In multilingual recordings every transcript line carries its language tag (`[uk]`, `[en]`, `[ru]`), and `HOW-TO.md` reports the language share.

## One folder per video

Every recording gets **its own working folder** — outputs never collide or overwrite each other.

By default the folder is `runs/<video-name>/`:

```
runs/
├── standup-2026-08-20/
│   ├── audio.wav
│   ├── transcript.json
│   ├── keyframes.json
│   ├── thumbs/ · frames/
│   └── artifacts/          <- the interface: hand this folder to your LLM
│       ├── transcript.md   — timestamped speech
│       ├── timeline.md     — speech + new on-screen text + silences, merged
│       ├── screens/ · screens_index.md
│       ├── PROMPT.md       — intro instruction for the model
│       └── HOW-TO.md       — drop-in guide for a human
└── onboarding-call/
    └── ...
```

- Change the root with `--out-root some/dir` (folders become `some/dir/<video-name>/`).
- Pin an exact folder with `--out path/to/dir` (overrides the per-video naming).

Because the folder name is derived from the video, re-running the **same** recording reuses its cache; a **different** recording lands in a **different** folder.

## Prompts are plain text files

The intro prompt the model receives (`PROMPT.md`) and the human guide (`HOW-TO.md`) live as editable text in [better_meeting/prompts/](better_meeting/prompts/) — tweak them for your workflow without touching code. They are deliberately task-agnostic: they describe what the materials *are*, not what to build from them. What you ask the model is up to you.

## Install

Requires **Python 3.12+** and **ffmpeg/ffprobe** on your `PATH`.

```bash
git clone https://github.com/your-org/better-meeting.git
cd better-meeting

# with uv (recommended)
uv sync
uv run bm meeting.mp4

# or with pip
pip install -e .
bm meeting.mp4
```

### System dependencies

- **ffmpeg / ffprobe** — required (audio extraction, frame sampling, duration).
- **macOS** — Whisper via `mlx-whisper` and OCR via the built-in Vision framework work out of the box.
- **Linux / Windows** — install the faster-whisper backend and tesseract:
  ```bash
  pip install -e ".[faster]"   # faster-whisper ASR backend
  # + tesseract-ocr from your package manager, then run with: --ocr tesseract
  ```

## Usage

```bash
bm RECORDING.mp4 [options]
```

Common options:

| Option                 | Default        | Meaning                                             |
|------------------------|----------------|-----------------------------------------------------|
| `--out-root DIR`       | `runs`         | root that holds one folder per video                |
| `--out DIR`            | *(auto)*       | exact working folder (overrides per-video naming)   |
| `--force`              | off            | redo every stage, ignore cache                      |
| `--only STAGE`         | —              | stop after `audio`/`transcribe`/`frames`/`ocr`/`bundle` |
| `--lang uk\|en\|ru\|auto` | `auto`      | pin one language (single pass) or `auto` (pass per `--langs`, best merge) |
| `--langs L1,L2,...`    | `uk,ru,en`     | candidate languages tried when `--lang auto`        |
| `--asr-model NAME`     | `large-v3-turbo` | Whisper model                                     |
| `--frame-interval SEC` | `2.0`          | thumbnail sampling interval                          |
| `--max-shots N`        | `30`           | how many screenshots to keep in `artifacts/`        |
| `--ocr vision\|tesseract\|none` | `vision` on macOS | OCR backend                            |

Run `bm --help` for the full list.

## Point queries — tooling for agents

Besides the full pipeline, `bm` has point commands so an LLM agent can drill into a specific moment without re-running anything. All print their result to stdout (logs go to stderr):

```bash
# grab one frame at a timecode (prints the file path)
bm frame meeting.mp4 -t 12:40
# -> runs/meeting/frames_at/00-12-40.jpg

# OCR a frame at a timecode (prints the recognized text)
bm ocr meeting.mp4 -t 12:40

# OCR an existing image (e.g. a screenshot from artifacts/screens/)
bm ocr runs/meeting/artifacts/screens/007_00-14-10.jpg

# re-transcribe a time range in a specific language
bm transcript meeting.mp4 --from 10:00 --to 12:30 --lang en

# ...with any whisper option passed through, and JSON output
bm transcript meeting.mp4 --from 10:00 --to 12:30 --lang uk \
    -O temperature=0.2 -O initial_prompt="назви сервісів, реліз, стейджинг" --json
```

Timecodes accept `SS`, `MM:SS`, or `HH:MM:SS`. The typical agent loop: read `timeline.md`, spot a suspicious stretch, pull the exact frame with `bm frame`, or re-run just that stretch with `bm transcript` — a different language, a domain `initial_prompt` to fix mangled terms, whatever Whisper accepts via repeatable `-O key=value` (values parse as JSON).

`bm transcript` results are **cached by their full parameter set** (range + language + model + backend + options) under `runs/<name>/transcripts_at/` — repeating the same query returns instantly; `--force` recomputes. Frames land under `frames_at/`; use `-o out.jpg` to override.

### Examples

```bash
# Ukrainian meeting
bm standup.mov --lang uk

# low-res recording where OCR is hopeless — skip it, keep the screenshots
bm call-360p.mp4 --ocr none

# batch a directory — each file gets its own folder under runs/
for f in recordings/*.mp4; do bm "$f"; done

# custom output root, keep more screenshots
bm demo.mkv --out-root out --max-shots 50
```

## Talking to the video

`artifacts/` is the whole interface:

- **By hand**: open `artifacts/HOW-TO.md` — attach `timeline.md` + screenshots to a chat, paste `PROMPT.md`, then ask anything: "what did we decide about the release?", "what command did they run at 12:40?", "summarize each person's status".
- **Via an agent**: point your agent at the `artifacts/` folder; `PROMPT.md` tells it what the materials are. The agent reads the files (and looks at the screenshots itself, if multimodal) and answers on top of them.

## License

[Apache 2.0](LICENSE)
