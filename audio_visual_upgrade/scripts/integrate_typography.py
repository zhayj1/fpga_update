"""Apply the approved optional typography path to the legacy board project."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
p=root/'rtl/top/skeleton_core.v'; s=p.read_text(encoding='utf-8')
s=s.replace("    parameter en_osd                  = 1'b0,", "    parameter en_osd                  = 1'b0,\n    parameter TYPOGRAPHY              = 1'b0,")
s=s.replace('    asset_manager u_assets (','    asset_manager #(.TYPOGRAPHY(TYPOGRAPHY)) u_assets (')
assert 'asset_manager #(.TYPOGRAPHY' in s
s=s.replace('.SC_PX (38)', '.SC_PX (TYPOGRAPHY ? 32 : 38)')
s=s.replace('overlay_vld_d<=ly_vld || ff_vld;', 'overlay_vld_d<=(TYPOGRAPHY ? 1\'b0 : ly_vld) || ff_vld;')
s=s.replace('.ly_vld (ly_vld)', '.ly_vld (TYPOGRAPHY ? 1\'b0 : ly_vld)')
s=s.replace('.tt_vld (ly_vld)', '.tt_vld (TYPOGRAPHY ? 1\'b0 : ly_vld)')
s=s.replace('    assign cmp_rgb = overlay_text_d2 ? cmp_raw_rgb : colorized_rgb;', '''    wire [3:0] text_alpha;
    generate if(TYPOGRAPHY) begin : g_text_composition
        reg [23:0] rgb1,rgb2,rgb3;
        reg [3:0] a1,a2,a3;
        always @(posedge clk_pix) begin
            if(rst_pix) begin rgb1<=0; rgb2<=0; rgb3<=0; a1<=0; a2<=0; a3<=0; end
            else begin rgb1<=ly_rgb; rgb2<=rgb1; rgb3<=rgb2;
                a1<=text_alpha; a2<=a1; a3<=a2; end
        end
        alpha_blend16 u_text_blend(.background(colorized_rgb),.foreground(rgb3),
            .alpha(a3),.rgb(cmp_rgb));
    end else begin : g_legacy_composition
        assign cmp_rgb=overlay_text_d2 ? cmp_raw_rgb : colorized_rgb;
    end endgenerate''')
a=s.index('        osd_layer u_osd_layer (')
b=s.index('\n    end else begin : g_no_osd_picture',a)
old=s[a:b]
s=s[:a]+'''        if(TYPOGRAPHY) begin : g_small
'''+old.replace('osd_layer u_osd_layer','osd_layer_small u_osd_layer')+'''
        end else begin : g_legacy
'''+old+'''
        end'''+s[b:]
a=s.index('    layer_text #(')
b=s.index('\n\n    //=========================================================================',a)
old=s[a:b]
ports=old[old.index('        .clk_pix'):]
new='''    generate if(TYPOGRAPHY) begin : g_aa_text
    layer_text_aa #(.V_ACT_DLY(35),.WIN_Y0(396),.WIN_H(72),.ROW_Y0(404),
        .PITCH(32),.BOX_X(32),.BOX_W(160),.TTL_Y0(16),.SGR_Y0(48),
        .LRC_BASE(21'h121440),.FONT_BASE(21'hE1000),
        .SPP(1200),.HOLD_N(24000),.CLK_HZ(SDR_CLK_MHZ*1000000)) u_lyr (
        .alpha(text_alpha),
'''+ports+'''
    end else begin : g_legacy_text
        assign text_alpha=4'd0;
'''+old+'''
    end endgenerate'''
s=s[:a]+new+s[b:]; p.write_text(s,encoding='utf-8')
p=root/'rtl/top/skeleton_top.v'; s=p.read_text(encoding='utf-8'); s=s.replace(".en_osd(1'b1)",".en_osd(1'b1), .TYPOGRAPHY(1'b1)"); p.write_text(s,encoding='utf-8')
p=root/'rtl/app/asset_manager.v'; s=p.read_text(); s=s.replace('module asset_manager (','module asset_manager #(parameter TYPOGRAPHY=0) (')
s=s.replace('candidate=font_valid;', 'candidate=font_valid && (!TYPOGRAPHY || (font_size>=32\'d33296 && font_size<=32\'d1046784 && font_size[1:0]==0));')
s=s.replace('candidate=asc_valid;', 'candidate=asc_valid && !TYPOGRAPHY;'); p.write_text(s)
p=root/'tb/tb_upgrade_core.v'; s=p.read_text(encoding='utf-8').replace('dut.u_lyr.','dut.g_legacy_text.u_lyr.'); p.write_text(s,encoding='utf-8')
sources=['alpha_blend16','text_row_aa','layer_text_aa','osd_font_youyuan','osd_layer_small']
p=root/'prj/skeleton.al'; s=p.read_text(encoding='utf-8')
for n,name in enumerate(sources):
    s=s.replace('</Verilog>',f'<File Path="../rtl/gfx/{name}.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="{130+n}"/></FileInfo></File></Verilog>')
p.write_text(s,encoding='utf-8')
p=root/'scripts/build.ps1'; s=p.read_text(encoding='utf-8'); s=s.replace("'gfx/osd_layer'))", "'gfx/osd_layer',"+','.join("'gfx/"+v+"'" for v in sources)+"))")
s=s.replace("'osd_font_ascii.dath'))", "'osd_font_ascii.dath','osd_youyuan_ch.dath','osd_youyuan_ascii.dath'))")
s=s.replace('$manifest.Add(@{path=$fontData;', 'Copy-Item -LiteralPath $fontData -Destination (Join-Path $run $fontFile)\n    $manifest.Add(@{path=$fontData;')
p.write_text(s,encoding='utf-8')
for p in (root/'sim').glob('modelsim*.json'):
    config=json.loads(p.read_text(encoding='utf-8-sig'))
    changed=False
    for lib in config['libraries']:
        if any(v['path']=='rtl/top/skeleton_core.v' for v in lib['sources']):
            existing={v['path'] for v in lib['sources']}
            for name in sources:
                path=f'rtl/gfx/{name}.v'
                if path not in existing: lib['sources'].append({'path':path,'language':'verilog'})
            phy='sim/vendor/eg4/eg_phy_bram32k.v'
            if phy not in existing: lib['sources'].append({'path':phy,'language':'verilog'})
            config.setdefault('data_files',[]).extend(['rtl/gfx/osd_youyuan_ch.dath','rtl/gfx/osd_youyuan_ascii.dath'])
            changed=True
    if changed: p.write_text(json.dumps(config,indent=2)+'\n')
