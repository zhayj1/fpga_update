`timescale 1ns/1ps
`default_nettype none
// Independent file-byte and FIFO-byte models; no DUT internals are referenced.
module tb_bmp_capacity;
    reg clk=0, rst_n=0, start=0;
    always #10 clk=~clk;
    wire busy,done,lo_open,lo_ready,lo_want,flush,we,cfg_valid,finish_valid;
    wire [7:0] err,lo_index,di;
    wire [15:0] img_w,img_h,cfg_wpr;
    wire [20:0] cfg_first;
    wire [18:0] cfg_words,finish_words;
    wire cfg_down;
    reg [20:0] base=0;
    reg [18:0] slot_words=19'd240000;
    reg [31:0] file_size=0;
    reg valid=0,eof=0,read_error=0,full=0,backend_done=0;
    reg [7:0] data=0,header[0:127];
    integer width,height,offset,source_stride,dest_stride,source_bytes;
    integer src_pos=0,out_pos=0,active=0,cycle=0,mode=0,serial=0;
    integer configs=0,finishes=0,opens=0,backend_delay=0;
    integer deliver_bytes=0,expected_error=0,check_pixels=1,expected_pixels=0;
    integer i,j,r,c,limit;
    reg [7:0] expected_byte;
    reg [31:0] exp_span,exp_first,exp_wpr;
    reg exp_down;

    bmp_load #(.EXTERNAL_BACKEND(1),.CLK_HZ(50000000),.WD_MS(1)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),.target_cover(1'b0),.file_index(8'd23),.slot_base(base),
        .busy(busy),.done(done),.err(err),.img_w(img_w),.img_h(img_h),
        .lo_open(lo_open),.lo_open_index(lo_index),.lo_open_busy(1'b0),
        .lo_rd_valid(valid),.lo_rd_data(data),.lo_rd_ready(lo_ready),.lo_want(lo_want),
        .lo_rd_eof(eof),.lo_rd_err(read_error),.file_size(file_size),.wd_max(32'd5000),
        .clk_sdr(clk),.rst_sdr_n(rst_n),.ld_rd(1'b0),.ld_ack(1'b0),.ld_done(1'b0),
        .ld_req(),.ld_addr(),.ld_len(),.ld_data(),
        .fifo_full_ext(full),.backend_done_ext(backend_done),.slot_words(slot_words),
        .fifo_flush_ext(flush),.fifo_we_ext(we),.fifo_di_ext(di),
        .cfg_valid_ext(cfg_valid),.cfg_first_ext(cfg_first),.cfg_words_ext(cfg_words),
        .cfg_wpr_ext(cfg_wpr),.cfg_down_ext(cfg_down),
        .finish_valid_ext(finish_valid),.finish_words_ext(finish_words)
    );
    task fail;
        input [8*100-1:0] why;
        begin
            $display("TEST_FAIL %0s case=%0d w=%0d h=%0d mode=%0d in=%0d out=%0d time=%0t",
                     why,serial,width,height,mode,src_pos,out_pos,$time);
            $finish;
        end
    endtask
    function [7:0] pixel;
        input integer row,pix,channel;
        begin pixel=(row*7+pix*13+channel*31+serial*3)&255;end
    endfunction
    function [31:0] get32;
        input integer at;
        begin get32={header[at+3],header[at+2],header[at+1],header[at]};end
    endfunction
    task put32;
        input integer at;
        input [31:0] value;
        begin
            header[at]=value[7:0];header[at+1]=value[15:8];
            header[at+2]=value[23:16];header[at+3]=value[31:24];
        end
    endtask

    // Data is held until acceptance. Gaps and FIFO full are independent of ready.
    always @(negedge clk) begin
        cycle=cycle+1;valid=0;eof=0;read_error=0;backend_done=0;
        full=(cycle%17==4 || cycle%17==5 || cycle%17==6);
        if(rst_n) begin
            if(backend_delay>0) begin
                backend_delay=backend_delay-1;
                if(backend_delay==0) backend_done=1;
            end
            if(active) begin
                if(mode==1) begin end // no progress: exercise watchdog
                else if(mode==2 && src_pos>=offset+7) begin
                    read_error=1;active=0;
                end else if(src_pos>=deliver_bytes) begin eof=1;active=0;end
                else if(cycle%13!=0) begin
                    valid=1;
                    if(src_pos<54) data=header[src_pos];
                    else if(src_pos<offset) data=8'hc7;
                    else begin
                        r=(src_pos-offset)/source_stride;
                        c=(src_pos-offset)%source_stride;
                        data=(c<width*3) ? pixel(r,c/3,c%3) : 8'h5a;
                    end
                end
            end
        end else begin active=0;backend_delay=0;full=0;end
    end
    always @(posedge clk) begin
        if(rst_n) begin
            if(lo_open) begin
                if(lo_index!==8'd23) fail("wrong file index");
                active=1;src_pos=0;opens=opens+1;
            end
            if(valid && lo_ready) src_pos=src_pos+1;
            if(we) begin
                if(full || !check_pixels || out_pos>=expected_pixels)
                    fail("unexpected FIFO byte");
                r=out_pos/dest_stride;c=out_pos%dest_stride;
                expected_byte=(c<width*3) ? pixel(r,c/3,2-c%3) : 8'd0;
                if(di!==expected_byte) fail("FIFO RGB byte or row padding mismatch");
                out_pos=out_pos+1;
            end
            if(cfg_valid) begin
                configs=configs+1;
                if(mode!=1 && (cfg_first!==exp_first[20:0] || cfg_wpr!==exp_wpr[15:0] ||
                    cfg_words!==exp_span[18:0] || cfg_down!==exp_down))
                    fail("configuration changed, including malformed-header path");
            end
            if(finish_valid) begin
                finishes=finishes+1;
                if(finish_words!==(out_pos/4)) fail("finish byte count mismatch");
                backend_delay=9;
            end
        end
    end
    task prepare;
        input integer w,h,off;
        begin
            @(negedge clk);#1;
            if(busy) fail("new case began while busy");
            serial=serial+1;width=w;height=h;offset=off;
            source_stride=((w*3+3)/4)*4;
            dest_stride=((w*3+15)/16)*16;
            source_bytes=off+source_stride*((h<0)?-h:h);
            file_size=source_bytes;deliver_bytes=source_bytes;
            expected_error=0;mode=0;check_pixels=1;
            expected_pixels=dest_stride*((h<0)?-h:h);
            base=21'h1000;slot_words=19'd240000;
            src_pos=0;out_pos=0;opens=0;configs=0;finishes=0;
            for(i=0;i<128;i=i+1) header[i]=0;
            header[0]=8'h42;header[1]=8'h4d;
            put32(2,source_bytes);put32(10,off);put32(14,40);
            put32(18,w);put32(22,h);header[26]=1;header[28]=24;
        end
    endtask
    task rejected;
        input integer code;
        begin expected_error=code;expected_pixels=0;check_pixels=0;end
    endtask
    task run_case;
        reg [31:0] hdr_height,hmag,w3,sts;
        begin
            hdr_height=get32(22);
            hmag=hdr_height[31] ? (~hdr_height+32'd1) : hdr_height;
            w3=get32(18)*32'd3;sts=(w3+32'd15)&32'hfffffff0;
            exp_wpr={16'd0,sts[17:2]};exp_span=hmag*exp_wpr;
            exp_down=!hdr_height[31];
            exp_first=(hdr_height[31]==0) ? base+exp_span-exp_wpr : base;
            @(negedge clk);#1;start=1;
            @(negedge clk);#1;start=0;
            limit=0;
            while(done!==1 && limit<3000000) begin @(negedge clk);#1;limit=limit+1;end
            if(limit==3000000) fail("completion timeout");
            if(err!==expected_error[7:0] || busy!==0 || opens!=1 || configs!=1 || finishes!=1)
                fail("completion status/configuration count mismatch");
            if(expected_error==0 && (img_w!==width || img_h!==((height<0)?-height:height) ||
                out_pos!=expected_pixels)) fail("successful image geometry/count mismatch");
            repeat(3) begin @(negedge clk);#1;if(done) fail("done was not a pulse");end
            if(active && mode!=1) fail("file stream was not drained");
            active=0;
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);#1;rst_n=1;
        // Widths cover all BMP four-byte and destination sixteen-byte residues.
        for(j=1;j<=17;j=j+1) begin
            prepare(j,3,54);run_case();
            prepare(j,-3,70);run_case();
        end
        $display("SCENARIO_PASS bmp-padding-and-orientation-matrix");
        prepare(640,480,54);run_case();
        prepare(639,-480,70);run_case();
        $display("SCENARIO_PASS bmp-maximum-image-and-backpressure");
        prepare(5,3,54);put32(18,32'h00010005);rejected(2);run_case();
        prepare(5,3,54);put32(18,32'h80000005);rejected(1);run_case();
        prepare(5,3,54);put32(22,32'h00010003);rejected(6);run_case();
        prepare(5,3,54);put32(22,32'h80000000);rejected(6);run_case();
        prepare(5,3,54);put32(18,0);put32(22,0);header[28]=16;rejected(1);run_case();
        prepare(5,3,54);put32(22,0);header[28]=16;rejected(1);run_case();
        prepare(5,3,54);put32(22,481);header[28]=16;rejected(6);run_case();
        prepare(5,3,54);header[26]=0;rejected(5);run_case();
        prepare(5,3,54);header[28]=16;rejected(5);run_case();
        prepare(5,3,54);put32(30,32'h00010000);rejected(5);run_case();
        prepare(5,3,54);put32(10,53);rejected(1);run_case();
        prepare(5,3,54);base=21'h1ffffc;rejected(2);run_case();
        prepare(5,3,54);slot_words=8;rejected(2);run_case();
        prepare(5,3,54);header[0]=0;put32(18,641);rejected(1);run_case();
        $display("SCENARIO_PASS bmp-header-full-width-and-error-priority");
        prepare(5,3,54);deliver_bytes=61;expected_error=3;run_case();
        prepare(5,3,54);file_size=61;expected_error=3;run_case();
        prepare(5,3,54);mode=2;expected_error=4;run_case();
        prepare(640,-2,54);run_case();
        $display("SCENARIO_PASS bmp-truncated-stream-and-recovery");
        prepare(5,3,54);mode=1;expected_error=4;run_case();
        // Reset an open transaction and then load without any retained byte state.
        prepare(5,3,54);
        @(negedge clk);#1;start=1;
        @(negedge clk);#1;start=0;
        repeat(70) @(negedge clk);#1;rst_n=0;
        repeat(5) @(negedge clk);#1;
        if(busy || done || we || cfg_valid || finish_valid) fail("reset did not cancel transaction");
        rst_n=1;
        prepare(1,-1,70);run_case();
        $display("SCENARIO_PASS bmp-watchdog-and-reset");
        $display("TEST_PASS");$finish;
    end
    initial begin #300000000;fail("global timeout");end
endmodule
`default_nettype wire
