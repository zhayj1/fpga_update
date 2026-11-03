"""Fill unused pixel-font slots; preserve every existing glyph byte exactly."""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / 'music_screen/.pylibs'))
from PIL import Image, ImageDraw, ImageFont

OUT = ROOT / 'output/transitions_20261102_r1'
NEW_CHARS = '转场速淡入出擦除溶解百叶窗快标慢很'
GLYPHS = {c: 95 + i for i, c in enumerate(NEW_CHARS)}


def glyph_mask(char):
    # Same Youyuan font, 8x supersampling and nearest 4-bit AA quantization.
    scale = 8
    size = 16 * scale
    font = ImageFont.truetype('C:/Windows/Fonts/SIMYOU.TTF', size)
    reference = '攻击检测实时声学音量色彩灵敏触发频谱强度相对饱和比基准上限Agjpx()'
    top, bottom = font.getbbox(reference, anchor='ls')[1::2]
    while bottom - top > size:
        size -= 1
        font = ImageFont.truetype('C:/Windows/Fonts/SIMYOU.TTF', size)
        top, bottom = font.getbbox(reference, anchor='ls')[1::2]
    baseline = (128 - (bottom - top)) // 2 - top
    advance = font.getlength(char)
    bounds = font.getbbox(char, anchor='ls')
    left = min(0, bounds[0])
    span = max(advance, bounds[2]) - left
    canvas = Image.new('L', (160, 160))
    ImageDraw.Draw(canvas).text((16 + (128-span)/2-left, 16+baseline),
                               char, font=font, anchor='ls', fill=255)
    mask = canvas.crop((16, 16, 144, 144)).resize((16, 16), Image.Resampling.LANCZOS)
    return mask.point([min(range(16), key=lambda a: abs(a*17-v)) for v in range(256)])


def install_font():
    path = ROOT / 'rtl/gfx/osd_youyuan_pixel.dath'
    words = [int(v, 16) for v in path.read_text().split()]
    assert len(words) == 16384 and len(GLYPHS) == 17
    prefix = words[:95*128]
    for char, glyph in GLYPHS.items():
        pixels = list(glyph_mask(char).getdata())
        assert any(pixels) and max(pixels) <= 15
        words[glyph*128:(glyph+1)*128] = [(pixels[i]<<4)|pixels[i+1] for i in range(0, 256, 2)]
    assert words[:95*128] == prefix
    path.write_text(''.join(f'{v:02x}\n' for v in words), encoding='ascii')
    OUT.mkdir(exist_ok=True, parents=True)
    mapping = json.loads((ROOT/'output/visual_controls_aa_20261031/generated.json').read_text(encoding='utf-8'))['glyphs']
    mapping.update(GLYPHS)
    (OUT/'glyphs.json').write_text(json.dumps(mapping, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == '__main__':
    print('Pixel font SHA256:', install_font())
