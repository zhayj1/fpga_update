"""One-time, assert-guarded migration from the saved OSD-corner baseline."""
from pathlib import Path
import json,re
R=Path(__file__).resolve().parents[1]
B=R/'output/visual_controls_aa_20261031/baseline'

def source(p): return (B/p).read_text(encoding='utf-8')
def save(p,s): (R/p).write_text(s,encoding='utf-8')
def sub(s,a,b):
    assert a in s,a
    return s.replace(a,b)

def controls():
    p='rtl/gfx/osd_controls.v';s=source(p)
    s=sub(s,'parameter integer CLK_HZ =','parameter integer EXTENDED=0,\n    parameter integer CLK_HZ =')
    s=sub(s,'output reg [1:0] page','output reg [2:0] page')
    s=sub(s,'output reg [8:0] volume, sat_base, sat_max, con_base, con_max','output reg [8:0] volume, sat_base, sat_max, con_base, con_max,\n    output reg [41:0] colors, output reg [4:0] effects')
    s=sub(s,'    always @(posedge clk) begin','    always @(posedge clk) begin')
    s=sub(s,'            con_base<=9\'d100; con_max<=9\'d135;',"            con_base<=9'd100; con_max<=9'd135;\n            colors<={6{7'd70}};effects<=5'b11111;")
    s=sub(s,"                else if (selected==3'd4) begin page<=2'd0; selected<=3'd0; end",'''                else if (EXTENDED && page==3) begin
                    if(selected==5) begin page<=4;selected<=0;end
                    else selected<=selected+3'd1;
                end else if(selected==3'd4) begin
                    page<=(EXTENDED && page==2)?3'd3:3'd0;selected<=0;
                end''')
    marker='''                    default: selected<=3'd0;
                    endcase
                end'''
    s=sub(s,marker,marker+''' else if(EXTENDED && page==3) begin
                    case(selected)
'''+''.join(f"                    {i}:colors[{i*7+6}:{i*7}]<=next_color(colors[{i*7+6}:{i*7}],plus);\n" for i in range(6))+'''                    endcase
                end else if(EXTENDED && page==4) begin
                    effects[selected]<=plus;
                end''')
    s=sub(s,'    localparam integer MS_TICKS=', '''    function [6:0] next_color;
        input [6:0] current;input up;
        begin next_color=up ? (current==70?7'd0:current+7'd1) :
                             (current==0?7'd70:current-7'd1);end
    endfunction
    localparam integer MS_TICKS=''')
    save(p,s)

def text():
    p='rtl/gfx/layer_text_aa.v';s=source(p)
    s=sub(s,'parameter integer LAST_GAP_TRIM=0,','parameter integer LAST_GAP_TRIM=0, DYNAMIC_COLORS=0,')
    s=sub(s,'    input wire clk_pix,rst_pix_n,hs,vs,de,en,en_ttl,','    input wire clk_pix,rst_pix_n,hs,vs,de,en,en_ttl,\n    input wire [23:0] color_title,color_singer,color_sung,color_other,')
    a=s.index('    assign dout=');b=s.index(';',a)
    original=s[a:b+1].replace('assign dout=','assign legacy_rgb=')
    s=s[:a]+'''    wire [23:0] legacy_rgb;
'''+original+'''
    assign dout=DYNAMIC_COLORS ?
        (active_kind==1?color_title:active_kind==2?color_singer:
         (active_cur && memory_pixel[4])?color_sung:color_other) : legacy_rgb;'''+s[b+1:]
    save(p,s)

def fft():
    p='rtl/gfx/layer_fft64.v';s=source(p)
    s=sub(s,'module layer_fft64 (','module layer_fft64 #(parameter integer DYNAMIC_COLORS=0) (')
    s=sub(s,'    input wire de, en,','    input wire de, en,\n    input wire [23:0] target_color,input wire spike_enable,')
    s=sub(s,'            if(attack_hit) begin','            if(attack_hit && (!DYNAMIC_COLORS || spike_enable)) begin')
    s=sub(s,'            if(bar_stb) begin','''            if(DYNAMIC_COLORS && !spike_enable) begin
                pending_hit<=0;spike_strength<=0;
            end
            if(bar_stb) begin''')
    pos=s.index('    wire [7:0] level=')
    s=s[:pos]+'''    // Bresenham recurrence gives round((255-target)*bar/63) exactly.
    // It updates once per 10-pixel bar: no multiplier, divider or gradient ROM.
    wire [23:0] gradient;
    genvar c;
    generate for(c=0;c<3;c=c+1) begin:g_gradient
        reg [7:0] value;
        reg [5:0] error;
        wire [8:0] sum={3'd0,error}+{1'b0,~target_color[c*8+:8]};
        wire [2:0] q=sum>=252?3'd4:sum>=189?3'd3:sum>=126?3'd2:sum>=63?3'd1:3'd0;
        wire [8:0] multiple=({6'd0,q}<<6)-{6'd0,q};
        always @(posedge clk) begin
            if(!rst_n || !de) begin value<=255;error<=31;end
            else if(scan_phase==9 && scan_bar<63) begin
                value<=value-{5'd0,q};error<=sum-multiple;
            end
        end
        assign gradient[c*8+:8]=value;
    end endgenerate
'''+s[pos:]
    s=sub(s,"24'hFFFFFF:color(scan_bar,cap_pixel);","24'hFFFFFF:(DYNAMIC_COLORS?gradient:color(scan_bar,cap_pixel));")
    save(p,s)

def font():
    p='rtl/gfx/osd_font_youyuan.v';s=source(p)
    s=sub(s,'input wire [5:0] glyph','input wire [6:0] glyph')
    s=sub(s,'    localparam CH_FILE=', '    localparam CH_FILE=')
    s=sub(s,'    localparam ASC_FILE="rtl/gfx/osd_youyuan_ascii.dath";','    localparam ASC_FILE="rtl/gfx/osd_youyuan_ascii.dath";\n    localparam EXTRA_FILE="rtl/gfx/osd_youyuan_extra.dath";')
    s=sub(s,'    localparam ASC_FILE="osd_youyuan_ascii.dath";','    localparam ASC_FILE="osd_youyuan_ascii.dath";\n    localparam EXTRA_FILE="osd_youyuan_extra.dath";')
    s=sub(s,'reg blank_d,ascii_d;','reg blank_d,ascii_d,extra_d;')
    s=sub(s,'ascii_d<=glyph>=30;','ascii_d<=glyph>=30 && glyph<64;extra_d<=glyph[6];')
    start=s.index('    EG_LOGIC_BRAM #(');end=s.index('    EG_LOGIC_BRAM #(',start+1)
    extra=s[start:end].replace('CH_FILE','EXTRA_FILE').replace('u_ch(','u_extra(').replace('.doa(hi)','.doa(extra_hi)').replace('.dob(lo)','.dob(extra_lo)')
    s=s[:end]+'    wire [31:0] extra_hi,extra_lo;\n'+extra+s[end:]
    s=sub(s,': {hi,lo};',': extra_d ? {extra_hi,extra_lo} : {hi,lo};')
    save(p,s)

def osd():
    p='rtl/gfx/osd_layer_small.v';s=source(p)
    s=sub(s,'module osd_layer_small (','module osd_layer_small #(parameter integer EXTENDED=0) (')
    s=sub(s,'input wire [1:0] page','input wire [2:0] page')
    s=sub(s,'    input wire [2:0] selected,','''    input wire [2:0] selected,
    input wire [41:0] color_indices,input wire [4:0] effects,
    output wire [6:0] swatch_index,input wire [23:0] swatch_rgb,''')
    s=s.replace('function [5:0] label_glyph','function [6:0] label_glyph').replace('input [1:0] p;','input [2:0] p;')
    s=s.replace('reg [23:0] word;','reg [27:0] word;').replace('word=24\'d0;',"word=28'd0;")
    s=re.sub(r"6'd(\d+)",r"7'd\1",s)
    s=s.replace('word[5:0]','word[6:0]').replace('word[11:6]','word[13:7]').replace('word[17:12]','word[20:14]').replace('word[23:18]','word[27:21]')
    glyphs=json.loads((R/'output/visual_controls_aa_20261031/generated.json').read_text(encoding='utf-8'))['glyphs']
    def label(text):
        ids=[glyphs[c] for c in text]+[0]*(4-len(text))
        return '{'+','.join("7'd"+str(i) for i in ids[::-1])+'}'
    cases=''
    for page,head,labels in [(3,'颜色设置',['频谱柱','歌词已唱','歌词其余','歌名','歌手','波纹']),
                             (4,'效果设置',['扩散圆环','封面回弹','柱顶尖峰','频谱柱','色彩联动'])]:
        cases+=f"            3'd{page}: case(row)\n                7:word={label(head)};\n"
        cases+=''.join(f'                {i}:word={label(t)};\n' for i,t in enumerate(labels))
        cases+='                default:word=0;\n            endcase\n'
    s=sub(s,'            default:word=0;\n            endcase\n            case (slot)',cases+'            default:word=0;\n            endcase\n            case (slot)')
    s=s.replace('reg [5:0] glyph_req;','reg [6:0] glyph_req;')
    s=s.replace('reg [1:0] page_d;','reg [2:0] page_d;').replace('reg [1:0] page_e;','reg [2:0] page_e;')
    s=sub(s,'else if (page==2 && y>=', 'else if ((page==2 || page==4) && y>=')
    s=sub(s,'2:glyph_req=33;',"2:glyph_req=EXTENDED?7'd35:7'd33;")
    s=sub(s,"7'd31+{4'd0,page}","7'd31+{4'd0,page}")
    s=sub(s,'end else if (row_active && y<row_top+10\'d16) begin',"end else if (page!=3 && row_active && y<row_top+10'd16) begin")
    s=sub(s,'if (page==2 && selected!=row_sel)','if ((page==2 || page==4) && selected!=row_sel)')
    s=sub(s,"end else if (x>=10'd588 && x<10'd628 && numeric_ink)","end else if (page<3 && x>=10'd588 && x<10'd628 && numeric_ink)")
    s=sub(s,'        glyph_col_req=ascii_req ?',f'''        if(EXTENDED && page==3) begin
            if(y>=306 && y<322 && x>=452 && x<516) begin
                glyph_req=label_glyph(3,selected,(x-452)>>4);
                glyph_row_req=y-306;glyph_col_req=x-452;glyph_color=TEXT;
            end
            if(y>=452 && y<468 && x>=452 && x<484) begin
                glyph_req=x<468?7'd{glyphs['默']}:7'd{glyphs['认']};
                glyph_row_req=y-452;glyph_col_req=x-452;glyph_color=TEXT;
            end
        end
        glyph_col_req=ascii_req ?''')
    s=sub(s,'    assign rgb=palette_rgb[23:0];','''    assign rgb=custom_f ? custom_rgb_f : palette_rgb[23:0];''')
    s=sub(s,'selected_d<=page==2 && selected==row_sel;','selected_d<=(page==2 || page==4) && selected==row_sel;')
    s=sub(s,'row_active_e && page_e==2 && selected_e','row_active_e && (page_e==2 || page_e==4) && selected_e')
    s=sub(s,'if(row_active_e && !(page_e==0', 'if(page_e<3 && row_active_e && !(page_e==0')
    at=s.index('    reg [9:0] x_e,')
    s=s[:at]+'''    wire [6:0] selected_index=selected==0?color_indices[6:0]:
        selected==1?color_indices[13:7]:selected==2?color_indices[20:14]:
        selected==3?color_indices[27:21]:selected==4?color_indices[34:28]:color_indices[41:35];
    wire [9:0] gx=x-10'd460,gy=y-10'd330;
    wire grid=page==3 && gx<160 && gy<112;
    wire [3:0] col=gx[7:4];wire [2:0] grow=gy[6:4];
    wire [6:0] cell_index=({4'd0,grow}<<3)+({4'd0,grow}<<1)+{3'd0,col};
    wire cell_inner=gx[3:0]>=2 && gx[3:0]<=13 && gy[3:0]>=2 && gy[3:0]<=13;
    wire cell_border=gx[3:0]>=1 && gx[3:0]<=14 && gy[3:0]>=1 && gy[3:0]<=14;
    wire default_box=page==3 && x>=504 && x<536 && y>=452 && y<468;
    wire default_inner=x>=506 && x<534 && y>=454 && y<466;
    wire check_box=page==4 && row_active && x>=604 && x<620 && y>=row_top && y<row_top+16;
    wire check_inner=x>=607 && x<617 && y>=row_top+3 && y<row_top+13;
    wire custom=EXTENDED && (grid || default_box || check_box);
    wire use_swatch=(grid && cell_inner) || (default_box && default_inner);
    wire highlight=(grid && cell_border && cell_index==selected_index) ||
        (default_box && selected_index==70);
    wire [23:0] flat_color=check_box ? (check_inner ?
        (effects[row_sel]?24'h49DED4:24'h070E13):24'h48636A) :
        highlight?24'hFFFFFF:24'h070E13;
    assign swatch_index=default_box ? 7'd70+{4'd0,selected} : cell_index;
    reg custom_d,custom_e,custom_f,swatch_d;
    reg [23:0] flat_d,custom_rgb_e,custom_rgb_f;
    always @(posedge clk) begin
        if(rst) begin
            custom_d<=0;custom_e<=0;custom_f<=0;swatch_d<=0;
            flat_d<=0;custom_rgb_e<=0;custom_rgb_f<=0;
        end else begin
            custom_d<=custom;custom_e<=custom_d;custom_f<=custom_e;
            swatch_d<=use_swatch;flat_d<=flat_color;
            custom_rgb_e<=swatch_d?swatch_rgb:flat_d;custom_rgb_f<=custom_rgb_e;
        end
    end
'''+s[at:]
    save(p,s)

def top():
    p='rtl/top/skeleton_core.v';s=source(p)
    s=sub(s,'    parameter TYPOGRAPHY', '    parameter VISUAL_CONTROLS=0,\n    parameter TYPOGRAPHY')
    s=sub(s,'wire [1:0] osd_page_clk;','wire [2:0] osd_page_clk;')
    s=sub(s,'reg [1:0] osd_page_s1, osd_page_s2;','reg [2:0] osd_page_s1, osd_page_s2;')
    at=s.index('    wire [8:0] gain_pct')
    s=s[:at]+'''    wire [41:0] visual_colors_clk,visual_indices;
    wire [4:0] visual_effects_clk,effects;
    wire [23:0] color_spectrum,color_sung,color_other,color_title,color_singer,color_rings;
    wire [6:0] swatch_index;
    wire [23:0] swatch_rgb;
    generate if(VISUAL_CONTROLS) begin:g_visual_settings
        visual_settings u_settings(.clk(clk),.rst_n(rst_n),
            .settings({visual_effects_clk,visual_colors_clk}),
            .clk_pix(clk_pix),.rst_pix(rst_pix),.frame_tick(fr_start),
            .swatch_index(swatch_index),.swatch_rgb(swatch_rgb),
            .spectrum(color_spectrum),.sung(color_sung),.other(color_other),
            .title(color_title),.singer(color_singer),.rings(color_rings),
            .effects(effects),.indices(visual_indices));
    end else begin:g_visual_defaults
        assign effects=5'b11111;assign visual_indices={6{7'd70}};
        assign color_spectrum=24'hD97A26;assign color_sung=24'hFF5FCB;
        assign color_other=24'hE8E4FF;assign color_title=24'hFFFFFF;
        assign color_singer=24'hBCC4D2;assign color_rings=24'h5EE8ED;
        assign swatch_rgb=24'd0;
    end endgenerate
'''+s[at:]
    s=sub(s,'osd_controls #(.CLK_HZ(CLK_HZ)', 'osd_controls #(.EXTENDED(VISUAL_CONTROLS),.CLK_HZ(CLK_HZ)')
    s=sub(s,'.con_base(osd_con_base_clk),.con_max(osd_con_max_clk)', '.con_base(osd_con_base_clk),.con_max(osd_con_max_clk),\n        .colors(visual_colors_clk),.effects(visual_effects_clk)')
    s=sub(s,"        assign osd_visible_clk=1'b0;", "        assign osd_visible_clk=1'b0;\n        assign visual_colors_clk={6{7'd70}};assign visual_effects_clk=5'b11111;")
    s=sub(s,'osd_layer_small u_osd_layer (','osd_layer_small #(.EXTENDED(VISUAL_CONTROLS)) u_osd_layer (\n            .color_indices(visual_indices),.effects(effects),\n            .swatch_index(swatch_index),.swatch_rgb(swatch_rgb),')
    s=sub(s,'layer_fft64 u_layer_fft (','layer_fft64 #(.DYNAMIC_COLORS(VISUAL_CONTROLS)) u_layer_fft (\n        .target_color(color_spectrum),.spike_enable(effects[2]),')
    s=sub(s,'.en        (en_fft),', '.en        (en_fft && effects[3]),')
    s=sub(s,'wire [7:0] color_rel = en_fft ?', 'wire [7:0] color_rel = (en_fft && effects[4]) ?')
    a=s.index('    cover_pop u_cover_pop');b=s.index('    cover_pop_geom',a)
    s=s[:a]+s[a:b].replace('rst_pix || spec_song_clear','rst_pix || spec_song_clear || !effects[1]').replace('sa_hit && en_fft','sa_hit && en_fft && effects[1]')+s[b:]
    a=s.index('    attack_rings #(');b=s.index('    );',a)
    s=s[:a]+s[a:b].replace('rst_pix || spec_song_clear','rst_pix || spec_song_clear || !effects[0]').replace('sa_hit && en_fft','sa_hit && en_fft && effects[0]')+s[b:]
    s=sub(s,'.FIVE_LINES(1),.LRC_X(296)', '.DYNAMIC_COLORS(VISUAL_CONTROLS),.FIVE_LINES(1),.LRC_X(296)')
    at=s.index('    ) u_lyr (',s.index('generate if(TYPOGRAPHY) begin : g_aa_text'))
    s=s[:at]+s[at:].replace('    ) u_lyr (','''    ) u_lyr (
        .color_title(color_title),.color_singer(color_singer),
        .color_sung(color_sung),.color_other(color_other),''',1)
    a=s.index('    wire [23:0] new_image=');b=s.index('    compositor u_cmp',a)
    s=s[:a]+'''    wire [23:0] new_image,old_image;
    wire [23:0] actual_ring_color=VISUAL_CONTROLS?color_rings:ring_rgb;
    wire [23:0] new_under=ring_vld_d?ring_over(new_bg_d,actual_ring_color,ring_alpha_d):new_bg_d;
    wire [23:0] old_under=ring_vld_d?ring_over(old_bg_d,actual_ring_color,ring_alpha_d):old_bg_d;
    generate if(VISUAL_CONTROLS) begin:g_cover_aa
        wire [3:0] coverage;
        cover_coverage u_coverage(.clk(clk_pix),.rst(rst_pix),.de(cb_de),
            .x(ff_x),.y(ff_y),.level(cover_pop_level),.alpha(coverage));
        alpha_blend16 #(.USE_DSP(1)) u_new(.background(new_under),.foreground(cv_rgb_d),
            .alpha(cv_vld_d?coverage:4'd0),.rgb(new_image));
        alpha_blend16 #(.USE_DSP(1)) u_old(.background(old_under),.foreground(ocv_rgb_d),
            .alpha(ocv_vld_d?coverage:4'd0),.rgb(old_image));
    end else begin:g_cover_binary
        assign new_image=cv_vld_d?cv_rgb_d:new_under;
        assign old_image=ocv_vld_d?ocv_rgb_d:old_under;
    end endgenerate
'''+s[b:]
    save(p,s)
    p='rtl/top/skeleton_top.v';s=source(p)
    s=sub(s,'.TYPOGRAPHY(1\'b1)',".TYPOGRAPHY(1'b1), .VISUAL_CONTROLS(1'b1)")
    save(p,s)

def manifests():
    modules=['cover_coverage','visual_palette','visual_settings']
    data=['cover_coverage.dath','visual_palette.dath','osd_youyuan_extra.dath']
    p='scripts/build.ps1';s=source(p)
    s=sub(s,"'gfx/osd_layer_small'","'gfx/osd_layer_small',"+','.join("'gfx/"+m+"'" for m in modules))
    s=sub(s,"'osd_blend_palette.dath'","'osd_blend_palette.dath',"+','.join("'"+m+"'" for m in data))
    save(p,s)
    for path in (R/'sim').glob('modelsim*.json'):
        cfg=json.loads(path.read_text(encoding='utf-8'))
        touched=False
        for lib in cfg.get('libraries',[]):
            paths=[v['path'] for v in lib.get('sources',[])]
            if any(x in paths for x in ['rtl/top/skeleton_core.v','rtl/gfx/osd_layer_small.v','rtl/gfx/osd_font_youyuan.v']):
                for m in modules:
                    name=f'rtl/gfx/{m}.v'
                    if name not in paths: lib['sources'].append({'path':name,'language':'verilog'})
                touched=True
        if touched:
            for name in data:
                name='rtl/gfx/'+name
                if name not in cfg.setdefault('data_files',[]):cfg['data_files'].append(name)
            path.write_text(json.dumps(cfg,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':
    controls();text();fft();font();osd();top();manifests()
