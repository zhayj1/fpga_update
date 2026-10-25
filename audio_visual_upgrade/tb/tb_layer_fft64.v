`timescale 1ns/1ps
`default_nettype none
module tb_layer_fft64;
    reg clk=0, rst_n=0, bar_stb=0, bars_done=0, frame_stb=0;
    reg attack_hit=0;
    reg [4:0] attack_band=0;
    reg [5:0] bar_idx=0;
    reg [7:0] bar_level=0;
    reg de=0, en=1;
    reg [15:0] x=0,y=0;
    wire [23:0] dout;
    wire dout_vld;
    always #20 clk=~clk;
    layer_fft64 dut(
        .clk(clk), .rst_n(rst_n), .bar_stb(bar_stb), .bars_done(bars_done),
        .bar_idx(bar_idx), .bar_level(bar_level), .frame_stb(frame_stb),
        .attack_hit(attack_hit), .attack_band(attack_band),
        .de(de), .en(en), .x(x), .y(y), .dout(dout), .dout_vld(dout_vld));
    task point;
        input integer yy;
        input integer xx;
        input expected;
        integer k;
        begin
            @(negedge clk); de=0; y=yy; x=0;
            @(negedge clk); de=1;
            for(k=0;k<=xx;k=k+1) begin
                x=k;
                #1;
                if(k==xx) begin
                    if(dout_vld!==expected) begin
                        $display("TEST_FAIL pixel x=%0d y=%0d actual=%b expected=%b",xx,yy,dout_vld,expected);$finish;
                    end
                    if(expected && (dout===24'hFFFFFF || dout===24'h000000)) begin
                        $display("TEST_FAIL colored bar rgb=%h",dout);$finish;
                    end
                end
                if(k<xx) @(negedge clk);
            end
        end
    endtask
    task white_point;
        input integer yy;
        input integer xx;
        integer k;
        begin
            @(negedge clk); de=0; y=yy; x=0;
            @(negedge clk); de=1;
            for(k=0;k<=xx;k=k+1) begin
                x=k;
                #1;
                if(k==xx && (dout_vld!==1'b1 || dout!==24'hFFFFFF)) begin
                    $display("TEST_FAIL white cap x=%0d y=%0d valid=%b rgb=%h",xx,yy,dout_vld,dout);
                    $finish;
                end
                if(k<xx) @(negedge clk);
            end
        end
    endtask
    initial begin
        #100; rst_n=1;
        @(negedge clk); bar_idx=50;bar_level=200;bar_stb=1;
        @(negedge clk);bar_stb=0;bars_done=1;
        @(negedge clk);bars_done=0;frame_stb=1;
        @(negedge clk);frame_stb=0;
        point(400,500,0);point(400,501,1);
        point(400,508,1);point(400,509,0);
        point(300,501,0);point(301,501,1);
        point(303,501,1);point(320,501,1);
        point(477,501,1);point(478,501,0);
        if(dut.height(8'd0)!==8'd0 || dut.height(8'd64)!==8'd56 ||
           dut.height(8'd128)!==8'd112 || dut.height(8'd200)!==8'd175 ||
           dut.height(8'd255)!==8'd224) begin
            $display("TEST_FAIL spectrum height mapping");$finish;
        end
        $display("SCENARIO_PASS colored_64_bar_geometry");
        @(negedge clk);de=0;bar_idx=50;bar_level=0;bar_stb=1;
        @(negedge clk);bar_stb=0;bars_done=1;
        @(negedge clk);bars_done=0;
        point(400,501,1);
        @(negedge clk);de=0;bar_idx=0;bar_stb=1;frame_stb=1;
        @(negedge clk);bar_stb=0;frame_stb=0;
        point(400,501,1);
        $display("SCENARIO_PASS no_swap_during_bar_write");
        @(negedge clk);de=0;bars_done=1;
        @(negedge clk);bars_done=0;
        @(negedge clk);de=0;frame_stb=1;
        @(negedge clk);frame_stb=0;
        point(400,501,0);
        $display("SCENARIO_PASS frame_bank_atomic_swap");
        @(negedge clk);de=0;bar_idx=50;bar_level=200;bar_stb=1;
        @(negedge clk);bar_idx=20;bar_level=0;
        @(negedge clk);bar_stb=0;bars_done=1;
        @(negedge clk);bars_done=0;frame_stb=1;
        @(negedge clk);frame_stb=0;
        @(negedge clk);attack_hit=1;attack_band=13;
        @(negedge clk);attack_hit=0;
        point(250,501,0);
        @(negedge clk);de=0;frame_stb=1;
        @(negedge clk);frame_stb=0;
        point(250,501,1);
        white_point(220,501);
        point(250,201,0);
        $display("SCENARIO_PASS local_spike_and_white_cap");
        repeat(28) begin
            @(negedge clk);de=0;frame_stb=1;
            @(negedge clk);frame_stb=0;
        end
        point(250,501,0);
        point(301,501,1);
        $display("SCENARIO_PASS spike_decay");
        $display("TEST_PASS");$finish;
    end
    initial begin #2000000;$display("TEST_FAIL display timeout");$finish;end
endmodule
`default_nettype wire
