`timescale 1ns/1ps
`default_nettype none
module tb_settings_equivalence;
    reg clk=0, pix=0, rst_n=0, rst_pix=1, frame=0;
    always #7 clk=~clk;
    always #10 pix=~pix;
    reg [46:0] settings=0;
    reg [3:0] transition_settings=0;
    reg [6:0] swatch=0;
    genvar g;
    generate for(g=0;g<2;g=g+1) begin: variants
        wire [218:0] actual, expected;
        visual_settings #(.TRANSITIONS(g)) dut(
            .clk(clk),.rst_n(rst_n),.settings(settings),
            .transition_settings(transition_settings),.clk_pix(pix),.rst_pix(rst_pix),
            .frame_tick(frame),.swatch_index(swatch),.swatch_rgb(actual[23:0]),
            .spectrum(actual[47:24]),.sung(actual[71:48]),.other(actual[95:72]),
            .title(actual[119:96]),.singer(actual[143:120]),.rings(actual[167:144]),
            .effects(actual[172:168]),.indices(actual[214:173]),.transition(actual[218:215]));
        visual_settings_reference #(.TRANSITIONS(g)) reference(
            .clk(clk),.rst_n(rst_n),.settings(settings),
            .transition_settings(transition_settings),.clk_pix(pix),.rst_pix(rst_pix),
            .frame_tick(frame),.swatch_index(swatch),.swatch_rgb(expected[23:0]),
            .spectrum(expected[47:24]),.sung(expected[71:48]),.other(expected[95:72]),
            .title(expected[119:96]),.singer(expected[143:120]),.rings(expected[167:144]),
            .effects(expected[172:168]),.indices(expected[214:173]),.transition(expected[218:215]));
        always @(negedge pix) if(actual !== expected) begin
            $display("TEST_FAIL settings cycle mismatch variant=%0d time=%0t actual=%h expected=%h",
                g,$time,actual,expected);$finish;
        end
    end endgenerate
    integer i,j,seed=1749;
    task tick; begin @(posedge pix);#1;@(negedge pix);#1;end endtask
    initial begin
        repeat(5) tick;rst_n=1;rst_pix=0;
        // Every reset position in the two-phase, six-object lookup, with
        // early/continuous frame pulses and changes while the source is busy.
        for(j=0;j<36;j=j+1) begin
            settings={$random(seed),$random(seed)};
            transition_settings=j;
            for(i=0;i<140;i=i+1) begin
                frame=(i%7==0 || i>100);
                if(i<30 && i%3==0) settings={$random(seed),$random(seed)};
                if(i==j) begin rst_n=0;rst_pix=1;end
                if(i==j+2) begin rst_n=1;rst_pix=0;end
                swatch=$random(seed);
                tick;
            end
        end
        $display("SCENARIO_PASS SETTINGS-cycle-reset-and-busy");
        // Include all 128 palette indices, default aliases, both transition
        // parameter modes, delayed frames and multiple mailbox generations.
        for(j=0;j<128;j=j+1) begin
            settings={j[4:0],{6{j[6:0]}}};transition_settings=j;
            for(i=0;i<100;i=i+1) begin frame=(i>=60 && i%3==0);tick;end
        end
        $display("SCENARIO_PASS SETTINGS-cycle-all-indices");
        for(i=0;i<100000;i=i+1) begin
            if(i%11==0) begin
                settings={$random(seed),$random(seed)};
                transition_settings=$random(seed);
            end
            frame=($random(seed)&31)==0;swatch=$random(seed);tick;
        end
        $display("SCENARIO_PASS SETTINGS-cycle-random-mailbox");
        $display("TEST_PASS");$finish;
    end
    initial begin #3000000;$display("TEST_FAIL settings equivalence timeout");$finish;end
endmodule
`default_nettype wire
