`timescale 1ns/1ps
`default_nettype none
module tb_layout_five_rings;
    reg clk=0;always #20 clk=~clk;
    reg rst=1,frame=0,hit=0,de=0;reg [9:0] x=0,y=0;
    wire [1:0] vl;wire [7:0] a0,a1;
    attack_rings #(.CENTER_X(160)) a(.clk(clk),.rst(rst),.frame_tick(frame),.hit(hit),.de(de),.x(x),.y(y),.valid(vl[0]),.rgb(),.alpha(a0));
    attack_rings b(.clk(clk),.rst(rst),.frame_tick(frame),.hit(hit),.de(de),.x(x),.y(y),.valid(vl[1]),.rgb(),.alpha(a1));
    integer xx,yy,i,center,d,lo,hi,age,opacity,k;
    reg expect;
    task draw;
        begin
            for(yy=0;yy<480;yy=yy+1) begin
                de=0;y=yy;x=0;repeat(3) @(negedge clk);
                for(xx=0;xx<640;xx=xx+1) begin
                    x=xx;de=1;#1;
                    for(k=0;k<2;k=k+1) begin
                        center=k==0 ? 160 : 260;
                        d=36*(xx-center)*(xx-center)+25*(yy-165)*(yy-165);
                        expect=d>=25*lo*lo && d<=25*hi*hi;
                        if(vl[k]!==expect || (expect && (k==0 ? a0 : a1)!==opacity)) begin
                            $display("TEST_FAIL ring center=%0d x=%0d y=%0d",center,xx,yy);$finish;end
                    end
                    @(negedge clk);
                end
            end
            de=0;
        end
    endtask
    task advance;
        begin frame=1;@(negedge clk);frame=0;hit=0;repeat(24) @(negedge clk);end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=0;hit=1;advance;hit=0;
        lo=130;hi=133;opacity=188;draw;
        for(i=0;i<10;i=i+1) advance;
        lo=165;hi=166;opacity=82;draw;
        $display("SCENARIO_PASS LAY-06-rings");$display("TEST_PASS");$finish;
    end
    initial begin #40000000;$display("TEST_FAIL watchdog");$finish;end
endmodule
`default_nettype wire
