"""Independent 20px lyric oracle from the packed font and existing records."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'output/typography_full_20261030/manifest.json').read_text(encoding='utf-8'))
raw = (root / 'card/FONT.HZK').read_bytes()
font_words = [int(v, 16) for v in (root / 'sim/typography_font.mem').read_text().split()]
assert raw == b''.join(v.to_bytes(4, 'little') for v in font_words)
records = [int(v, 16) for v in (root / 'sim/layout_five_lrc.mem').read_text().split()]
info = [int(v, 16) for v in (root / 'sim/layout_five_info.mem').read_text().split()]
gold, widths = [], []
for line in range(8):
    first, count = info[line * 3:line * 3 + 2]
    chars = []
    for i in range(count):
        record = records[136 + 2 * (first + i)]
        code = record.to_bytes(4, 'little')[:2]
        char = chr(code[1]) if code[0] == 0 else code.decode('gb2312')
        chars.append((manifest['chars'][char], records[137 + 2 * (first + i)] <= 2500))
    width = sum(char['width20'] for char, _ in chars)
    widths.append(width)
    for y in range(20):
        row = []
        for char, sung in chars:
            offset = char['offset_words'] * 4 + 288 + y * 10
            packed = raw[offset:offset + 10]
            row += [((packed[x // 2] >> (4 if x % 2 == 0 else 0)) & 15) | (16 if sung else 0)
                    for x in range(char['width20'])]
        gold += row + [0] * (480 - width)
(root / 'sim/split14_gold.mem').write_text(''.join(f'{v:02x}\n' for v in gold), encoding='ascii')
(root / 'sim/split14_widths.mem').write_text(''.join(f'{v:04x}\n' for v in widths), encoding='ascii')
print('Prepared independent 20px pixels/highlighting; widths:', widths)
