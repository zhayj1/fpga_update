"""Preserve R3, then apply the final bounded structural timing repair."""
import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
backup = root / 'output/timing_cleanup_20261030/source_before_r4'
backup.mkdir()
for name in ['rtl/mem/sdram_arb.v', 'rtl/gfx/text_row_aa.v',
             'rtl/gfx/layer_fft64.v', 'doc/workflow/state.json']:
    target = backup / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / name, target)

p = root / 'rtl/mem/sdram_arb.v'
text = (root / 'output/timing_cleanup_20261030/source_before_r2/rtl/mem/sdram_arb.v').read_text(encoding='utf-8')
text = text.replace('//   ⇒ **本文件的逻辑一行都没必要改**；',
    '//   2026-10-30: Bound issued-word counter by MAX_BURST; all interface cycles unchanged.\n//   历史结论：')
text = text.replace('    reg [2:0]  st;', '''    function integer count_bits;
        input integer maximum;
        integer v;
        begin
            count_bits=1;
            for(v=maximum;v>1;v=v>>1) count_bits=count_bits+1;
        end
    endfunction
    // n can reach the accepted length on the final RUN edge. Zero-length
    // requests still issue one RUN iteration, hence the minimum one bit.
    localparam integer N_W=count_bits(MAX_BURST[15:0]);
    reg [2:0]  st;''')
assert text.count('reg [15:0] n;') == 1
text = text.replace('reg [15:0] n;', 'reg [N_W-1:0] n;')
p.write_text(text, encoding='utf-8')

p = root / 'rtl/gfx/text_row_aa.v'
text = p.read_text(encoding='utf-8')
text = text.replace('    reg [31:0] word0,word1,word2,word3;',
    '    reg [31:0] word0,word1,word2,word3;\n    reg [3:0] header_ok_q;')
text = text.replace('            watchdog<=0; word0<=0;',
    '            header_ok_q<=0;\n            watchdog<=0; word0<=0;')
text = text.replace('            done<=0; wr_en<=0;', '''            done<=0; wr_en<=0;
            // RX -> CHECK supplies a full cycle before HEADER consumes this.
            // Parallel word checks remove 128-bit validation from request,
            // state and watchdog controls without adding a protocol cycle.
            header_ok_q<={word0==32'h32505954,word1==32'h00141804,
                          word2==32'd964240,word3==32'd7540};''')
old = "if(word0!=32'h32505954 || word1!=32'h00141804 ||\n                   word2!=32'd964240 || word3!=32'd7540)"
assert old in text
text = text.replace(old, 'if(!(&header_ok_q))')
p.write_text(text, encoding='utf-8')

p = root / 'rtl/gfx/layer_fft64.v'
text = p.read_text(encoding='utf-8')
text = text.replace("    wire [9:0] bar_top=10'd478-{2'd0,pixel_height};\n", '')
text = text.replace("    wire [9:0] cap_top=bar_top-(bright_cap?10'd3:10'd2);", '''    // Move the fixed-origin subtraction to the coordinate side. The height
    // chain no longer contains bar_top and cap_top serial subtractions.
    // y<=477 gates the ten-bit distance; off-screen high bits cannot alias.
    wire [9:0] bottom_distance=10'd478-y[9:0];
    wire [8:0] cap_height={1'b0,pixel_height}+(bright_cap?9'd3:9'd2);''')
text = text.replace("(y>={6'd0,bar_top}) && (y<=16'd477)",
    "(y<=16'd477) && (bottom_distance<={2'd0,pixel_height})")
text = text.replace("(y>={6'd0,cap_top}) && (y<{6'd0,bar_top})",
    "(y<=16'd477) && (bottom_distance>{2'd0,pixel_height}) &&\n                   (bottom_distance<={1'b0,cap_height})")
p.write_text(text, encoding='utf-8')
reference = (backup / 'rtl/gfx/layer_fft64.v').read_text(encoding='utf-8')
(root / 'tb/timing_fft_reference.v').write_text(
    reference.replace('module layer_fft64 (', 'module timing_fft_reference ('), encoding='utf-8')

p = root / 'doc/workflow/state.json'
v = json.loads(p.read_text(encoding='utf-8-sig'))
v['timing_cleanup'].update(structural_attempts_started=4,
    automatic_retries_after_first_failure=3, attempt='timingclean_r4',
    stage='simulation_r4', r3_result=dict(setup_violations=93,
    non_shifted_setup_endpoints=29, setup_wns_ns=-5.565,hold_violations=0,
    slices=9640, physical='timingclean_r3_congestion_seed3_phy',selected=False))
p.write_text(json.dumps(v, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print('R3 preserved; final R4 structural repair applied.')
