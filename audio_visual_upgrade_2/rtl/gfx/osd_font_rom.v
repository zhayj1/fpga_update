`default_nettype none
// Native 32x32/16x32 subset from card/FONT.HZK and ASC.HZK.
module osd_font_rom(input wire clk, input wire [5:0] glyph,
                    input wire [4:0] row, output wire [31:0] bits);
`ifdef OSD_SIM
    localparam CH_FILE="rtl/gfx/osd_font_ch.dath";
    localparam ASCII_FILE="rtl/gfx/osd_font_ascii.dath";
`else
    localparam CH_FILE="osd_font_ch.dath";
    localparam ASCII_FILE="osd_font_ascii.dath";
`endif
    wire [31:0] chinese_bits;
    wire [15:0] ascii_bits;
    wire [3:0] ascii_index = glyph[3:0] - 4'd14;
    reg blank_d, ascii_d;
    always @(posedge clk) begin
        blank_d <= glyph==6'd0;
        ascii_d <= glyph>=6'd30;
    end
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(32),.DATA_WIDTH_B(32),
        .ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),
        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"),.DEBUGGABLE("NO"),.PACKABLE("NO"),
        .FORCE_KEEP("OFF"),.INIT_FILE(CH_FILE),
        .FILL_ALL("NONE"),.IMPLEMENT("32K")
    ) u_chinese (
        .dia(32'd0),.addra(10'd0),.cea(1'b0),.ocea(1'b0),
        .clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),
        .dib(32'd0),.addrb({glyph[4:0],row}),.ceb(1'b1),.oceb(1'b1),
        .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(chinese_bits)
    );
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16),.DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
        .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),
        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"),.DEBUGGABLE("NO"),.PACKABLE("NO"),
        .FORCE_KEEP("OFF"),.INIT_FILE(ASCII_FILE),
        .FILL_ALL("NONE"),.IMPLEMENT("9K")
    ) u_ascii (
        .dia(16'd0),.addra(9'd0),.cea(1'b0),.ocea(1'b0),
        .clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),
        .dib(16'd0),.addrb({ascii_index,row}),.ceb(1'b1),.oceb(1'b1),
        .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(ascii_bits)
    );
    assign bits=blank_d ? 32'd0 : (ascii_d ? {16'd0,ascii_bits} : chinese_bits);
endmodule
`default_nettype wire
