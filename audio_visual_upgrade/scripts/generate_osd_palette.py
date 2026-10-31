"""Generate the exact 16-level OSD blend palette (one 32K BRAM)."""
from pathlib import Path

BACKGROUNDS = (0x070E13, 0x48636A, 0x49DED4, 0x405258, 0x24303B,
               0x070B10, 0x35D0C4, 0xB8893C, 0xFFB347)
FOREGROUNDS = (0xE7F0F0, 0x49DED4, 0xFFB347, 0xB6C6C9)


def main():
    words = []
    for bi in range(16):
        bg = BACKGROUNDS[bi] if bi < len(BACKGROUNDS) else BACKGROUNDS[0]
        for fg in FOREGROUNDS:
            for alpha in range(16):
                rgb = 0
                for shift in (16, 8, 0):
                    b, f = (bg >> shift) & 255, (fg >> shift) & 255
                    rgb |= ((b * (15-alpha) + f * alpha + 7) // 15) << shift
                words.append(f'{rgb:08x}')
    dest = Path(__file__).resolve().parents[1] / 'rtl/gfx/osd_blend_palette.dath'
    dest.write_text('\n'.join(words) + '\n', encoding='ascii')


if __name__ == '__main__':
    main()
