`timescale 1ns/1ps
module tb_alpha_blend16;
    reg [23:0] b,f;
    reg [3:0] a;
    wire [23:0] rgb,rgb_mask,rgb_dsp;
    integer ib,iff,ia,ref_value;
    alpha_blend16 dut(.background(b),.foreground(f),.alpha(a),.rgb(rgb));
    alpha_blend16 #(.USE_DSP(1),.DSP_CHANNELS(1)) masked(.background(b),.foreground(f),.alpha(a),.rgb(rgb_mask));
    alpha_blend16 #(.USE_DSP(1)) all_dsp(.background(b),.foreground(f),.alpha(a),.rgb(rgb_dsp));
    initial begin
        for(ib=0;ib<256;ib=ib+1)
          for(iff=0;iff<256;iff=iff+1)
            for(ia=0;ia<16;ia=ia+1) begin
                b={ib[7:0],iff[7:0],ib[7:0]};
                f={iff[7:0],ib[7:0],iff[7:0]}; a=ia; #1;
                if(rgb_mask!==rgb || rgb_dsp!==rgb) begin
                    $display("TEST_FAIL DSP mapping b=%0d f=%0d a=%0d",ib,iff,ia);$finish;
                end
                ref_value=(ib*(15-ia)+iff*ia+7)/15;
                if(rgb[23:16]!==ref_value[7:0] || rgb[7:0]!==ref_value[7:0]) begin
                    $display("TEST_FAIL blend b=%0d f=%0d a=%0d got=%h expected=%0d",ib,iff,ia,rgb,ref_value); $finish;
                end
                ref_value=(iff*(15-ia)+ib*ia+7)/15;
                if(rgb[15:8]!==ref_value[7:0]) begin $display("TEST_FAIL green"); $finish; end
            end
        $display("SCENARIO_PASS TYP-02"); $display("TEST_PASS"); $finish;
    end
endmodule
