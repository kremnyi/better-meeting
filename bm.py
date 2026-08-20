#!/usr/bin/env python3
"""
better-meeting v0.2 — CLI

Вхід: запис мітингу (mp4/mov/mkv).
Вихід: для КОЖНОГО відео — власна тека runs/<ім'я відео>/ (корінь змінюється
       через --out-root, точна тека — через --out). Усередині artifacts/ —
       транскрипт, таймлайн, відібрані скріншоти, промпт та інструкція
       «що з цим робити». Все це руками кидається в чат-бота.

Пайплайн (реалізація — у пакеті better_meeting/):
  1. audio      ffmpeg -> 16kHz mono wav                   better_meeting/audio.py
  2. transcribe mlx-whisper / faster-whisper з таймкодами  better_meeting/asr.py
  3. thumbs     ffmpeg -> дрібні кадри раз на N сек        better_meeting/frames.py
  4. keyframes  grid-diff -> тільки де екран змінився      better_meeting/frames.py
  5. frames     повнорозмірний кадр для відібраних тайм.   better_meeting/frames.py
  6. ocr        macOS Vision / tesseract + діф рядків      better_meeting/ocr.py
  7. bundle     artifacts/: transcript, timeline, screens/ better_meeting/bundle.py
  8. summarize  (опційно, --summarize) -> runbook.md       better_meeting/summarize.py

Кожен етап кешується в робочій теці відео. --force щоб перезробити.
"""

from better_meeting.cli import main

if __name__ == "__main__":
    main()
