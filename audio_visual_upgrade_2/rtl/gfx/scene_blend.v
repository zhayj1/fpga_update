`default_nettype none
// Exact endpoints, rounded 8-bit linear blend. Three signed multipliers.
// RGB/overlay/DE/VS/HS all leave after the same two register stages.
module scene_blend(
    input wire clk,rst,de,vs,hs,
    input wire [23:0] old_rgb,new_rgb,overlay_rgb,
    input wire overlay_valid,
    input wire [8:0] alpha,
    output reg [23:0] rgb,
    output reg out_de,out_vs,out_hs
);
    wire signed [9:0] a=$signed({1'b0,alpha});
    wire signed [8:0] dr=$signed({1'b0,new_rgb[23:16]})-$signed({1'b0,old_rgb[23:16]});
    wire signed [8:0] dg=$signed({1'b0,new_rgb[15:8]})-$signed({1'b0,old_rgb[15:8]});
    wire signed [8:0] db=$signed({1'b0,new_rgb[7:0]})-$signed({1'b0,old_rgb[7:0]});
    reg signed [18:0] pr,pg,pb;
    reg [23:0] old_d,ov_d;
    reg de_d,vs_d,hs_d,ov_valid_d;
    wire signed [18:0] rr=$signed({3'b0,old_d[23:16],8'b0})+pr+19'sd128;
    wire signed [18:0] rg=$signed({3'b0,old_d[15:8],8'b0})+pg+19'sd128;
    wire signed [18:0] rb=$signed({3'b0,old_d[7:0],8'b0})+pb+19'sd128;
    always @(posedge clk) begin
        if (rst) begin
            pr<=0; pg<=0; pb<=0; old_d<=0; ov_d<=0; ov_valid_d<=0;
            de_d<=0; vs_d<=0; hs_d<=0; rgb<=0; out_de<=0; out_vs<=0; out_hs<=0;
        end else begin
            pr<=dr*a; pg<=dg*a; pb<=db*a;
            old_d<=old_rgb; ov_d<=overlay_rgb; ov_valid_d<=overlay_valid;
            de_d<=de; vs_d<=vs; hs_d<=hs;
            rgb<=ov_valid_d ? ov_d : {rr[15:8],rg[15:8],rb[15:8]};
            out_de<=de_d; out_vs<=vs_d; out_hs<=hs_d;
        end
    end
endmodule

// Spatial transitions share the existing blend datapath. Evaluate at the
// undelayed raster, then register alpha alongside the image/DE/VS/HS stage.
// No framebuffer, random state, divider or multiplier is required.
module scene_transition_mask(
    input wire [9:0] x,y,
    input wire [8:0] progress,
    input wire [1:0] effect,
    output wire [8:0] alpha
);
    wire [9:0] wipe_edge={progress,1'b0}+{2'b0,progress[8:1]};
    // A permutation of the 256 positions in each 16x16 tile. High coordinate
    // bits decorrelate adjacent tiles; triangular xor/and stages are bijective
    // and keep exactly one of every threshold per tile. Stable across frames.
    wire [7:0] seed={x[0],y[0],x[1],y[1],x[2],y[2],x[3],y[3]} ^
                    {y[6:4],x[8:4]};
    wire [7:0] h1=seed ^ (seed<<3);
    wire [7:0] h2=h1 ^ (h1>>5);
    wire [7:0] rank=h2 ^ ((h2<<1)&(h2<<2));
    wire reveal=effect==2'd1 ? ({1'b0,x}< {1'b0,wipe_edge}) :
                effect==2'd2 ? ({1'b0,rank}<progress) :
                              ({1'b0,y[4:0],3'b0}<progress);
    assign alpha=effect==0 ? progress :
                 progress[8] ? 9'd256 : reveal ? 9'd256 : 9'd0;
endmodule
`default_nettype wire
