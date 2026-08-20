"""Промпти живуть у текстових файлах better_meeting/prompts/ — правляться без коду.

Тут лише завантаження. Інструмент сам НЕ викликає жодних мовних моделей:
PROMPT.md — вступна інструкція для зовнішньої моделі, якій віддадуть artifacts/.
"""

from importlib import resources


def _read(name: str) -> str:
    return (resources.files(__package__) / "prompts" / name).read_text(encoding="utf-8")


PROMPT = _read("PROMPT.md")
HOWTO = _read("HOWTO.md")
