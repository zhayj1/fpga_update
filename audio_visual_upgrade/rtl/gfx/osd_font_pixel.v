`default_nettype none
// Identical 4-bit glyph samples, directly addressed by glyph/row/column.
// Trading spare 32K RAM for the 64-bit row mux saves LUTs without quantization.
module osd_font_pixel(input wire clk,input wire [6:0] glyph,
    input wire [3:0] row,col,output wire [3:0] alpha);
`ifdef OSD_SIM
    localparam FILE="rtl/gfx/osd_youyuan_pixel.dath";
`else
    localparam FILE="osd_youyuan_pixel.dath";
`endif
    wire [7:0] pair;
    reg odd;
    always @(posedge clk) odd<=col[0];
    assign alpha=odd ? pair[3:0] : pair[7:4];
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(14),.ADDR_WIDTH_B(14),.DATA_DEPTH_A(16384),.DATA_DEPTH_B(16384),
        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.DEBUGGABLE("NO"),
        .PACKABLE("NO"),.FORCE_KEEP("OFF"),.INIT_FILE(FILE),.FILL_ALL("NONE"),.IMPLEMENT("32K")) u_rom(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.addra({glyph,row,col[3:1]}),
        .dia(8'd0),.doa(pair),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b0),.oceb(1'b0),.web(1'b0),.addrb(14'd0),
        .dib(8'd0),.dob(),.rstb(1'b0),.beb(1'b0));
endmodule
`default_nettype wire
