`timescale 1ns/1ps
module tb_osd_numeric;
reg clk=0;always #5 clk=~clk;
reg [8:0] number=0,bar_value=0;reg [2:0] bar_kind=0;
wire [11:0] bcd;wire [7:0] bar;
osd_numeric_rom dut(.clk(clk),.number(number),.bar_value(bar_value),.bar_kind(bar_kind),.bcd(bcd),.bar(bar));
integer n,k,h,t,r,delta,factor,want;
initial begin
for(k=0;k<8;k=k+1) for(n=0;n<512;n=n+1) begin
 @(negedge clk);number=n;bar_value=n;bar_kind=k;
 h=n>=200?2:n>=100?1:0;r=n-h*100;
 t=r>=90?9:r>=80?8:r>=70?7:r>=60?6:r>=50?5:r>=40?4:r>=30?3:r>=20?2:r>=10?1:0;
 case(k)
 0:begin delta=(n-2)&511;factor=1186;end
 1:begin delta=n;factor=176;end
 2:begin delta=n;factor=451;end
 3:begin delta=(n-60)&511;factor=501;end
 4:begin delta=(n-100)&511;factor=282;end
 5:begin delta=(n-80)&511;factor=902;end
 6:begin delta=(n-100)&511;factor=644;end
 7:begin delta=0;factor=0;end
 endcase
 want=(delta*factor)>>8;if(want>176) want=176;
 @(posedge clk);#1;
 if(bcd!==((h<<8)|(t<<4)|((r-t*10)&15)) || bar!==want) begin
  $display("TEST_FAIL numeric k=%0d value=%0d bcd=%h bar=%0d want=%0d",k,n,bcd,bar,want);$finish;
 end
end
$display("SCENARIO_PASS numeric-full-input-range");$display("TEST_PASS");$finish;
end
initial begin #1000000;$display("TEST_FAIL timeout");$finish;end
endmodule
