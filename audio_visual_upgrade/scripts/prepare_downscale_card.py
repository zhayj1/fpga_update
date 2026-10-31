#!/usr/bin/env python3
"""Package current artwork at larger BMP3 sizes for board downscale checks."""
from __future__ import annotations

import hashlib
import json
import shutil
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "card"
PACK = ROOT / "output" / "card_downscale_board_20261029"
SIZES = {
    "BG1": (800, 600), "BG2": (1280, 960), "BG3": (1600, 1200),
    "CV1": (300, 300), "CV2": (480, 480), "CV3": (600, 600),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_bmp(path: Path) -> tuple[int, int, bytes, int]:
    raw = path.read_bytes()
    size, _, _, offset = struct.unpack_from("<IHHI", raw, 2)
    dib, width, height, planes, bpp, compression = struct.unpack_from(
        "<IiiHHI", raw, 14)
    if (raw[:2], offset, dib, planes, bpp, compression) != (
            b"BM", 54, 40, 1, 24, 0) or width <= 0 or height <= 0:
        raise ValueError(f"Not bottom-up 24-bit BMP3: {path}")
    stride = (width * 3 + 3) & ~3
    if size != len(raw) or size != 54 + stride * height:
        raise ValueError(f"Invalid BMP length: {path}")
    return width, height, raw[54:], stride


def enlarge(source: Path, destination: Path, width: int, height: int) -> None:
    sw, sh, pixels, stride = read_bmp(source)
    if width < sw or height < sh or width * sh != height * sw:
        raise ValueError("Enlargement must preserve aspect ratio")
    xs = [(2 * x + 1) * sw // (2 * width) for x in range(width)]
    pad = bytes((-width * 3) % 4)
    rows = []
    for y in range(sh):
        row = pixels[(sh - 1 - y) * stride:(sh - y) * stride]
        rows.append(b"".join(row[x * 3:x * 3 + 3] for x in xs) + pad)
    body = b"".join(rows[(2 * y + 1) * sh // (2 * height)]
                    for y in range(height - 1, -1, -1))
    header = struct.pack("<2sIHHI", b"BM", 54 + len(body), 0, 0, 54)
    dib = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0,
                      len(body), 2835, 2835, 0, 0)
    destination.write_bytes(header + dib + body)


def phase_indices(source: int, target: int, bottom_up: bool = False) -> list[int]:
    # Replay bmp_load's phase selection; bottom-up rows complement exact ties.
    phase = source - int(bottom_up)
    selected = []
    for index in range(source):
        keep = phase < 2 * target
        if keep:
            selected.append(index)
        phase += (2 * source if keep else 0) - 2 * target
    if len(selected) != target:
        raise ValueError("Unexpected phase sample count")
    return selected


def check_image(source: Path, generated: Path) -> dict:
    sw, sh, original, source_stride = read_bmp(source)
    width, height, pixels, stride = read_bmp(generated)
    if width > 4096 or height > 4096 or generated.stat().st_size > 64 * 1024**2:
        raise ValueError("Image exceeds RTL input limits")
    xs = phase_indices(width, sw)
    ys = phase_indices(height, sh, bottom_up=True)
    formula_xs = [(2 * x + 1) * width // (2 * sw) for x in range(sw)]
    formula_ys = [(2 * y + 1) * height // (2 * sh) for y in range(sh)]
    if xs != formula_xs or [height - 1 - y for y in reversed(ys)] != formula_ys:
        raise ValueError("Phase selection disagrees with center-nearest formula")
    sampled = b"".join(
        pixels[y * stride + x * 3:y * stride + x * 3 + 3]
        for y in ys for x in xs)
    expected = b"".join(original[y * source_stride:y * source_stride + sw * 3]
                        for y in range(sh))
    if sampled != expected:
        raise ValueError(f"Downscaled image differs from original: {generated.name}")
    return {
        "name": generated.name, "kind": "image", "input_size": [width, height],
        "display_size": [sw, sh], "bytes": generated.stat().st_size,
        "sha256": digest(generated), "source_sha256": digest(source),
        "downscale_matches_original_pixels": True,
        "checked_pixels": sw * sh,
        "transparent_key": "FF00FF" if "CV" in generated.stem else None,
    }


def main() -> None:
    sources = sorted(path for path in SOURCE.iterdir() if path.is_file())
    before = {path.name: digest(path) for path in sources}
    card = PACK / "sd_card"
    card.mkdir(parents=True, exist_ok=True)
    records = []
    for source in sources:
        if source.name == "manifest.json":
            continue  # The original manifest describes the small images.
        destination = card / source.name
        if source.suffix.upper() == ".BMP":
            width, height = SIZES[source.stem[3:]]
            enlarge(source, destination, width, height)
            records.append(check_image(source, destination))
        elif source.suffix.upper() in (".WAV", ".LRC", ".HZK"):
            shutil.copy2(source, destination)
            if digest(source) != digest(destination):
                raise ValueError(f"Copied file differs: {source.name}")
            records.append({"name": source.name, "kind": "copied",
                            "bytes": destination.stat().st_size,
                            "sha256": digest(destination)})
        else:
            raise ValueError(f"Unexpected card input: {source.name}")
    expected_names = {record["name"] for record in records}
    if {path.name for path in card.iterdir()} != expected_names:
        raise ValueError("Unexpected file in generated SD-card directory")
    if before != {path.name: digest(path) for path in sources}:
        raise ValueError("Original card files changed during generation")
    implementation = json.loads((ROOT / "doc/compile/bmp_downscale_implementation_result.json")
                                .read_text(encoding="utf-8"))["implementation"]
    bit = Path(implementation["bitstream"]["path"])
    if digest(bit).upper() != implementation["bitstream"]["sha256"]:
        raise ValueError("Candidate bitstream hash differs from implementation report")
    manifest = {
        "purpose": "当前素材的大尺寸上板缩小验证包",
        "generation": "将当前 card BMP 按中心最近邻放大；不新增原生画面细节",
        "bmp_format": "BMP3 / DIB40 / 24-bit BI_RGB / bottom-up",
        "expected": "按当前 RTL 缩小后，每一像素与原 card 图像相同，包括 FF00FF",
        "original_card_unchanged": True,
        "files": records,
        "verified_pixels": sum(r.get("checked_pixels", 0) for r in records),
        "bitstream": implementation["bitstream"],
        "timing_clean": implementation["timing_clean"],
        "board_validation": "pending_user",
    }
    (PACK / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    readme = """# 当前素材大尺寸上板验证包

把 `sd_card` 里面的 18 个文件复制到现有 FAT32 卡的根目录；保持原文件名，同名文件覆盖。
不要把 `sd_card` 文件夹本身直接放到卡上。音频、歌词、字库均已带齐，与当前 card 内容一致。
工程原 card 素材未修改；原小图仍可用于还原对照。

| 两首歌均适用 | 背景输入 → 输出 | 封面输入 → 输出 |
| --- | --- | --- |
| 第 1 组（BG1/CV1） | 800×600 → 640×480 | 300×300 → 240×240 |
| 第 2 组（BG2/CV2） | 1280×960 → 640×480 | 480×480 → 240×240 |
| 第 3 组（BG3/CV3） | 1600×1200 → 640×480 | 600×600 → 240×240 |

图片由当前卡里的画面放大生成，用来验证 FPGA 对大分辨率文件的读取和缩小；
不代表新增高分辨率细节。已按 RTL 的相位累加规则和独立中心抽样公式核对：
12 张图缩回显示尺寸后，共 2,188,800 个像素与当前原图完全一致，包含封面 FF00FF 透明色。
全部是 24 位无压缩 BMP3（DIB40），覆盖 1.25、2、2.5 倍输入尺寸。

## 上板观察

1. 使用含缩小功能的 `bmp_downscale_r1_seed3_phy/skeleton.bit`，旧 bit 不支持本包的大图。
2. 断电后装卡，启动，等待素材装载完成。大图仍需完整顺序读取，启动与预加载会更慢。
3. 对照原小图观察第一组画面，再检查另外两组及两首歌的切换。
4. 画面位置、颜色、封面圆形和透明区域应保持一致，无倒置、错行或花屏；同时观察音频是否连续。

第三组单张背景约 5.49 MiB，在 12.5 MHz SPI 理论上仅数据传输就至少约 3.69 秒，
实际装载还包含协议、FAT 和音频争用；这不是整机启动或切换耗时保证。
本包用于首次功能验证，不包含 4096 极限尺寸。

配套 bit 是已生成的上板测试候选，静态时序尚未全部收敛；实际板上结果待验证。
`manifest.json` 保存每个文件的分辨率、哈希、逐像素校验结果及配套 bit 路径/哈希。
"""
    (PACK / "README.md").write_text(readme, encoding="utf-8")
    archive = PACK.with_suffix(".zip")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as out:
        for path in sorted(PACK.rglob("*")):
            if path.is_file():
                out.write(path, path.relative_to(PACK.parent))
    with zipfile.ZipFile(archive) as out:
        bad = out.testzip()
        if bad is not None:
            raise ValueError(f"ZIP CRC failure: {bad}")
    print(json.dumps({"directory": str(PACK), "zip": str(archive),
                      "card_files": len(records), "image_files": 12,
                      "verified_pixels": manifest["verified_pixels"],
                      "card_bytes": sum(r["bytes"] for r in records),
                      "zip_bytes": archive.stat().st_size,
                      "source_unchanged": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
