`default_nettype none
// 64 ten-pixel pitch bars. Data banks exchange only at vertical frame start.
module layer_fft64 (
    input wire clk, rst_n,
    input wire bar_stb, bars_done,
    input wire [5:0] bar_idx,
    input wire [7:0] bar_level,
    input wire frame_stb,
    input wire attack_hit,
    input wire [4:0] attack_band,
    input wire de, en,
    input wire [15:0] x, y,
    output wire [23:0] dout,
    output wire dout_vld
);
    reg [7:0] heights [0:127];
    reg [7:0] read_height;
    reg active_bank, pending_ready, building;
    reg pending_hit;
    reg [4:0] pending_band;
    reg [5:0] spike_center;
    reg [7:0] spike_strength;
    reg [5:0] scan_bar;
    reg [3:0] scan_phase;
    wire [5:0] next_scan_bar=(scan_phase==4'd9 && scan_bar<6'd63)
                               ? scan_bar+6'd1 : scan_bar;
    wire [6:0] read_addr={active_bank,next_scan_bar};
    wire [6:0] write_addr={~active_bank,bar_idx};
    always @(posedge clk) begin
        if(bar_stb) heights[write_addr]<=bar_level;
        read_height<=heights[read_addr];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active_bank<=0; pending_ready<=0; building<=0;
            scan_bar<=0; scan_phase<=0;
            pending_hit<=0; pending_band<=0;
            spike_center<=0; spike_strength<=0;
        end else begin
            if(frame_stb) begin
                if(pending_hit) begin
                    spike_center<=attack_center(pending_band);
                    spike_strength<=8'd214; // HTML decays the hit to 0.84 before drawing
                    pending_hit<=0;
                end else if(spike_strength<=8'd8) spike_strength<=0;
                else spike_strength<=spike_strength-(spike_strength>>3)-
                                      (spike_strength>>5)-8'd1;
            end
            if(attack_hit) begin
                pending_hit<=1;
                pending_band<=attack_band;
            end
            if(bar_stb) begin
                if(bar_idx==0) begin building<=1; pending_ready<=0; end
            end
            if(bars_done) begin building<=0; pending_ready<=1; end
            if(frame_stb && pending_ready && !building && !bar_stb) begin
                active_bank<=~active_bank;
                pending_ready<=0;
            end
            if(!de) begin scan_bar<=0; scan_phase<=0; end
            else if(scan_phase==4'd9) begin
                scan_phase<=0;
                if(scan_bar<6'd63) scan_bar<=scan_bar+6'd1;
            end else scan_phase<=scan_phase+4'd1;
        end
    end
    function [5:0] attack_center;
        input [4:0] b;
        begin
            case(b)
                5'd0: attack_center=6'd0;
                5'd1: attack_center=6'd4;
                5'd2: attack_center=6'd7;
                5'd3: attack_center=6'd11;
                5'd4: attack_center=6'd15;
                5'd5: attack_center=6'd19;
                5'd6: attack_center=6'd22;
                5'd7: attack_center=6'd26;
                5'd8: attack_center=6'd30;
                5'd9: attack_center=6'd33;
                5'd10: attack_center=6'd37;
                5'd11: attack_center=6'd41;
                5'd12: attack_center=6'd44;
                5'd13: attack_center=6'd48;
                5'd14: attack_center=6'd52;
                5'd15: attack_center=6'd56;
                5'd16: attack_center=6'd59;
                5'd17: attack_center=6'd63;
                default: attack_center=6'd0;
            endcase
        end
    endfunction
    function [7:0] height;
        input [7:0] level;
        begin
            height=level-(level>>3);
        end
    endfunction
    function [23:0] color;
        input [5:0] index;
        input cap;
        begin
            if(cap) case(index)
            6'd0: color=24'h67E4E4;
            6'd1: color=24'h67E4DF;
            6'd2: color=24'h67E4DA;
            6'd3: color=24'h67E4D5;
            6'd4: color=24'h67E4D0;
            6'd5: color=24'h67E4CB;
            6'd6: color=24'h67E4C6;
            6'd7: color=24'h67E4C1;
            6'd8: color=24'h67E4BC;
            6'd9: color=24'h67E4B7;
            6'd10: color=24'h67E4B2;
            6'd11: color=24'h67E4AD;
            6'd12: color=24'h67E4A8;
            6'd13: color=24'h67E4A3;
            6'd14: color=24'h67E49E;
            6'd15: color=24'h67E499;
            6'd16: color=24'h67E494;
            6'd17: color=24'h67E48F;
            6'd18: color=24'h67E48A;
            6'd19: color=24'h67E485;
            6'd20: color=24'h67E480;
            6'd21: color=24'h67E47B;
            6'd22: color=24'h67E476;
            6'd23: color=24'h67E471;
            6'd24: color=24'h67E46C;
            6'd25: color=24'h68E467;
            6'd26: color=24'h6DE467;
            6'd27: color=24'h72E467;
            6'd28: color=24'h77E467;
            6'd29: color=24'h7CE467;
            6'd30: color=24'h81E467;
            6'd31: color=24'h86E467;
            6'd32: color=24'h8BE467;
            6'd33: color=24'h90E467;
            6'd34: color=24'h95E467;
            6'd35: color=24'h9AE467;
            6'd36: color=24'h9FE467;
            6'd37: color=24'hA4E467;
            6'd38: color=24'hA9E467;
            6'd39: color=24'hAEE467;
            6'd40: color=24'hB3E467;
            6'd41: color=24'hB8E467;
            6'd42: color=24'hBDE467;
            6'd43: color=24'hC2E467;
            6'd44: color=24'hC7E467;
            6'd45: color=24'hCCE467;
            6'd46: color=24'hD1E467;
            6'd47: color=24'hD6E467;
            6'd48: color=24'hDBE467;
            6'd49: color=24'hE1E467;
            6'd50: color=24'hE4E367;
            6'd51: color=24'hE4DE67;
            6'd52: color=24'hE4D967;
            6'd53: color=24'hE4D467;
            6'd54: color=24'hE4CF67;
            6'd55: color=24'hE4CA67;
            6'd56: color=24'hE4C567;
            6'd57: color=24'hE4C067;
            6'd58: color=24'hE4BB67;
            6'd59: color=24'hE4B667;
            6'd60: color=24'hE4B167;
            6'd61: color=24'hE4AC67;
            6'd62: color=24'hE4A767;
            6'd63: color=24'hE4A267;
                default: color=24'h81D7D7;
            endcase
            else case(index)
            6'd0: color=24'h26D9D9;
            6'd1: color=24'h26D9D2;
            6'd2: color=24'h26D9CA;
            6'd3: color=24'h26D9C3;
            6'd4: color=24'h26D9BC;
            6'd5: color=24'h26D9B5;
            6'd6: color=24'h26D9AE;
            6'd7: color=24'h26D9A7;
            6'd8: color=24'h26D99F;
            6'd9: color=24'h26D998;
            6'd10: color=24'h26D991;
            6'd11: color=24'h26D98A;
            6'd12: color=24'h26D983;
            6'd13: color=24'h26D97B;
            6'd14: color=24'h26D974;
            6'd15: color=24'h26D96D;
            6'd16: color=24'h26D966;
            6'd17: color=24'h26D95F;
            6'd18: color=24'h26D958;
            6'd19: color=24'h26D950;
            6'd20: color=24'h26D949;
            6'd21: color=24'h26D942;
            6'd22: color=24'h26D93B;
            6'd23: color=24'h26D934;
            6'd24: color=24'h26D92C;
            6'd25: color=24'h27D926;
            6'd26: color=24'h2ED926;
            6'd27: color=24'h36D926;
            6'd28: color=24'h3DD926;
            6'd29: color=24'h44D926;
            6'd30: color=24'h4BD926;
            6'd31: color=24'h52D926;
            6'd32: color=24'h59D926;
            6'd33: color=24'h61D926;
            6'd34: color=24'h68D926;
            6'd35: color=24'h6FD926;
            6'd36: color=24'h76D926;
            6'd37: color=24'h7DD926;
            6'd38: color=24'h85D926;
            6'd39: color=24'h8CD926;
            6'd40: color=24'h93D926;
            6'd41: color=24'h9AD926;
            6'd42: color=24'hA1D926;
            6'd43: color=24'hA8D926;
            6'd44: color=24'hB0D926;
            6'd45: color=24'hB7D926;
            6'd46: color=24'hBED926;
            6'd47: color=24'hC5D926;
            6'd48: color=24'hCCD926;
            6'd49: color=24'hD3D926;
            6'd50: color=24'hD9D726;
            6'd51: color=24'hD9D026;
            6'd52: color=24'hD9C926;
            6'd53: color=24'hD9C126;
            6'd54: color=24'hD9BA26;
            6'd55: color=24'hD9B326;
            6'd56: color=24'hD9AC26;
            6'd57: color=24'hD9A526;
            6'd58: color=24'hD99D26;
            6'd59: color=24'hD99626;
            6'd60: color=24'hD98F26;
            6'd61: color=24'hD98826;
            6'd62: color=24'hD98126;
            6'd63: color=24'hD97A26;
                default: color=24'h26D9D9;
            endcase
        end
    endfunction
    wire [7:0] level=read_height;
    wire [7:0] h=height(level);
    wire [5:0] spike_distance=(scan_bar>=spike_center)?
                              scan_bar-spike_center:spike_center-scan_bar;
    wire [7:0] spike_boost=(spike_distance<=6'd2)?(spike_strength>>1):
                            (spike_distance<=6'd4)?((spike_strength>>2)+(spike_strength>>3)):
                            (spike_distance<=6'd6)?(spike_strength>>2):
                            (spike_distance<=6'd8)?(spike_strength>>3):
                            (spike_distance<=6'd10)?(spike_strength>>4):
                            (spike_distance<=6'd12)?(spike_strength>>5):8'd0;
    wire [8:0] height_sum={1'b0,h}+{1'b0,spike_boost};
    wire [7:0] pixel_height=height_sum[8]?8'hff:height_sum[7:0];
    wire [9:0] bar_top=10'd478-{2'd0,pixel_height};
    wire bright_cap=(spike_boost>8'd6);
    wire [9:0] cap_top=bar_top-(bright_cap?10'd3:10'd2);
    wire within_x=(scan_phase>=4'd1 && scan_phase<=4'd8);
    wire body=de && en && within_x && (pixel_height!=0) &&
              (y>={6'd0,bar_top}) && (y<=16'd477);
    wire cap_pixel=de && en && within_x && (pixel_height!=0) &&
                   (y>={6'd0,cap_top}) && (y<{6'd0,bar_top});
    assign dout_vld=body || cap_pixel;
    assign dout=(cap_pixel && bright_cap)?24'hFFFFFF:color(scan_bar,cap_pixel);
endmodule
`default_nettype wire
