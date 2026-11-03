`timescale 1ns/1ps
`default_nettype none
module tb_bmp_downscale #(
    parameter integer EXTERNAL = 1,
    parameter integer SMALL = 0
);
    localparam integer BW = SMALL ? 8 : 640;
    localparam integer BH = SMALL ? 6 : 480;
    localparam integer CW = SMALL ? 5 : 240;
    reg clk=0, sdr=0, rst_n=0, start=0, cover=0;
    always #10 clk=~clk;
    always #5 sdr=~sdr;
    wire busy,done,lo_open,lo_ready,lo_want,flush,we,cfg_valid,finish_valid;
    wire [7:0] err,lo_index,di;
    wire [15:0] img_w,img_h,cfg_wpr;
    wire [20:0] cfg_first;
    wire [18:0] cfg_words,finish_words;
    wire cfg_down,ld_req;
    wire [20:0] ld_addr;
    wire [15:0] ld_len;
    wire [31:0] ld_data;
    reg ld_take=0,ld_ack=0,ld_done=0,complete_pending=0;
    reg [20:0] base=21'h1000;
    reg [18:0] slot_words=19'd230400;
    reg [31:0] file_size=0;
    reg valid=0,eof=0,read_error=0,full=0,backend_done=0;
    reg [7:0] data=0,header[0:127];
    integer width,height,abs_h,offset,source_stride,dest_stride,source_bytes,dw,dh;
    integer src_pos=0,out_pos=0,active=0,cycle=0,mode=0,serial=0;
    integer configs=0,finishes=0,opens=0,backend_delay=0;
    integer deliver_bytes=0,expected_error=0,check_pixels=1,expected_pixels=0;
    integer i,j,k,r,c,limit,word_count=0,burst_left=0,burst_addr=0,sdr_cycle=0;
    integer expected_addr,burst_start=0,ack_wait=0,full_cycles=0;
    reg [31:0] expected_word;
    reg [31:0] exp_span,exp_first,exp_wpr;
    reg [7:0] expected_byte;
    reg exp_down;

    bmp_load #(.EXTERNAL_BACKEND(EXTERNAL),.DOWNSCALE(1),
        .BG_W(BW),.BG_H(BH),.COVER_W(CW),.COVER_H(CW)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),.target_cover(cover),
        .file_index(8'd11),.slot_base(base),.busy(busy),.done(done),.err(err),
        .img_w(img_w),.img_h(img_h),.lo_open(lo_open),.lo_open_index(lo_index),
        .lo_open_busy(1'b0),.lo_rd_valid(valid),.lo_rd_data(data),
        .lo_rd_ready(lo_ready),.lo_want(lo_want),.lo_rd_eof(eof),
        .lo_rd_err(read_error),.file_size(file_size),.wd_max(32'd10000),
        .clk_sdr(sdr),.rst_sdr_n(rst_n),.ld_req(ld_req),.ld_addr(ld_addr),
        .ld_len(ld_len),.ld_data(ld_data),.ld_rd(ld_take),.ld_ack(ld_ack),.ld_done(ld_done),
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
                why,serial,width,height,mode,src_pos,out_pos,$time);$finish;
        end
    endtask
    // Pattern is defined in logical top-down coordinates. Include exact magenta.
    function [7:0] pixel;
        input integer y,x,bgr;
        begin
            if((x+y)%11==0) pixel=(bgr==1)?0:255;
            else pixel=(y*7+x*13+bgr*31)&255;
        end
    endfunction
    // Independent division-based reference, not the RTL phase recurrence.
    function [7:0] golden_byte;
        input integer pos;
        integer row,col,logical_y,sx,sy;
        begin
            row=pos/dest_stride;col=pos%dest_stride;
            logical_y=(height>0)?dh-1-row:row;
            sx=((2*(col/3)+1)*width)/(2*dw);
            sy=((2*logical_y+1)*abs_h)/(2*dh);
            golden_byte=(col<dw*3)?pixel(sy,sx,2-col%3):0;
        end
    endfunction
    task put32;
        input integer at;
        input [31:0] value;
        begin
            header[at]=value[7:0];header[at+1]=value[15:8];
            header[at+2]=value[23:16];header[at+3]=value[31:24];
        end
    endtask
    always @(negedge clk) begin
        cycle=cycle+1;valid=0;eof=0;read_error=0;backend_done=0;
        full=(cycle%17>=4 && cycle%17<=6);
        if(rst_n) begin
            if(backend_delay>0) begin
                backend_delay=backend_delay-1;
                if(backend_delay==0) backend_done=1;
            end
            if(active) begin
                if(mode==1) begin end
                else if(mode==2 && src_pos>=offset+7) begin read_error=1;active=0;end
                else if(src_pos>=deliver_bytes) begin eof=1;active=0;end
                else if(cycle%13!=0) begin
                    valid=1;
                    if(src_pos<54) data=header[src_pos];
                    else if(src_pos<offset) data=8'hc7;
                    else begin
                        r=(src_pos-offset)/source_stride;c=(src_pos-offset)%source_stride;
                        data=(c<width*3 && r<abs_h)?
                            pixel((height>0)?abs_h-1-r:r,c/3,c%3):8'h5a;
                    end
                end
            end
        end else begin active=0;backend_delay=0;full=0;end
    end
    always @(posedge clk) if(rst_n) begin
        if(lo_open) begin
            if(lo_index!==8'd11) fail("wrong file index");
            active=1;src_pos=0;opens=opens+1;
        end
        if(valid && lo_ready) src_pos=src_pos+1;
        if(EXTERNAL && full) full_cycles=full_cycles+1;
        if(we) begin
            if((EXTERNAL && full) || !check_pixels || out_pos>=expected_pixels)
                fail("unexpected FIFO byte");
            expected_byte=golden_byte(out_pos);
            if(di!==expected_byte) begin
                $display("byte actual=%02h expected=%02h at=%0d",di,expected_byte,out_pos);
                fail("RGB/sample/orientation/padding mismatch");
            end
            out_pos=out_pos+1;
        end
        if(cfg_valid) begin
            configs=configs+1;
            if(expected_error==0 && (cfg_first!==exp_first[20:0] || cfg_wpr!==exp_wpr[15:0] ||
                cfg_words!==exp_span[18:0] || cfg_down!==exp_down)) fail("destination configuration");
        end
        if(finish_valid) begin
            finishes=finishes+1;
            if(finish_words!==(out_pos/4)) fail("finish count");
            backend_delay=9;
        end
    end
    // Real writeback/FIFO in EXTERNAL=0. SDRAM consumer inserts independent
    // ACK and data stalls; checks every destination address and packed word.
    always @(negedge sdr) begin
        sdr_cycle=sdr_cycle+1;ld_ack=0;ld_done=complete_pending;complete_pending=0;ld_take=0;
        if(!rst_n) begin burst_left=0;ack_wait=0;end
        else if(!EXTERNAL) begin
            if(burst_left>0) ld_take=(sdr_cycle%7!=0);
            else if(ack_wait>0) ack_wait=ack_wait-1;
            else if(ld_req) begin
                if(ld_len==0 || ld_len%4!=0 || ld_len>128) fail("invalid burst length");
                if((ld_addr-base)%exp_wpr+ld_len>exp_wpr) fail("burst crossed target row");
                burst_left=ld_len;burst_addr=ld_addr;burst_start=1;ld_ack=1;
            end
        end
    end
    always @(posedge sdr) if(rst_n && !EXTERNAL && ld_take) begin
        for(k=0;k<4;k=k+1) expected_word[k*8 +:8]=golden_byte(word_count*4+k);
        expected_addr=base+(height>0 ? dh-1-word_count/exp_wpr : word_count/exp_wpr)*exp_wpr+
                      word_count%exp_wpr;
        if(burst_addr!=expected_addr || ld_data!==expected_word)
            fail("writeback destination address/data mismatch");
        burst_addr=burst_addr+1;word_count=word_count+1;burst_left=burst_left-1;
        if(burst_left==0) begin complete_pending=1;ack_wait=3;end
    end
    task prepare;
        input integer w,h,off,is_cover;
        begin
            @(negedge clk);#1;
            if(busy) fail("new case while busy");
            serial=serial+1;width=w;height=h;abs_h=(h<0)?-h:h;offset=off;cover=is_cover;
            dw=is_cover?CW:BW;dh=is_cover?CW:BH;
            source_stride=((w*3+3)/4)*4;dest_stride=((dw*3+15)/16)*16;
            source_bytes=off+source_stride*abs_h;file_size=source_bytes;deliver_bytes=source_bytes;
            expected_error=0;mode=0;check_pixels=1;expected_pixels=dest_stride*dh;
            base=21'h1000;slot_words=19'd230400;
            exp_wpr=dest_stride/4;exp_span=exp_wpr*dh;exp_down=(height>0);
            exp_first=(height>0)?base+exp_span-exp_wpr:base;
            src_pos=0;out_pos=0;opens=0;configs=0;finishes=0;word_count=0;
            for(i=0;i<128;i=i+1) header[i]=0;
            header[0]=8'h42;header[1]=8'h4d;
            put32(2,source_bytes);put32(10,off);put32(14,40);
            put32(18,w);put32(22,h);header[26]=1;header[28]=24;
        end
    endtask
    task rejected;
        input integer code;
        begin expected_error=code;expected_pixels=0;check_pixels=0;deliver_bytes=128;end
    endtask
    task run_case;
        begin
            exp_wpr=dest_stride/4;exp_span=exp_wpr*dh;exp_down=(height>0);
            exp_first=(height>0)?base+exp_span-exp_wpr:base;
            @(negedge clk);#1;start=1;
            @(negedge clk);#1;start=0;cover=!cover; // verify start-time latch
            limit=0;
            while(done!==1 && limit<90000000) begin @(negedge clk);#1;limit=limit+1;end
            if(limit==90000000) fail("completion timeout");
            if(err!==expected_error[7:0] || busy!==0 || opens!=1 || configs!=1 || finishes!=1) begin
                $display("status actual=%02h expected=%02h cfg=%0d finish=%0d",err,expected_error,configs,finishes);
                fail("completion status");
            end
            if(expected_error==0 && (img_w!==dw || img_h!==dh || out_pos!=expected_pixels))
                fail("normalized geometry/count");
            if(!EXTERNAL && expected_error==0 && word_count!=expected_pixels/4) fail("missing SDRAM words");
            repeat(3) begin @(negedge clk);#1;if(done) fail("done not pulse");end
            if(active && mode!=1) fail("stream not drained");
            active=0;
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);#1;rst_n=1;
        prepare(BW,BH,54,0);run_case();prepare(BW,-BH,70,0);run_case();
        prepare(CW,CW,54,1);run_case();prepare(CW,-CW,70,1);run_case();
        $display("SCENARIO_PASS downscale-identity-key-and-backpressure");
        prepare(BW*2,BH*2,54,0);run_case();prepare(BW*2,-BH*2,70,0);run_case();
        prepare(BW+4,BH+3,70,0);run_case();prepare(BW+4,-BH-3,54,0);run_case();
        prepare(CW+1,CW+1,54,1);run_case();prepare(CW+1,-CW-1,70,1);run_case();
        prepare(CW*3+1,CW*3+1,54,1);run_case();
        if(!SMALL) begin prepare(800,600,54,0);run_case();prepare(1000,-1000,70,1);run_case();end
        else for(j=6;j<=31;j=j+1) begin prepare(j,j,54,1);run_case();prepare(j,-j,70,1);run_case();end
        $display("SCENARIO_PASS downscale-rational-and-orientation-matrix");
        if(EXTERNAL) begin
            prepare(4096,3072,54,0);run_case();
            prepare(4096,-4096,54,1);deliver_bytes=54+source_stride*3+7;expected_error=3;run_case();
            prepare(BW,BH,54,0);base=2097152-(dest_stride/4)*dh;run_case();
            prepare(BW,-BH,70,0);file_size=source_bytes+31;deliver_bytes=file_size;run_case();
            $display("SCENARIO_PASS downscale-source-limit-and-destination-bounds");
            prepare(BW-4,BH-3,54,0);rejected(8);run_case();
            prepare(CW-1,CW-1,54,1);rejected(8);run_case();
            prepare(BW+4,BH,54,0);rejected(7);run_case();
            prepare(CW+1,CW+2,54,1);rejected(7);run_case();
            prepare(BW,BH,54,0);put32(18,4097);rejected(2);run_case();
            prepare(BW,BH,54,0);put32(22,4097);rejected(6);run_case();
            prepare(BW,BH,54,0);put32(22,32'h80000000);rejected(6);run_case();
            prepare(BW,BH,54,0);file_size=67108865;rejected(9);run_case();
            prepare(BW,BH,54,0);header[28]=32;rejected(5);run_case();
            prepare(BW,BH,54,0);base=21'h1ffffc;rejected(2);run_case();
            prepare(BW,BH,54,0);slot_words=dest_stride*dh/4-1;rejected(2);run_case();
            $display("SCENARIO_PASS downscale-reject-no-upscale-ratio-and-overflow");
            prepare(BW+4,-BH-3,54,0);deliver_bytes=54+source_stride+7;expected_error=3;run_case();
            prepare(BW+4,-BH-3,54,0);file_size=61;expected_error=3;run_case();
            prepare(BW,BH,54,0);mode=2;expected_error=4;run_case();
            prepare(BW,BH,54,0);mode=1;expected_error=4;run_case();
            prepare(BW,-BH,54,0);run_case();
            $display("SCENARIO_PASS downscale-truncation-error-watchdog-recovery");
            prepare(BW*2,BH*2,54,0);
            @(negedge clk);#1;start=1;@(negedge clk);#1;start=0;
            repeat(100) @(negedge clk);#1;rst_n=0;
            repeat(5) @(negedge clk);#1;
            if(busy || done || we || cfg_valid || finish_valid) fail("reset cancellation");
            rst_n=1;prepare(CW,-CW,54,1);run_case();
            $display("SCENARIO_PASS downscale-reset-recovery");
        end else $display("SCENARIO_PASS downscale-real-fifo-writeback-addresses");
        $display("TEST_PASS");$finish;
    end
    initial begin #(64'd5000000000);fail("global timeout");end
endmodule
`default_nettype wire
