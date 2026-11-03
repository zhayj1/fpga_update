`timescale 1ns/1ps
module tb_text_row_aa;
    reg clk=0; always #3.333 clk=~clk;
    reg rst_n=0,start=0,cancel=0,bank=0,small_sel=0;
    reg [15:0] fc=0,cnt=8;
    reg [4:0] grow=0;
    wire busy,done,we,req;
    wire [7:0] err,wd;
    wire [9:0] width;
    wire [10:0] wa;
    wire [20:0] addr;
    wire [15:0] len;
    reg ack=0,rdone=0,valid=0;
    reg [31:0] data=0;
    reg [31:0] font[0:964239],lrc[0:1111];
    reg [3:0] gold[0:6055];
    reg [7:0] widths[0:15];
    integer mode=0,bs=0,delay_count=0,rx=0,transactions=0,saved_len=0;
    reg [20:0] saved_addr;
    integer seen,base_gold,expected_width,ci,edge_x,cycles,maximum_cycles=0,i,j;
    reg checking=0;
    reg [31:0] saved_magic,saved_desc;
    text_row_aa #(.WD_MS(1),.CLK_HZ(100000)) dut(
        .clk_sdr(clk),.rst_sdr_n(rst_n),.start(start),.cancel(cancel),
        .bank(bank),.small_font(small_sel),.fc(fc),.cnt(cnt),.grow(grow),.played(24'd2500),
        .busy(busy),.done(done),.err(err),.width(width),.wr_en(we),.wr_addr(wa),.wr_data(wd),
        .px_req(req),.px_addr(addr),.px_len(len),.px_ack(ack),.px_done(rdone),.px_valid(valid),.px_data(data));
    always @(negedge clk) begin
        ack=0; valid=0; rdone=0;
        if(!rst_n) begin bs=0; transactions=0; end
        else case(bs)
        0: if(req && mode!=3) begin
            if(addr[1:0]!=0 || (len!=4 && len!=8)) begin $display("TEST_FAIL alignment"); $finish; end
            saved_addr=addr; saved_len=len; delay_count=2; bs=1;
        end
        1: begin
            if(!req || saved_addr!=addr) begin $display("TEST_FAIL unstable request"); $finish; end
            if(delay_count==0) begin ack=1; bs=2; delay_count=2; rx=0; transactions=transactions+1; end
            else delay_count=delay_count-1;
        end
        2: begin
            if(delay_count!=0) delay_count=delay_count-1;
            else begin
                if(saved_addr>=21'h10BBB0 && saved_addr<21'h10BBB0+964240) data=font[saved_addr-21'h10BBB0+rx];
                else if(saved_addr>=21'h10B300 && saved_addr<21'h10B300+1112) data=lrc[saved_addr-21'h10B300+rx];
                else begin $display("TEST_FAIL range %h",saved_addr); $finish; end
                valid=1; delay_count=1;
                if(rx==((mode==2 && transactions==3)?2:saved_len-1)) begin
                    if(mode==4) begin bs=3; delay_count=2; end
                    else begin rdone=1; bs=0; end
                end else rx=rx+1;
            end
        end
        3: if(delay_count==0) begin rdone=1; bs=0; end else delay_count=delay_count-1;
        endcase
    end
    always @(posedge clk) begin
        if(rst_n && checking && we) begin
            if(seen>=expected_width || wa!==({bank,10'd0}+seen) ||
               wd[3:0]!==gold[base_gold+seen] || wd[7:5]!==0 || wd[4]!== (ci<3)) begin
                $display("TEST_FAIL row small_sel=%0d y=%0d x=%0d addr=%0d data=%h gold=%h ci=%0d",small_sel,grow,seen,wa,wd,gold[base_gold+seen],ci); $finish;
            end
            seen=seen+1;
            if(seen==edge_x && ci<7) begin ci=ci+1; edge_x=edge_x+widths[(small_sel?8:0)+ci]; end
        end
    end
    task launch;
        begin
            @(negedge clk); start=1; seen=0; ci=0; edge_x=widths[small_sel?8:0];
            @(negedge clk); start=0;
        end
    endtask
    task finish_row;
        input [7:0] error_expected;
        begin
            cycles=0;
            while(!done && cycles<6000) begin @(posedge clk); #1; cycles=cycles+1; end
            if(!done || err!==error_expected || width!==(error_expected==0 ? expected_width : 0)) begin
                $display("TEST_FAIL completion mode=%0d done=%b err=%h width=%0d cycles=%0d",mode,done,err,width,cycles); $finish;
            end
            if(checking && seen!=expected_width) begin $display("TEST_FAIL incomplete pixels"); $finish; end
            if(cycles>maximum_cycles) maximum_cycles=cycles;
            @(negedge clk);
        end
    endtask
    initial begin
        $readmemh("sim/typography_font.mem",font);
        $readmemh("sim/typography_sample_lrc.mem",lrc);
        $readmemh("sim/typography_row_golden.mem",gold);
        $readmemh("sim/typography_sample_widths.mem",widths);
        repeat(4) @(negedge clk); rst_n=1;
        for(i=0;i<2;i=i+1) begin
            small_sel=i; expected_width=i==0?149:124;
            for(j=0;j<(i==0?24:20);j=j+1) begin
                grow=j; bank=j%2; base_gold=(i==0?0:3576)+j*expected_width;
                checking=1; launch; finish_row(0);
            end
        end
        $display("SCENARIO_PASS TYP-03-pixels"); checking=0;
        grow=0; small_sel=0; expected_width=149;
        saved_magic=font[0]; font[0]=0; launch; finish_row(8'h66); font[0]=saved_magic;
        saved_desc=lrc[136];lrc[136]=32'h0000FFFF;
        launch;finish_row(8'h66);
        lrc[136]=32'h0000A1A2;launch;finish_row(8'h66);
        lrc[136]=32'h0000F4A4;launch;finish_row(8'h66);
        lrc[136]=32'h0000FAA5;launch;finish_row(8'h66);
        lrc[136]=32'h0000B9A6;launch;finish_row(8'h66);
        lrc[136]=32'h0000C2A7;launch;finish_row(8'h66);
        lrc[136]=32'h0000BBA8;launch;finish_row(8'h66);
        lrc[136]=32'h0000F0A9;launch;finish_row(8'h66);
        lrc[136]=32'h0000A1AA;launch;finish_row(8'h66);
        lrc[136]=32'h0000FAD7;launch;finish_row(8'h66);
        lrc[136]=32'h00007F00;launch;finish_row(8'h66);
        lrc[136]=saved_desc;
        mode=2; transactions=0; launch; finish_row(8'h04); mode=0;
        cnt=25; launch; finish_row(8'h66);
        fc=487;cnt=2;launch;finish_row(8'h66);fc=0;cnt=8;
        grow=24; launch; finish_row(8'h66); grow=0;
        font[2]=964241; launch; finish_row(8'h66); font[2]=964240;
        $display("SCENARIO_PASS TYP-03-invalid");
        mode=3; launch; finish_row(8'h04); mode=0;
        launch; wait(bs==2); @(negedge clk); cancel=1;
        @(negedge clk); cancel=0; finish_row(8'h08);
        mode=4; checking=1; base_gold=0; launch; finish_row(0);
        checking=0; cnt=0; expected_width=0; launch; finish_row(0);
        rst_n=0; repeat(4) @(negedge clk); rst_n=1; cnt=8; expected_width=149;
        mode=0; checking=1; launch; finish_row(0);
        $display("SCENARIO_PASS TYP-03-recovery");
        $display("ROW_MAX_CYCLES %0d",maximum_cycles);
        $display("TEST_PASS"); $finish;
    end
    initial begin #10000000; $display("TEST_FAIL watchdog"); $finish; end
endmodule
