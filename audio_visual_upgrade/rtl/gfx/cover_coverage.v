`default_nettype none
// Shared S01 ellipse; one synchronous 64-bit half-row lookup. The display
// rectangle is the same for both scene slots, including during cross-fades.
module cover_coverage(input wire clk,rst,de,
    input wire [9:0] x,y, input wire [1:0] level,
    output wire [3:0] alpha);
`ifdef OSD_SIM
    localparam FILE="rtl/gfx/cover_coverage.dath";
`else
    localparam FILE="cover_coverage.dath";
`endif
    wire [8:0] size=level==3?9'd260:level==2?9'd256:level==1?9'd250:9'd240;
    wire [8:0] margin=level==3?9'd10:level==2?9'd8:level==1?9'd5:9'd0;
    wire [9:0] lx=x-(10'd40-{1'b0,margin});
    wire [9:0] ly=y-(10'd45-{1'b0,margin});
    wire [8:0] fx=(lx<size/2)?lx[8:0]:size-9'd1-lx[8:0];
    wire [8:0] fy=(ly<size/2)?ly[8:0]:size-9'd1-ly[8:0];
    wire [8:0] offset=level==3?9'd373:level==2?9'd245:level==1?9'd120:9'd0;
    wire [8:0] addr=offset+fy;
    wire [31:0] hi,lo;
    reg inside_d;
    reg [7:0] fx_d;
    wire [63:0] row={hi,lo};
    wire [7:0] start=row[7:0];
    wire [7:0] index=fx_d-start;
    always @(posedge clk) begin
        inside_d<=!rst && de && lx<size && ly<size;
        fx_d<=fx[7:0];
    end
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),
        .ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),.DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),
        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.DEBUGGABLE("NO"),
        .PACKABLE("NO"),.FORCE_KEEP("OFF"),.INIT_FILE(FILE),.FILL_ALL("NONE"),
        .IMPLEMENT("32K")) u_rom(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.addra({addr,1'b1}),
        .dia(32'd0),.doa(hi),.rsta(1'b0),.bea(1'b0),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb({addr,1'b0}),
        .dib(32'd0),.dob(lo),.rstb(1'b0),.beb(1'b0));
    assign alpha=!inside_d || fx_d<start ? 4'd0 :
        index>=8'd14 ? 4'd15 : (row>>(8+{index[3:0],2'b00}));
endmodule
`default_nettype wire
