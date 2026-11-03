"""Copy the existing two-song SPI fixture and independently decode its BMPs.

The compact fixture exercises end-to-end control; full-sized traffic is tested
by tb_display_memory. Golden pixels come from card bytes, never RTL RAM state.
"""
from pathlib import Path
import json
import struct
import shutil

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'music_screen_area_opt'


def main():
    raw = bytes.fromhex((BASE / 'sim/fat32_twosong_distinct.mem').read_text())
    (ROOT / 'sim/fat32_core.mem').write_text('\n'.join(f'{b:02x}' for b in raw) + '\n')
    shutil.copy2(BASE / 'tb/sd_card_model_min.v', ROOT / 'tb/sd_card_model_min.v')
    u16 = lambda p: struct.unpack_from('<H', raw, p)[0]
    u32 = lambda p: struct.unpack_from('<I', raw, p)[0]
    bps, spc, reserved = u16(11), raw[13], u16(14)
    data = reserved + raw[16] * u32(36)

    def chain(c):
        seen = set()
        while 2 <= c < 0x0ffffff8:
            assert c not in seen
            seen.add(c)
            p = (data + (c - 2) * spc) * bps
            yield raw[p:p + spc * bps]
            c = u32(reserved * bps + c * 4) & 0x0fffffff

    files = []
    for block in chain(u32(44)):
        for off in range(0, len(block), 32):
            e = block[off:off + 32]
            if e[0] in (0, 0xe5) or e[11] & 0x18 or e[11] == 0x0f:
                continue
            name = e[:8].decode().strip() + '.' + e[8:11].decode().strip()
            c = struct.unpack_from('<H', e, 26)[0] | struct.unpack_from('<H', e, 20)[0] << 16
            size = struct.unpack_from('<I', e, 28)[0]
            files.append((name, b''.join(chain(c))[:size]))
    decoded = dict(files)
    pixels, meta = [], []
    for song in (1, 2):
        for group in (1, 2, 3):
            row = []
            for kind in ('BG', 'CV'):
                bmp = decoded[f'S{song:02d}{kind}{group}.BMP']
                w, h = struct.unpack_from('<ii', bmp, 18)
                assert w > 0 and h > 0 and struct.unpack_from('<H', bmp, 28)[0] == 24
                start, stride, dest = struct.unpack_from('<I', bmp, 10)[0], (w * 3 + 3) & ~3, len(pixels)
                for y in range(h):
                    for x in range(w):
                        b, g, r = bmp[start + (h - 1 - y) * stride + x * 3:][:3]
                        pixels.append(r << 16 | g << 8 | b)
                row.append((w, h, dest))
            meta.append(row)
    (ROOT / 'sim/core_pixels.mem').write_text('\n'.join(f'{p:06x}' for p in pixels) + '\n')
    lines = [f'localparam integer PIXEL_COUNT={len(pixels)};', 'initial begin']
    for sid, (bg, cv) in enumerate(meta):
        for kind, values in (('bg', bg), ('cv', cv)):
            for field, val in zip(('w', 'h', 'off'), values):
                lines.append(f'  {kind}_{field}[{sid}]={val};')
    lines += ['end', 'function integer asset_of_file;', 'input integer ft;', 'begin', 'case(ft)']
    # Requests use catalog resource IDs, independent of FAT directory order.
    for name, _ in files:
        if name.endswith('.BMP'):
            song, group = int(name[1:3]), int(name[5])
            sid = (song - 1) * 3 + group - 1
            ft = song * 8 + group - 1 + (3 if name[3:5] == 'CV' else 0)
            lines.append(f'  {ft}: asset_of_file={sid}; // {name}')
    lines += ['  default: asset_of_file=-1;', 'endcase', 'end', 'endfunction']
    (ROOT / 'tb/core_fixture.vh').write_text('\n'.join(lines) + '\n')
    cfg = json.loads((ROOT / 'sim/modelsim_core.json').read_text(encoding='utf-8-sig'))
    cfg['tb_top'] = 'work.tb_upgrade_core'
    cfg['dut_parameters'] = {'SDR_CLK_MHZ': 150}
    cfg['data_files'] = ['sim/fat32_core.mem', 'sim/core_pixels.mem', 'tb/core_fixture.vh']
    cfg['libraries'][0]['include_dirs'].append('tb')
    cfg['libraries'][0]['sources'] += [{'path': p, 'language': 'verilog'} for p in ('tb/sd_card_model_min.v', 'tb/tb_upgrade_core.v')]
    (ROOT / 'sim/modelsim_integration.json').write_text(json.dumps(cfg, indent=2) + '\n')
    print(json.dumps({'files': [n for n, _ in files], 'pixels': len(pixels), 'images': meta}))


if __name__ == '__main__':
    main()
