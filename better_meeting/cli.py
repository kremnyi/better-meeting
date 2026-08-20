"""CLI: розбір аргументів і запуск.

Підкоманди:
  extract  повний пайплайн: відео -> runs/<ім'я>/artifacts/  (дефолт: `bm video.mp4`)
  frame    точковий запит: один кадр на заданому таймкоді
  ocr      точковий запит: OCR кадру відео на таймкоді або готового зображення

`frame` і `ocr` — інструментарій для зовнішньої моделі: побачила в timeline.md
цікавий момент — дістала кадр чи перечитала текст, не переганяючи весь пайплайн.
Дані (шлях до кадру / розпізнаний текст) друкуються в stdout, лог — у stderr.
"""

import argparse
import platform
import sys
from pathlib import Path

from .pipeline import run_pipeline
from .utils import die, parse_ts, ts_file

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".tiff", ".bmp"}
COMMANDS = {"extract", "frame", "ocr"}


def _default_ocr_backend() -> str:
    return "vision" if platform.system() == "Darwin" else "tesseract"


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="bm",
        description="better-meeting: витягує всі дані з запису зустрічі для зовнішньої моделі")
    sub = ap.add_subparsers(dest="cmd", required=True)

    px = sub.add_parser("extract", help="повний пайплайн: відео -> artifacts/")
    px.add_argument("video", type=Path)
    px.add_argument("--out", type=Path, default=None,
                    help="точна робоча тека (за замовч. <out-root>/<ім'я відео>)")
    px.add_argument("--out-root", type=Path, default=Path("runs"),
                    help="корінь, у якому для кожного відео створюється своя тека")
    px.add_argument("--force", action="store_true", help="перезробити всі етапи")
    px.add_argument("--only", choices=["audio", "transcribe", "frames", "ocr", "bundle"],
                    help="зупинитись після етапу")

    px.add_argument("--lang", default="auto",
                    help="конкретна мова (uk/ru/en/...) = один прогін нею; "
                         "auto = повний прогін кожною з --langs зі злиттям найкращого")
    px.add_argument("--langs", default="uk,ru,en",
                    help="які мови проганяти при --lang auto (через кому)")
    px.add_argument("--asr-backend", default="auto", choices=["auto", "mlx", "faster"])
    px.add_argument("--asr-model", default="large-v3-turbo")

    px.add_argument("--frame-interval", type=float, default=2.0)
    px.add_argument("--cell-delta", type=int, default=14, help="поріг зміни зони кадру")
    px.add_argument("--min-cells", type=int, default=3, help="скільки зон має змінитись")
    px.add_argument("--max-gap", type=float, default=90.0, help="примусовий кадр раз на N сек")
    px.add_argument("--frame-width", type=int, default=1920)

    px.add_argument("--ocr", default=_default_ocr_backend(),
                    choices=["vision", "tesseract", "none"])
    px.add_argument("--ocr-lang", default="en-US,uk-UA")
    px.add_argument("--ocr-sim", type=float, default=0.97, help="поріг «той самий екран»")

    px.add_argument("--pause", type=float, default=8.0,
                    help="від скількох секунд тиша йде в таймлайн")

    px.add_argument("--max-shots", type=int, default=30,
                    help="скільки скріншотів класти в artifacts")
    px.add_argument("--shot-width", type=int, default=1400)
    px.add_argument("--shot-quality", type=int, default=72)
    px.add_argument("--no-label", action="store_true", help="не випалювати таймкод на кадрі")
    px.add_argument("--sheet", type=int, default=0,
                    help="склеїти по N кадрів у сітку (0 = вимкнено)")

    pf = sub.add_parser("frame", help="один кадр відео на заданому таймкоді")
    pf.add_argument("video", type=Path)
    pf.add_argument("-t", "--at", required=True, help="таймкод: SS / MM:SS / HH:MM:SS")
    pf.add_argument("-o", "--out", type=Path, default=None,
                    help="файл кадру (за замовч. <out-root>/<ім'я відео>/frames_at/<таймкод>.jpg)")
    pf.add_argument("--out-root", type=Path, default=Path("runs"))
    pf.add_argument("--width", type=int, default=1920)

    po = sub.add_parser("ocr", help="OCR: кадр відео на таймкоді або готове зображення")
    po.add_argument("target", type=Path, help="відео (потрібен --at) або зображення")
    po.add_argument("-t", "--at", default=None, help="таймкод: SS / MM:SS / HH:MM:SS")
    po.add_argument("--backend", default=_default_ocr_backend(),
                    choices=["vision", "tesseract"])
    po.add_argument("--lang", default="en-US,uk-UA")
    po.add_argument("--out-root", type=Path, default=Path("runs"))
    po.add_argument("--width", type=int, default=1920)
    return ap


def resolve_out(args) -> Path:
    """Кожне відео -> власна тека. --out має пріоритет, інакше <out-root>/<stem>."""
    return args.out if args.out is not None else args.out_root / args.video.stem


def _grab_at(video: Path, at: str, out: Path | None, out_root: Path, width: int) -> Path:
    from .frames import grab_frame
    if not video.exists():
        die(f"немає файлу {video}")
    t = parse_ts(at)
    path = out or out_root / video.stem / "frames_at" / f"{ts_file(t)}.jpg"
    path.parent.mkdir(parents=True, exist_ok=True)
    grab_frame(video, t, path, width)
    return path


def cmd_frame(a) -> None:
    print(_grab_at(a.video, a.at, a.out, a.out_root, a.width))


def cmd_ocr(a) -> None:
    from .ocr import ocr_tesseract, ocr_vision
    if a.target.suffix.lower() in IMAGE_EXTS:
        if not a.target.exists():
            die(f"немає файлу {a.target}")
        path = a.target
    else:
        if a.at is None:
            die("для відео потрібен таймкод: --at MM:SS")
        path = _grab_at(a.target, a.at, None, a.out_root, a.width)
    fn = ocr_vision if a.backend == "vision" else ocr_tesseract
    print(fn(str(path), a.lang.split(",")))


def main() -> None:
    argv = sys.argv[1:]
    # зворотна сумісність: `bm video.mp4 ...` == `bm extract video.mp4 ...`
    if argv and argv[0] not in COMMANDS and not argv[0].startswith("-"):
        argv = ["extract", *argv]
    a = build_parser().parse_args(argv)
    if a.cmd == "extract":
        a.out = resolve_out(a)
        run_pipeline(a)
    elif a.cmd == "frame":
        cmd_frame(a)
    else:
        cmd_ocr(a)
