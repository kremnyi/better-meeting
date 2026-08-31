"""better-meeting — витягує з відеозапису зустрічі всі дані (мова + екран)
у самодостатню теку artifacts/, яку зовнішня модель бере як повний контекст.

Всередині інструмента мовних моделей немає — він лише екстрактор.

Пайплайн і його етапи розкладені по модулях:

  utils      дрібні хелпери: таймкоди, лог, subprocess, json
  audio      1. ffmpeg -> 16kHz mono wav
  asr        2. mlx-whisper / faster-whisper -> сегменти з таймкодами
  frames     3-5. прев'ю -> grid-diff -> повнорозмірні кадри
  ocr        6. macOS Vision / tesseract -> текст + діф нових рядків
  render     рендер transcript.md / timeline.md
  shots      відбір і підпис скріншотів
  bundle     7. збирання теки artifacts/
  pipeline   склейка етапів з кешуванням у теці відео
  cli        argparse + main()
"""

__version__ = "0.3"
