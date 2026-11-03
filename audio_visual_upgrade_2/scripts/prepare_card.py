#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate a small, deterministic SD-card image for the upgrade bring-up.

The source project already contains strict BMP3 assets and one WAV.  This
script keeps the source untouched, trims the WAV to 45 seconds for two named
tracks, makes 240x240 cover assets for the new centred cover window, and
emits a short manifest plus a PC-only preview sheet.
"""
from __future__ import annotations

import hashlib
import argparse
import json
import shutil
import struct
import wave
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError as exc:  # pragma: no cover - a clear operator error
    raise SystemExit("需要 Pillow；请使用工作区提供的 Python 运行时") from exc


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "music_screen_area_opt" / "card"
SOURCE_LRC = ROOT.parent / "music_screen_area_opt" / "card_out"
OUT = ROOT / "card"
PREVIEW = ROOT / "sim" / "card_layout_preview.png"
MAGENTA = (255, 0, 255)
BMP_HEADER = 54
COVER_CENTER = (260, 165)
COVER_SIZE = (240, 240)
COVER_ORIGIN = tuple(center - size // 2
                     for center, size in zip(COVER_CENTER, COVER_SIZE))
RESOURCE_IDS = {"FONT.HZK": 136, "ASC.HZK": 137}
for _song in (1, 2):
    for _field, _suffix in enumerate(("BG1.BMP", "BG2.BMP", "BG3.BMP",
                                     "CV1.BMP", "CV2.BMP", "CV3.BMP",
                                     ".WAV", ".LRC")):
        RESOURCE_IDS[f"S{_song:02d}{_suffix}"] = _song * 8 + _field


def bmp_stride(width: int) -> int:
    return ((width * 3 + 3) // 4) * 4


def read_bmp(path: Path) -> Image.Image:
    raw = path.read_bytes()
    if raw[:2] != b"BM":
        raise ValueError(f"{path.name}: BMP magic 错误")
    size, _r1, _r2, off = struct.unpack_from("<IHHI", raw, 2)
    ih, width, height, planes, bpp, compression = struct.unpack_from("<IiiHHI", raw, 14)
    if ((ih, planes, bpp, compression, off) != (40, 1, 24, 0, BMP_HEADER)
            or width <= 0 or height <= 0):
        raise ValueError(f"{path.name}: 不是严格 bottom-up BMP3")
    stride = bmp_stride(width)
    if size != BMP_HEADER + stride * height or len(raw) != size:
        raise ValueError(f"{path.name}: BMP 文件长度不匹配")
    image = Image.new("RGB", (width, height))
    px = image.load()
    for y in range(height):
        base = off + (height - 1 - y) * stride
        for x in range(width):
            b, g, r = raw[base + x * 3:base + x * 3 + 3]
            px[x, y] = (r, g, b)
    return image


def write_bmp24(path: Path, image: Image.Image) -> None:
    image = image.convert("RGB")
    width, height = image.size
    stride = bmp_stride(width)
    pad = b"\x00" * (stride - width * 3)
    body = bytearray()
    px = image.load()
    for y in range(height - 1, -1, -1):
        for x in range(width):
            r, g, b = px[x, y]
            body.extend((b, g, r))
        body.extend(pad)
    total = BMP_HEADER + len(body)
    header = struct.pack("<2sIHHI", b"BM", total, 0, 0, BMP_HEADER)
    info = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0,
                       len(body), 2835, 2835, 0, 0)
    path.write_bytes(header + info + body)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def trim_wav(source: Path, destination: Path, seconds: int = 45) -> int:
    with wave.open(str(source), "rb") as inp:
        params = inp.getparams()
        if (params.nchannels, params.sampwidth, params.framerate,
                params.comptype) != (2, 2, 48000, "NONE"):
            raise ValueError(f"{source.name}: 需要 48kHz 16bit stereo PCM")
        frames = min(inp.getnframes(), params.framerate * seconds)
        data = inp.readframes(frames)
    with wave.open(str(destination), "wb") as out:
        out.setparams(params._replace(nframes=frames))
        out.writeframes(data)
    return frames


def copy_common_assets() -> None:
    for name in ("FONT.HZK", "ASC.HZK"):
        shutil.copy2(SOURCE / name, OUT / name)


def make_assets() -> dict:
    # The two tracks deliberately reuse the same source recording for a
    # repeatable hardware demo.  The image order differs so a song change is
    # visible even when the audio content is identical.
    bg_order = {1: (1, 2, 3), 2: (2, 3, 1)}
    cv_order = {1: (1, 2, 3), 2: (2, 3, 1)}
    records = []
    for song in (1, 2):
        wav_name = f"S{song:02d}.WAV"
        frames = trim_wav(SOURCE / "S01.WAV", OUT / wav_name)
        shutil.copy2(SOURCE_LRC / "S01.LRC", OUT / f"S{song:02d}.LRC")
        records.append({
            "song": song,
            "audio": wav_name,
            "audio_source": "music_screen_area_opt/card/S01.WAV (前45秒复用)",
            "lrc": f"S{song:02d}.LRC",
            "frames": frames,
            "sample_rate": 48000,
            "channels": 2,
            "duration_seconds": frames / 48000,
            "background_order": list(bg_order[song]),
            "cover_order": list(cv_order[song]),
        })

        for group, source_group in enumerate(bg_order[song], 1):
            image = read_bmp(SOURCE / f"S01BG{source_group}.BMP")
            if image.size != (640, 480):
                raise ValueError("背景尺寸不是 640x480")
            name = f"S{song:02d}BG{group}.BMP"
            write_bmp24(OUT / name, image)
            records.append({"file": name, "kind": "BG", "size": list(image.size),
                            "source": f"S01BG{source_group}.BMP"})

        for group, source_group in enumerate(cv_order[song], 1):
            image = read_bmp(SOURCE / f"S01CV{source_group}.BMP")
            # The legacy art already has a narrow circular mask for this display.
            left = (image.width - 240) // 2
            top = (image.height - 240) // 2
            image = image.crop((left, top, left + 240, top + 240))
            if image.size != (240, 240):
                raise ValueError("封面尺寸不是 240x240")
            name = f"S{song:02d}CV{group}.BMP"
            write_bmp24(OUT / name, image)
            records.append({"file": name, "kind": "CV", "size": list(image.size),
                            "source": f"S01CV{source_group}.BMP", "key": "FF00FF",
                            "display_correction": "source mask already narrow"})
    # Preserve the user's approved S01 artwork on future card regeneration.
    # Only this song's six images override the original bring-up artwork.
    import prepare_photo_art
    if prepare_photo_art.available():
        artwork = prepare_photo_art.render_assets(OUT)
        by_name = {record["file"]: record for record in artwork}
        records = [by_name.get(record.get("file"), record) for record in records]
    return {"songs": records}


def make_preview() -> None:
    sheet = Image.new("RGB", (1280, 1440), (24, 24, 30))
    draw = ImageDraw.Draw(sheet)
    for idx, (song, group) in enumerate((
        (1, 1), (1, 2), (1, 3), (2, 1), (2, 2), (2, 3)
    )):
        x0 = (idx % 2) * 640
        y0 = (idx // 2) * 480
        bg = read_bmp(OUT / f"S{song:02d}BG{group}.BMP")
        cv = read_bmp(OUT / f"S{song:02d}CV{group}.BMP")
        # Exact #FF00FF pixels are transparent in the FPGA cover layer.
        frame = bg.copy()
        mask = Image.new("L", cv.size, 0)
        mask.putdata([0 if pixel == MAGENTA else 255 for pixel in cv.getdata()])
        frame.paste(cv, COVER_ORIGIN, mask)
        sheet.paste(frame, (x0, y0))
        draw.rectangle((x0 + 8, y0 + 8, x0 + 180, y0 + 30), fill=(0, 0, 0))
        draw.text((x0 + 14, y0 + 12), f"S{song:02d}  group {group}", fill=(255, 255, 255))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)
    sheet.resize((1536, 1440), Image.Resampling.NEAREST).save(
        PREVIEW.with_name("card_layout_display16x10_preview.png"))


def inspect_assets() -> list:
    """Check the exact files consumed by resource_catalog and the loaders."""
    records = []
    for name, resource_id in sorted(RESOURCE_IDS.items()):
        path = OUT / name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f"{name}: 素材缺失或为空")
        if path.suffix == ".BMP":
            image = read_bmp(path)
            is_cover = "CV" in name
            expected = COVER_SIZE if is_cover else (640, 480)
            limit = 732121 if is_cover else 921654
            if image.size != expected or path.stat().st_size > limit:
                raise ValueError(f"{name}: 尺寸或长度超出 RTL 限制")
            if is_cover and MAGENTA not in image.getdata():
                raise ValueError(f"{name}: 没有精确 FF00FF 透明色键")
        elif path.suffix == ".WAV":
            with wave.open(str(path), "rb") as inp:
                params = inp.getparams()
                if (params.nchannels, params.sampwidth, params.framerate,
                        params.comptype, params.nframes) != (2, 2, 48000, "NONE", 2160000):
                    raise ValueError(f"{name}: 不是45秒 48kHz 16bit stereo PCM")
                if len(inp.readframes(params.nframes)) != params.nframes * 4:
                    raise ValueError(f"{name}: PCM 数据被截断")
        records.append({"name": name, "resource_id": resource_id,
                        "bytes": path.stat().st_size, "sha256": sha256(path)})
    return records


def check_card() -> None:
    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    if manifest["files"] != inspect_assets():
        raise ValueError("素材内容与 manifest.json 不一致")
    if manifest["cover_window"] != cover_window():
        raise ValueError("封面位置与 RTL 中心不一致")
    print(json.dumps({"status": "PASS", "files": len(RESOURCE_IDS),
                      "cover_origin": COVER_ORIGIN}, ensure_ascii=False))


def cover_window() -> dict:
    return {"x": COVER_ORIGIN[0], "y": COVER_ORIGIN[1],
            "w": COVER_SIZE[0], "h": COVER_SIZE[1],
            "center_x": COVER_CENTER[0], "center_y": COVER_CENTER[1],
            "color_key": "FF00FF"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="只校验现有素材和清单")
    parser.add_argument("--correct-circles", action="store_true",
                        help="只从原始素材重建六张预压缩圆形封面")
    args = parser.parse_args()
    if args.check:
        check_card()
        return
    if args.correct_circles:
        check_card()
        import prepare_photo_art
        if not prepare_photo_art.available():
            raise FileNotFoundError("S01 approved photo sources are missing")
        generated = prepare_photo_art.render_assets(OUT / ".." / "output" / "circle_correction_s01")
        for record in generated:
            if record["kind"] == "CV":
                shutil.copy2(OUT / ".." / "output" / "circle_correction_s01" /
                             record["file"], OUT / record["file"])
        for song in (2,):
            for group, source_group in enumerate((2, 3, 1), 1):
                source = read_bmp(SOURCE / f"S01CV{source_group}.BMP")
                left, top = (source.width - 240) // 2, (source.height - 240) // 2
                cover = source.crop((left, top, left + 240, top + 240))
                write_bmp24(OUT / f"S{song:02d}CV{group}.BMP", cover)
        manifest_path = OUT / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["files"] = inspect_assets()
        manifest["cover_circle_correction"] = "S01 photos horizontal 5/6; S02 source mask already narrow"
        for record in manifest["songs"]:
            if record.get("kind") == "CV":
                record["display_correction"] = (
                    "horizontal 5/6" if record["file"].startswith("S01")
                    else "source mask already narrow")
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                 encoding="utf-8")
        make_preview()
        check_card()
        return
    OUT.mkdir(parents=True, exist_ok=True)
    # Replace only this script's assets; leave any other card files intact.
    copy_common_assets()
    detail = make_assets()
    make_preview()
    manifest = {
        "format": "audio_visual_upgrade_bringup_card_v1",
        "purpose": "新工程上板小样；PC 静态预览不代表实拍",
        "cover_window": cover_window(),
        "background": {"w": 640, "h": 480, "bmp": "24bit BI_RGB bottom-up"},
        "audio": "S01/S02 均使用 S01.WAV 前45秒，便于重复观察切图与跨歌渐变",
        "cover_circle_correction": "S01 photos horizontal 5/6; S02 source mask already narrow",
        "preview": str(PREVIEW.relative_to(ROOT)).replace("\\", "/"),
        "files": inspect_assets(),
        "songs": detail["songs"],
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False,
                                                   indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"out": str(OUT), "preview": str(PREVIEW),
                      "files": len(manifest["files"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
