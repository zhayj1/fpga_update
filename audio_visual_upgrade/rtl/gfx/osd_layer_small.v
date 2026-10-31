`default_nettype none
// Three-page 640x480 OSD at x=440..639, y=256..479 (200x224).
// All drawing uses the current raster; only the
// attack history and the small subset font ROM occupy on-chip memory.
module osd_layer_small #(parameter integer EXTENDED=0) (
    input wire clk, rst, de,
    input wire [9:0] x, y,
    input wire visible,
    input wire [2:0] page,
    input wire [2:0] selected,
    input wire [41:0] color_indices,input wire [4:0] effects,
    output wire [6:0] swatch_index,input wire [23:0] swatch_rgb,
    input wire [5:0] sensitivity,
    input wire [8:0] volume, sat_base, sat_max, con_base, con_max,
    input wire [8:0] sat_current, con_current,
    input wire [7:0] loud, relative,
    input wire analysis_stb, attack_hit, song_clear,
    input wire [12:0] flux, threshold,
    input wire [16:0] scope_max,
    output wire [23:0] rgb,
    output reg valid
);
    // Palette indices; scripts/generate_osd_palette.py holds the RGB values.
    localparam [1:0] TEXT=0, CYAN=1, AMBER=2, MUTED=3;
    localparam [3:0] BG=0, LINE=1, B_CYAN=2, BAR_OFF=3,
        SCOPE_BORDER=4, SCOPE_BG=5, SCOPE_LINE=6, THRESHOLD=7, B_AMBER=8;

    function [6:0] label_glyph;
        input [2:0] p;
        input [2:0] row, slot;
        reg [27:0] word;
        begin
            word=28'd0;
            case (p)
            2'd0: case (row)
                3'd7:word={7'd4,7'd3,7'd2,7'd1};
                3'd0:word={7'd0,7'd0,7'd14,7'd13};
                3'd1:word={7'd0,7'd0,7'd16,7'd15};
                default:word=0;
            endcase
            2'd1: case (row)
                3'd7:word={7'd8,7'd7,7'd6,7'd5};
                3'd0:word={7'd20,7'd19,7'd18,7'd17};
                3'd1:word={7'd10,7'd9,7'd22,7'd21};
                3'd2:word={7'd0,7'd20,7'd24,7'd23};
                3'd3:word={7'd0,7'd20,7'd25,7'd22};
                default:word=0;
            endcase
            2'd2: case (row)
                3'd7:word={7'd12,7'd11,7'd10,7'd9};
                3'd0:word={7'd0,7'd0,7'd10,7'd9};
                3'd1:word={7'd27,7'd26,7'd24,7'd23};
                3'd2:word={7'd29,7'd28,7'd24,7'd23};
                3'd3:word={7'd27,7'd26,7'd25,7'd22};
                3'd4:word={7'd29,7'd28,7'd25,7'd22};
                default:word=0;
            endcase
            3'd3: case(row)
                7:word={7'd66,7'd65,7'd11,7'd64};
                0:word={7'd0,7'd67,7'd18,7'd17};
                1:word={7'd71,7'd70,7'd69,7'd68};
                2:word={7'd73,7'd72,7'd69,7'd68};
                3:word={7'd0,7'd0,7'd74,7'd68};
                4:word={7'd0,7'd0,7'd75,7'd68};
                5:word={7'd0,7'd0,7'd77,7'd76};
                default:word=0;
            endcase
            3'd4: case(row)
                7:word={7'd66,7'd65,7'd79,7'd78};
                0:word={7'd83,7'd82,7'd81,7'd80};
                1:word={7'd87,7'd86,7'd85,7'd84};
                2:word={7'd90,7'd89,7'd88,7'd67};
                3:word={7'd0,7'd67,7'd18,7'd17};
                4:word={7'd92,7'd91,7'd12,7'd11};
                default:word=0;
            endcase
            default:word=0;
            endcase
            case (slot)
                3'd0:label_glyph=word[6:0];
                3'd1:label_glyph=word[13:7];
                3'd2:label_glyph=word[20:14];
                3'd3:label_glyph=word[27:21];
                default:label_glyph=0;
            endcase
        end
    endfunction

    reg [13:0] history [0:319];
    reg [13:0] history_read;
    reg [8:0] write_ptr, count;
    reg [19:0] hits_bcd;
    // Exact floor(local_x*320/176) = floor(local_x*20/11).
    // Raster recurrence keeps the original 320-sample time window without a divider.
    reg [8:0] source_idx;
    reg [4:0] source_phase;
    always @(posedge clk) begin
        if(rst || x<10'd452 || x>=10'd628) begin source_idx<=0; source_phase<=0; end
        else if(source_phase>=5'd2) begin
            source_idx<=source_idx+9'd2; source_phase<=source_phase-5'd2;
        end else begin
            source_idx<=source_idx+9'd1; source_phase<=source_phase+5'd9;
        end
    end
    wire [9:0] addr_sum={1'b0,(count==9'd320 ? write_ptr : 9'd0)}+{1'b0,source_idx};
    wire [8:0] read_addr=(addr_sum>=10'd320) ? addr_sum-10'd320 : addr_sum[8:0];
    // One serial reciprocal calculation per analysis frame. The same DSP
    // normalizes the raw history during the scope and its threshold elsewhere.
    // Q14 reciprocal: 56 pixels * 16384 / max(5, baseline + 4*deviation).
    reg [16:0] divisor, remainder;
    reg [19:0] divide_bits;
    reg [4:0] divide_left;
    reg [17:0] scale_q14;
    reg [12:0] threshold_hold;
    wire [17:0] trial={remainder,divide_bits[19]};
    wire subtract_ok=trial>={1'b0,divisor};
    wire [17:0] trial_rest=subtract_ok ? trial-{1'b0,divisor} : trial;
    wire [19:0] quotient_next={divide_bits[18:0],subtract_ok};
    reg scope_sample_d,scope_sample_e;
    reg [30:0] normalize_product_q;
    wire [12:0] normalize_source=scope_sample_d ? history_read[12:0] : threshold_hold;
    wire [30:0] normalize_product=normalize_source*scale_q14;
    wire [5:0] sample_amp=(normalize_product_q[30:14]>17'd56)?7'd56:
                            normalize_product_q[19:14];
    reg [5:0] threshold_amp;
    always @(posedge clk) begin
        if (rst || song_clear) begin
            write_ptr<=0; count<=0; hits_bcd<=0; threshold_amp<=0;
            divisor<=5; remainder<=0; divide_bits<=0; divide_left<=0;
            scale_q14<=18'd183500; threshold_hold<=0; scope_sample_d<=0;scope_sample_e<=0;normalize_product_q<=0;
        end else begin
          normalize_product_q<=normalize_product;
          scope_sample_e<=scope_sample_d;
          scope_sample_d<=x>=10'd452 && x<10'd628 && page==0;
          if (analysis_stb) begin
            history[write_ptr]<={attack_hit,flux};
            divisor<=(scope_max<17'd5)?17'd5:scope_max;
            divide_bits<=20'd917504; remainder<=0; divide_left<=20;
            threshold_hold<=threshold;
            write_ptr<=(write_ptr==9'd319) ? 9'd0 : write_ptr+9'd1;
            if (count<9'd320) count<=count+9'd1;
            if (attack_hit && hits_bcd!=20'h99999) begin
                if (hits_bcd[3:0]!=4'd9) hits_bcd[3:0]<=hits_bcd[3:0]+4'd1;
                else begin
                    hits_bcd[3:0]<=0;
                    if (hits_bcd[7:4]!=4'd9) hits_bcd[7:4]<=hits_bcd[7:4]+4'd1;
                    else begin
                        hits_bcd[7:4]<=0;
                        if (hits_bcd[11:8]!=4'd9) hits_bcd[11:8]<=hits_bcd[11:8]+4'd1;
                        else begin
                            hits_bcd[11:8]<=0;
                            if (hits_bcd[15:12]!=4'd9) hits_bcd[15:12]<=hits_bcd[15:12]+4'd1;
                            else begin
                                hits_bcd[15:12]<=0;
                                hits_bcd[19:16]<=hits_bcd[19:16]+4'd1;
                            end
                        end
                    end
                end
            end
          end else if (divide_left!=0) begin
            divide_left<=divide_left-5'd1;
            remainder<=trial_rest[16:0]; divide_bits<=quotient_next;
            if (divide_left==1) scale_q14<=quotient_next[17:0];
          end
          if (!scope_sample_e && divide_left==0) threshold_amp<=sample_amp;
        end
        history_read<=history[read_addr];
    end

    reg [2:0] row_sel, row_sel_next;
    reg [9:0] row_top, row_top_next;
    reg row_active, row_active_next;
    reg [8:0] value;
    reg percent;
    wire [2:0] numeric_pos=(x-10'd588)>>3;
    reg [2:0] numeric_index;
    reg [19:0] numeric_bcd;
    reg numeric_ink;
    reg [6:0] glyph_req;
    reg [3:0] glyph_row_req, glyph_col_req;
    reg ascii_req;
    reg [1:0] glyph_color;
    reg [3:0] digit_value;
    reg [2:0] bar_kind;
    reg [8:0] bar_value;
    reg [9:0] bar_y;
    reg [8:0] value_q;
    wire [11:0] value_bcd_q;
    wire [7:0] bar_lookup;
    wire [8:0] bar_width_q={1'b0,bar_lookup};
    osd_numeric_rom u_numeric(.clk(clk),.number(value_q),.bar_value(bar_value),
        .bar_kind(bar_kind),.bcd(value_bcd_q),.bar(bar_lookup));
    wire [3:0] font_pixel;
    osd_font_pixel u_font (.clk(clk),.glyph(glyph_req),.row(glyph_row_req),
                         .col(glyph_col_req),.alpha(font_pixel));

    // Row descriptors settle in the left margin, hundreds of clocks before
    // the first OSD pixel. Keep Y decoding out of the numeric/font path.
    always @(posedge clk) begin
        row_sel<=row_sel_next; row_top<=row_top_next;
        row_active<=row_active_next;
        value_q<=value;
    end
    always @(*) begin
        row_sel_next=0; row_top_next=0; row_active_next=0;
        if (y>=10'd306 && y<10'd332) begin row_sel_next=0; row_top_next=306; row_active_next=1; end
        else if (y>=10'd338 && y<10'd364) begin row_sel_next=1; row_top_next=338; row_active_next=1; end
        else if (page!=0 && y>=10'd370 && y<10'd396) begin row_sel_next=2; row_top_next=370; row_active_next=1; end
        else if (page!=0 && y>=10'd402 && y<10'd428) begin row_sel_next=3; row_top_next=402; row_active_next=1; end
        else if ((page==2 || page==4) && y>=10'd434 && y<10'd460) begin row_sel_next=4; row_top_next=434; row_active_next=1; end
    end
    always @(*) begin
        value=0; percent=1; bar_kind=7; bar_value=0;
        case(page)
        0:begin
            percent=0;
            if(row_sel==0) begin value={3'd0,sensitivity};bar_kind=0;bar_value=value;end
        end
        1:begin
            bar_kind=1;bar_value={1'b0,relative};
            case(row_sel)
            0:begin value=({8'd0,loud}*17'd100)>>8;bar_value={1'b0,loud};end
            1:value=({8'd0,relative}*17'd100)>>8;
            2:value=sat_current;
            3:value=con_current;
            default:begin bar_kind=7;bar_value=0;end
            endcase
        end
        default:begin
            case(row_sel)
            0:begin value=volume;bar_kind=2;end
            1:begin value=sat_base;bar_kind=3;end
            2:begin value=sat_max;bar_kind=4;end
            3:begin value=con_base;bar_kind=5;end
            4:begin value=con_max;bar_kind=6;end
            endcase
            bar_value=value;
        end
        endcase
        bar_y=row_top+10'd22;
        numeric_bcd=(page==0 && row_sel==1) ? hits_bcd : {8'd0,value_bcd_q};
        numeric_index=percent ? numeric_pos+3'd1 : numeric_pos;
        numeric_ink=0;
        digit_value=0;
        case (numeric_index)
            3'd0: begin digit_value=numeric_bcd[19:16]; numeric_ink=|numeric_bcd[19:16]; end
            3'd1: begin digit_value=numeric_bcd[15:12]; numeric_ink=|numeric_bcd[19:12]; end
            3'd2: begin digit_value=numeric_bcd[11:8]; numeric_ink=|numeric_bcd[19:8]; end
            3'd3: begin digit_value=numeric_bcd[7:4]; numeric_ink=|numeric_bcd[19:4]; end
            3'd4: begin digit_value=numeric_bcd[3:0]; numeric_ink=1'b1; end
            default: begin digit_value=0; numeric_ink=0; end
        endcase
        if (percent && numeric_pos==3'd4) begin
            numeric_ink=1'b1;
        end
        glyph_req=0; glyph_row_req=0; glyph_col_req=0;
        ascii_req=0; glyph_color=TEXT;
        if (y>=10'd268 && y<10'd284) begin
            glyph_row_req=y-10'd268;
            if (x>=10'd452 && x<10'd516) begin
                glyph_req=label_glyph(page,3'd7,(x-10'd452)>>4);
                glyph_col_req=x-10'd452;
            end else if (x>=10'd572 && x<10'd580) begin
                glyph_req=42; ascii_req=1; glyph_color=CYAN; glyph_col_req=x-10'd572;
            end else if (x>=10'd588 && x<10'd612) begin
                ascii_req=1; glyph_color=AMBER;
                case ((x-10'd588)>>3)
                0:glyph_req=7'd31+{4'd0,page};
                1:glyph_req=41;
                2:glyph_req=EXTENDED?7'd35:7'd33;
                endcase
                glyph_col_req=x-10'd588;
            end else if (x>=10'd620 && x<10'd628) begin
                glyph_req=43; ascii_req=1; glyph_color=CYAN; glyph_col_req=x-10'd620;
            end
        end else if (page!=3 && row_active && y<row_top+10'd16) begin
            glyph_row_req=y-row_top;
            if (x>=10'd452 && x<10'd516) begin
                glyph_req=label_glyph(page,row_sel,(x-10'd452)>>4);
                glyph_col_req=x-10'd452;
                if ((page==2 || page==4) && selected!=row_sel) glyph_color=MUTED;
            end else if (page<3 && x>=10'd588 && x<10'd628 && numeric_ink) begin
                ascii_req=1;
                glyph_req=(percent && numeric_pos==3'd4) ? 7'd40 : (7'd30+{2'd0,digit_value});
                glyph_col_req=x-10'd588;
                glyph_color=(page==0 && row_sel==1) ? AMBER : CYAN;
            end
        end
        if(EXTENDED && page==3) begin
            if(y>=306 && y<322 && x>=452 && x<516) begin
                glyph_req=label_glyph(3,selected,(x-452)>>4);
                glyph_row_req=y-306;glyph_col_req=x-452;glyph_color=TEXT;
            end
            if(y>=452 && y<468 && x>=452 && x<484) begin
                glyph_req=x<468?7'd93:7'd94;
                glyph_row_req=y-452;glyph_col_req=x-452;glyph_color=TEXT;
            end
        end
        glyph_col_req=ascii_req ? {1'b0,glyph_col_req[2:0]} : glyph_col_req;
    end

    wire [6:0] selected_index=selected==0?color_indices[6:0]:
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
    reg [9:0] x_e,y_e,row_top_e,bar_y_e;
    reg [8:0] bar_width_e;
    reg [3:0] glyph_col_d;
    reg [9:0] x_d,y_d,row_top_d,bar_y_d;
    reg [8:0] bar_width_d;
    reg panel_d,row_active_d,selected_d,history_valid_d;
    reg [2:0] page_d;
    reg [1:0] glyph_color_d;
    reg history_hit_e;
    reg [3:0] glyph_alpha;
    reg ascii_d, panel_e, glyph_d, row_active_e, selected_e, history_valid_e;
    reg [2:0] page_e;
    reg [1:0] glyph_color_e;
    reg [5:0] prev_amp;
    wire [5:0] scope_level=10'd432-y_e;
    wire [5:0] min_amp=(x_e==10'd452 || sample_amp<prev_amp)?sample_amp:prev_amp;
    wire [5:0] max_amp=(x_e==10'd452 || sample_amp>prev_amp)?sample_amp:prev_amp;
    reg [3:0] panel_rgb;
    // Synchronous lookup replaces the old output register and the entire
    // variable RGB multiply/divide chain. Latency remains three pixel clocks.
`ifdef OSD_SIM
    localparam PALETTE_FILE="rtl/gfx/osd_blend_palette.dath";
`else
    localparam PALETTE_FILE="osd_blend_palette.dath";
`endif
    wire [31:0] palette_rgb;
    assign rgb=custom_f ? custom_rgb_f : palette_rgb[23:0];
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
        .addrb(10'd0),.dib(32'd0),.dob(),.rstb(1'b0),.beb(1'b0));
    always @(posedge clk) begin
        if (rst) begin
            x_e<=0; y_e<=0; row_top_e<=0; bar_y_e<=0; bar_width_e<=0;
            glyph_col_d<=0; ascii_d<=0; panel_e<=0; glyph_d<=0;
            row_active_e<=0; selected_e<=0; history_valid_e<=0;
            page_e<=0; glyph_color_e<=0; prev_amp<=0;
            x_d<=0;y_d<=0;row_top_d<=0;bar_y_d<=0;bar_width_d<=0;
            panel_d<=0;row_active_d<=0;selected_d<=0;history_valid_d<=0;
            page_d<=0;glyph_color_d<=0;history_hit_e<=0;glyph_alpha<=0;
            valid<=0;
        end else begin
            x_d<=x; y_d<=y; page_d<=page;
            x_e<=x_d;y_e<=y_d;page_e<=page_d;
            row_top_e<=row_top_d;bar_y_e<=bar_y_d;bar_width_e<=bar_width_d;
            panel_e<=panel_d;row_active_e<=row_active_d;selected_e<=selected_d;
            history_valid_e<=history_valid_d;glyph_color_e<=glyph_color_d;
            history_hit_e<=history_read[13];
            glyph_alpha<=glyph_d ? font_pixel : 4'd0;
            row_top_d<=row_top; bar_y_d<=bar_y; bar_width_d<=bar_width_q;
            glyph_col_d<=glyph_col_req; ascii_d<=ascii_req;
            glyph_d<=glyph_req!=0; glyph_color_d<=glyph_color;
            panel_d<=visible && de && x>=10'd440 && x<10'd640 && y>=10'd256 && y<10'd480;
            row_active_d<=row_active;
            selected_d<=(page==2 || page==4) && selected==row_sel;
            history_valid_d<=count==9'd320 || source_idx<count;
            if (x_e>=10'd452 && x_e<10'd628) prev_amp<=sample_amp;

            valid<=panel_e;
        end
    end
    // Mix the glyph into the actual pixel (panel, bar or scope), preserving
    // the full 4-bit edge coverage even where foreground elements cross.
    always @(*) begin
        panel_rgb=BG;
        if(panel_e) begin
            if(x_e==10'd440 || x_e==10'd639 || y_e==10'd256 || y_e==10'd479 ||
                (y_e==10'd295 && x_e>=10'd452 && x_e<10'd628)) panel_rgb=LINE;
            if(row_active_e && (page_e==2 || page_e==4) && selected_e &&
                x_e>=10'd444 && x_e<10'd447 &&
                y_e>=row_top_e+10'd1 && y_e<row_top_e+10'd15) panel_rgb=B_CYAN;
            if(page_e<3 && row_active_e && !(page_e==0 && row_top_e==10'd338) &&
                x_e>=10'd452 && x_e<10'd628 && y_e>=bar_y_e && y_e<bar_y_e+10'd3)
                panel_rgb=((x_e-10'd452)<bar_width_e) ? B_CYAN : BAR_OFF;
            if(page_e==0 && x_e>=10'd451 && x_e<=10'd628 &&
                (y_e==10'd369 || y_e==10'd436)) panel_rgb=SCOPE_BORDER;
            if(page_e==0 && y_e>=10'd370 && y_e<10'd436 && x_e>=10'd452 && x_e<10'd628) begin
                panel_rgb=SCOPE_BG;
                if(history_valid_e && y_e<=10'd432 && scope_level>=min_amp && scope_level<=max_amp)
                    panel_rgb=SCOPE_LINE;
                if(y_e<=10'd432 && scope_level==threshold_amp && x_e[2:0]<3'd4) panel_rgb=THRESHOLD;
                if(history_valid_e && history_hit_e) panel_rgb=B_AMBER;
            end
        end
    end
endmodule
`default_nettype wire
