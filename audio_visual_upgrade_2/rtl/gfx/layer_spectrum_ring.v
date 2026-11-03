`default_nettype none
// Constant-width radial capsules. Three registered pixel stages line up with
// skeleton_core's scene blend. Q8 projections use shift/add, never DSPs.
// 4 KiB nearest-sector ROM replaces the previous 8 KiB angular-gap ROM.
module layer_spectrum_ring #(
    parameter integer CENTER_X=320,CENTER_Y=254,INNER_RADIUS=136,USE_PRODUCT_RAM=0
)(
    input wire clk,rst_n,bar_stb,bars_done,frame_stb,
    input wire [5:0] bar_idx,input wire [7:0] bar_level,
    input wire attack_hit,spike_enable,input wire [4:0] attack_band,
    input wire de,en,input wire [9:0] x,y,
    input wire [23:0] radius_distance,target_color,
    output wire [23:0] dout,output wire dout_vld,
    output wire [3:0] coverage
);
`ifdef OSD_SIM
    localparam ANGLE_FILE="rtl/gfx/spectrum_angles.dath";
    localparam SX_FILE="rtl/gfx/spectrum_sx_products.dath",CY_FILE="rtl/gfx/spectrum_cy_products.dath";
`else
    localparam ANGLE_FILE="spectrum_angles.dath";
    localparam SX_FILE="spectrum_sx_products.dath",CY_FILE="spectrum_cy_products.dath";
`endif
    localparam integer ROOT_Q8=(INNER_RADIUS+2)*256;
    reg [7:0] levels[0:127];
    reg [7:0] source_level;
    reg active_bank,pending_ready,building,active_valid;
    reg pending_hit;reg [4:0] pending_band;
    reg [5:0] spike_center,build_index;
    reg [7:0] spike_strength;
    reg [1:0] build_state;
    reg display_ready;
    // 31 bits instead of 65: length, tip accent and existing gradient color.
    reg [30:0] display_data[0:63];
    reg [30:0] pixel_data;
    // Map each attack band's integer bin midpoint into the log display bands.
    function [5:0] attack_center;
        input [4:0] b;
        begin
            case(b)
                5'd0: attack_center=6'd0;
                5'd1: attack_center=6'd0;
                5'd2: attack_center=6'd0;
                5'd3: attack_center=6'd1;
                5'd4: attack_center=6'd2;
                5'd5: attack_center=6'd3;
                5'd6: attack_center=6'd5;
                5'd7: attack_center=6'd8;
                5'd8: attack_center=6'd12;
                5'd9: attack_center=6'd16;
                5'd10: attack_center=6'd22;
                5'd11: attack_center=6'd28;
                5'd12: attack_center=6'd34;
                5'd13: attack_center=6'd39;
                5'd14: attack_center=6'd45;
                5'd15: attack_center=6'd51;
                5'd16: attack_center=6'd57;
                5'd17: attack_center=6'd62;
                default: attack_center=6'd0;
            endcase
        end
    endfunction
    wire [5:0] delta=build_index>=spike_center?build_index-spike_center:spike_center-build_index;
    wire [5:0] separation=delta>32?7'd64-{1'b0,delta}:delta;
    wire [7:0] boost=!spike_enable?8'd0:separation<=2?spike_strength>>1:
        separation<=4?(spike_strength>>2)+(spike_strength>>3):
        separation<=6?spike_strength>>2:separation<=8?spike_strength>>3:
        separation<=10?spike_strength>>4:separation<=12?spike_strength>>5:8'd0;
    wire [7:0] original_height=active_valid?source_level-(source_level>>3):8'd0;
    wire [8:0] boosted={1'b0,original_height}+{1'b0,boost};
    wire [7:0] height=boosted[8]?8'hff:boosted[7:0];
    wire [5:0] extension={1'b0,height[7:3]}+{3'd0,height[7:5]}+{4'd0,height[7:6]};
    wire [23:0] build_color;
    genvar c;
    generate for(c=0;c<3;c=c+1) begin:g_gradient
        reg [7:0] value;reg [5:0] error;
        wire [8:0] sum={3'd0,error}+{1'b0,~target_color[c*8+:8]};
        wire [2:0] q=sum>=315?3'd5:sum>=252?3'd4:sum>=189?3'd3:sum>=126?3'd2:sum>=63?3'd1:3'd0;
        wire [8:0] multiple=({6'd0,q}<<6)-{6'd0,q};
        always @(posedge clk) begin
            if(!rst_n||frame_stb)begin value<=255;error<=31;end
            else if(build_state==3&&build_index<63)begin value<=value-{5'd0,q};error<=sum-multiple;end
        end
        assign build_color[c*8+:8]=value;
    end endgenerate
    always @(posedge clk) begin
        if(bar_stb)levels[{~active_bank,bar_idx}]<=bar_level;
        source_level<=levels[{active_bank,build_index}];
        if(build_state==3)display_data[build_index]<={extension,boost>6,build_color};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            active_bank<=0;pending_ready<=0;building<=0;active_valid<=0;
            pending_hit<=0;pending_band<=0;spike_center<=0;spike_strength<=0;
            build_index<=0;build_state<=0;display_ready<=0;
        end else begin
            if(bar_stb&&bar_idx==0)begin building<=1;pending_ready<=0;end
            if(bars_done)begin building<=0;pending_ready<=1;end
            if(attack_hit&&spike_enable)begin pending_hit<=1;pending_band<=attack_band;end
            if(frame_stb)begin
                if(pending_ready&&!building&&!bar_stb)begin active_bank<=~active_bank;pending_ready<=0;active_valid<=1;end
                if(pending_hit)begin spike_center<=attack_center(pending_band);spike_strength<=214;pending_hit<=0;end
                else if(spike_strength<=8)spike_strength<=0;
                else spike_strength<=spike_strength-(spike_strength>>3)-(spike_strength>>5)-1'b1;
                build_index<=0;build_state<=1;display_ready<=0;
            end else case(build_state)
                1:build_state<=2;
                2:build_state<=3;
                3:if(build_index==63)begin build_state<=0;display_ready<=1;end
                  else begin build_index<=build_index+1'b1;build_state<=1;end
                default:build_state<=0;
            endcase
            if(!spike_enable)begin pending_hit<=0;spike_strength<=0;end
        end
    end
    wire [9:0] dy=y>=CENTER_Y?y-CENTER_Y:CENTER_Y-y;
    // Keep the subtraction sign explicit: the r7 mapped netlist lost the
    // comparison/mux of the two unsigned subtractions on the right half.
    localparam signed [10:0] CENTER_X_SIGNED=CENTER_X;
    wire signed [10:0] x_delta=$signed({1'b0,x})-CENTER_X_SIGNED;
    wire [9:0] dx=(x_delta[9:0]^{10{x_delta[10]}})+{9'd0,x_delta[10]};
    wire [9:0] next_x=de?(x==639?10'd639:x+10'd1):10'd0;
    wire [9:0] next_dx=next_x>=CENTER_X?next_x-CENTER_X:CENTER_X-next_x;
    reg [4:0] phase,next_phase;
    wire [7:0] boundary;
    always @* begin
        next_phase=phase;
        if(!de)next_phase=16;
        else if(next_x==CENTER_X)next_phase=0;
        else if(next_x<CENTER_X)begin
            if(phase!=0&&next_dx<{2'd0,boundary})next_phase=phase-1'b1;
        end else if(phase<15&&next_dx>={2'd0,boundary})next_phase=phase+1'b1;
    end
    wire [3:0] boundary_index=next_x<CENTER_X?next_phase-1'b1:next_phase[3:0];
    wire [3:0] sector=next_phase==16?4'd15:next_phase[3:0];
    wire [5:0] next_band=y<CENTER_Y?
        (next_x<CENTER_X?6'd63-{2'd0,sector}:{2'd0,sector}):
        (next_x<CENTER_X?6'd32+{2'd0,sector}:6'd31-{2'd0,sector});
    // sx=1.2*sin(theta), cy=cos(theta), cx=1.2*cos(theta), sy=sin(theta), Q8.
    function [35:0] coefficients;
        input [3:0] i;
        begin case(i)
            0:coefficients={9'd15,9'd256,9'd307,9'd13};
            1:coefficients={9'd45,9'd253,9'd304,9'd38};
            2:coefficients={9'd75,9'd248,9'd298,9'd62};
            3:coefficients={9'd103,9'd241,9'd289,9'd86};
            4:coefficients={9'd131,9'd231,9'd278,9'd109};
            5:coefficients={9'd158,9'd220,9'd263,9'd132};
            6:coefficients={9'd183,9'd206,9'd247,9'd152};
            7:coefficients={9'd206,9'd190,9'd228,9'd172};
            8:coefficients={9'd228,9'd172,9'd206,9'd190};
            9:coefficients={9'd247,9'd152,9'd183,9'd206};
            10:coefficients={9'd263,9'd132,9'd158,9'd220};
            11:coefficients={9'd278,9'd109,9'd131,9'd231};
            12:coefficients={9'd289,9'd86,9'd103,9'd241};
            13:coefficients={9'd298,9'd62,9'd75,9'd248};
            14:coefficients={9'd304,9'd38,9'd45,9'd253};
            default:coefficients={9'd307,9'd13,9'd15,9'd256};
        endcase end
    endfunction
    reg [35:0] coeff;
    always @(posedge clk)begin
        if(!rst_n)phase<=16;else phase<=next_phase;
        pixel_data<=display_data[next_band];coeff<=coefficients(sector);
    end
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(12),.ADDR_WIDTH_B(12),.DATA_DEPTH_A(4096),.DATA_DEPTH_B(4096),
        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.DEBUGGABLE("NO"),
        .PACKABLE("NO"),.FORCE_KEEP("OFF"),.INIT_FILE(ANGLE_FILE),.FILL_ALL("NONE"),
        .IMPLEMENT("32K")) u_angles(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.addra({dy[7:0],boundary_index}),
        .dia(8'd0),.doa(boundary),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b0),.oceb(1'b0),.web(1'b0),.addrb(12'd0),
        .dib(8'd0),.dob(),.rstb(1'b0),.beb(1'b0));
    // Visible capsules are confined to |dx|<=154 and |dy|<=183. Discard
    // the ninth coordinate bit outside that masked region. Eight partial
    // products and 17-bit sums preserve every visible Q8 projection exactly.
    function [10:0] digit_product;
        input [1:0] digit;
        input [8:0] b;
        input [10:0] triple;
        begin case(digit)
            0:digit_product=0;
            1:digit_product={2'd0,b};
            2:digit_product={1'd0,b,1'b0};
            3:digit_product=triple;
        endcase end
    endfunction
    // Radix-4 shares 3*b across all four digits: four short additions
    // instead of seven binary partial-product additions, still bit-exact.
    function [16:0] multiply8x9;
        input [7:0] a;
        input [8:0] b;
        reg [10:0] triple,p0,p1,p2,p3;
        reg [12:0] lo,hi;
        begin
            triple={2'd0,b}+{1'd0,b,1'b0};
            p0=digit_product(a[1:0],b,triple);
            p1=digit_product(a[3:2],b,triple);
            p2=digit_product(a[5:4],b,triple);
            p3=digit_product(a[7:6],b,triple);
            lo={2'd0,p0}+{p1,2'd0};
            hi={2'd0,p2}+{p3,2'd0};
            multiply8x9={4'd0,lo}+{hi,4'd0};
        end
    endfunction
    // Four-bit partial products retain the original Q8 values exactly.
    // One synchronous lookup replaces each pair of radix-4 shift/add trees.
    // The low/high nibble ports prefetch for the same pixel as coeff.
    wire [15:0] sx_lo,sx_hi,cy_lo,cy_hi;
    generate if(USE_PRODUCT_RAM) begin:g_product_ram
        EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),
            .ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),.DATA_DEPTH_A(512),.DATA_DEPTH_B(512),
            .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
            .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
            .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.DEBUGGABLE("NO"),
            .PACKABLE("NO"),.FORCE_KEEP("OFF"),.INIT_FILE(SX_FILE),.FILL_ALL("NONE"),
            .IMPLEMENT("32K")) u_sx(
            .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.addra({1'b0,sector,next_dx[3:0]}),
            .dia(16'd0),.doa(sx_lo),.rsta(1'b0),.bea(1'b0),
            .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb({1'b0,sector,next_dx[7:4]}),
            .dib(16'd0),.dob(sx_hi),.rstb(1'b0),.beb(1'b0));
        EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),
            .ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),.DATA_DEPTH_A(512),.DATA_DEPTH_B(512),
            .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
            .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
            .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.DEBUGGABLE("NO"),
            .PACKABLE("NO"),.FORCE_KEEP("OFF"),.INIT_FILE(CY_FILE),.FILL_ALL("NONE"),
            .IMPLEMENT("9K")) u_cy(
            .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.addra({1'b0,sector,dy[3:0]}),
            .dia(16'd0),.doa(cy_lo),.rsta(1'b0),.bea(1'b0),
            .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb({1'b0,sector,dy[7:4]}),
            .dib(16'd0),.dob(cy_hi),.rstb(1'b0),.beb(1'b0));
    end endgenerate
    reg [16:0] ax1,ay1,px1,py1;
    reg [30:0] data1;
    reg valid1,valid2,valid3;
    reg [17:0] along2;
    reg signed [17:0] across2;
    reg [15:0] end2;
    reg [23:0] color2,color3;
    reg bright2;
    reg [3:0] alpha3;
    // The visible alpha only needs distances below 992 Q8 units.
    // Keep the full range check, but negate/round only the ten low bits.
    wire [9:0] abs_across_low=across2[17]?-across2[9:0]:across2[9:0];
    wire across_outside=$signed(across2)<-18'sd991 || $signed(across2)>18'sd991;
    localparam [17:0] ROOT_DISTANCE=ROOT_Q8;
    // Borrow bits replace separate full-width magnitude comparisons.
    wire [18:0] to_root={1'b0,ROOT_DISTANCE}-{1'b0,along2};
    wire [18:0] from_end={1'b0,along2}-{3'd0,end2};
    wire before_root=!to_root[18] && (|to_root[17:0]);
    wire [17:0] over=before_root?to_root[17:0]:
        !from_end[18]?from_end[17:0]:18'd0;
    wire [9:0] av_round=abs_across_low+10'd32;
    wire [9:0] ov_round=over[9:0]+10'd32;
    wire outside=across_outside || over>=18'd992;
    // Exact original square4(a)+square4(b) -> circle_alpha mapping.
    // Constant combinational lookup: no RAM, clock, or extra pipeline stage.
    localparam [1023:0] CAPSULE_ALPHA=1024'h0000000000000000000000000000000000000000000123440000000002456778000000014679abbb0000002479bcdeff00000257acefffff0000147adfffffff000047adffffffff000269cfffffffff00047befffffffff00159cffffffffff0026adffffffffff0037beffffffffff0047bfffffffffff0048bfffffffffff;
    wire [3:0] edge_alpha=CAPSULE_ALPHA[{av_round[9:6],ov_round[9:6],2'b00}+:4];
    always @(posedge clk)begin
        if(USE_PRODUCT_RAM) begin
            ax1<={4'd0,sx_lo[12:0]}+{sx_hi[12:0],4'd0};
            ay1<={4'd0,cy_lo[12:0]}+{cy_hi[12:0],4'd0};
        end else begin
            ax1<=multiply8x9(dx[7:0],coeff[35:27]);ay1<=multiply8x9(dy[7:0],coeff[26:18]);
        end
        if(USE_PRODUCT_RAM) px1<=dx[7:0]*coeff[17:9];
        else px1<=multiply8x9(dx[7:0],coeff[17:9]);
        py1<=multiply8x9(dy[7:0],coeff[8:0]);
        data1<=pixel_data;
        along2<={1'b0,ax1}+{1'b0,ay1};
        across2<=$signed({1'b0,px1})-$signed({1'b0,py1});
        end2<=ROOT_Q8+{2'd0,data1[30:25],8'd0};
        color2<=data1[23:0];bright2<=data1[24];
        color3<=(bright2&&along2>{2'd0,end2})?24'hffffff:color2;
        alpha3<=outside?4'd0:edge_alpha;
        if(!rst_n)begin valid1<=0;valid2<=0;valid3<=0;end
        else begin
            valid1<=de&&en&&display_ready&&dy<=183&&dx<=154;
            valid2<=valid1;valid3<=valid2;
        end
    end
    assign coverage=valid3?alpha3:4'd0;
    assign dout_vld=valid3&&alpha3!=0;
    assign dout=color3;
endmodule
`default_nettype wire
