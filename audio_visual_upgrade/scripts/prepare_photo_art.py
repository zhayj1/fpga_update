#!/usr/bin/env python3
"""Prepare the three approved S01 photos without changing audio or RTL."""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / "music_screen"
sys.path.insert(0, str(BASE / ".pylibs"))
sys.path.insert(0, str(BASE / "scripts"))
from PIL import Image, ImageDraw, ImageFilter, ImageOps
from cover_circle import correct_circle
import mk_bg_style as bg_style

SOURCES = tuple(ROOT / "assets_in" / "s01_card_sources" / name for name in (
    "S01_1_source.jpg", "S01_2_source.png", "S01_3_source.png"))
PACK = ROOT / "output" / "card_art_s01"
PREVIEW = ROOT / "assets_out" / "S01_card_art_preview.png"
STYLE = {"zoom": 1.15, "blur": 24.0, "saturation": 0.75,
         "top": 0.10, "bottom": 0.62, "tint": 0.45}
KEY = (255, 0, 255)
# Source-pixel square crops: match photo 1's subject scale and right-hand framing.
# These do not affect the full-photo background processing below.
COVER_CROPS = {2: (410, 425, 1510, 1525),
               3: (400, 360, 1500, 1460)}


def available() -> bool:
    return all(path.is_file() for path in SOURCES)


def render_assets(destination: Path) -> list[dict]:
    """Use exactly the existing background algorithm and loader-compatible BMP3."""
    if not available():
        raise FileNotFoundError("The three approved S01 photo sources are missing")
    destination.mkdir(parents=True, exist_ok=True)
    records = []
    for group, source in enumerate(SOURCES, 1):
        with Image.open(source) as image:
            photo = ImageOps.exif_transpose(image).convert("RGB")
        crop_box = COVER_CROPS.get(group)
        if crop_box is None:
            # Keep the approved first cover unchanged.
            cover = ImageOps.fit(photo, (240, 240), Image.Resampling.LANCZOS,
                                 centering=(0.5, 0.5))
        else:
            left, top, right, bottom = crop_box
            if not (0 <= left < right <= photo.width
                    and 0 <= top < bottom <= photo.height
                    and right - left == bottom - top):
                raise ValueError(f"Invalid cover crop for {source.name}: {crop_box}")
            cover = photo.crop(crop_box).resize((240, 240), Image.Resampling.LANCZOS)
        mask = Image.new("L", (240, 240), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, 239, 239), fill=255)
        keyed = Image.new("RGB", (240, 240), KEY)
        keyed.paste(cover, (0, 0), mask)
        keyed = correct_circle(keyed)

        dominant = bg_style.dominant_rgb(photo)
        background = bg_style.cover_resize(photo, 640, 480, STYLE["zoom"])
        background = background.filter(ImageFilter.GaussianBlur(STYLE["blur"]))
        background = Image.blend(background.convert("L").convert("RGB"),
                                 background, STYLE["saturation"])
        gradient = bg_style.gradient_mask(640, 480, dominant, STYLE["top"],
                                          STYLE["bottom"], STYLE["tint"])
        background = bg_style.make_dark(background, gradient)
        for kind, result in (("CV", keyed), ("BG", background)):
            name = f"S01{kind}{group}.BMP"
            bg_style.write_bmp3(str(destination / name), result)
            record = {"file": name, "kind": kind, "size": list(result.size),
                      "source": source.relative_to(ROOT).as_posix()}
            if kind == "CV":
                record.update(key="FF00FF", mask="circle",
                              display_correction="horizontal 5/6",
                              crop="right-subject-square" if crop_box else "center-square")
                if crop_box:
                    record["crop_box"] = list(crop_box)
            else:
                record["style"] = STYLE.copy()
            records.append(record)
    return records


def preview(directory: Path) -> None:
    sheet = Image.new("RGB", (1920, 480))
    for group in (1, 2, 3):
        with Image.open(directory / f"S01BG{group}.BMP") as image:
            frame = image.convert("RGB")
        with Image.open(directory / f"S01CV{group}.BMP") as image:
            cover = image.convert("RGB")
        mask = Image.new("L", cover.size)
        mask.putdata([0 if pixel == KEY else 255 for pixel in cover.getdata()])
        frame.paste(cover, (140, 45), mask)
        draw = ImageDraw.Draw(frame)
        draw.rectangle((8, 8, 112, 29), fill=(0, 0, 0))
        draw.text((15, 13), f"S01 / GROUP {group}", fill=(255, 255, 255))
        sheet.paste(frame, ((group - 1) * 640, 0))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="Update only six S01 images and the existing card manifest")
    args = parser.parse_args()
    import prepare_card as card
    old_manifest = json.loads((card.OUT / "manifest.json").read_text(encoding="utf-8"))
    before = {record["name"]: record["sha256"] for record in card.inspect_assets()}
    replacements = render_assets(PACK)
    for record in replacements:
        image = card.read_bmp(PACK / record["file"])
        expected = (240, 240) if record["kind"] == "CV" else (640, 480)
        if image.size != expected:
            raise ValueError(f"Invalid image size: {record['file']}")
        if record["kind"] == "CV" and image.getpixel((0, 0)) != KEY:
            raise ValueError("Missing exact magenta colour key")
    preview(PACK)
    if args.apply:
        for record in replacements:
            shutil.copy2(PACK / record["file"], card.OUT / record["file"])
        # Replace the six provenance entries; preserve all song/audio metadata.
        by_name = {record["file"]: record for record in replacements}
        old_manifest["songs"] = [by_name.get(record.get("file"), record)
                                  for record in old_manifest["songs"]]
        after = card.inspect_assets()
        touched = set(by_name)
        for record in after:
            if record["name"] not in touched and before[record["name"]] != record["sha256"]:
                raise ValueError(f"Unrelated file changed: {record['name']}")
        old_manifest["files"] = after
        old_manifest["artwork_preview"] = PREVIEW.relative_to(ROOT).as_posix()
        (card.OUT / "manifest.json").write_text(
            json.dumps(old_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        card.make_preview()
        card.check_card()
    print(json.dumps({"pack": str(PACK), "preview": str(PREVIEW),
                      "applied": args.apply, "files": len(replacements)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
