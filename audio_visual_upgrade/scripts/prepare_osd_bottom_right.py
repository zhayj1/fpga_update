"""Translate the approved OSD by (+16,+240), preserving its pixel oracle."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/osd_bottom_right_20261030'
FILES = ('rtl/gfx/osd_layer_small.v', 'tb/tb_osd_typography.v', 'tb/tb_typography_core.v')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    before = {}
    for name in FILES:
        path = ROOT / name
        backup = OUT / 'source_before' / name
        if backup.exists():
            raise RuntimeError('Preserve existing backup: ' + str(backup))
        backup.parent.mkdir(parents=True, exist_ok=True)
        backup.write_bytes(path.read_bytes())
        before[name] = hashlib.sha256(path.read_bytes()).hexdigest()

    path = ROOT / FILES[0]
    source = path.read_text(encoding='utf-8')
    # Only absolute geometry constants change. Relative sizes, pipeline stages,
    # font addresses, history mapping and arithmetic coefficients stay intact.
    xs = {424, 428, 431, 435, 436, 500, 556, 564, 572, 596, 604, 612, 623, 624}
    ys = {28, 44, 55, 66, 92, 98, 124, 129, 130, 156, 162, 188, 192, 194, 196, 220, 239, 240}
    def translate(match):
        value = int(match.group(1))
        if value in xs:
            value += 16
        elif value in ys:
            value += 240
        return "10'd" + str(value)
    source = re.sub(r"10'd(\d+)", translate, source)
    source = source.replace("y>=10'd16", "y>=10'd256")
    source = source.replace("y_e==10'd16", "y_e==10'd256")
    for top in (66, 98, 130, 162, 194):
        source = source.replace('row_top_next=' + str(top) + ';',
                                'row_top_next=' + str(top + 240) + ';')
    source = source.replace('// Three-page 640x480 OSD. All drawing',
        '// Three-page 640x480 OSD at x=440..639, y=256..479 (200x224).\n// All drawing')
    path.write_text(source, encoding='utf-8')

    path = ROOT / FILES[1]
    source = path.read_text(encoding='utf-8')
    source = source.replace('yy<256', 'yy<480')
    source = source.replace('want=golden[frame_id*163840+yy*640+xx];',
        '''// Inverse-translate the independently rendered original image.
                    // Outside its bounds the expected output is transparent.
                    want=0;
                    if(xx>=16 && yy>=240 && yy<496)
                        want=golden[frame_id*163840+(yy-240)*640+(xx-16)];''')
    source = source.replace('x=450;y=30', 'x=466;y=270')
    source = source.replace('yy=130;yy<196', 'yy=370;yy<436')
    source = source.replace('xx>=436 && xx<612', 'xx>=452 && xx<628')
    source = source.replace('xx-436', 'xx-452').replace('xx==436', 'xx==452')
    source = source.replace('xx-437', 'xx-453')
    source = source.replace('level=192-yy', 'level=432-yy').replace('yy<=192', 'yy<=432')
    source = source.replace('#20000000', '#30000000')
    source = source.replace('sim/typography_osd_actual.mem', 'sim/osd_bottom_right_actual.mem')
    path.write_text(source, encoding='utf-8')

    path = ROOT / FILES[2]
    source = path.read_text(encoding='utf-8')
    source = source.replace('''                if(osd_golden[327680+py*640+px][24])
                    input_expected=osd_golden[327680+py*640+px][23:0];''',
        '''                // Preserve the independent original OSD reference and apply
                // the requested (+16,+240) translation at the checker boundary.
                if(px>=16 && py>=240 && py<496) begin
                    if(osd_golden[327680+(py-240)*640+(px-16)][24])
                        input_expected=osd_golden[327680+(py-240)*640+(px-16)][23:0];
                end''')
    source = source.replace('yy<256', 'yy<480')
    source = source.replace('checked!=163840', 'checked!=307200')
    source = source.replace('axis_pixels!=163840 || axis_lines!=256',
                            'axis_pixels!=307200 || axis_lines!=480')
    source = source.replace('#12000000', '#20000000')
    source = source.replace('sim/typography_core_actual.mem', 'sim/osd_bottom_right_core_actual.mem')
    path.write_text(source, encoding='utf-8')
    (OUT / 'change_inputs.json').write_text(json.dumps({
        'before_sha256': before,
        'after_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES},
        'translation': [16, 240], 'panel_xywh': [440, 256, 200, 224],
        'oracle': 'Original independent six-frame reference, inverse-translated by the TB',
        'hardware_baseline': 'User reports timing_cleanup_20261030 bit works on board',
    }, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
