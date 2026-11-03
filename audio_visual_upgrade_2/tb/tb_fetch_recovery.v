`timescale 1ns/1ps
`default_nettype none
module tb_fetch_recovery;
    reg cp=0,cs=0,rn=0;
    always #20 cp=~cp;
    initial begin #3; forever #5 cs=~cs; end
    reg start=0,go=0,ack=0,done=0,valid=0,discard=0;
    reg [23:0] tag=0,expected_tag=0;
    reg [14:0] frame_id=1;
    reg [8:0] min_row=0;
    reg [31:0] data=0;
    wire ready,busy,err,req,pv,ld;
    wire [23:0] pixel;
    wire [31:0] und,stall;
    fetch_line_scene #(.MAX_W(80)) dut(
        .clk_sdr(cs),.rst_sdr_n(rn),.fetch_start(start),.row_base(21'd0),
        .words_per_row(16'd60),.fetch_tag(tag),.fetch_ready(ready),.fetch_busy(busy),.fetch_err(err),
        .px_req(req),.px_addr(),.px_len(),.px_ack(ack),.px_done(done),.px_data(data),.px_valid(valid),
        .clk_pix(cp),.rst_pix_n(rn),.px_go(go),.expect_tag(expected_tag),.frame_id(frame_id),
        .min_row(min_row),.discard_all(discard),.img_w(16'd80),.wr_pix(16'd60),
        .px_out(pixel),.px_out_vld(pv),.px_line_done(ld),.underrun_cnt(und),.go_cnt(),.stall_cnt(stall));
    integer seen=0,monitor=0,j,failures=0;
    reg [7:0] color=0;
    always @(negedge cp) if(monitor && pv) begin
        seen=seen+1;
        if(pixel!=={color,color,color}) begin $display("TEST_FAIL wrong row content"); $finish; end
    end
    always @(posedge cs) if(rn && dut.mem_we && dut.stream_on && dut.wr_buf_l==dut.rd_buf) begin
        $display("TEST_FAIL buffer overwritten during display"); $finish;
    end
    task begin_fetch;
        input [23:0] t;
        begin
            wait(ready); @(negedge cs); tag=t; start=1;
            @(negedge cs); start=0; wait(req);
            @(negedge cs); ack=1; @(negedge cs); ack=0;
        end
    endtask
    task return_words;
        input integer count;
        input [7:0] v;
        begin
            for(j=0;j<count;j=j+1) begin @(negedge cs); valid=1; data={v,v,v,v}; end
            @(negedge cs); valid=0; done=1;
            @(negedge cs); done=0;
            repeat(8) @(negedge cp);
        end
    endtask
    task read_row;
        input [23:0] t;
        input integer count;
        input [7:0] v;
        begin
            @(negedge cp); expected_tag=t; go=1; seen=0; color=v; monitor=1;
            @(negedge cp); go=0;
            wait(ld); repeat(2) @(negedge cp); monitor=0;
            if(seen!=count) begin $display("TEST_FAIL visible pixels=%0d expected=%0d",seen,count); $finish; end
        end
    endtask
    initial begin
        #213; rn=1;
        begin_fetch({15'd1,9'd0}); return_words(60,8'h31); read_row({15'd1,9'd0},80,8'h31);
        $display("SCENARIO_PASS valid_row");
        min_row=1;
        begin_fetch({15'd1,9'd1});
        read_row({15'd1,9'd1},0,0); min_row=2;
        return_words(60,8'h92); wait(ready);
        begin_fetch({15'd1,9'd2}); return_words(60,8'h43); read_row({15'd1,9'd2},80,8'h43);
        $display("SCENARIO_PASS late_row_discard_and_recovery");
        min_row=3;
        begin_fetch({15'd1,9'd3}); return_words(22,8'h64);
        read_row({15'd1,9'd3},0,0);
        $display("SCENARIO_PASS truncated_burst_rejected");
        min_row=4;
        begin_fetch({15'd1,9'd4}); frame_id=2; min_row=0;
        return_words(60,8'h75); wait(ready);
        begin_fetch({15'd2,9'd0}); return_words(60,8'h86); read_row({15'd2,9'd0},80,8'h86);
        $display("SCENARIO_PASS old_frame_discard");
        begin_fetch({15'd2,9'd1}); discard=1; return_words(60,8'h97); wait(ready);
        discard=0; rn=0; repeat(8) @(negedge cp); rn=1; frame_id=1; min_row=0;
        begin_fetch({15'd1,9'd0}); return_words(60,8'h18); read_row({15'd1,9'd0},80,8'h18);
        if(stall!=0) begin $display("TEST_FAIL queue stall"); $finish; end
        $display("SCENARIO_PASS disable_and_reset_recovery");
        $display("TEST_PASS"); $finish;
    end
    initial begin #1000000; $display("TEST_FAIL watchdog"); $finish; end
endmodule
`default_nettype wire
