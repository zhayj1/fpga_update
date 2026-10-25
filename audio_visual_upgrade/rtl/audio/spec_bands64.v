`default_nettype none
// One bin RAM and one serial accumulator serve 64 disjoint bands.
module spec_bands64 (
    input wire clk, rst_n,
    input wire bin_stb,
    input wire [8:0] bin_idx,
    input wire [7:0] bin_mag,
    input wire frame_stb,
    output reg bar_stb,
    output reg [5:0] bar_idx,
    output reg [7:0] bar_level,
    output reg bars_done,
    output reg attack_band_stb,
    output reg [4:0] attack_band_idx,
    output reg [7:0] attack_band_level
);
    reg [7:0] bins [0:511];
    reg [8:0] rd_addr;
    reg [7:0] rd_data;
    always @(posedge clk) begin
        if (bin_stb) bins[bin_idx] <= bin_mag;
        rd_data <= bins[rd_addr];
    end
    // The approved 48 kHz map partitions bins 1..256 without overlap.
    // The lower edge is the previous band's upper edge plus one.
    function [8:0] band_hi;
        input [5:0] b;
        begin
            if (b <= 6'd21) band_hi = {3'd0, b} + 9'd1;
            else begin
                case (b)
                    6'd22: band_hi = 9'd24;
                    6'd23: band_hi = 9'd25;
                    6'd24: band_hi = 9'd27;
                    6'd25: band_hi = 9'd28;
                    6'd26: band_hi = 9'd30;
                    6'd27: band_hi = 9'd32;
                    6'd28: band_hi = 9'd34;
                    6'd29: band_hi = 9'd36;
                    6'd30: band_hi = 9'd38;
                    6'd31: band_hi = 9'd40;
                    6'd32: band_hi = 9'd43;
                    6'd33: band_hi = 9'd45;
                    6'd34: band_hi = 9'd48;
                    6'd35: band_hi = 9'd51;
                    6'd36: band_hi = 9'd54;
                    6'd37: band_hi = 9'd57;
                    6'd38: band_hi = 9'd61;
                    6'd39: band_hi = 9'd64;
                    6'd40: band_hi = 9'd68;
                    6'd41: band_hi = 9'd72;
                    6'd42: band_hi = 9'd76;
                    6'd43: band_hi = 9'd81;
                    6'd44: band_hi = 9'd86;
                    6'd45: band_hi = 9'd91;
                    6'd46: band_hi = 9'd96;
                    6'd47: band_hi = 9'd102;
                    6'd48: band_hi = 9'd108;
                    6'd49: band_hi = 9'd114;
                    6'd50: band_hi = 9'd121;
                    6'd51: band_hi = 9'd128;
                    6'd52: band_hi = 9'd136;
                    6'd53: band_hi = 9'd144;
                    6'd54: band_hi = 9'd153;
                    6'd55: band_hi = 9'd162;
                    6'd56: band_hi = 9'd171;
                    6'd57: band_hi = 9'd181;
                    6'd58: band_hi = 9'd192;
                    6'd59: band_hi = 9'd203;
                    6'd60: band_hi = 9'd215;
                    6'd61: band_hi = 9'd228;
                    6'd62: band_hi = 9'd242;
                    6'd63: band_hi = 9'd256;
                    default: band_hi = 9'd1;
                endcase
            end
        end
    endfunction

    // Q16 reciprocal for multi-bin bands; single-bin bands bypass this path.
    function [15:0] band_recip;
        input [5:0] b;
        begin
            case (b)
                6'd22, 6'd24, 6'd26, 6'd27, 6'd28, 6'd29, 6'd30, 6'd31, 6'd33: band_recip = 16'd32768;
                6'd32, 6'd34, 6'd35, 6'd36, 6'd37, 6'd39: band_recip = 16'd21845;
                6'd38, 6'd40, 6'd41, 6'd42: band_recip = 16'd16384;
                6'd43, 6'd44, 6'd45, 6'd46: band_recip = 16'd13107;
                6'd47, 6'd48, 6'd49: band_recip = 16'd10923;
                6'd50, 6'd51: band_recip = 16'd9362;
                6'd52, 6'd53: band_recip = 16'd8192;
                6'd54, 6'd55, 6'd56: band_recip = 16'd7282;
                6'd57: band_recip = 16'd6554;
                6'd58, 6'd59: band_recip = 16'd5958;
                6'd60: band_recip = 16'd5461;
                6'd61: band_recip = 16'd5041;
                6'd62, 6'd63: band_recip = 16'd4681;
                default: band_recip = 16'd0;
            endcase
        end
    endfunction

    // HTML's 36..13000 Hz attack bands at 48 kHz/1024 points. Adjacent
    // endpoints intentionally overlap; the first three bands are identical.
    function [8:0] attack_lo;
        input [4:0] b;
        begin
            case (b)
                5'd0, 5'd1, 5'd2: attack_lo=9'd1;
                5'd3: attack_lo=9'd2;
                5'd4: attack_lo=9'd3;
                5'd5: attack_lo=9'd4;
                5'd6: attack_lo=9'd5;
                5'd7: attack_lo=9'd8;
                5'd8: attack_lo=9'd11;
                5'd9: attack_lo=9'd15;
                5'd10: attack_lo=9'd20;
                5'd11: attack_lo=9'd28;
                5'd12: attack_lo=9'd39;
                5'd13: attack_lo=9'd54;
                5'd14: attack_lo=9'd75;
                5'd15: attack_lo=9'd104;
                5'd16: attack_lo=9'd144;
                5'd17: attack_lo=9'd200;
                default: attack_lo=9'd1;
            endcase
        end
    endfunction
    function [8:0] attack_hi;
        input [4:0] b;
        begin
            case (b)
                5'd0, 5'd1, 5'd2: attack_hi=9'd2;
                5'd3: attack_hi=9'd3;
                5'd4: attack_hi=9'd4;
                5'd5: attack_hi=9'd5;
                5'd6: attack_hi=9'd8;
                5'd7: attack_hi=9'd11;
                5'd8: attack_hi=9'd15;
                5'd9: attack_hi=9'd20;
                5'd10: attack_hi=9'd28;
                5'd11: attack_hi=9'd39;
                5'd12: attack_hi=9'd54;
                5'd13: attack_hi=9'd75;
                5'd14: attack_hi=9'd104;
                5'd15: attack_hi=9'd144;
                5'd16: attack_hi=9'd200;
                5'd17: attack_hi=9'd277;
                default: attack_hi=9'd2;
            endcase
        end
    endfunction
    function [15:0] attack_recip;
        input [4:0] b;
        begin
            case (b)
                5'd0, 5'd1, 5'd2, 5'd3, 5'd4, 5'd5: attack_recip=16'd32768;
                5'd6, 5'd7: attack_recip=16'd16384;
                5'd8: attack_recip=16'd13107;
                5'd9: attack_recip=16'd10923;
                5'd10: attack_recip=16'd7282;
                5'd11: attack_recip=16'd5461;
                5'd12: attack_recip=16'd4096;
                5'd13: attack_recip=16'd2979;
                5'd14: attack_recip=16'd2185;
                5'd15: attack_recip=16'd1598;
                5'd16: attack_recip=16'd1150;
                5'd17: attack_recip=16'd840;
                default: attack_recip=16'd0;
            endcase
        end
    endfunction
    reg [2:0] state;
    localparam [2:0] IDLE=0, ISSUE=1, WAIT_DATA=2, ADD=3, EMIT=4;
    reg attack_mode;
    reg [8:0] cursor;
    reg [14:0] sum; // 78 bins maximum, 78*255 = 19890
    reg [7:0] history [0:63];
    wire [14:0] sum_next=sum+{7'd0,rd_data};
    wire [15:0] recip=attack_mode ? attack_recip(attack_band_idx)
                                    : band_recip(bar_idx);
    wire [30:0] scaled=sum_next*recip;
    wire [8:0] target_hi=attack_mode ? attack_hi(attack_band_idx)
                                      : band_hi(bar_idx);
    wire single_bin=!attack_mode &&
                    ((bar_idx<=6'd21)||(bar_idx==6'd23)||(bar_idx==6'd25));
    wire [7:0] average=single_bin ? rd_data
                      : ((scaled[30:16]>255)?8'd255:scaled[23:16]);
    wire [8:0] smooth={1'b0,average}-{1'b0,average[7:3]}+{1'b0,history[bar_idx][7:3]};
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; bar_stb<=0; bars_done<=0; bar_idx<=0;
            attack_band_stb<=0; attack_band_idx<=0; attack_band_level<=0;
            bar_level<=0; cursor<=0; rd_addr<=0; sum<=0; attack_mode<=0;
            for(i=0;i<64;i=i+1) history[i]<=0;
        end else begin
            bar_stb<=0; bars_done<=0; attack_band_stb<=0;
            case(state)
            IDLE: if(frame_stb) begin
                bar_idx<=0; cursor<=9'd1; sum<=0; attack_mode<=0; state<=ISSUE;
            end
            ISSUE: begin rd_addr<=cursor; state<=WAIT_DATA; end
            WAIT_DATA: state<=ADD;
            ADD: begin
                // The RAM read is registered; issue and add are separated.
                if(cursor==target_hi) begin
                    if(attack_mode) begin
                        attack_band_level<=average;
                        attack_band_stb<=1;
                    end else begin
                        bar_level<=smooth[8]?8'd255:smooth[7:0];
                        history[bar_idx]<=smooth[8]?8'd255:smooth[7:0];
                        bar_stb<=1;
                        if(bar_idx==6'd63) bars_done<=1;
                    end
                    state<=EMIT;
                end else begin
                    sum<=sum_next; cursor<=cursor+9'd1; state<=ISSUE;
                end
            end
            EMIT: begin
                if(attack_mode) begin
                    if(attack_band_idx==5'd17) state<=IDLE;
                    else begin
                        attack_band_idx<=attack_band_idx+5'd1;
                        cursor<=attack_lo(attack_band_idx+5'd1);
                        sum<=0; state<=ISSUE;
                    end
                end else if(bar_idx==6'd63) begin
                    attack_mode<=1;
                    attack_band_idx<=0;
                    cursor<=9'd1;
                    sum<=0; state<=ISSUE;
                end else begin
                    bar_idx<=bar_idx+6'd1;
                    cursor<=cursor+9'd1;
                    sum<=0; state<=ISSUE;
                end
            end
            endcase
        end
    end
endmodule
`default_nettype wire
