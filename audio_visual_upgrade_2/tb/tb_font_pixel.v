`timescale 1ns/1ps
module tb_font_pixel;
reg clk=0;always #5 clk=~clk;
reg [6:0] glyph=0;reg [3:0] row=0,col=0;
wire [63:0] bits;wire [3:0] alpha;
osd_font_youyuan ref_font(.clk(clk),.glyph(glyph),.row(row),.bits(bits));
osd_font_pixel dut(.clk(clk),.glyph(glyph),.row(row),.col(col),.alpha(alpha));
integer g,r,c;
initial begin
for(g=0;g<128;g=g+1) for(r=0;r<16;r=r+1) for(c=0;c<16;c=c+1) begin
 @(negedge clk);glyph=g;row=r;col=c;@(posedge clk);#1;
 if(alpha!==((bits>>((15-c)*4))&4'hf)) begin
  $display("TEST_FAIL font pixel g=%0d row=%0d col=%0d got=%h row=%h",g,r,c,alpha,bits);$finish;
 end
end
$display("SCENARIO_PASS all-glyph-pixels-exact");$display("TEST_PASS");$finish;
end
initial begin #1000000;$display("TEST_FAIL timeout");$finish;end
endmodule
