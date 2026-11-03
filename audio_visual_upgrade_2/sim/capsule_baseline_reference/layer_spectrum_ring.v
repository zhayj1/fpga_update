`default_nettype none
// 64 clockwise radial bars, centered between the cardinal axes. Geometry
// uses the same 6:5 horizontal correction as the board-approved cover/rings.
// An 8 KiB angle-boundary ROM replaces per-pixel trigonometry. Radius squares
// come from attack_rings; one multiplier prepares the 64 bounds in blanking.
// Raster contract: sequential x=0..639; y stable >=2 blank clocks before DE.
// frame_stb precedes active video by >=386 clocks. No output pixel latency.
module layer_spectrum_ring #(
    parameter integer CENTER_X=320, CENTER_Y=254, INNER_RADIUS=136
)(
    input wire clk,rst_n,bar_stb,bars_done,frame_stb,
    input wire [5:0] bar_idx,
    input wire [7:0] bar_level,
    input wire attack_hit,spike_enable,
    input wire [4:0] attack_band,
    input wire de,en,
    input wire [9:0] x,y,
    input wire [23:0] radius_distance,target_color,
    output wire [23:0] dout,
    output wire dout_vld
);
`ifdef OSD_SIM
    localparam ANGLE_FILE="sim/capsule_baseline_reference/spectrum_angles.dath";
`else
    localparam ANGLE_FILE="spectrum_angles.dath";
`endif
    localparam [23:0] INNER_SQUARE=25*INNER_RADIUS*INNER_RADIUS;
    reg [7:0] levels[0:127];
    reg [7:0] source_level;
    reg active_bank,pending_ready,building,active_valid;
    reg pending_hit;
    reg [4:0] pending_band;
    reg [5:0] spike_center;
    reg [7:0] spike_strength;
    reg [5:0] build_index;
    reg [2:0] build_state;
    reg display_ready;
    reg [8:0] radius;
    reg [17:0] square;
    reg [19:0] body_bound;
    reg has_height,bright;
    // One read port and one write port; contents are replaced in VS blanking.
    reg [64:0] display_data[0:63];
    reg [64:0] pixel_data;

    function [5:0] attack_center;
        input [4:0] b;
        begin
            case(b)
             0:attack_center=0; 1:attack_center=4; 2:attack_center=7;
             3:attack_center=11;4:attack_center=15;5:attack_center=19;
             6:attack_center=22;7:attack_center=26;8:attack_center=30;
             9:attack_center=33;10:attack_center=37;11:attack_center=41;
             12:attack_center=45;13:attack_center=48;14:attack_center=52;
             15:attack_center=56;16:attack_center=59;17:attack_center=63;
             default:attack_center=0;
            endcase
        end
    endfunction
    wire [5:0] delta=build_index>=spike_center ? build_index-spike_center : spike_center-build_index;
    wire [5:0] separation=delta>32 ? 7'd64-{1'b0,delta} : delta;
    wire [7:0] boost=!spike_enable ? 8'd0 :
        separation<=2 ? spike_strength>>1 :
        separation<=4 ? (spike_strength>>2)+(spike_strength>>3) :
        separation<=6 ? spike_strength>>2 : separation<=8 ? spike_strength>>3 :
        separation<=10 ? spike_strength>>4 : separation<=12 ? spike_strength>>5 : 8'd0;
    wire [7:0] original_height=source_level-(source_level>>3);
    wire [8:0] boosted={1'b0,original_height}+{1'b0,boost};
    wire [7:0] height=boosted[8] ? 8'hff : boosted[7:0];
    // Preserve the existing level/spike relationship; fit the radial extent
    // between the title and lyric bands (maximum radius 182 pixels).
    wire [8:0] body_radius=INNER_RADIUS+9'd2+
        {4'd0,height[7:3]}+{6'd0,height[7:5]}+{7'd0,height[7:6]};
    wire [19:0] scaled_square=({2'd0,square}<<4)+({2'd0,square}<<3)+{2'd0,square};
    wire [23:0] build_color;
    genvar c;
    generate for(c=0;c<3;c=c+1) begin:g_gradient
        reg [7:0] value;
        reg [5:0] error;
        wire [8:0] sum={3'd0,error}+{1'b0,~target_color[c*8+:8]};
        wire [2:0] q=sum>=315?3'd5:sum>=252?3'd4:sum>=189?3'd3:sum>=126?3'd2:sum>=63?3'd1:3'd0;
        wire [8:0] multiple=({6'd0,q}<<6)-{6'd0,q};
        always @(posedge clk) begin
            if(!rst_n || frame_stb) begin value<=255;error<=31;end
            else if(build_state==6 && build_index<63) begin
                value<=value-{5'd0,q};error<=sum-multiple;
            end
        end
        assign build_color[c*8+:8]=value;
    end endgenerate
    always @(posedge clk) begin
        if(bar_stb) levels[{~active_bank,bar_idx}]<=bar_level;
        source_level<=levels[{active_bank,build_index}];
        if(build_state==3 || build_state==5) square<=radius*radius;
        if(build_state==6)
            display_data[build_index]<={bright,has_height?scaled_square:20'd0,body_bound,build_color};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active_bank<=0;pending_ready<=0;building<=0;active_valid<=0;
            pending_hit<=0;pending_band<=0;spike_center<=0;spike_strength<=0;
            build_index<=0;build_state<=0;display_ready<=0;radius<=0;
            body_bound<=0;has_height<=0;bright<=0;
        end else begin
            if(bar_stb && bar_idx==0) begin building<=1;pending_ready<=0;end
            if(bars_done) begin building<=0;pending_ready<=1;end
            if(attack_hit && spike_enable) begin pending_hit<=1;pending_band<=attack_band;end
            if(frame_stb) begin
                if(pending_ready && !building && !bar_stb) begin
                    active_bank<=~active_bank;pending_ready<=0;active_valid<=1;
                end
                if(pending_hit) begin
                    spike_center<=attack_center(pending_band);spike_strength<=214;pending_hit<=0;
                end else if(spike_strength<=8) spike_strength<=0;
                else spike_strength<=spike_strength-(spike_strength>>3)-(spike_strength>>5)-1'b1;
                build_index<=0;build_state<=1;display_ready<=0;
            end else case(build_state)
                1:build_state<=2; // synchronous level read after bank/index change
                2:begin radius<=body_radius;has_height<=height!=0;bright<=boost>6;build_state<=3;end
                3:build_state<=4;
                4:begin body_bound<=scaled_square;radius<=radius+9'd3;build_state<=5;end
                5:build_state<=6;
                6:begin
                    if(build_index==63) begin build_state<=0;display_ready<=1;end
                    else begin build_index<=build_index+1'b1;build_state<=1;end
                end
                default:build_state<=0;
            endcase
            if(!spike_enable) begin pending_hit<=0;spike_strength<=0;end
        end
    end

    // Traverse 32 sorted angular boundaries in each screen half. Advance
    // using the next raster coordinate so both ROMs prefetch the current
    // pixel without inserting a new stage into the existing compositor.
    wire [9:0] dy=y>=CENTER_Y ? y-CENTER_Y : CENTER_Y-y;
    wire [9:0] next_x=de ? (x==639 ? 10'd639 : x+10'd1) : 10'd0;
    wire [9:0] next_dx=next_x>=CENTER_X ? next_x-CENTER_X : CENTER_X-next_x;
    reg [5:0] phase;
    reg [5:0] next_phase;
    wire [7:0] boundary;
    always @(*) begin
        next_phase=phase;
        if(!de) next_phase=32;
        else if(next_x==CENTER_X) next_phase=0;
        else if(next_x<CENTER_X) begin
            if(phase!=0 && next_dx<{2'd0,boundary}) next_phase=phase-1'b1;
        end else if(phase!=32 && next_dx>={2'd0,boundary}) next_phase=phase+1'b1;
    end
    wire [4:0] boundary_index=next_x<CENTER_X ? next_phase-1'b1 : next_phase[4:0];
    wire [12:0] angle_address={dy[7:0],boundary_index};
    wire [3:0] sector=next_phase[4:1];
    wire [5:0] next_band=y<CENTER_Y ?
        (next_x<CENTER_X ? 6'd63-{2'd0,sector} : {2'd0,sector}) :
        (next_x<CENTER_X ? 6'd32+{2'd0,sector} : 6'd31-{2'd0,sector});
    always @(posedge clk) begin
        if(!rst_n) phase<=32;else phase<=next_phase;
        pixel_data<=display_data[next_band];
    end
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(13),.ADDR_WIDTH_B(13),.DATA_DEPTH_A(8192),.DATA_DEPTH_B(8192),
        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.DEBUGGABLE("NO"),
        .PACKABLE("NO"),.FORCE_KEEP("OFF"),.INIT_FILE(ANGLE_FILE),.FILL_ALL("NONE"),
        .IMPLEMENT("32K")) u_angles(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.addra(angle_address),
        .dia(8'd0),.doa(boundary),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b0),.oceb(1'b0),.web(1'b0),.addrb(13'd0),
        .dib(8'd0),.dob(),.rstb(1'b0),.beb(1'b0));
    wire cap=radius_distance>{4'd0,pixel_data[43:24]};
    assign dout_vld=de && en && active_valid && display_ready && phase[0] &&
        dy<=182 && radius_distance>=INNER_SQUARE && radius_distance<={4'd0,pixel_data[63:44]};
    assign dout=cap && pixel_data[64] ? 24'hFFFFFF : pixel_data[23:0];
endmodule
`default_nettype wire
