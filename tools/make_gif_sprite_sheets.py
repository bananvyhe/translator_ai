import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Tuple

from PIL import Image, ImageSequence


@dataclass
class FrameData:
    image: Image.Image
    duration_ms: int
    crop_box: Optional[Tuple[int, int, int, int]]
    offset: Tuple[int, int]


def iter_gif_files(root: Path, output_root: Path) -> Iterable[Path]:
    for path in sorted(root.rglob("*.gif")):
        if not path.is_file():
            continue
        if output_root in path.parents:
            continue
        yield path


def extract_frames(gif_path: Path) -> List[FrameData]:
    with Image.open(gif_path) as im:
        canvas_size = im.size
        frames: List[FrameData] = []
        canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
        previous_canvas = canvas.copy()
        previous_disposal = 0

        for index, frame in enumerate(ImageSequence.Iterator(im)):
            frame_rgba = frame.convert("RGBA")

            if index > 0:
                if previous_disposal == 2:
                    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
                elif previous_disposal == 3:
                    canvas = previous_canvas.copy()

            previous_canvas = canvas.copy()
            canvas.alpha_composite(frame_rgba)

            bbox = canvas.getbbox()
            if bbox is None:
                cropped = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
                offset = (0, 0)
            else:
                cropped = canvas.crop(bbox)
                offset = (bbox[0], bbox[1])

            duration = int(frame.info.get("duration", im.info.get("duration", 100)) or 100)
            frames.append(
                FrameData(
                    image=cropped,
                    duration_ms=duration,
                    crop_box=bbox,
                    offset=offset,
                )
            )

            previous_disposal = frame.info.get("disposal", im.info.get("disposal", 0)) or 0

        return frames


def build_sprite_sheet(frames: List[FrameData], padding: int) -> Image.Image:
    if not frames:
        raise ValueError("GIF has no frames")

    cell_w = max(frame.image.width for frame in frames)
    cell_h = max(frame.image.height for frame in frames)
    cols = max(1, math.ceil(math.sqrt(len(frames))))
    rows = math.ceil(len(frames) / cols)
    sheet_w = cols * cell_w + max(0, cols - 1) * padding
    sheet_h = rows * cell_h + max(0, rows - 1) * padding

    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        x = (index % cols) * (cell_w + padding)
        y = (index // cols) * (cell_h + padding)
        sheet.alpha_composite(frame.image, (x, y))

    return sheet


def process_gif(gif_path: Path, output_root: Path, padding: int) -> dict:
    frames = extract_frames(gif_path)
    sheet = build_sprite_sheet(frames, padding=padding)

    output_root.mkdir(parents=True, exist_ok=True)
    sheet_path = output_root / f"{gif_path.stem}.sprite_sheet.png"
    sheet.save(sheet_path)

    manifest = {
        "source": str(gif_path),
        "sheet": str(sheet_path),
        "frame_count": len(frames),
        "sheet_size": [sheet.width, sheet.height],
        "frames": [
            {
                "index": index,
                "duration_ms": frame.duration_ms,
                "width": frame.image.width,
                "height": frame.image.height,
                "offset": list(frame.offset),
                "crop_box": list(frame.crop_box) if frame.crop_box else None,
            }
            for index, frame in enumerate(frames)
        ],
    }

    manifest_path = output_root / f"{gif_path.stem}.sprite_sheet.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Build sprite sheets from animated GIFs.")
    parser.add_argument("--input", default=r"D:\giif", help="Input folder with GIFs")
    parser.add_argument(
        "--output",
        default=None,
        help="Output folder for sprite sheets (default: <input>\\sprite_sheets)",
    )
    parser.add_argument("--padding", type=int, default=2, help="Padding between frames in the sheet")
    args = parser.parse_args()

    input_root = Path(args.input)
    output_root = Path(args.output) if args.output else input_root / "sprite_sheets"
    output_root.mkdir(parents=True, exist_ok=True)

    gifs = list(iter_gif_files(input_root, output_root))
    if not gifs:
        print(f"No GIF files found in {input_root}")
        return 1

    for gif_path in gifs:
        manifest = process_gif(gif_path, output_root, padding=args.padding)
        print(f"{gif_path.name}: {manifest['frame_count']} frames -> {manifest['sheet']}")

    print(f"Done. Output: {output_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
