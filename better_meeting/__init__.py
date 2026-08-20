"""better-meeting — запис мітингу -> артефакти для чат-бота.

Пайплайн і його етапи розкладені по модулях:

  utils      дрібні хелпери: таймкоди, лог, subprocess, json
  audio      1. ffmpeg -> 16kHz mono wav
  asr        2. mlx-whisper / faster-whisper -> сегменти з таймкодами
  frames     3-5. прев'ю -> grid-diff -> повнорозмірні кадри
  ocr        6. macOS Vision / tesseract -> текст + діф нових рядків
  render     рендер transcript.md / timeline.md
  shots      відбір, підпис і склейка скріншотів
  prompts    тексти PROMPT.md / HOW-TO.md / промпти самарі
  bundle     7. збирання теки artifacts/
  summarize  8. опційний прогін через модель у runbook.md
  pipeline   склейка етапів з кешуванням у --out
  cli        argparse + main()
"""

__version__ = "0.2"
