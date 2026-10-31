`default_nettype none
// TYP2 complete-font row renderer. One aligned 4/8-word transaction at a time. Partial
// rows are never published; an accepted cancelled/timed-out read is drained.
module text_row_aa #(
    parameter [20:0] LRC_BASE=21'h10B300, FONT_BASE=21'h10BBB0,
    parameter integer MAX_CH=24, CLK_HZ=150000000, WD_MS=4
)(
    input wire clk_sdr,rst_sdr_n,start,cancel,bank,small_font,
    input wire [15:0] fc,cnt,
    input wire [4:0] grow,
    input wire [23:0] played,
    output reg busy,done,
    output reg [7:0] err,
    output reg [9:0] width,
    output reg wr_en,
    output reg [10:0] wr_addr,
    output reg [7:0] wr_data,
    output reg px_req,
    output reg [20:0] px_addr,
    output wire [15:0] px_len,
    input wire px_ack,px_done,px_valid,
    input wire [31:0] px_data
);
    localparam [3:0] IDLE=0,REQ=1,RX=2,CHECK=3,HEADER=4,RECORD=5,
        DIRECTORY=6,GLYPH=7,WRITE=8,FINISH=9,DRAIN=10,ADDRESS=13;
    function integer bits_for;
        input integer n;
        integer v;
        begin bits_for=1; for(v=n-1;v>1;v=v>>1) bits_for=bits_for+1; end
    endfunction
    localparam integer WD_MAX=(CLK_HZ/1000)*WD_MS;
    localparam integer WD_W=bits_for(WD_MAX+1), CNT_W=bits_for(MAX_CH+1);
    reg [3:0] state,after_read;
    reg [WD_W-1:0] watchdog;
    reg [31:0] word0,word1,word2,word3;
    reg [3:0] received;
    reg [2:0] stored;
    reg [1:0] skip_words;
    reg long_read,record_cached;
    reg [63:0] next_record;
    reg [17:0] glyph_block;
    // Full input fields are validated in IDLE before these compact values are used.
    reg [8:0] first_l;
    reg [CNT_W-1:0] count_l;
    reg [15:0] code;
    reg [23:0] played_l;
    reg bank_l,small_l,sung;
    reg [4:0] row_l,pixels_left,glyph_width;
    reg time_hi_lt,time_hi_eq,time_mid_lt,time_mid_eq,time_lo_le;
    reg [4:0] char_number;
    reg [9:0] cursor;
    reg [1:0] select_word;
    reg [31:0] glyph_word;
    reg [2:0] nibble_number,skip_nibbles;
    reg [7:0] failure;
    wire [9:0] record_number={1'b0,first_l}+{5'd0,char_number};
    wire [20:0] record_addr=LRC_BASE+21'd136+{10'd0,record_number,1'b0};
    // Two byte lookups share one 512x18 9K ROM. DIRECTORY gives its
    // synchronous ports a full clock; ADDRESS only adds the two results.
    // This replaces the code->zone*94->compact slot->slot*31 carry chain.
    // The high-byte contribution includes the signed low-byte origin; the
    // 18-bit modular sum is the exact existing TYP2 16-byte block address.
`ifdef TEXT_SIM
    localparam BLOCK_FILE="rtl/gfx/glyph_blocks.dath";
`else
    localparam BLOCK_FILE="glyph_blocks.dath";
`endif
    wire [17:0] zone_block,column_block;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(18),.DATA_WIDTH_B(18),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
        .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE(BLOCK_FILE),.FILL_ALL("NONE"),.IMPLEMENT("9K")
    ) u_blocks(.clka(clk_sdr),.cea(1'b1),.ocea(1'b1),.wea(1'b0),
        .addra({1'b0,code[15:8]}),.dia(18'd0),.doa(zone_block),.rsta(1'b0),.bea(1'b0),
        .clkb(clk_sdr),.ceb(1'b1),.oceb(1'b1),.web(1'b0),
        .addrb({1'b1,code[7:0]}),.dib(18'd0),.dob(column_block),.rstb(1'b0),.beb(1'b0));
    // Compare the two bytes independently in DIRECTORY. ADDRESS combines
    // eight registered pairs; no selected low-byte comparator feeds a flop.
    reg [7:0] symbol_zone_q,symbol_column_q;
    reg single_q,ascii_ok_q,column_ok_q,chinese_ok_q;
    wire symbol_ok_q=|(symbol_zone_q & symbol_column_q);
    wire code_ok=single_q ? ascii_ok_q :
        (column_ok_q && (symbol_ok_q || chinese_ok_q));
    function [9:0] ascii_widths;
        input [6:0] c;
        begin
            case(c)
            7'd32,7'd39,7'd45:ascii_widths={5'd6,5'd5};
            7'd33,7'd106:ascii_widths={5'd11,5'd9};
            7'd34,7'd42,7'd60,7'd62,7'd69,7'd94,7'd95,7'd96,7'd122,7'd124:ascii_widths={5'd12,5'd10};
            7'd35,7'd71:ascii_widths={5'd17,5'd14};
            7'd36,7'd48,7'd49,7'd50,7'd51,7'd52,7'd53,7'd54,7'd55,7'd56,7'd57,7'd66,7'd78,7'd80,7'd85,7'd86,7'd88,7'd89,7'd97,7'd98,7'd99,7'd100,7'd101,7'd103,7'd107,7'd111,7'd112,7'd113:ascii_widths={5'd14,5'd12};
            7'd37:ascii_widths={5'd22,5'd19};
            7'd38,7'd109,7'd119:ascii_widths={5'd19,5'd16};
            7'd40,7'd41,7'd44,7'd46,7'd58,7'd59,7'd91,7'd93,7'd115,7'd123,7'd125:ascii_widths={5'd9,5'd8};
            7'd43,7'd61,7'd64,7'd67,7'd68,7'd79,7'd81:ascii_widths={5'd18,5'd15};
            7'd47,7'd92,7'd102:ascii_widths={5'd9,5'd7};
            7'd63,7'd70,7'd84,7'd90,7'd104,7'd110,7'd117,7'd120,7'd121:ascii_widths={5'd13,5'd11};
            7'd65,7'd82:ascii_widths={5'd15,5'd12};
            7'd72:ascii_widths={5'd15,5'd13};
            7'd73,7'd74,7'd76,7'd114,7'd116:ascii_widths={5'd8,5'd7};
            7'd75:ascii_widths={5'd16,5'd13};
            7'd77,7'd87:ascii_widths={5'd20,5'd17};
            7'd83:ascii_widths={5'd10,5'd9};
            7'd105,7'd108:ascii_widths={5'd7,5'd6};
            7'd118:ascii_widths={5'd11,5'd10};
            7'd126:ascii_widths={5'd16,5'd14};
            default:ascii_widths=0;
            endcase
        end
    endfunction
    wire [9:0] ascii_sizes=ascii_widths(code[6:0]);
    wire [4:0] descriptor_width=code[15:8]!=0 ? (small_l ? 5'd20 : 5'd24) :
                                         (small_l ? ascii_sizes[4:0] : ascii_sizes[9:5]);
    wire [31:0] next_glyph_word=select_word==0 ? word1 : select_word==1 ? word2 : word3;
    wire [23:0] record_time=state==4'd12 ? next_record[55:32] :
                                         (select_word[1] ? word3[23:0] : word1[23:0]);
    // Directory offsets are 16-byte blocks. 24px rows occupy three words;
    // 20px rows occupy 2.5 words, with the odd rows starting at a halfword.
    wire [6:0] row_words=small_l ? 7'd72+{1'b0,row_l,1'b0}+{3'd0,row_l[4:1]} :
                                               {1'b0,row_l,1'b0}+{2'd0,row_l};
    wire [20:0] glyph_addr=FONT_BASE+{1'b0,glyph_block,2'b00}+{14'd0,row_words};
    wire [10:0] next_width={1'b0,cursor}+{6'd0,glyph_width};
    assign px_len=long_read ? 16'd8 : 16'd4;
    function [31:0] be;
        input [31:0] value;
        begin be={value[7:0],value[15:8],value[23:16],value[31:24]}; end
    endfunction
    task read_four;
        input [20:0] address;
        input [3:0] following;
        begin px_addr<=address; after_read<=following; received<=0;
              stored<=0;skip_words<=0;long_read<=0;
              px_req<=1'b1; state<=REQ; watchdog<=0; end
    endtask
    always @(posedge clk_sdr) begin
        if(!rst_sdr_n) begin
            state<=IDLE; after_read<=IDLE; busy<=0; done<=0; err<=0; width<=0;
            wr_en<=0; wr_addr<=0; wr_data<=0; px_req<=0; px_addr<=0;
            watchdog<=0; word0<=0; word1<=0; word2<=0; word3<=0;
            received<=0;stored<=0;skip_words<=0;long_read<=0;
            record_cached<=0;next_record<=0;glyph_block<=0;
            first_l<=0; count_l<=0; code<=0; played_l<=0;
            bank_l<=0; small_l<=0; sung<=0; row_l<=0; pixels_left<=0;
            time_hi_lt<=0; time_hi_eq<=0; time_mid_lt<=0; time_mid_eq<=0; time_lo_le<=0;
            glyph_width<=0; char_number<=0; cursor<=0; select_word<=0;
            glyph_word<=0; nibble_number<=0; skip_nibbles<=0; failure<=0;
            single_q<=0;ascii_ok_q<=0;column_ok_q<=0;symbol_zone_q<=0;symbol_column_q<=0;chinese_ok_q<=0;
        end else begin
            done<=0; wr_en<=0;
            // Compare the timestamp bytes before combining the result in
            // DIRECTORY. No 24-bit compare feeds the sung register directly.
            if(state==RECORD || state==4'd12) begin
                time_hi_lt<=record_time[23:16]<played_l[23:16];
                time_hi_eq<=record_time[23:16]==played_l[23:16];
                time_mid_lt<=record_time[15:8]<played_l[15:8];
                time_mid_eq<=record_time[15:8]==played_l[15:8];
                time_lo_le<=record_time[7:0]<=played_l[7:0];
            end
            // Word changes depend only on the nibble boundary. Loading a
            // spare word after the final pixel is harmless; removing that
            // pixel/count condition shortens the 32-bit load mux control.
            if(state==4'd11) begin
                glyph_word<=nibble_number==3'd7 ? be(next_glyph_word) : {glyph_word[27:0],4'd0};
                nibble_number<=nibble_number+3'd1;
                if(nibble_number==3'd7) select_word<=select_word+2'd1;
            end
            if(state==IDLE || state==FINISH || px_ack || px_valid || px_done)
                watchdog<=0;
            else if(watchdog<WD_MAX) watchdog<=watchdog+1'b1;
            case(state)
            IDLE: if(start) begin
                busy<=1; failure<=0; cursor<=0; char_number<=0;record_cached<=0;
                width<=0; err<=0; first_l<=fc; count_l<=cnt; row_l<=grow;
                bank_l<=bank; small_l<=small_font; played_l<=played;
                if(cnt>MAX_CH || {1'b0,fc}+{1'b0,cnt}>17'd488 || grow>=(small_font ? 20 : 24)) begin
                    failure<=8'h66; state<=FINISH;
                end else if(cnt==0) state<=FINISH;
                else read_four(FONT_BASE,HEADER);
            end
            REQ: if(px_ack) begin px_req<=0; state<=RX; received<=0; end
            RX: begin
                if(px_valid) begin
                    if(skip_words!=0) skip_words<=skip_words-2'd1;
                    else begin
                        case(stored)
                        0:word0<=px_data; 1:word1<=px_data;
                        2:word2<=px_data; 3:word3<=px_data;
                        endcase
                        if(stored<4) stored<=stored+3'd1;
                    end
                    if(received<9) received<=received+4'd1;
                end
                if(px_done) state<=CHECK;
            end
            CHECK: if(received!=(long_read ? 4'd8 : 4'd4)) begin failure<=8'h04; state<=FINISH; end
                   else state<=after_read;
            HEADER: begin
                if(word0!=32'h32505954 || word1!=32'h00141804 ||
                   word2!=32'd964240 || word3!=32'd7540) begin
                    failure<=8'h66; state<=FINISH;
                end else begin
                    select_word<=record_addr[1:0];
                    read_four({record_addr[20:2],2'b00},RECORD);
                end
            end
            RECORD: begin
                code<=select_word[1] ? {word2[7:0],word2[15:8]} : {word0[7:0],word0[15:8]};
                next_record<={word3,word2};record_cached<=!select_word[1];
                state<=DIRECTORY;
            end
            DIRECTORY: begin
                sung<=time_hi_lt || (time_hi_eq && (time_mid_lt || (time_mid_eq && time_lo_le)));
                single_q<=code[15:8]==0;
                ascii_ok_q<=code[7:0]>=8'd32 && code[7:0]<=8'd126;
                column_ok_q<=code[7:0]>=8'hA1 && code[7:0]<=8'hFE;
                symbol_zone_q<={code[15:8]==8'hA9,code[15:8]==8'hA8,
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
                symbol_column_q[7]<=code[7:0]>=8'hA4 && code[7:0]<=8'hEF;
                chinese_ok_q<=code[15:8]>=8'hB0 && code[15:8]<=8'hF7 &&
                    !(code[15:8]==8'hD7 && code[7:0]>=8'hFA);
                glyph_width<=descriptor_width;state<=ADDRESS;
            end
            ADDRESS: begin
                if(!code_ok) begin failure<=8'h66; state<=FINISH; end
                else begin glyph_block<=zone_block+column_block;state<=GLYPH;end
            end
            GLYPH: begin
                if(glyph_width==0 || next_width>11'd640) begin
                    failure<=8'h66; state<=FINISH;
                end else begin
                    pixels_left<=glyph_width;
                    skip_nibbles<=(small_l && row_l[0]) ? 3'd4 : 3'd0;
                    select_word<=0;
                    read_four({glyph_addr[20:2],2'b00},WRITE);
                    // Three words per fixed row; one or two aligned granules.
                    skip_words<=glyph_addr[1:0];long_read<=glyph_addr[1];
                end
            end
            WRITE: begin
                // Only one 32-bit word is shifted at a time.
                glyph_word<=be(word0); nibble_number<=0; state<=4'd11;
            end
            4'd11: begin
                if(skip_nibbles!=0) skip_nibbles<=skip_nibbles-3'd1;
                else begin
                    wr_en<=1; wr_addr<={bank_l,cursor};
                    wr_data<={3'd0,sung,glyph_word[31:28]};
                    cursor<=cursor+10'd1; pixels_left<=pixels_left-5'd1;
                    if(pixels_left==5'd1) begin
                        if(char_number+5'd1>=count_l) state<=FINISH;
                        else begin char_number<=char_number+5'd1; state<=4'd12; end
                    end
                end
            end
            4'd12: begin
                if(record_cached) begin
                    code<={next_record[7:0],next_record[15:8]};
                    record_cached<=0;state<=DIRECTORY;
                end else begin
                    select_word<=record_addr[1:0];read_four({record_addr[20:2],2'b00},RECORD);
                end
            end
            DRAIN: if(px_done) state<=FINISH;
            FINISH: begin
                px_req<=0; done<=1; busy<=0; err<=failure;
                width<=failure==0 ? cursor : 10'd0; state<=IDLE;
            end
            default: state<=IDLE;
            endcase
            if((cancel || watchdog>=WD_MAX) && state!=IDLE && state!=FINISH && state!=DRAIN) begin
                failure<=cancel ? 8'h08 : 8'h04; px_req<=0; wr_en<=0;
                // An acknowledged transaction must close before another request.
                state<=((state==RX && !px_done) || (state==REQ && px_ack)) ? DRAIN : FINISH;
            end
        end
    end
endmodule
`default_nettype wire
