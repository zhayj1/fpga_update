`default_nettype none
// Common raster state. All users sample the same pre-edge counters as before.
module scene_raster(
    input wire clk_pix,rst_pix_n,hs,vs,de,
    output wire [66:0] state
);
    reg hs_d,vs_d,frame_seen;
    reg [16:0] lcnt;
    reg [15:0] vln,xcnt;
    reg [14:0] frame_id;
    wire hs_f=hs_d && !hs,vs_f=vs_d && !vs;
    assign state={hs_f,vs_f,frame_seen,lcnt,vln,xcnt,frame_id};
    always @(posedge clk_pix) begin
        if(!rst_pix_n) begin
            hs_d<=0; vs_d<=0; frame_seen<=0; lcnt<=0; vln<=0; xcnt<=0; frame_id<=0;
        end else begin
            hs_d<=hs; vs_d<=vs;
            if(hs_f) lcnt<=0;
            else if(lcnt!=17'h1ffff) lcnt<=lcnt+1'b1;
            if(vs_f) begin vln<=0; frame_seen<=1; frame_id<=frame_id+1'b1; end
            else if(hs_f) vln<=vln+1'b1;
            if(!de) xcnt<=0; else xcnt<=xcnt+1'b1;
        end
    end
endmodule
`default_nettype wire
