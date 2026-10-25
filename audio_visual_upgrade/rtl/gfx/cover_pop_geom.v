`default_nettype none
// Expand the displayed window only. The source dimensions and SDRAM stride stay fixed.
module cover_pop_geom(
    input wire [15:0] x,y,w,h,
    input wire [1:0] level,
    output wire [15:0] out_x,out_y,out_w,out_h
);
    wire [15:0] mx_full=(w>>5)+(w>>6);
    wire [15:0] my_full=(h>>5)+(h>>6);
    wire [15:0] mx_raw=(level==2'd3) ? mx_full :
                       (level==2'd2) ? (mx_full-(mx_full>>2)) :
                       (level==2'd1) ? (mx_full>>1) : 16'd0;
    wire [15:0] my_raw=(level==2'd3) ? my_full :
                       (level==2'd2) ? (my_full-(my_full>>2)) :
                       (level==2'd1) ? (my_full>>1) : 16'd0;
    wire [15:0] mx=(mx_raw>x) ? x : mx_raw;
    wire [15:0] my=(my_raw>y) ? y : my_raw;
    assign out_x=x-mx;
    assign out_y=y-my;
    assign out_w=w+(mx<<1);
    assign out_h=h+(my<<1);
endmodule
`default_nettype wire
