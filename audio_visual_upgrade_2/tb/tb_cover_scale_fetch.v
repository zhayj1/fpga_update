`timescale 1ns/1ps
`default_nettype none
module tb_cover_scale_fetch;
    reg cp=0,cs=0,rn=0;
    always #20 cp=~cp;
    initial begin #3; forever #5 cs=~cs; end
    reg start=0,go=0,ack=0,done=0,valid=0;
    reg [23:0] tag=0;
    reg [15:0] out_w=16;
    reg [31:0] data=0;
    wire ready,req,pv,ld;
    wire [23:0] pixel;
    fetch_line_scene #(.MAX_W(32),.SCALE(1)) dut(
        .clk_sdr(cs),.rst_sdr_n(rn),.fetch_start(start),.row_base(21'd0),
        .words_per_row(16'd12),.fetch_tag(tag),.fetch_ready(ready),
        .fetch_busy(),.fetch_err(),.px_req(req),.px_addr(),.px_len(),
        .px_ack(ack),.px_done(done),.px_data(data),.px_valid(valid),
        .clk_pix(cp),.rst_pix_n(rn),.px_go(go),.expect_tag(tag),
        .frame_id(15'd1),.min_row(9'd0),.discard_all(1'b0),
        .img_w(16'd16),.out_w(out_w),.wr_pix(16'd12),
        .px_out(pixel),.px_out_vld(pv),.px_line_done(ld),
        .underrun_cnt(),.go_cnt(),.stall_cnt(),
        .shared_take(1'b0),.shared_active(1'b0),.shared_done(1'b0),
        .shared_error(1'b0),.shared_we(1'b0),.shared_good(1'b0),
        .shared_addr(10'd0),.next_bank()
    );
    function [7:0] byte_val;
        input integer pos;
        begin byte_val=(pos/3)+1; end
    endfunction
    integer j,k,seen,expected_count,source_width,extra,phase,position;
    reg [7:0] expected_seq [0:35];
    reg [7:0] expected_byte;
    reg monitoring=0;
    always @(negedge cp) if(monitoring && pv) begin
        expected_byte=expected_seq[seen];
        if(pixel!=={3{expected_byte}}) begin
            $display("TEST_FAIL scaled pixel %0d got=%h expected=%h",seen,pixel,{3{expected_byte}});
            $finish;
        end
        seen=seen+1;
    end
    task load_row;
        input [23:0] row_tag;
        begin
            wait(ready); @(negedge cs); tag=row_tag; start=1;
            @(negedge cs); start=0; wait(req);
            @(negedge cs); ack=1; @(negedge cs); ack=0;
            for(j=0;j<12;j=j+1) begin
                @(negedge cs); valid=1;
                data={byte_val(j*4+3),byte_val(j*4+2),
                      byte_val(j*4+1),byte_val(j*4)};
            end
            @(negedge cs); valid=0; done=1;
            @(negedge cs); done=0;
            repeat(8) @(negedge cp);
        end
    endtask
    task check_row;
        input integer count;
        begin
            source_width=16; extra=count-source_width; phase=0; position=0;
            for(k=0;k<source_width;k=k+1) begin
                expected_seq[position]=k+1; position=position+1;
                phase=phase+extra;
                if(phase>=source_width) begin
                    expected_seq[position]=k+1; position=position+1;
                    phase=phase-source_width;
                end
            end
            if(position!=count) begin $display("TEST_FAIL reference sequence length"); $finish; end
            @(negedge cp); expected_count=count; seen=0; monitoring=1; go=1;
            @(negedge cp); go=0;
            wait(ld); repeat(2) @(negedge cp); monitoring=0;
            if(seen!=count) begin
                $display("TEST_FAIL scaled count %0d expected %0d",seen,count); $finish;
            end
        end
    endtask
    initial begin
        #213; rn=1;
        load_row({15'd1,9'd0}); check_row(16);
        $display("SCENARIO_PASS scale_zero_identity");
        out_w=18;
        load_row({15'd1,9'd1}); check_row(18);
        $display("SCENARIO_PASS scaled_pixel_sequence");
        out_w=19;
        load_row({15'd1,9'd2}); check_row(19);
        out_w=21;
        load_row({15'd1,9'd3}); check_row(21);
        $display("SCENARIO_PASS scaled_all_byte_phases");
        $display("TEST_PASS"); $finish;
    end
    initial begin #1000000; $display("TEST_FAIL watchdog"); $finish; end
endmodule
`default_nettype wire
