`timescale 1ns/1ps
`default_nettype none
module tb_full_font_load;
    reg clk=0,cs=0;always #10 clk=~clk;always #3.333 cs=~cs;
    reg rn=0,start=0;
    reg [20:0] base=21'h10BBB0;
    reg [19:0] capacity=1000528;
    reg [31:0] bytes=3856960;
    wire busy,done;wire [7:0] err;wire [31:0] nbytes;
    wire open,ready,want;reg obusy=0,valid=0,eof=0;reg [7:0] di=0;
    wire flush,we,full,cfg,finish,backdone;wire [7:0] fifo_di;
    wire [20:0] first;wire [19:0] words,endwords;wire [15:0] wpr;wire down;
    wire req;wire [20:0] addr;wire [15:0] len;wire [31:0] data;
    reg take=0,ack=0,wdone=0;
    reg [7:0] source[0:3856959];
    reg [31:0] golden[0:964239];
    integer src_n=3856960,src_pos=0,src_state=0,wait_n=0;
    integer bs=0,delay_n=0,taken=0,total=0,bursts=0,cycles=0,fd,read_bytes;
    reg [20:0] saved_addr;reg [15:0] saved_len;reg [31:0] first_data;
    reg [7:0] expected_error;
    integer expected_bytes=0,expected_words=0;
    reg [31:0] expected_word;
    font_load #(.EXTERNAL_BACKEND(1),.WD_MS(2)) dut(
        .clk(clk),.rst_n(rn),.start(start),.file_index(8'd136),.slot_base(base),.byte_len(bytes),
        .busy(busy),.done(done),.err(err),.nbytes(nbytes),.lo_open(open),.lo_open_index(),
        .lo_open_busy(obusy),.lo_rd_valid(valid),.lo_rd_data(di),.lo_rd_ready(ready),
        .lo_want(want),.lo_rd_eof(eof),.lo_rd_err(1'b0),.file_size(bytes),
        .clk_sdr(cs),.rst_sdr_n(rn),.ld_req(),.ld_addr(),.ld_len(),.ld_data(),
        .ld_rd(1'b0),.ld_ack(1'b0),.ld_done(1'b0),.fifo_full_ext(full),.backend_done_ext(backdone),
        .slot_words(capacity),.fifo_flush_ext(flush),.fifo_we_ext(we),.fifo_di_ext(fifo_di),
        .cfg_valid_ext(cfg),.cfg_first_ext(first),.cfg_words_ext(words),.cfg_wpr_ext(wpr),
        .cfg_down_ext(down),.finish_valid_ext(finish),.finish_words_ext(endwords));
    load_writeback backend(.clk(clk),.rst_n(rn),.clk_sdr(cs),.rst_sdr_n(rn),
        .flush(flush),.byte_we(we),.byte_data(fifo_di),.full(full),
        .cfg_valid(cfg),.cfg_first(first),.cfg_words(words),.cfg_wpr(wpr),.cfg_rows(1'b0),.cfg_down(down),
        .finish_valid(finish),.finish_words(endwords),.done(backdone),
        .ld_req(req),.ld_addr(addr),.ld_len(len),.ld_data(data),.ld_take(take),.ld_ack(ack),.ld_done(wdone));
    always @(posedge clk) begin
        if(!rn) begin src_state<=0;valid<=0;eof<=0;obusy<=0;src_pos<=0;end
        else begin
            eof<=0;
            case(src_state)
            0:if(open) begin src_state<=1;obusy<=1;wait_n<=5;src_pos<=0;end
            1:if(wait_n!=0) wait_n<=wait_n-1;else src_state<=2;
            2:begin
                if(src_pos>=src_n) begin
                    valid<=0;if(ready) begin eof<=1;obusy<=0;src_state<=0;end
                end else if(!valid) begin valid<=1;di<=source[src_pos];end
                else if(ready) begin
                    src_pos<=src_pos+1;
                    if(src_pos+1<src_n) di<=source[src_pos+1];else valid<=0;
                end
            end
            endcase
        end
    end
    always @(posedge cs) begin
        if(!rn) begin bs<=0;take<=0;ack<=0;wdone<=0;total<=0;bursts<=0;end
        else begin
            ack<=0;wdone<=0;
            case(bs)
            0:if(req) begin
                if(addr!==base+total || addr[1:0]!=0 || len==0 || len[1:0]!=0 ||
                   addr+len>base+expected_words) begin
                    $display("TEST_FAIL full load burst base=%h addr=%h total=%0d len=%0d",base,addr,total,len);$finish;end
                saved_addr<=addr;saved_len<=len;first_data<=data;taken<=0;
                delay_n<=(bursts%7==0)?120:7;bursts<=bursts+1;bs<=1;
            end
            1:begin
                if(!req || addr!==saved_addr || len!==saved_len || data!==first_data) begin
                    $display("TEST_FAIL full load unstable request");$finish;end
                if(delay_n!=0) delay_n<=delay_n-1;
                else begin ack<=1;take<=1;bs<=2;end
            end
            2:begin
                expected_word=0;
                if(total*4<src_n) expected_word[7:0]=source[total*4];
                if(total*4+1<src_n) expected_word[15:8]=source[total*4+1];
                if(total*4+2<src_n) expected_word[23:16]=source[total*4+2];
                if(total*4+3<src_n) expected_word[31:24]=source[total*4+3];
                if(data!==expected_word || (src_n==3856960 && data!==golden[total])) begin
                    $display("TEST_FAIL full load data word=%0d got=%h want=%h",total,data,expected_word);$finish;end
                if(taken!=0 && req) begin $display("TEST_FAIL late request");$finish;end
                total<=total+1;
                if(taken+1==saved_len) begin take<=0;wdone<=1;bs<=0;end
                else taken<=taken+1;
            end
            endcase
        end
    end
    task run_case;
        input [31:0] n;
        input integer actual;
        input [7:0] error;
        input integer written;
        begin
            @(negedge clk);rn=0;start=0;bytes=n;src_n=actual;
            expected_error=error;expected_bytes=written;expected_words=written/4;
            repeat(8) @(negedge clk);rn=1;
            repeat(8) @(negedge clk);start=1;@(negedge clk);start=0;cycles=0;
            while(!done && cycles<6000000) begin @(posedge clk);#1;cycles=cycles+1;end
            if(!done || err!==error || nbytes!==written || total!=expected_words) begin
                $display("TEST_FAIL full load completion bytes=%0d err=%h/%h nbytes=%0d/%0d words=%0d cycles=%0d",n,err,error,nbytes,written,total,cycles);$finish;end
            if(error==0 && src_pos!=actual) begin $display("TEST_FAIL full load source drain");$finish;end
            repeat(8) @(negedge clk);
        end
    endtask
    initial begin
        fd=$fopen("output/typography_full_20261030/sd_card/FONT.HZK","rb");
        if(!fd) begin $display("TEST_FAIL full font missing");$finish;end
        read_bytes=$fread(source,fd);$fclose(fd);
        if(read_bytes!=3856960) begin $display("TEST_FAIL full file length");$finish;end
        $readmemh("sim/typography_font.mem",golden);
        run_case(3856960,3856960,0,3856960);
        $display("FULL_LOAD_WORDS %0d BURSTS %0d CYCLES %0d",total,bursts,cycles);
        $display("SCENARIO_PASS FULL-03-real-file-over-2MiB");
        run_case(17,17,0,32);
        run_case(200,64,8'h03,64);
        capacity=964236;run_case(3856960,0,8'h02,0);capacity=1000528;
        base=21'h1ffff0;run_case(128,0,8'h02,0);base=21'h10bbb0;
        run_case(32'hffffffff,0,8'h02,0);run_case(0,0,8'h02,0);
        run_case(64,64,0,64);
        $display("SCENARIO_PASS FULL-03-padding-bounds-short-file-recovery");
        $display("TEST_PASS");$finish;
    end
    initial begin #130000000;$display("TEST_FAIL full load watchdog");$finish;end
endmodule
`default_nettype wire
