#!/usr/bin/env python3
"""Prepare standalone RGBA cover sources; existing FPGA BMPs are untouched."""
from pathlib import Path
import hashlib
import json
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / "music_screen" / ".pylibs"))
from PIL import Image, ImageDraw

OUT = ROOT / "output" / "cover_source_aa_20261031"
KEY = (255, 0, 255)
SAMPLES = 16


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def original_mask(rgb):
    mask = Image.new("L", rgb.size)
    mask.putdata([0 if px == KEY else 255 for px in rgb.get_flattened_data()])
    return mask


def smooth_source(rgb):
    old = original_mask(rgb)
    box = old.getbbox()
    hi = Image.new("L", (rgb.width * SAMPLES, rgb.height * SAMPLES))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(hi).ellipse(
        (x0 * SAMPLES, y0 * SAMPLES,
         x1 * SAMPLES - 1, y1 * SAMPLES - 1), fill=255)
    alpha = hi.resize(rgb.size, Image.Resampling.BOX)
    # Recover only newly exposed boundary colours from the closest valid pixel.
    # Never interpolate magenta into the edge, or blur the existing artwork.
    colour = rgb.copy()
    for y in range(rgb.height):
        for x in range(rgb.width):
            if not alpha.getpixel((x, y)):
                colour.putpixel((x, y), (0, 0, 0))
            elif not old.getpixel((x, y)):
                candidates = [(dx * dx + dy * dy, x + dx, y + dy)
                              for dy in range(-4, 5) for dx in range(-4, 5)
                              if 0 <= x + dx < rgb.width
                              and 0 <= y + dy < rgb.height
                              and old.getpixel((x + dx, y + dy))]
                if not candidates:
                    raise ValueError("Boundary exceeds local colour recovery range")
                _, nx, ny = min(candidates)
                colour.putpixel((x, y), rgb.getpixel((nx, ny)))
    colour.putalpha(alpha)
    return colour, old, box


def main():
    inputs = [p for directory in (ROOT / "card", ROOT / "rtl")
              for p in directory.rglob("*") if p.is_file()]
    before = {str(p.relative_to(ROOT)): digest(p) for p in inputs}
    OUT.mkdir(parents=True, exist_ok=False)
    source_dir = OUT / "rgba_sources"
    source_dir.mkdir()
    comparison = Image.new("RGB", (1280, 6 * 272), (24, 24, 24))
    draw = ImageDraw.Draw(comparison)
    records = []
    for index, source in enumerate(sorted((ROOT / "card").glob("*CV*.BMP"))):
        rgb = Image.open(source).convert("RGB")
        rgba, old, bbox = smooth_source(rgb)
        target = source_dir / (source.stem + ".png")
        rgba.save(target)
        decoded = Image.open(target).convert("RGBA")
        assert decoded.tobytes() == rgba.tobytes()
        alpha = decoded.getchannel("A")
        partial = sum(0 < a < 255 for a in alpha.get_flattened_data())
        assert partial > 0
        unchanged = 0
        for y in range(240):
            for x in range(240):
                px = decoded.getpixel((x, y))
                if old.getpixel((x, y)) and px[3]:
                    assert px[:3] == rgb.getpixel((x, y))
                    unchanged += 1
                if px[3]:
                    assert px[:3] != KEY
        # Preview the identical artwork against its associated static background.
        # The RGBA panel is a PC reference, not a simulation of the current bit.
        background_path = ROOT / "card" / source.name.replace("CV", "BG")
        background = Image.open(background_path).convert("RGB")
        matte = background.crop((40, 45, 280, 285))
        old_panel = matte.copy()
        old_panel.paste(rgb, (0, 0), old)
        new_panel = matte.copy()
        new_panel.paste(rgba, (0, 0), alpha)
        top = index * 272
        draw.text((8, top + 4), source.stem + "  BEFORE | RGBA REFERENCE | EDGE BEFORE | EDGE AFTER", fill="white")
        comparison.paste(old_panel, (8, top + 24))
        comparison.paste(new_panel, (256, top + 24))
        # 4x nearest enlargement makes the partial edge pixels visible.
        crop = (20, 36, 84, 96)
        comparison.paste(old_panel.crop(crop).resize((256, 240), Image.Resampling.NEAREST), (512, top + 24))
        comparison.paste(new_panel.crop(crop).resize((256, 240), Image.Resampling.NEAREST), (776, top + 24))
        records.append({"source": str(source.relative_to(ROOT)),
                        "source_sha256": digest(source),
                        "output": str(target.relative_to(OUT)),
                        "sha256": digest(target), "size": list(rgba.size),
                        "ellipse_bounds": list(bbox),
                        "partial_alpha_pixels": partial,
                        "original_visible_rgb_preserved_pixels": unchanged})
    comparison.save(OUT / "comparison.png")
    assert before == {str(p.relative_to(ROOT)): digest(p) for p in inputs}
    report = {"method": "16x16 subpixel ellipse coverage; 8-bit alpha; original RGB retained",
              "purpose": "Source-art preparation only; not a drop-in SD-card replacement",
              "current_bit_supports_rgba": False,
              "card_and_rtl_hashes_unchanged": True,
              "alpha_levels": 256, "files": records}
    (OUT / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "README.md").write_text(
        "# 圆形封面源素材抗锯齿\n\n"
        "rgba_sources 中为六张 240×240 RGBA PNG，保留原画面及横向比例修正。"
        "用每像素 16×16 子采样计算椭圆覆盖率，边缘使用 8 位半透明过渡；原有可见像素的 RGB 保持。"
        "新边缘所需的颜色取最近有效像素，不混入 FF00FF，不模糊图像主体。\n\n"
        "comparison.png 每行依次为原图、平滑源图、原图边缘4倍放大、平滑边缘4倍放大。"
        "两图均在该组静态背景上做 PC 合成；预览不代表当前 FPGA 的输出。\n\n"
        "当前 bit 只支持 24 位 BMP 和二值色键，不支持 PNG/半透明。"
        "本包不能直接复制到 SD 卡使用；转为 FF00FF 二值 BMP 会再次失去边缘过渡。"
        "与固定背景预混只能适配该背景及位置，封面弹动/背景变化时可能出现色边，故未采用。"
        "需要显示链路支持覆盖率混合才能保留本包的透明边缘效果。"
        "240×240 输出仍是有限像素，抗锯齿减轻阶梯感，不能保证任何放大观察下都不可见像素。\n\n"
        "原 card 文件、字库和 RTL 均未修改；manifest.json 包含输出哈希和核验记录。\n",
        encoding="utf-8")
    archive = OUT.with_suffix(".zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(OUT.rglob("*")):
            if p.is_file():
                z.write(p, p.relative_to(OUT))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
    print(json.dumps({"zip": str(archive), "files": len(records),
                      "partial_alpha_pixels": [r["partial_alpha_pixels"] for r in records],
                      "card_and_rtl_unchanged": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
