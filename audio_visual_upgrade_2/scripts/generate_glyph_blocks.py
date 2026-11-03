"""Build the two-port TYP2 byte-address ROM; check against the font directory."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


def main():
    table = []
    for hi in range(256):
        if hi == 0:
            base = 2081 + (8178 - 564 - 32) * 31
        else:
            base = 2081 + ((hi - 161) * 94 - (564 if hi >= 176 else 0) - 161) * 31
        table.append(base & 0x3ffff)
    table.extend(lo * 31 for lo in range(256))
    font = (ROOT / 'output/typography_full_20261030/sd_card/FONT.HZK').read_bytes()
    checked = 0
    for hi in range(256):
        for lo in range(256):
            if hi == 0:
                valid = 32 <= lo <= 126
                index = 8178 + lo - 32
            else:
                try:
                    bytes((hi, lo)).decode('gb2312')
                    valid = 161 <= hi <= 247 and 161 <= lo <= 254
                except UnicodeDecodeError:
                    valid = False
                index = (hi - 161) * 94 + lo - 161
            if valid:
                offset = 16 + index * 4
                reference = int.from_bytes(font[offset:offset + 4], 'little') & 0x3ffff
                actual = (table[hi] + table[256 + lo]) & 0x3ffff
                assert actual == reference, (hi, lo, actual, reference)
                checked += 1
    assert checked == 7540, checked
    path = ROOT / 'rtl/gfx/glyph_blocks.dath'
    path.write_text(''.join(f'{word:05x}\n' for word in table), encoding='ascii')
    print(json.dumps({'status': 'PASS', 'glyphs': checked, 'rom_words': len(table),
                      'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
