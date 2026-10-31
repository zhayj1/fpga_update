`default_nettype none
// One tiny dual-port ROM: one port resolves frame settings, the other draws
// the OSD colour grid. No replicated six-way RGB decode trees.
module visual_palette(input wire clk,
    input wire [6:0] index_a,index_b, output wire [23:0] rgb_a,rgb_b);
`ifdef OSD_SIM
    localparam FILE="rtl/gfx/visual_palette.dath";
`else
    localparam FILE="visual_palette.dath";
`endif
    wire [31:0] a,b;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),
        .ADDR_WIDTH_A(8),.ADDR_WIDTH_B(8),.DATA_DEPTH_A(256),.DATA_DEPTH_B(256),
        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.DEBUGGABLE("NO"),
        .PACKABLE("NO"),.FORCE_KEEP("OFF"),.INIT_FILE(FILE),.FILL_ALL("NONE"),
        .IMPLEMENT("9K")) u_rom(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.addra({1'b0,index_a}),
        .dia(32'd0),.doa(a),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb({1'b0,index_b}),
        .dib(32'd0),.dob(b),.rstb(1'b0),.beb(1'b0));
    assign rgb_a=a[23:0];assign rgb_b=b[23:0];
endmodule
`default_nettype wire
