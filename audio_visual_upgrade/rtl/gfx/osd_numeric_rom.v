`default_nettype none
// Exact original numeric and bar functions, including their 9-bit input range.
module osd_numeric_rom(input wire clk,input wire [8:0] number,bar_value,
    input wire [2:0] bar_kind,output wire [11:0] bcd,output wire [7:0] bar);
`ifdef OSD_SIM
    localparam BCD_FILE="rtl/gfx/osd_bcd.dath",BAR_FILE="rtl/gfx/osd_bar.dath";
`else
    localparam BCD_FILE="osd_bcd.dath",BAR_FILE="osd_bar.dath";
`endif
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(12),.DATA_WIDTH_B(12),
        .ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),.DATA_DEPTH_A(512),.DATA_DEPTH_B(512),
        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE(BCD_FILE),.FILL_ALL("NONE"),.IMPLEMENT("9K")) u_bcd(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.addra(number),
        .dia(12'd0),.doa(bcd),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b0),.oceb(1'b0),.web(1'b0),.addrb(9'd0),
        .dib(12'd0),.dob(),.rstb(1'b0),.beb(1'b0));
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(12),.ADDR_WIDTH_B(12),.DATA_DEPTH_A(4096),.DATA_DEPTH_B(4096),
        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE(BAR_FILE),.FILL_ALL("NONE"),.IMPLEMENT("32K")) u_bar(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.addra({bar_kind,bar_value}),
        .dia(8'd0),.doa(bar),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b0),.oceb(1'b0),.web(1'b0),.addrb(12'd0),
        .dib(8'd0),.dob(),.rstb(1'b0),.beb(1'b0));
endmodule
`default_nettype wire
