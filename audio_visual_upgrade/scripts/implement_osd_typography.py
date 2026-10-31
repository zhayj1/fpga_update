"""One-time migration helper; retained to make the geometry change reviewable."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/'rtl/gfx/osd_layer.v').read_text()
s=s.replace('module osd_layer (','module osd_layer_small (')
a=s.index('    wire [8:0] local_x=')
b=s.index('    wire [9:0] addr_sum=',a)
s=s[:a]+'''    // Exact floor(local_x*320/176) = floor(local_x*20/11).
    // Raster recurrence keeps the original 320-sample time window without a divider.
    reg [8:0] source_idx;
    reg [4:0] source_phase;
    always @(posedge clk) begin
        if(rst || x<10'd436 || x>=10'd612) begin source_idx<=0; source_phase<=0; end
        else if(source_phase>=5'd2) begin
            source_idx<=source_idx+9'd2; source_phase<=source_phase-5'd2;
        end else begin
            source_idx<=source_idx+9'd1; source_phase<=source_phase+5'd9;
        end
    end
'''+s[b:]
s=s.replace("x>=10'd405 && x<10'd625", "x>=10'd436 && x<10'd612")
s=s.replace("wire [2:0] numeric_pos=(x-10'd545)>>4;", "wire [2:0] numeric_pos=(x-10'd572)>>3;")
s=s.replace('reg [4:0] glyph_row_req, glyph_col_req;', 'reg [3:0] glyph_row_req, glyph_col_req;')
s=s.replace('wire [31:0] font_bits;','wire [63:0] font_bits;')
s=s.replace('osd_font_rom u_font','osd_font_youyuan u_font')
a=s.index('        if (page==0) begin',s.index('always @(*) begin\n        row_sel_next'))
b=s.index('    always @(*) begin\n        value=0;',a)
s=s[:a]+'''        if (y>=10'd66 && y<10'd92) begin row_sel_next=0; row_top_next=66; row_active_next=1; end
        else if (y>=10'd98 && y<10'd124) begin row_sel_next=1; row_top_next=98; row_active_next=1; end
        else if (page!=0 && y>=10'd130 && y<10'd156) begin row_sel_next=2; row_top_next=130; row_active_next=1; end
        else if (page!=0 && y>=10'd162 && y<10'd188) begin row_sel_next=3; row_top_next=162; row_active_next=1; end
        else if (page==2 && y>=10'd194 && y<10'd220) begin row_sel_next=4; row_top_next=194; row_active_next=1; end
    end
'''+s[b:]
for old,new in [('1468','1186'),('219','176'),('558','451'),('620','501'),('349','282'),('1116','902'),('797','644')]:
    s=s.replace("11'd"+old,"11'd"+new)
s=s.replace("bar_width=(bar_product[19:8]>12'd218) ? 9'd218 : bar_product[16:8];", "bar_width=(bar_product[19:8]>12'd176) ? 9'd176 : bar_product[16:8];")
s=s.replace("bar_y=row_top+((page==0) ? 10'd40 : (page==1 ? 10'd41 : 10'd39));", "bar_y=row_top+10'd22;")
a=s.index("        if (y>=10'd12")
b=s.index('\n    reg [9:0] x_d',a)
s=s[:a]+'''        if (y>=10'd28 && y<10'd44) begin
            glyph_row_req=y-10'd28;
            if (x>=10'd436 && x<10'd500) begin
                glyph_req=label_glyph(page,3'd7,(x-10'd436)>>4);
                glyph_col_req=x-10'd436;
            end else if (x>=10'd556 && x<10'd564) begin
                glyph_req=42; ascii_req=1; glyph_color=CYAN; glyph_col_req=x-10'd556;
            end else if (x>=10'd572 && x<10'd596) begin
                ascii_req=1; glyph_color=AMBER;
                case ((x-10'd572)>>3)
                0:glyph_req=6'd31+{4'd0,page};
                1:glyph_req=41;
                2:glyph_req=33;
                endcase
                glyph_col_req=x-10'd572;
            end else if (x>=10'd604 && x<10'd612) begin
                glyph_req=43; ascii_req=1; glyph_color=CYAN; glyph_col_req=x-10'd604;
            end
        end else if (row_active && y<row_top+10'd16) begin
            glyph_row_req=y-row_top;
            if (x>=10'd436 && x<10'd500) begin
                glyph_req=label_glyph(page,row_sel,(x-10'd436)>>4);
                glyph_col_req=x-10'd436;
                if (page==2 && selected!=row_sel) glyph_color=MUTED;
            end else if (x>=10'd572 && x<10'd612 && numeric_ink) begin
                ascii_req=1;
                glyph_req=(percent && numeric_pos==3'd4) ? 6'd40 : (6'd30+{2'd0,digit_value});
                glyph_col_req=x-10'd572;
                glyph_color=(page==0 && row_sel==1) ? AMBER : CYAN;
            end
        end
        glyph_col_req=ascii_req ? {1'b0,glyph_col_req[2:0]} : glyph_col_req;
    end
'''+s[b:]
s=s.replace('reg [4:0] glyph_col_d;','reg [3:0] glyph_col_d;')
s=s.replace("wire [5:0] scope_level=10'd230-y_d;", "wire [5:0] scope_level=10'd192-y_d;")
s=s.replace("x_d==10'd405", "x_d==10'd436")
s=s.replace('    wire glyph_ink=ascii_d ? font_bits[15-glyph_col_d] : font_bits[31-glyph_col_d];', '''    wire [3:0] glyph_alpha=glyph_d ? (font_bits >> ((15-glyph_col_d)*4)) : 4'd0;
    reg [23:0] panel_rgb;
    wire [23:0] blended_rgb;
    alpha_blend16 u_blend(.background(panel_rgb),.foreground(glyph_color_d),
        .alpha(glyph_alpha),.rgb(blended_rgb));''')
a=s.index('            panel_d<=visible')
b=s.index('            row_active_d<=',a)
s=s[:a]+'''            panel_d<=visible && de && x>=10'd424 && x<10'd624 && y>=10'd16 && y<10'd240;
'''+s[b:]
s=s.replace("if (x_d>=10'd405 && x_d<10'd625)","if (x_d>=10'd436 && x_d<10'd612)")
a=s.index('            valid<=panel_d;')
s=s[:a]+'''            valid<=panel_d;
            rgb<=blended_rgb;
        end
    end
    // Mix the glyph into the actual pixel (panel, bar or scope), preserving
    // the full 4-bit edge coverage even where foreground elements cross.
    always @(*) begin
        panel_rgb=BG;
        if(panel_d) begin
            if(x_d==10'd424 || x_d==10'd623 || y_d==10'd16 || y_d==10'd239 ||
                (y_d==10'd55 && x_d>=10'd436 && x_d<10'd612)) panel_rgb=LINE;
            if(row_active_d && page_d==2 && selected_d &&
                x_d>=10'd428 && x_d<10'd431 &&
                y_d>=row_top_d+10'd1 && y_d<row_top_d+10'd15) panel_rgb=CYAN;
            if(row_active_d && !(page_d==0 && row_top_d==10'd98) &&
                x_d>=10'd436 && x_d<10'd612 && y_d>=bar_y_d && y_d<bar_y_d+10'd3)
                panel_rgb=((x_d-10'd436)<bar_width_d) ? CYAN : 24'h405258;
            if(page_d==0 && x_d>=10'd435 && x_d<=10'd612 &&
                (y_d==10'd129 || y_d==10'd196)) panel_rgb=24'h24303b;
            if(page_d==0 && y_d>=10'd130 && y_d<10'd196 && x_d>=10'd436 && x_d<10'd612) begin
                panel_rgb=24'h070b10;
                if(history_valid_d && y_d<=10'd192 && scope_level>=min_amp && scope_level<=max_amp)
                    panel_rgb=24'h35d0c4;
                if(y_d<=10'd192 && scope_level==threshold_amp && x_d[2:0]<3'd4) panel_rgb=24'hb8893c;
                if(history_valid_d && history_read[13]) panel_rgb=AMBER;
            end
        end
    end
endmodule
`default_nettype wire
'''
(root/'rtl/gfx/osd_layer_small.v').write_text(s,encoding='utf-8')
