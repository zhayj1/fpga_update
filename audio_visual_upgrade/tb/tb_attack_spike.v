`timescale 1ns/1ps
`default_nettype none
module tb_attack_spike;
    reg clk=0, rst_n=0, bar_stb=0, bars_done=0, frame_stb=0;
    reg attack_hit=0, de=0, en=1;
    reg [5:0] bar_idx=0;
    reg [4:0] attack_band=0;
    reg [7:0] bar_level=0;
    reg [15:0] x=0,y=0;
    wire [23:0] dout;
    wire dout_vld;
    integer i;
    always #20 clk=~clk;
    layer_fft64 dut(
        .clk(clk), .rst_n(rst_n), .bar_stb(bar_stb),
        .bars_done(bars_done), .bar_idx(bar_idx), .bar_level(bar_level),
        .frame_stb(frame_stb), .attack_hit(attack_hit),
        .attack_band(attack_band), .de(de), .en(en),
        .x(x), .y(y), .dout(dout), .dout_vld(dout_vld));

    task frame_pulse;
        begin
            @(negedge clk);de=0;frame_stb=1;
            @(negedge clk);frame_stb=0;
        end
    endtask
    task check_pixel;
        input integer yy,xx;
        input expected_valid, expected_white;
        integer k;
        begin
            @(negedge clk);de=0;y=yy;x=0;
            @(negedge clk);de=1;
            for(k=0;k<=xx;k=k+1) begin
                x=k;#1;
                if(k==xx) begin
                    if(dout_vld!==expected_valid) begin
                        $display("TEST_FAIL pixel x=%0d y=%0d valid=%b expected=%b",xx,yy,dout_vld,expected_valid);$finish;
                    end
                    if(expected_valid && (dout===24'hFFFFFF)!==expected_white) begin
                        $display("TEST_FAIL pixel x=%0d y=%0d rgb=%h white=%b",xx,yy,dout,expected_white);$finish;
                    end
                end
                if(k<xx) @(negedge clk);
            end
        end
    endtask
    task hit_band;
        input [4:0] b;
        begin
            @(negedge clk);de=0;attack_band=b;attack_hit=1;
            @(negedge clk);attack_hit=0;
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        for(i=0;i<64;i=i+1) begin
            @(negedge clk);bar_idx=i;bar_level=0;bar_stb=1;
        end
        @(negedge clk);bar_stb=0;bars_done=1;
        @(negedge clk);bars_done=0;
        frame_pulse();
        check_pixel(369,331,0,0);
        hit_band(9);
        check_pixel(369,331,0,0);
        $display("SCENARIO_PASS spike_waits_for_frame");
        frame_pulse();
        check_pixel(369,331,1,1);
        check_pixel(430,381,1,0);
        check_pixel(369,101,0,0);
        check_pixel(369,330,0,0);
        check_pixel(369,339,0,0);
        $display("SCENARIO_PASS local_spike_bright_cap");
        frame_pulse();
        check_pixel(369,331,0,0);
        check_pixel(386,331,1,1);
        repeat(45) frame_pulse();
        check_pixel(386,331,0,0);
        $display("SCENARIO_PASS spike_decay");
        hit_band(17);
        frame_pulse();
        check_pixel(369,631,1,1);
        check_pixel(369,331,0,0);
        $display("SCENARIO_PASS high_band_edge_mapping");
        $display("TEST_PASS");$finish;
    end
    initial begin #4000000;$display("TEST_FAIL attack spike timeout");$finish;end
endmodule
`default_nettype wire
