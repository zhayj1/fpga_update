`default_nettype none
// Three-page 640x480 OSD. All drawing uses the current raster; only the
// attack history and the small subset font ROM occupy on-chip memory.
module osd_layer (
    input wire clk, rst, de,
    input wire [9:0] x, y,
    input wire visible,
    input wire [1:0] page,
    input wire [2:0] selected,
    input wire [5:0] sensitivity,
    input wire [8:0] volume, sat_base, sat_max, con_base, con_max,
    input wire [8:0] sat_current, con_current,
    input wire [7:0] loud, relative,
    input wire analysis_stb, attack_hit, song_clear,
    input wire [12:0] flux, threshold,
    input wire [16:0] scope_max,
    output reg [23:0] rgb,
    output reg valid
);
    localparam [23:0] BG=24'h070e13, TEXT=24'he7f0f0;
    localparam [23:0] CYAN=24'h49ded4, AMBER=24'hffb347;
    localparam [23:0] MUTED=24'hb6c6c9, LINE=24'h48636a;

    function [5:0] label_glyph;
        input [1:0] p;
        input [2:0] row, slot;
        reg [23:0] word;
        begin
            word=24'd0;
            case (p)
            2'd0: case (row)
                3'd7:word={6'd4,6'd3,6'd2,6'd1};
                3'd0:word={6'd0,6'd0,6'd14,6'd13};
                3'd1:word={6'd0,6'd0,6'd16,6'd15};
                default:word=0;
            endcase
            2'd1: case (row)
                3'd7:word={6'd8,6'd7,6'd6,6'd5};
                3'd0:word={6'd20,6'd19,6'd18,6'd17};
                3'd1:word={6'd10,6'd9,6'd22,6'd21};
                3'd2:word={6'd0,6'd20,6'd24,6'd23};
                3'd3:word={6'd0,6'd20,6'd25,6'd22};
                default:word=0;
            endcase
            2'd2: case (row)
                3'd7:word={6'd12,6'd11,6'd10,6'd9};
                3'd0:word={6'd0,6'd0,6'd10,6'd9};
                3'd1:word={6'd27,6'd26,6'd24,6'd23};
                3'd2:word={6'd29,6'd28,6'd24,6'd23};
                3'd3:word={6'd27,6'd26,6'd25,6'd22};
                3'd4:word={6'd29,6'd28,6'd25,6'd22};
                default:word=0;
            endcase
            default:word=0;
            endcase
            case (slot)
                3'd0:label_glyph=word[5:0];
                3'd1:label_glyph=word[11:6];
                3'd2:label_glyph=word[17:12];
                3'd3:label_glyph=word[23:18];
                default:label_glyph=0;
            endcase
        end
    endfunction

    reg [13:0] history [0:319];
    reg [13:0] history_read;
    reg [8:0] write_ptr, count;
    reg [19:0] hits_bcd;
    wire [8:0] local_x=x-10'd405;
    wire [8:0] source_approx=local_x+(local_x>>1)-(local_x>>4)+
        (local_x>>6)+((local_x>=9'd192)?9'd1:9'd0);
    wire [8:0] source_idx=(x>=10'd405 && x<10'd625) ? source_approx : 9'd0;
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
    reg scope_sample_d;
    wire [12:0] normalize_source=scope_sample_d ? history_read[12:0] : threshold_hold;
    wire [30:0] normalize_product=normalize_source*scale_q14;
    wire [5:0] sample_amp=(normalize_product[30:14]>17'd56)?6'd56:
                            normalize_product[19:14];
    reg [5:0] threshold_amp;
    always @(posedge clk) begin
        if (rst || song_clear) begin
            write_ptr<=0; count<=0; hits_bcd<=0; threshold_amp<=0;
            divisor<=5; remainder<=0; divide_bits<=0; divide_left<=0;
            scale_q14<=18'd183500; threshold_hold<=0; scope_sample_d<=0;
        end else begin
          scope_sample_d<=x>=10'd405 && x<10'd625 && page==0;
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
          if (!scope_sample_d && divide_left==0) threshold_amp<=sample_amp;
        end
        history_read<=history[read_addr];
    end

    reg [2:0] row_sel, row_sel_next;
    reg [9:0] row_top, row_top_next;
    reg row_active, row_active_next;
    reg [8:0] value, bar_width;
    reg percent;
    wire [2:0] numeric_pos=(x-10'd545)>>4;
    reg [2:0] numeric_index;
    reg [19:0] numeric_bcd;
    reg numeric_ink;
    reg [5:0] glyph_req;
    reg [4:0] glyph_row_req, glyph_col_req;
    reg ascii_req;
    reg [23:0] glyph_color;
    reg [3:0] digit_value;
    reg [8:0] bar_delta;
    reg [10:0] bar_scale;
    wire [19:0] bar_product=bar_delta*bar_scale;
    reg [9:0] bar_y;
    reg [11:0] value_bcd;
    reg [8:0] value_q, bar_width_q;
    reg [11:0] value_bcd_q;
    reg [8:0] decimal_rest;
    reg [8:0] decimal_ones;
    reg [3:0] decimal_hundreds, decimal_tens;
    wire [31:0] font_bits;
    osd_font_rom u_font (.clk(clk),.glyph(glyph_req),.row(glyph_row_req),
                         .bits(font_bits));

    // Row descriptors settle in the left margin, hundreds of clocks before
    // the first OSD pixel. Keep Y decoding out of the numeric/font path.
    always @(posedge clk) begin
        row_sel<=row_sel_next; row_top<=row_top_next;
        row_active<=row_active_next;
        value_q<=value; value_bcd_q<=value_bcd;
        bar_width_q<=bar_width;
    end
    always @(*) begin
        row_sel_next=0; row_top_next=0; row_active_next=0;
        if (page==0) begin
            if (y>=10'd61 && y<10'd106) begin row_sel_next=0; row_top_next=61; row_active_next=1; end
            else if (y>=10'd115 && y<10'd160) begin row_sel_next=1; row_top_next=115; row_active_next=1; end
        end else if (page==1) begin
            if (y>=10'd62 && y<10'd109) begin row_sel_next=0; row_top_next=62; row_active_next=1; end
            else if (y>=10'd124 && y<10'd171) begin row_sel_next=1; row_top_next=124; row_active_next=1; end
            else if (y>=10'd186 && y<10'd233) begin row_sel_next=2; row_top_next=186; row_active_next=1; end
            else if (y>=10'd248 && y<10'd295) begin row_sel_next=3; row_top_next=248; row_active_next=1; end
        end else begin
            if (y>=10'd58 && y<10'd105) begin row_sel_next=0; row_top_next=58; row_active_next=1; end
            else if (y>=10'd110 && y<10'd157) begin row_sel_next=1; row_top_next=110; row_active_next=1; end
            else if (y>=10'd162 && y<10'd209) begin row_sel_next=2; row_top_next=162; row_active_next=1; end
            else if (y>=10'd214 && y<10'd261) begin row_sel_next=3; row_top_next=214; row_active_next=1; end
            else if (y>=10'd266 && y<10'd313) begin row_sel_next=4; row_top_next=266; row_active_next=1; end
        end
    end
    always @(*) begin
        value=0; bar_width=0; percent=1; bar_delta=0; bar_scale=0;
        case (page)
        2'd0: begin
            if (row_sel==0) begin
                value={3'd0,sensitivity};
                bar_delta={3'd0,sensitivity}-9'd2;
                bar_scale=11'd1468;
                percent=0;
            end else begin value=0; percent=0; end
        end
        2'd1: begin
            case (row_sel)
            0: begin value=({8'd0,loud}*16'd100)>>8;
                     bar_delta={1'd0,loud}; bar_scale=11'd219; end
            1: begin value=({8'd0,relative}*16'd100)>>8;
                     bar_delta={1'd0,relative}; bar_scale=11'd219; end
            2: begin value=sat_current;
                     bar_delta={1'd0,relative}; bar_scale=11'd219; end
            3: begin value=con_current;
                     bar_delta={1'd0,relative}; bar_scale=11'd219; end
            endcase
        end
        default: begin
            case (row_sel)
            0: begin value=volume; bar_delta=volume; bar_scale=11'd558; end
            1: begin value=sat_base; bar_delta=sat_base-9'd60;
                     bar_scale=11'd620; end
            2: begin value=sat_max; bar_delta=sat_max-9'd100;
                     bar_scale=11'd349; end
            3: begin value=con_base; bar_delta=con_base-9'd80;
                     bar_scale=11'd1116; end
            4: begin value=con_max; bar_delta=con_max-9'd100;
                     bar_scale=11'd797; end
            endcase
        end
        endcase
        bar_width=(bar_product[19:8]>12'd218) ? 9'd218 : bar_product[16:8];
        bar_y=row_top+((page==0) ? 10'd40 : (page==1 ? 10'd41 : 10'd39));
        decimal_hundreds=(value_q>=9'd200)?4'd2:((value_q>=9'd100)?4'd1:4'd0);
        decimal_rest=value_q-(decimal_hundreds==4'd2 ? 9'd200 :
                            (decimal_hundreds==4'd1 ? 9'd100 : 9'd0));
        decimal_tens=(decimal_rest>=9'd90)?4'd9:
                     (decimal_rest>=9'd80)?4'd8:
                     (decimal_rest>=9'd70)?4'd7:
                     (decimal_rest>=9'd60)?4'd6:
                     (decimal_rest>=9'd50)?4'd5:
                     (decimal_rest>=9'd40)?4'd4:
                     (decimal_rest>=9'd30)?4'd3:
                     (decimal_rest>=9'd20)?4'd2:
                     (decimal_rest>=9'd10)?4'd1:4'd0;
        decimal_ones=decimal_rest-((decimal_tens<<3)+(decimal_tens<<1));
        value_bcd={decimal_hundreds,decimal_tens,decimal_ones[3:0]};
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
        if (y>=10'd12 && y<10'd44) begin
            glyph_row_req=y-10'd12;
            if (x>=10'd401 && x<10'd529) begin
                glyph_req=label_glyph(page,3'd7,(x-10'd401)>>5);
                glyph_col_req=x-10'd401;
            end else if (x>=10'd540 && x<10'd556) begin
                glyph_req=42; ascii_req=1; glyph_color=CYAN;
                glyph_col_req=x-10'd540;
            end else if (x>=10'd562 && x<10'd610) begin
                ascii_req=1; glyph_color=AMBER;
                case ((x-10'd562)>>4)
                0:glyph_req=6'd31+{4'd0,page};
                1:glyph_req=41;
                2:glyph_req=33;
                endcase
                glyph_col_req=x-10'd562;
            end else if (x>=10'd619 && x<10'd635) begin
                glyph_req=43; ascii_req=1; glyph_color=CYAN;
                glyph_col_req=x-10'd619;
            end
        end else if (row_active && y<row_top+10'd32) begin
            glyph_row_req=y-row_top;
            if (x>=10'd405 && x<10'd533) begin
                glyph_req=label_glyph(page,row_sel,(x-10'd405)>>5);
                glyph_col_req=x-10'd405;
                if (page==2 && selected!=row_sel) glyph_color=MUTED;
            end else if (x>=10'd545 && x<10'd625 &&
                         (numeric_ink || (percent && numeric_pos==3'd4))) begin
                ascii_req=1;
                glyph_req=(percent && numeric_pos==3'd4) ? 6'd40 :
                          (6'd30+{2'd0,digit_value});
                glyph_col_req=x-10'd545;
                glyph_color=(page==0 && row_sel==1) ? AMBER : CYAN;
            end
        end
        glyph_col_req=ascii_req ? {1'b0,glyph_col_req[3:0]} : glyph_col_req;
    end

    reg [9:0] x_d,y_d,row_top_d,bar_y_d;
    reg [8:0] bar_width_d;
    reg [4:0] glyph_col_d;
    reg ascii_d, panel_d, glyph_d, row_active_d, selected_d, history_valid_d;
    reg [1:0] page_d;
    reg [23:0] glyph_color_d;
    reg [5:0] prev_amp;
    wire [5:0] scope_level=10'd230-y_d;
    wire [5:0] min_amp=(x_d==10'd405 || sample_amp<prev_amp)?sample_amp:prev_amp;
    wire [5:0] max_amp=(x_d==10'd405 || sample_amp>prev_amp)?sample_amp:prev_amp;
    wire glyph_ink=ascii_d ? font_bits[15-glyph_col_d] : font_bits[31-glyph_col_d];
    always @(posedge clk) begin
        if (rst) begin
            x_d<=0; y_d<=0; row_top_d<=0; bar_y_d<=0; bar_width_d<=0;
            glyph_col_d<=0; ascii_d<=0; panel_d<=0; glyph_d<=0;
            row_active_d<=0; selected_d<=0; history_valid_d<=0;
            page_d<=0; glyph_color_d<=0; prev_amp<=0;
            rgb<=0; valid<=0;
        end else begin
            x_d<=x; y_d<=y; page_d<=page;
            row_top_d<=row_top; bar_y_d<=bar_y; bar_width_d<=bar_width_q;
            glyph_col_d<=glyph_col_req; ascii_d<=ascii_req;
            glyph_d<=glyph_req!=0; glyph_color_d<=glyph_color;
            panel_d<=visible && de && x>=10'd392 &&
                ((page==0 && y<10'd268) || (page!=0 && y<10'd318));
            row_active_d<=row_active;
            selected_d<=page==2 && selected==row_sel;
            history_valid_d<=count==9'd320 || source_idx<count;
            if (x_d>=10'd405 && x_d<10'd625) prev_amp<=sample_amp;

            valid<=panel_d;
            rgb<=BG;
            if (panel_d) begin
                if (x_d==10'd392 || y_d==10'd0 ||
                    (y_d==10'd51 && x_d>=10'd401 && x_d<10'd629) ||
                    (page_d==0 && y_d==10'd267) ||
                    (page_d!=0 && y_d==10'd317)) rgb<=LINE;
                if (row_active_d && page_d==2 && selected_d &&
                    x_d>=10'd396 && x_d<10'd400 &&
                    y_d>=row_top_d+10'd3 && y_d<row_top_d+10'd30) rgb<=CYAN;
                if (row_active_d && !(page_d==0 && row_top_d==10'd115) &&
                    x_d>=10'd405 && x_d<10'd623 &&
                    y_d>=bar_y_d && y_d<bar_y_d+10'd5)
                    rgb<=((x_d-10'd405)<bar_width_d) ? CYAN : 24'h405258;
                if (page_d==0 && x_d>=10'd404 && x_d<=10'd625 &&
                    (y_d==10'd173 || y_d==10'd234)) rgb<=24'h24303b;
                if (page_d==0 && y_d>=10'd174 && y_d<10'd234 &&
                    x_d>=10'd405 && x_d<10'd625) begin
                    rgb<=24'h070b10;
                    if (history_valid_d && y_d<=10'd230 &&
                        scope_level>=min_amp && scope_level<=max_amp)
                        rgb<=24'h35d0c4;
                    if (y_d<=10'd230 && scope_level==threshold_amp &&
                        x_d[2:0]<3'd4) rgb<=24'hb8893c;
                    if (history_valid_d && history_read[13]) rgb<=AMBER;
                end
                if (glyph_d && glyph_ink) rgb<=glyph_color_d;
            end
        end
    end
endmodule
`default_nettype wire
