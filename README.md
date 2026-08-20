# better-meeting

Turn a screen-share meeting recording into a **self-contained folder of artifacts** you can drop straight into a chatbot: a timestamped transcript, a merged timeline, the handful of screenshots that actually matter, and a ready-to-paste prompt telling the model what to do with them.

No cloud upload of the video, no manual scrubbing. Point it at an `.mp4`/`.mov`/`.mkv`, get back a folder.

```bash
bm meeting.mp4
# -> runs/meeting/artifacts/  (transcript.md, timeline.md, screens/, PROMPT.md, HOW-TO.md)
```

## What it does

The pipeline runs in cached stages — each writes into the video's working folder, and re-running skips finished stages (`--force` redoes them):

| # | Stage      | What happens                                                       |
|---|------------|--------------------------------------------------------------------|
| 1 | `audio`    | `ffmpeg` extracts a 16 kHz mono WAV                                 |
| 2 | `transcribe` | Whisper (mlx on macOS / faster-whisper elsewhere) with timecodes |
| 3 | `frames`   | sample thumbnails, keep only keyframes where the screen changed    |
| 4 | `ocr`      | macOS Vision / tesseract reads each keyframe, diffs new on-screen text |
| 5 | `bundle`   | assembles `artifacts/`: transcript, timeline, selected screenshots |
| 6 | `summarize`| *(optional, `--summarize`)* runs the timeline through an LLM into `runbook.md` |

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
│   └── artifacts/          <- this is what you hand to the chatbot
│       ├── transcript.md
│       ├── timeline.md
│       ├── screens/ · screens_index.md
│       ├── PROMPT.md
│       └── HOW-TO.md
└── onboarding-call/
    └── ...
```

- Change the root with `--out-root some/dir` (folders become `some/dir/<video-name>/`).
- Pin an exact folder with `--out path/to/dir` (overrides the per-video naming).

Because the folder name is derived from the video, re-running the **same** recording reuses its cache; a **different** recording lands in a **different** folder.

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
- **`--summarize`** uses the `claude` CLI by default, or `--llm litellm` with `pip install -e ".[litellm]"`.

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
| `--lang uk\|en\|auto`  | `auto`         | meeting language                                    |
| `--asr-model NAME`     | `large-v3-turbo` | Whisper model                                     |
| `--frame-interval SEC` | `2.0`          | thumbnail sampling interval                          |
| `--max-shots N`        | `30`           | how many screenshots to keep in `artifacts/`        |
| `--ocr vision\|tesseract\|none` | `vision` on macOS | OCR backend                            |
| `--summarize`          | off            | also produce `artifacts/runbook.md` via an LLM      |

Run `bm --help` for the full list.

### Examples

```bash
# Ukrainian meeting, produce a runbook too
bm standup.mov --lang uk --summarize

# batch a directory — each file gets its own folder under runs/
for f in recordings/*.mp4; do bm "$f"; done

# custom output root, keep more screenshots
bm demo.mkv --out-root out --max-shots 50
```

## How to use the artifacts

Open `artifacts/HOW-TO.md` — it explains the drop-in flow. In short: paste `PROMPT.md` into the chatbot, attach `timeline.md` and the images from `screens/`, and let the model produce the notes / runbook / doc you need.

## License

[Apache 2.0](LICENSE)
