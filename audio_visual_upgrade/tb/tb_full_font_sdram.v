`timescale 1ns/1ps
`default_nettype none
module tb_full_font_sdram;
    reg clk=0; always #5 clk=~clk;
    reg clk_sft=0;initial begin #2.5;forever begin clk_sft=1;#5;clk_sft=0;#5;end end
    reg rn=0,start=0,small_sel=0;
    reg [4:0] row=0;
    reg [15:0] count=1,first=0;
    wire done,we,req; wire [7:0] err,wd;
    wire [9:0] width; wire [10:0] wa;
    wire [20:0] addr; wire [15:0] len;
    wire [4:0] ca,cd,cv;
    wire bus_req;wire [20:0] bus_addr;wire [15:0] bus_len;
    wire ack,rdone,valid;wire [31:0] data;
    reg [31:0] font[0:964239],lrc[0:1111];
    reg [15:0] codes[0:7539];reg [7:0] widths[0:15079];
    reg [127:0] gold[0:15079];
    integer row_test,kind_test,chosen_code;
    integer i,j,k,ci,seen=0,cycles=0,max_cycles=0,expected_width=0;
    integer bs=0,delay_n=0,rx=0,setup_delay=2,saved_len=0,stress=0;
    integer remain[0:4],img_len[0:4],img_words=0;
    reg [4:0] img_req=0;
    reg [20:0] saved_addr;
    reg [127:0] expected_row;
    reg checking=0;
    text_row_aa #(.CLK_HZ(100000000)) dut(.clk_sdr(clk),.rst_sdr_n(rn),.start(start),.cancel(1'b0),
        .bank(1'b0),.small_font(small_sel),.fc(first),.cnt(count),.grow(row),.played(24'hffffff),
        .busy(),.done(done),.err(err),.width(width),.wr_en(we),.wr_addr(wa),.wr_data(wd),
        .px_req(req),.px_addr(addr),.px_len(len),.px_ack(ca[2]),.px_done(cd[2]),
        .px_valid(cv[2]),.px_data(data));
    wire [15:0] il0=img_len[0],il1=img_len[1],il3=img_len[3],il4=img_len[4];
    wire [79:0] all_len={il4,il3,len,il1,il0};
    px_arb5 arb(.clk_sdr(clk),.rst_sdr_n(rn),.c_req(img_req|{2'b00,req,2'b00}),
        .c_addr({21'h100A40,21'h0A8C00,addr,21'h0E1000,21'h000000}),
        .c_len(all_len),.c_ack(ca),.c_done(cd),.c_valid(cv),
        .arb_req(bus_req),.arb_addr(bus_addr),.arb_len(bus_len),
        .arb_ack(ack),.arb_done(rdone),.arb_valid(valid),.grant_cnt(),.contend_cnt());
    wire init_done,ref_vld,sbusy,sren,aren,awen;
    wire [31:0] srdata,awdata;wire [20:0] ara,awa;wire [3:0] adm;
    reg load_req=0;reg [20:0] load_addr=0;reg [15:0] load_len=0;
    wire load_ack,load_done,load_take;wire [31:0] load_data;
    integer load_pos=0,load_origin=0,upload=0;
    reg load_font=0;
    assign load_data=load_font ? font[load_origin+load_pos] : lrc[load_origin+load_pos];
    always @(posedge clk) if(load_take) load_pos<=load_pos+1;
    sdram_arb memarb(.clk(clk),.rst_n(rn),.app_rd_en(aren),.app_rd_addr(ara),
        .app_wr_en(awen),.app_wr_addr(awa),.app_wr_dm(adm),.app_wr_din(awdata),
        .sdr_rd_en(sren),.sdr_rd_dout(srdata),.sdr_busy(sbusy),
        .sdr_init_done(init_done),.sdr_init_ref_vld(ref_vld),
        .px_req(bus_req),.px_addr(bus_addr),.px_len(bus_len),.px_ack(ack),.px_done(rdone),
        .px_data(data),.px_valid(valid),.ctl_req(1'b0),.ctl_addr(21'd0),.ctl_len(16'd0),
        .ctl_ack(),.ctl_done(),.ctl_data(),.ctl_valid(),
        .ld_req(load_req),.ld_addr(load_addr),.ld_len(load_len),.ld_data(load_data),
        .ld_rd(load_take),.ld_ack(load_ack),.ld_done(load_done),.arb_busy(),.gnt());
    sdram_top phy(.Clk(clk),.Clk_sft(clk_sft),.Rst(!rn),
        .Sdr_init_done(init_done),.Sdr_init_ref_vld(ref_vld),.Sdr_busy(sbusy),
        .App_rd_en(aren),.App_rd_addr(ara),.App_wr_en(awen),.App_wr_addr(awa),
        .App_wr_dm(adm),.App_wr_din(awdata),.Sdr_rd_en(sren),.Sdr_rd_dout(srdata),
        .SDR_RAS_MON(),.SDR_CAS_MON(),.SDR_WE_MON());
    task write_chunk;
        input integer origin,amount;
        input font_select;
        begin
            @(negedge clk);load_origin=origin;load_pos=0;load_font=font_select;
            load_addr=(font_select ? 21'h10BBB0 : 21'h10B300)+origin;
            load_len=amount;load_req=1;
            wait(load_ack);@(negedge clk);load_req=0;
            wait(load_done);@(negedge clk);
        end
    endtask
    always @(posedge clk) if(rn) begin
        for(k=0;k<5;k=k+1) if(k!=2) begin
            if(ca[k]) img_req[k]<=0;
            if(cd[k]) begin
                remain[k]=remain[k]-img_len[k];img_words=img_words+img_len[k];
                img_len[k]=remain[k]>128 ? 128 : remain[k];
                if(remain[k]>0) img_req[k]<=1;
            end
        end
        if(checking && we) begin
            if(seen>=expected_width || wa!==seen || wd[7:4]!==4'b0001 ||
                wd[3:0]!==expected_row[127-4*(seen%(expected_width/count)) -:4]) begin
                $display("TEST_FAIL full glyph=%0d small=%0d row=%0d pixel=%0d data=%h",ci,small_sel,row,seen,wd);$finish;end
            seen=seen+1;
        end
    end
    function [127:0] reference_row;
        input integer glyph_no,row_no,small_no;
        integer idx,at,x,byte_at;
        reg [31:0] word_value;
        reg [127:0] result;
        begin
            idx=codes[glyph_no][15:8]==0 ? 8178+codes[glyph_no][7:0]-32 :
                (codes[glyph_no][15:8]-161)*94+codes[glyph_no][7:0]-161;
            at=(font[4+idx]&32'h3ffff)*16+(small_no ? 288+10*row_no : 12*row_no);
            result=0;
            for(x=0;x<widths[2*glyph_no+small_no];x=x+1) begin
                byte_at=at+x/2;word_value=font[byte_at/4];
                result[127-4*x -:4]=(word_value>>(8*(byte_at%4)+4*(1-x%2)))&15;
            end
            reference_row=result;
        end
    endfunction
    task run_row;
        begin
            @(negedge clk);seen=0;start=1;checking=1;
            @(negedge clk);start=0;cycles=0;
            while(!done && cycles<3200) begin @(posedge clk);#1;cycles=cycles+1;end
            if(!done || err!=0 || width!=expected_width || seen!=expected_width) begin
                $display("REAL_HEADER %h %h %h %h",dut.word0,dut.word1,dut.word2,dut.word3);
                $display("TEST_FAIL full completion glyph=%0d small=%0d row=%0d err=%h width=%0d expected=%0d seen=%0d cycles=%0d",ci,small_sel,row,err,width,expected_width,seen,cycles);$finish;end
            if(cycles>max_cycles) max_cycles=cycles;
            @(negedge clk);checking=0;
        end
    endtask
    initial begin
        $readmemh("sim/typography_font.mem",font);$readmemh("sim/full_font_codes.mem",codes);
        $readmemh("sim/full_font_widths.mem",widths);$readmemh("sim/full_font_rows.mem",gold);
        for(i=0;i<1112;i=i+1) lrc[i]=0;
        for(i=0;i<5;i=i+1) begin remain[i]=0;img_len[i]=0;end
        repeat(5) @(negedge clk);rn=1;wait(init_done);
        for(upload=0;upload<964240;upload=upload+128)
            write_chunk(upload,(964240-upload>128)?128:964240-upload,1);
        $display("REAL_SDRAM_FULL_FONT_UPLOADED");
        for(ci=0;ci<7540;ci=ci+1) begin
            lrc[136]={16'd0,codes[ci][7:0],codes[ci][15:8]};
            write_chunk(136,4,0);
            for(j=0;j<2;j=j+1) begin
                small_sel=j;row=ci%(j==0?24:20);expected_row=gold[2*ci+j];
                expected_width=widths[2*ci+j];run_row;
            end
        end
        // First and final physical glyph, all rows; final legal LRC record.
        for(kind_test=0;kind_test<2;kind_test=kind_test+1) begin
            ci=kind_test==0?0:7539;first=487;count=1;
            lrc[1110]={16'd0,codes[ci][7:0],codes[ci][15:8]};
            write_chunk(1108,4,0);
            for(j=0;j<2;j=j+1) begin
                small_sel=j;expected_width=widths[2*ci+j];
                for(row_test=0;row_test<(j==0?24:20);row_test=row_test+1) begin
                    row=row_test;expected_row=reference_row(ci,row,j);run_row;
                end
            end
        end
        $display("SCENARIO_PASS FULL-04-real-sdram-all-glyphs-100MHz");
        // Saturate four image clients with two full backgrounds and covers.
        // 19 lyric characters and 24 title characters both must meet a line.
        for(kind_test=0;kind_test<3;kind_test=kind_test+1) begin
            chosen_code=kind_test==0 ? 16'hD7B7 : kind_test==1 ? 16'h0025 : 16'hA1A3;
            for(i=0;i<7540;i=i+1) if(codes[i]==chosen_code) ci=i;
            first=kind_test%2;
            for(i=0;i<25;i=i+1) lrc[136+2*i]={16'd0,codes[ci][7:0],codes[ci][15:8]};
            write_chunk(136,52,0);
            for(j=0;j<3;j=j+1) begin
                count=j==0?19:24;small_sel=j==2;
                expected_width=count*widths[2*ci+small_sel];stress=1;setup_delay=24;
                for(row_test=0;row_test<(small_sel?20:24);row_test=row_test+1) begin
                    row=row_test;expected_row=reference_row(ci,row,small_sel);img_words=0;
                    @(negedge clk);
                    for(i=0;i<5;i=i+1) if(i!=2) begin
                        remain[i]=(i==0 || i==3)?480:180;img_len[i]=128;img_req[i]=1;
                    end
                    run_row;
                    if(img_words!=1320) begin $display("TEST_FAIL image clients starved %0d",img_words);$finish;end
                end
            end
        end
        $display("SCENARIO_PASS FULL-04-real-sdram-contention-deadline");
        $display("FULL_ROW_MAX_CYCLES %0d",max_cycles);
        $display("TEST_PASS");$finish;
    end
    initial begin #300000000;$display("TEST_FAIL full rows watchdog");$finish;end
endmodule
`default_nettype wire
