#!/usr/bin/env python3
"""
better-meeting — CLI

Чистий екстрактор: жодних мовних моделей всередині.

Вхід: відеозапис зустрічі (mp4/mov/mkv) — дейлік, демо, воркшоп, будь-що.
Вихід: для КОЖНОГО відео — власна тека runs/<ім'я відео>/ (корінь змінюється
       через --out-root, точна тека — через --out). Усередині artifacts/ —
       повний витяг даних: транскрипт з таймкодами, таймлайн, текст з екрана,
       скріншоти, і PROMPT.md — вступна інструкція для зовнішньої моделі.
       Віддаєш теку своїй нейронці — і спілкуєшся «з відео».

Точкові запити для зовнішньої моделі (результат — у stdout):
  bm frame VIDEO -t MM:SS   один кадр на таймкоді
  bm ocr   VIDEO -t MM:SS   OCR кадру на таймкоді (або: bm ocr image.jpg)

Пайплайн `bm extract` (реалізація — у пакеті better_meeting/):
  1. audio      ffmpeg -> 16kHz mono wav                   better_meeting/audio.py
  2. transcribe без --lang — повний прогін КОЖНОЮ з     better_meeting/asr.py
                мов --langs (uk,ru,en) і злиття найкращих
                сегментів по впевненості whisper
                (mlx-whisper / faster-whisper)
  3. thumbs     ffmpeg -> дрібні кадри раз на N сек        better_meeting/frames.py
  4. keyframes  grid-diff -> тільки де екран змінився      better_meeting/frames.py
  5. frames     повнорозмірний кадр для відібраних тайм.   better_meeting/frames.py
  6. ocr        macOS Vision / tesseract + діф рядків      better_meeting/ocr.py
  7. bundle     artifacts/: transcript, timeline, screens/ better_meeting/bundle.py

Кожен етап кешується в робочій теці відео. --force щоб перезробити.
"""

from better_meeting.cli import main

if __name__ == "__main__":
    main()
