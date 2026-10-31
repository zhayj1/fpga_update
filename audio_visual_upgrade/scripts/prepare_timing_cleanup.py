"""Apply the first timing cleanup, preserving the previous build evidence."""
from pathlib import Path
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]


def main():
    out = ROOT / 'output/timing_cleanup_20261030/source_before_r1'
    out.mkdir(parents=True, exist_ok=False)
    files = ('rtl/gfx/osd_layer_small.v', 'rtl/gfx/text_row_aa.v',
             'rtl/gfx/layer_text_aa.v', 'scripts/build.ps1', 'doc/workflow/state.json')
    for f in files:
        dest = out / f
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / f, dest)

    p = ROOT / files[0]
    s = p.read_text(encoding='utf-8')
    s = s.replace('output reg [23:0] rgb,', 'output wire [23:0] rgb,')
    s = s.replace("localparam [23:0] BG=24'h070e13, TEXT=24'he7f0f0;\n    localparam [23:0] CYAN=24'h49ded4, AMBER=24'hffb347;\n    localparam [23:0] MUTED=24'hb6c6c9, LINE=24'h48636a;", '''// Palette indices; scripts/generate_osd_palette.py holds the RGB values.
    localparam [1:0] TEXT=0, CYAN=1, AMBER=2, MUTED=3;
    localparam [3:0] BG=0, LINE=1, B_CYAN=2, BAR_OFF=3,
        SCOPE_BORDER=4, SCOPE_BG=5, SCOPE_LINE=6, THRESHOLD=7, B_AMBER=8;''')
    s = s.replace('reg [23:0] glyph_color', 'reg [1:0] glyph_color')
    s = s.replace('reg [23:0] panel_rgb;', 'reg [3:0] panel_rgb;')
    old = '''    wire [23:0] blended_rgb;
    alpha_blend16 #(.USE_DSP(1)) u_blend(.background(panel_rgb),.foreground(glyph_color_e),
        .alpha(glyph_alpha),.rgb(blended_rgb));'''
    new = '''    // Synchronous lookup replaces the old output register and the entire
    // variable RGB multiply/divide chain. Latency remains three pixel clocks.
`ifdef OSD_SIM
    localparam PALETTE_FILE="rtl/gfx/osd_blend_palette.dath";
`else
    localparam PALETTE_FILE="osd_blend_palette.dath";
`endif
    wire [31:0] palette_rgb;
    assign rgb=palette_rgb[23:0];
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE(PALETTE_FILE),.FILL_ALL("NONE"),.IMPLEMENT("32K")
    ) u_palette(.clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),
        .addra({panel_rgb,glyph_color_e,glyph_alpha}),.dia(32'd0),.doa(palette_rgb),
        .rsta(1'b0),.bea(1'b0),.clkb(clk),.ceb(1'b0),.oceb(1'b0),.web(1'b0),
        .addrb(10'd0),.dib(32'd0),.dob(),.rstb(1'b0),.beb(1'b0));'''
    assert old in s
    s = s.replace(old, new).replace('rgb<=0; valid<=0;', 'valid<=0;')
    s = s.replace('            rgb<=blended_rgb;\n', '')
    s = s.replace('panel_rgb=CYAN;', 'panel_rgb=B_CYAN;')
    s = s.replace("? CYAN : 24'h405258", '? B_CYAN : BAR_OFF')
    for a,b in (("24'h24303b",'SCOPE_BORDER'),("24'h070b10",'SCOPE_BG'),
                ("24'h35d0c4",'SCOPE_LINE'),("24'hb8893c",'THRESHOLD')):
        s = s.replace('panel_rgb='+a, 'panel_rgb='+b)
    s = s.replace('panel_rgb=AMBER;', 'panel_rgb=B_AMBER;')
    p.write_text(s, encoding='utf-8')

    p = ROOT / files[1]
    s = p.read_text(encoding='utf-8')
    start, end = s.index('    reg symbol_ok;'), s.index('    function [9:0] ascii_widths;')
    s = s[:start] + '''    // Compare the two bytes independently in DIRECTORY. ADDRESS combines
    // eight registered pairs; no selected low-byte comparator feeds a flop.
    reg [7:0] symbol_zone_q,symbol_column_q;
    reg single_q,ascii_ok_q,column_ok_q,chinese_ok_q;
    wire symbol_ok_q=|(symbol_zone_q & symbol_column_q);
    wire code_ok=single_q ? ascii_ok_q :
        (column_ok_q && (symbol_ok_q || chinese_ok_q));
''' + s[end:]
    s = s.replace('symbol_ok_q<=0;', 'symbol_zone_q<=0;symbol_column_q<=0;')
    s = s.replace('                symbol_ok_q<=symbol_ok;', '''                symbol_zone_q<={code[15:8]==8'hA9,code[15:8]==8'hA8,
                    code[15:8]==8'hA7,code[15:8]==8'hA6,code[15:8]==8'hA5,
                    code[15:8]==8'hA4,code[15:8]==8'hA2,
                    (code[15:8]==8'hA1 || code[15:8]==8'hA3)};
                symbol_column_q[0]<=1'b1;
                symbol_column_q[1]<=(code[7:0]>=8'hB1 && code[7:0]<=8'hE2) ||
                    (code[7:0]>=8'hE5 && code[7:0]<=8'hEE) ||
                    (code[7:0]>=8'hF1 && code[7:0]<=8'hFC);
                symbol_column_q[2]<=code[7:0]<=8'hF3;
                symbol_column_q[3]<=code[7:0]<=8'hF6;
                symbol_column_q[4]<=code[7:0]<=8'hB8 || (code[7:0]>=8'hC1 && code[7:0]<=8'hD8);
                symbol_column_q[5]<=code[7:0]<=8'hC1 || (code[7:0]>=8'hD1 && code[7:0]<=8'hF1);
                symbol_column_q[6]<=code[7:0]<=8'hBA || (code[7:0]>=8'hC5 && code[7:0]<=8'hE9);
                symbol_column_q[7]<=code[7:0]>=8'hA4 && code[7:0]<=8'hEF;''')
    p.write_text(s, encoding='utf-8')

    p = ROOT / files[2]
    s = p.read_text(encoding='utf-8')
    s = s.replace("begin valid_desc=cnt!=0 && cnt<=limit && ({1'b0,fc}+{1'b0,cnt}<=17'd488); end", '''begin valid_desc=fc[15:9]==0 && cnt[15:5]==0 && cnt[4:0]!=0 &&
            cnt[4:0]<=limit && ({1'b0,fc[8:0]}+{5'd0,cnt[4:0]}<=10'd488); end''')
    marker = '    // Sample pulses cross as a toggle'
    i = s.index(marker)
    source = '''    // Source-domain validation settles one SDR clock after descriptor
    // publication. The existing two-stage pixel toggle capture occurs later;
    // the descriptor bundle remains stable until that capture (same contract).
    reg cur_desc_ok,nxt_desc_ok,n3_desc_ok,ttl_desc_ok,sgr_desc_ok;
    reg prev2_desc_ok,prev_desc_ok,n4_desc_ok;
    always @(posedge clk_sdr) begin
        if(!rst_sdr_n) begin
            cur_desc_ok<=0;nxt_desc_ok<=0;n3_desc_ok<=0;ttl_desc_ok<=0;sgr_desc_ok<=0;
            prev2_desc_ok<=0;prev_desc_ok<=0;n4_desc_ok<=0;
        end else begin
'''
    pairs = [('cur',19),('nxt',19),('n3',19),('ttl',24),('sgr',24),('prev2',19),('prev',19),('n4',19)]
    for name,limit in pairs:
        old = f'{name}_vld && valid_desc({name}_fc,{name}_cnt,{limit})'
        assert old in s
        s = s.replace(old, f'{name}_desc_ok')
        source += f'            {name}_desc_ok<={old};\n'
    source += '        end\n    end\n'
    i = s.index(marker)
    s = s[:i] + source + s[i:]
    p.write_text(s, encoding='utf-8')

    p = ROOT / files[3]
    s = p.read_text(encoding='utf-8').replace("'osd_youyuan_ascii.dath')", "'osd_youyuan_ascii.dath','osd_blend_palette.dath')")
    p.write_text(s, encoding='utf-8')
    for p in (ROOT / 'sim').glob('modelsim*.json'):
        cfg = json.loads(p.read_text(encoding='utf-8-sig'))
        if 'rtl/gfx/osd_layer_small.v' in json.dumps(cfg):
            data = cfg.setdefault('data_files', [])
            if 'rtl/gfx/osd_blend_palette.dath' not in data:
                data.append('rtl/gfx/osd_blend_palette.dath')
                p.write_text(json.dumps(cfg, indent=2)+'\n', encoding='utf-8')
    p = ROOT / files[4]
    state = json.loads(p.read_text(encoding='utf-8-sig'))
    state.update(active_stage='timing_cleanup', status='running',
                 scope='Preserve all display behavior and remove timing violations by structural optimization.')
    state['timing_cleanup'] = dict(status='running', authorization='用户：违例太多了，消除一下',
        new_budget_reason='Explicit authorization for a new timing repair round after lyric spacing implementation.',
        baseline='lyricspace_r1_congestion_seed3_phy', baseline_setup_violations=152,
        structural_attempts_started=1, automatic_retries_after_first_failure=0, max_retries=3,
        preserved_previous_retry_records=True, attempt='timingclean_r1',
        acceptance=['unchanged pixels and latency', 'complete font and layout regressions',
                    'routed setup and hold analysis without timing exceptions'])
    p.write_text(json.dumps(state, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
