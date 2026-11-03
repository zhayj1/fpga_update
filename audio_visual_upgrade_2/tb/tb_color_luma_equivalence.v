`timescale 1ns/1ps
`default_nettype none
module tb_color_luma_equivalence;
    skeleton_core #(.en_fft(0),.en_osd(0)) dut(
        .clk_pix(1'b0),.clk_pix5x(1'b0),.rst_pix(1'b1),
        .clk_sdr(1'b0),.clk_sdr_sft(1'b0),.rst_sdr(1'b1),
        .clk(1'b0),.rst_n(1'b0),.key4(1'b1));
    function [7:0] color_clip;
        input signed [19:0] value;
        begin
            if (value < 0) color_clip=8'd0;
            else if (value > 20'sd255) color_clip=8'd255;
            else color_clip=value[7:0];
        end
    endfunction
    function [23:0] color_link_gains_reference;
        input [23:0] src;
        input [9:0] sat_gain, con_gain;
        // Exact algebra: d*256+d*(gain-256) = d*gain, including
        // the original 20-bit wrap before contrast clipping. Saturation
        // output is -1019..1274 for every 10-bit gain; signed 12 bits suffice.
        reg [7:0] r,g,b,lum;
        reg signed [10:0] sat_factor,con_factor;
        reg signed [8:0] dr,dg,db;
        reg signed [19:0] sr,sg,sb;
        reg signed [11:0] sat_r,sat_g,sat_b;
        reg signed [11:0] lr,lg,lb;
        reg signed [19:0] cr,cg,cb;
        begin
            r=src[23:16]; g=src[15:8]; b=src[7:0];
            // Canvas saturate()/contrast() uses the CSS filter luma matrix
            // 0.213/0.715/0.072. 55/183/18 is its Q8 shift/add form.
            lum=({3'd0,r,5'd0}+{4'd0,r,4'd0}+{6'd0,r,2'd0}+{7'd0,r,1'd0}+{8'd0,r}+
                 {1'd0,g,7'd0}+{3'd0,g,5'd0}+{4'd0,g,4'd0}+{6'd0,g,2'd0}+
                 {7'd0,g,1'd0}+{8'd0,g}+
                 {4'd0,b,4'd0}+{7'd0,b,1'd0}) >> 8;
            sat_factor=$signed({1'b0,sat_gain});
            con_factor=$signed({1'b0,con_gain});
            dr=$signed({1'b0,r})-$signed({1'b0,lum});
            dg=$signed({1'b0,g})-$signed({1'b0,lum});
            db=$signed({1'b0,b})-$signed({1'b0,lum});
            sr=dr*sat_factor;
            sg=dg*sat_factor;
            sb=db*sat_factor;
            sat_r=$signed({1'b0,lum})+((sr+20'sd128)>>>8);
            sat_g=$signed({1'b0,lum})+((sg+20'sd128)>>>8);
            sat_b=$signed({1'b0,lum})+((sb+20'sd128)>>>8);
            lr=sat_r-20'sd128; lg=sat_g-20'sd128; lb=sat_b-20'sd128;
            cr=lr*con_factor;
            cg=lg*con_factor;
            cb=lb*con_factor;
            color_link_gains_reference={color_clip(20'sd128+((cr+20'sd128)>>>8)),
                        color_clip(20'sd128+((cg+20'sd128)>>>8)),
                        color_clip(20'sd128+((cb+20'sd128)>>>8))};
        end
    endfunction

    integer i,want,seed;
    reg [23:0] src;
    reg [9:0] sg,cg;
    reg [23:0] actual,expected;
    initial begin
        #1;
        for(i=0;i<16777216;i=i+1) begin
            src=i;
            want=(55*src[23:16]+183*src[15:8]+18*src[7:0])/256;
            if(dut.color_luma(src)!==want[7:0]) begin
                $display("TEST_FAIL luma rgb=%h got=%0d expected=%0d",src,dut.color_luma(src),want);$finish;
            end
        end
        $display("SCENARIO_PASS TR-luma-all-16777216-colors");
        seed=32'h13579BDF;
        for(i=0;i<262144;i=i+1) begin
            src=$random(seed);sg=$random(seed);cg=$random(seed);
            actual=dut.color_link_gains(src,sg,cg);
            expected=color_link_gains_reference(src,sg,cg);
            if(actual!==expected) begin
                $display("TEST_FAIL color transform rgb=%h gains=%0d,%0d got=%h expected=%h",src,sg,cg,actual,expected);$finish;
            end
        end
        $display("SCENARIO_PASS TR-color-transform-reference-including-wrap");
        $display("TEST_PASS");$finish;
    end
endmodule
`default_nettype wire
