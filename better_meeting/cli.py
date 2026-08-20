"""CLI: розбір аргументів і запуск пайплайну."""

import argparse
import platform
from pathlib import Path

from .pipeline import run_pipeline


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="better-meeting: запис мітингу -> артефакти для чату")
    ap.add_argument("video", type=Path)
    ap.add_argument("--out", type=Path, default=None,
                    help="точна робоча тека (за замовч. <out-root>/<ім'я відео>)")
    ap.add_argument("--out-root", type=Path, default=Path("runs"),
                    help="корінь, у якому для кожного відео створюється своя тека")
    ap.add_argument("--force", action="store_true", help="перезробити всі етапи")
    ap.add_argument("--only", choices=["audio", "transcribe", "frames", "ocr", "bundle"],
                    help="зупинитись після етапу")

    ap.add_argument("--lang", default="auto", help="мова мітингу: uk / en / auto")
    ap.add_argument("--asr-backend", default="auto", choices=["auto", "mlx", "faster"])
    ap.add_argument("--asr-model", default="large-v3-turbo")

    ap.add_argument("--frame-interval", type=float, default=2.0)
    ap.add_argument("--cell-delta", type=int, default=14, help="поріг зміни зони кадру")
    ap.add_argument("--min-cells", type=int, default=3, help="скільки зон має змінитись")
    ap.add_argument("--max-gap", type=float, default=90.0, help="примусовий кадр раз на N сек")
    ap.add_argument("--frame-width", type=int, default=1920)

    ap.add_argument("--ocr", default="vision" if platform.system() == "Darwin" else "tesseract",
                    choices=["vision", "tesseract", "none"])
    ap.add_argument("--ocr-lang", default="en-US,uk-UA")
    ap.add_argument("--ocr-sim", type=float, default=0.97, help="поріг «той самий екран»")

    ap.add_argument("--pause", type=float, default=8.0, help="від скількох секунд тиша йде в таймлайн")

    ap.add_argument("--max-shots", type=int, default=30, help="скільки скріншотів класти в artifacts")
    ap.add_argument("--shot-width", type=int, default=1400)
    ap.add_argument("--shot-quality", type=int, default=72)
    ap.add_argument("--no-label", action="store_true", help="не випалювати таймкод на кадрі")
    ap.add_argument("--sheet", type=int, default=0, help="склеїти по N кадрів у сітку (0 = вимкнено)")

    ap.add_argument("--summarize", action="store_true", help="ще й прогнати через модель у runbook.md")
    ap.add_argument("--llm", default="claude", choices=["claude", "litellm"])
    ap.add_argument("--model", default="claude-sonnet-4-6")
    ap.add_argument("--max-chars", type=int, default=120000)
    return ap


def resolve_out(args) -> Path:
    """Кожне відео -> власна тека. --out має пріоритет, інакше <out-root>/<stem>."""
    return args.out if args.out is not None else args.out_root / args.video.stem


def main() -> None:
    args = build_parser().parse_args()
    args.out = resolve_out(args)
    run_pipeline(args)
