"""Stage the final timing candidate and its independent r7 comparator."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/transitions_timing'
current = (ROOT / 'rtl/gfx/layer_text_aa.v').read_text()
assert 'reg [31:0] title_limit,singer_limit;' in current
(OUT / 'layer_text_aa_r8.v').write_text(current)
old = '''    // Cache the width-derived boundaries when a row completes. The unsigned
    // 32-bit expression retains the old integer-parameter arithmetic, including
    // limits beyond the 10-bit offset range (which must never wrap).
    reg [31:0] title_limit,singer_limit;
    reg title_wide,singer_wide;
    wire title_wrap=title_wide && off_t>=title_limit;
    wire singer_wrap=singer_wide && off_s>=singer_limit;'''
new = '''    // A reachable wrap limit is in [2*BOX_W,1023]. Cache only its
    // varying low bits and rebuild the common prefix as wires. Limits beyond
    // the offset range disable wrapping; the offset still overflows at 1024,
    // exactly as in the original width-based arithmetic.
    localparam integer WRAP_LOW_W=(BOX_W>0 && BOX_W<512) ?
        bits_for((1023 ^ (2*BOX_W))+1) : 10;
    localparam [9:0] WRAP_PREFIX=(2*BOX_W) & (1023 << WRAP_LOW_W);
    reg [WRAP_LOW_W-1:0] title_limit,singer_limit;
    reg title_wide,singer_wide,title_can_wrap,singer_can_wrap;
    wire [9:0] title_boundary=WRAP_PREFIX | title_limit;
    wire [9:0] singer_boundary=WRAP_PREFIX | singer_limit;
    wire title_wrap=title_can_wrap && off_t>=title_boundary;
    wire singer_wrap=singer_can_wrap && off_s>=singer_boundary;'''
assert old in current
candidate = current.replace(old, new)
candidate = candidate.replace('title_wide<=0; singer_wide<=0; div_count<=0;',
    'title_wide<=0; singer_wide<=0; title_can_wrap<=0; singer_can_wrap<=0; div_count<=0;')
for kind in ('title', 'singer'):
    candidate = candidate.replace(f'{kind}_wide<=row_width>BOX_W;',
        f'{kind}_wide<=row_width>BOX_W;\n'
        f'                        {kind}_can_wrap<=row_width>BOX_W && row_width+BOX_W-1<=32\'d1023;')
    candidate = candidate.replace(f'{kind}_limit<=BOX_W-1; {kind}_wide<=0;',
        f'{kind}_limit<=BOX_W-1; {kind}_wide<=0; {kind}_can_wrap<=0;')
(OUT / 'layer_text_aa_r9.v').write_text(candidate)

tb = (ROOT / 'tb/tb_marquee_equivalence.v').read_text()
tb = tb.replace('tb_marquee_equivalence', 'tb_marquee_compressed_equivalence')
tb = tb.replace("dut.title_limit!==({22'd0,reference.wt}+BOX_W-1)",
    'dut.title_wrap!==(reference.wt>BOX_W && reference.off_t>=reference.wt+BOX_W-1)')
tb = tb.replace("dut.singer_limit!==({22'd0,reference.ws}+BOX_W-1)",
    'dut.singer_wrap!==(reference.ws>BOX_W && reference.off_s>=reference.ws+BOX_W-1)')
(ROOT / 'tb/tb_marquee_compressed_equivalence.v').write_text(tb)
cfg = json.loads((ROOT / 'sim/modelsim_marquee_equivalence.json').read_text())
cfg['dut_top'] = cfg['tb_top'] = 'work.tb_marquee_compressed_equivalence'
for source in cfg['libraries'][0]['sources']:
    if source['path'] == 'tb/tb_marquee_equivalence.v':
        source['path'] = 'tb/tb_marquee_compressed_equivalence.v'
(ROOT / 'sim/modelsim_marquee_compressed_equivalence.json').write_text(json.dumps(cfg, indent=2)+'\n')
