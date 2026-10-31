`default_nettype none
// A 16px Chinese row needs 64 bits. Read both halves from the two ports of
// one 32K block; the narrow ASCII subset fits in one 9K block.
module osd_font_youyuan(input wire clk,input wire [6:0] glyph,
    input wire [3:0] row,output wire [63:0] bits);
`ifdef OSD_SIM
    localparam CH_FILE="rtl/gfx/osd_youyuan_ch.dath";
    localparam ASC_FILE="rtl/gfx/osd_youyuan_ascii.dath";
    localparam EXTRA_FILE="rtl/gfx/osd_youyuan_extra.dath";
`else
    localparam CH_FILE="osd_youyuan_ch.dath";
    localparam ASC_FILE="osd_youyuan_ascii.dath";
    localparam EXTRA_FILE="osd_youyuan_extra.dath";
`endif
    wire [31:0] hi,lo,ascii_bits;
    wire [3:0] ascii_index=glyph[3:0]-4'd14;
    reg blank_d,ascii_d,extra_d;
    always @(posedge clk) begin blank_d<=glyph==0; ascii_d<=glyph>=30 && glyph<64;extra_d<=glyph[6]; end
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE(CH_FILE),.FILL_ALL("NONE"),.IMPLEMENT("32K")
    ) u_ch(.clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),
        .addra({glyph[4:0],row,1'b0}),.dia(32'd0),.doa(hi),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),
        .addrb({glyph[4:0],row,1'b1}),.dib(32'd0),.dob(lo),.rstb(1'b0),.beb(1'b0));
    wire [31:0] extra_hi,extra_lo;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE(EXTRA_FILE),.FILL_ALL("NONE"),.IMPLEMENT("32K")
    ) u_extra(.clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),
        .addra({glyph[4:0],row,1'b0}),.dia(32'd0),.doa(extra_hi),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),
        .addrb({glyph[4:0],row,1'b1}),.dib(32'd0),.dob(extra_lo),.rstb(1'b0),.beb(1'b0));
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(8),.ADDR_WIDTH_B(8),
        .DATA_DEPTH_A(256),.DATA_DEPTH_B(256),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE(ASC_FILE),.FILL_ALL("NONE"),.IMPLEMENT("9K")
    ) u_ascii(.clka(clk),.cea(1'b0),.ocea(1'b0),.wea(1'b0),.addra(8'd0),
        .dia(32'd0),.doa(),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb({ascii_index,row}),
        .dib(32'd0),.dob(ascii_bits),.rstb(1'b0),.beb(1'b0));
    assign bits=blank_d ? 64'd0 : ascii_d ? {ascii_bits,32'd0} : extra_d ? {extra_hi,extra_lo} : {hi,lo};
endmodule
`default_nettype wire
