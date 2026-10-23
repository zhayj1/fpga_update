`timescale 1ns/1ps
`default_nettype none
// Independent rational scroll model, driven only through public interfaces.
module lyric_bounds_case #(
    parameter integer SAMPLES=16, PIXELS=7, WD_CYCLES=16
)(output reg finished=0);
    reg clk=0; always #5 clk=~clk;
    reg rst=0,tick=0,samp=0;
    reg [23:0] played=0;
    wire busy,done,ok,req,scroll;
    wire [7:0] err;
    wire [5:0] offset;
    wire [20:0] addr;
    wire [15:0] len;
    reg ack=0,valid=0,read_done=0,hang=0;
    reg [31:0] data=0;
    integer phase=0,index=0,j,waited,expected_offset;
    reg [31:0] expected_acc;
    localparam integer NEXT_SAMPLE=100000;
    lyric_pick #(.CLK_HZ(1000),.WD_MS(WD_CYCLES),
        .SC_SAMP(SAMPLES),.SC_PX(PIXELS)) dut (
        .clk_sdr(clk),.rst_sdr_n(rst),.tick(tick),.samp_stb(samp),
        .played(played),.busy(busy),.done(done),.err(err),.tab_ok(ok),
        .off_px(offset),.scroll_on(scroll),.px_req(req),.px_addr(addr),
        .px_len(len),.px_ack(ack),.px_done(read_done),.px_data(data),.px_valid(valid)
    );
    task fail;
        input [511:0] message;
        begin
            $display("TEST_FAIL bounds S=%0d P=%0d WD=%0d: %0s",SAMPLES,PIXELS,WD_CYCLES,message);
            $finish;
        end
    endtask
    function [31:0] table_word;
        input integer word_index;
        begin
            case(word_index)
                0:table_word=32'h3143524c;
                4:table_word=32'h00020002;
                8:table_word=0;
                9:table_word=32'h00010000;
                10:table_word=NEXT_SAMPLE;
                11:table_word=32'h00010001;
                default:table_word=0;
            endcase
        end
    endfunction
    always @(negedge clk) begin
        ack=0; valid=0; read_done=0;
        if(!rst) begin phase=0;index=0;end
        else if(!hang) begin
            case(phase)
                0:if(req) begin
                    if(addr!==21'h17f040 || len!==136) fail("request geometry");
                    ack=1;phase=1;index=0;
                end
                1:begin valid=1;data=table_word(index);index=index+1;
                    if(index==136) phase=2;end
                2:begin read_done=1;phase=0;end
            endcase
        end
    end
    task fetch;
        begin
            @(posedge clk); #1;tick=1;
            @(posedge clk); #1;tick=0;
            waited=0;
            while(done!==1 && waited<300) begin @(posedge clk);#1;waited=waited+1;end
            if(done!==1 || busy!==0) fail("fetch did not finish");
        end
    endtask
    task sample_step;
        begin
            @(posedge clk);#1;samp=1;
            @(posedge clk);#1;samp=0;
        end
    endtask
    initial begin
        repeat(4) @(posedge clk);#1;rst=1;
        played=NEXT_SAMPLE-SAMPLES;
        fetch;
        if(err!==0 || ok!==1) fail("valid table");
        sample_step;
        expected_acc=PIXELS;expected_offset=0;
        if(offset!==0 || scroll!==1) fail("window preload");
        // Check every output step, including repeated carries and saturation.
        for(j=1;j<=SAMPLES+80;j=j+1) begin
            expected_acc=expected_acc+PIXELS;
            if(expected_acc>=SAMPLES) begin
                expected_acc=expected_acc-SAMPLES;
                if(expected_offset<(PIXELS & 63)) expected_offset=expected_offset+1;
            end
            sample_step;
            if(offset!==expected_offset || scroll!==1) fail("scroll phase differs from integer model");
        end
        played=NEXT_SAMPLE;
        sample_step;
        if(offset!==expected_offset || scroll!==0) fail("window exit must hold offset");
        fetch;
        if(err!==0 || offset!==0 || scroll!==0) fail("line change reset");
        // A stalled request must time out and remain idle beyond counter wrap.
        repeat(WD_CYCLES+4) @(posedge clk);
        #1;hang=1;
        fetch;
        if(err!==8'h04 || ok!==0) fail("watchdog threshold");
        repeat(WD_CYCLES*3+5) @(posedge clk);
        #1;hang=0;
        fetch;
        if(err!==0 || ok!==1) fail("recovery after saturated watchdog");
        finished=1;
    end
endmodule

module tb_lyric_bounds;
    wire [6:0] finished;
    lyric_bounds_case #(.SAMPLES(1),.PIXELS(1),.WD_CYCLES(8)) c0(finished[0]);
    lyric_bounds_case #(.SAMPLES(2),.PIXELS(1),.WD_CYCLES(16)) c1(finished[1]);
    lyric_bounds_case #(.SAMPLES(16),.PIXELS(16),.WD_CYCLES(32)) c2(finished[2]);
    lyric_bounds_case #(.SAMPLES(64),.PIXELS(38),.WD_CYCLES(64)) c3(finished[3]);
    lyric_bounds_case #(.SAMPLES(14400),.PIXELS(38),.WD_CYCLES(128)) c4(finished[4]);
    lyric_bounds_case #(.SAMPLES(16),.PIXELS(63),.WD_CYCLES(16)) c5(finished[5]);
    lyric_bounds_case #(.SAMPLES(16384),.PIXELS(1),.WD_CYCLES(32)) c6(finished[6]);
    initial begin
        wait(&finished);
        $display("SCENARIO_PASS lyric-scroll-parameter-boundaries");
        $display("SCENARIO_PASS lyric-watchdog-power-of-two-and-recovery");
        $display("TEST_PASS");$finish;
    end
    initial begin #10000000;$display("TEST_FAIL global timeout");$finish;end
endmodule
`default_nettype wire
