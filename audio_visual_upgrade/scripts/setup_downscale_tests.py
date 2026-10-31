"""Prepare reproducible downscale tests without changing existing SD fixtures."""
from pathlib import Path
import json
import struct

ROOT = Path(__file__).resolve().parents[1]


def write_json(path, data):
    (ROOT / path).write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def main():
    scenarios = ['downscale-identity-key-and-backpressure',
                 'downscale-rational-and-orientation-matrix']
    sources = ['rtl/load/bmp_load.v', 'tb/tb_bmp_downscale.v']
    cfg = dict(dut_top='work.bmp_load', dut_parameters={'EXTERNAL_BACKEND': 1, 'DOWNSCALE': 1},
               tb_top='work.tb_bmp_downscale',
               libraries=[dict(name='work', sources=[dict(path=p, language='verilog') for p in sources])])
    write_json('sim/modelsim_bmp_downscale.json', cfg)
    write_json('tb/expected_bmp_downscale.json', scenarios + [
        'downscale-source-limit-and-destination-bounds',
        'downscale-reject-no-upscale-ratio-and-overflow',
        'downscale-truncation-error-watchdog-recovery', 'downscale-reset-recovery'])
    cfg['dut_parameters']['EXTERNAL_BACKEND'] = 0
    cfg['tb_parameters'] = {'EXTERNAL': 0, 'SMALL': 1}
    cfg['libraries'][0]['sources'] = [dict(path=p, language='verilog') for p in [
        'sim/vendor/eg4/eg_logic_bram.v', 'rtl/ip/afifo_8i_32o_1024.v',
        'rtl/ip/afifo_8i_32o_bram.v', 'rtl/load/load_writeback.v'] + sources]
    write_json('sim/modelsim_bmp_downscale_writeback.json', cfg)
    write_json('tb/expected_bmp_downscale_writeback.json', scenarios + ['downscale-real-fifo-writeback-addresses'])

    # Retain FAT geometry, audio, lyrics and fonts; replace only image payloads.
    raw = bytearray.fromhex((ROOT / 'sim/fat32_core.mem').read_text())
    u16 = lambda p: struct.unpack_from('<H', raw, p)[0]
    u32 = lambda p: struct.unpack_from('<I', raw, p)[0]
    bps, spc, reserved = u16(11), raw[13], u16(14)
    data_start = reserved + raw[16] * u32(36)

    def chain(cluster):
        seen = set()
        while 2 <= cluster < 0x0ffffff8:
            assert cluster not in seen
            seen.add(cluster)
            yield (data_start + (cluster - 2) * spc) * bps
            cluster = u32(reserved * bps + cluster * 4) & 0x0fffffff

    pixels, meta, files = [], {}, []
    for block in list(chain(u32(44))):
        for off in range(block, block + spc * bps, 32):
            e = raw[off:off+32]
            if e[0] in (0, 0xe5) or e[11] & 0x18 or e[11] == 0x0f or e[8:11] != b'BMP':
                continue
            name = e[:8].decode().strip()
            song, group = int(name[1:3]), int(name[5])
            cover = name[3:5] == 'CV'
            sid = (song-1)*3+group-1
            w, h = (7+group, 7+group) if cover else (12, 9)
            dw, dh = (5, 5) if cover else (8, 6)
            bottom_up = (song+group+cover) % 2 == 0
            stride = (w*3+3) & ~3
            bmp = bytearray(54+stride*h)
            bmp[:2] = b'BM'
            struct.pack_into('<III', bmp, 2, len(bmp), 0, 54)
            # Explicit standard BMP header fields, with signed orientation.
            struct.pack_into('<I', bmp, 14, 40)
            struct.pack_into('<iiHHI', bmp, 18, w, h if bottom_up else -h, 1, 24, 0)

            def pixel(x, y):
                if cover and (x+y) % 5 == 0:
                    return (255, 0, 255)
                return ((x*17+sid*23) & 255, (y*29+sid*11) & 255, (x*7+y*13+sid*31) & 255)

            for y in range(h):
                for x in range(w):
                    at = 54+(h-1-y if bottom_up else y)*stride+x*3
                    bmp[at:at+3] = bytes(reversed(pixel(x,y)))
            cluster = struct.unpack_from('<H', e, 26)[0] | struct.unpack_from('<H', e, 20)[0] << 16
            blocks = list(chain(cluster))
            assert len(bmp) <= len(blocks)*spc*bps
            for n, at in enumerate(blocks):
                chunk = bmp[n*spc*bps:(n+1)*spc*bps]
                raw[at:at+len(chunk)] = chunk
            struct.pack_into('<I', raw, off+28, len(bmp))
            meta[(sid, cover)] = (dw, dh, len(pixels))
            for y in range(dh):
                for x in range(dw):
                    r,g,b = pixel((2*x+1)*w//(2*dw), (2*y+1)*h//(2*dh))
                    pixels.append(r<<16 | g<<8 | b)
            files.append((song*8+group-1+(3 if cover else 0), sid))
    assert len(meta) == 12
    (ROOT/'sim/fat32_downscale.mem').write_text(''.join(f'{b:02x}\n' for b in raw))
    (ROOT/'sim/downscale_pixels.mem').write_text(''.join(f'{p:06x}\n' for p in pixels))
    lines = [f'localparam integer PIXEL_COUNT={len(pixels)};', 'initial begin']
    for (sid, cover), values in sorted(meta.items()):
        for field, value in zip(('w','h','off'), values):
            lines.append(f'  {"cv" if cover else "bg"}_{field}[{sid}]={value};')
    lines += ['end', 'function integer asset_of_file;', 'input integer ft;', 'begin case(ft)']
    lines += [f'  {ft}: asset_of_file={sid};' for ft,sid in files]
    lines += ['  default: asset_of_file=-1;', 'endcase end', 'endfunction']
    (ROOT/'tb/downscale_fixture.vh').write_text('\n'.join(lines)+'\n')
    cfg = json.loads((ROOT/'sim/modelsim_integration.json').read_text(encoding='utf-8-sig'))
    cfg['libraries'][0]['defines'].append('BMP_SCALE_FIXTURE')
    cfg['data_files'] = ['sim/fat32_downscale.mem', 'sim/downscale_pixels.mem', 'tb/downscale_fixture.vh',
                         'rtl/gfx/osd_font_ch.dath', 'rtl/gfx/osd_font_ascii.dath']
    write_json('sim/modelsim_downscale_integration.json', cfg)
    print('Prepared downscale unit, writeback and SPI/FAT system fixtures.')


if __name__ == '__main__':
    main()
