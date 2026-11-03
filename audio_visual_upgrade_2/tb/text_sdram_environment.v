`timescale 1ns/1ps
`default_nettype none
// Real controller/device plus four competing line-fetch clients. The loader
// writes the unchanged complete font and independent layout fixture over the
// controller interface before the raster starts.
module text_sdram_environment(
    input wire clk,rst_n,hs,raster_on,
    input wire [7:0] contention_delay,
    output reg ready,
    input wire req,input wire [20:0] addr,input wire [15:0] len,
    output wire ack,done,valid,output wire [31:0] data
);
    reg clk_sft=0; initial begin #2.5;forever begin clk_sft=1;#5;clk_sft=0;#5;end end
    reg [31:0] font[0:964239],lrc[0:1111];
    wire [4:0] ca,cd,cv;
    wire bus_req,bus_ack,bus_done,bus_valid;
    wire [20:0] bus_addr;wire [15:0] bus_len;
    reg [4:0] img_req=0;
    integer remain[0:4],amount[0:4];
    integer k,upload,delay_left=0,lines=0;
    reg hs_d=1;
    wire [15:0] il0=amount[0],il1=amount[1],il3=amount[3],il4=amount[4];
    assign ack=ca[2];assign done=cd[2];assign valid=cv[2];
    px_arb5 arb(.clk_sdr(clk),.rst_sdr_n(rst_n),.c_req(img_req|{2'b00,req,2'b00}),
        .c_addr({21'h100A40,21'h0A8C00,addr,21'h0E1000,21'h000000}),
        .c_len({il4,il3,len,il1,il0}),.c_ack(ca),.c_done(cd),.c_valid(cv),
        .arb_req(bus_req),.arb_addr(bus_addr),.arb_len(bus_len),
        .arb_ack(bus_ack),.arb_done(bus_done),.arb_valid(bus_valid),.grant_cnt(),.contend_cnt());
    wire init_done,ref_vld,sbusy,sren,aren,awen;
    wire [31:0] srdata,awdata;wire [20:0] ara,awa;wire [3:0] adm;
    reg load_req=0;reg [20:0] load_addr=0;reg [15:0] load_len=0;
    wire load_ack,load_done,load_take;wire [31:0] load_data;
    integer load_pos=0,load_origin=0;
    reg load_font=0;
    assign load_data=load_font ? font[load_origin+load_pos] : lrc[load_origin+load_pos];
    always @(posedge clk) if(load_take) load_pos<=load_pos+1;
    sdram_arb memarb(.clk(clk),.rst_n(rst_n),.app_rd_en(aren),.app_rd_addr(ara),
        .app_wr_en(awen),.app_wr_addr(awa),.app_wr_dm(adm),.app_wr_din(awdata),
        .sdr_rd_en(sren),.sdr_rd_dout(srdata),.sdr_busy(sbusy),
        .sdr_init_done(init_done),.sdr_init_ref_vld(ref_vld),
        .px_req(bus_req),.px_addr(bus_addr),.px_len(bus_len),.px_ack(bus_ack),.px_done(bus_done),
        .px_data(data),.px_valid(bus_valid),.ctl_req(1'b0),.ctl_addr(21'd0),.ctl_len(16'd0),
        .ctl_ack(),.ctl_done(),.ctl_data(),.ctl_valid(),
        .ld_req(load_req),.ld_addr(load_addr),.ld_len(load_len),.ld_data(load_data),
        .ld_rd(load_take),.ld_ack(load_ack),.ld_done(load_done),.arb_busy(),.gnt());
    sdram_top phy(.Clk(clk),.Clk_sft(clk_sft),.Rst(!rst_n),
        .Sdr_init_done(init_done),.Sdr_init_ref_vld(ref_vld),.Sdr_busy(sbusy),
        .App_rd_en(aren),.App_rd_addr(ara),.App_wr_en(awen),.App_wr_addr(awa),
        .App_wr_dm(adm),.App_wr_din(awdata),.Sdr_rd_en(sren),.Sdr_rd_dout(srdata),
        .SDR_RAS_MON(),.SDR_CAS_MON(),.SDR_WE_MON());
    task write_chunk;
        input integer origin,words;
        input font_select;
        begin
            @(negedge clk);load_origin=origin;load_pos=0;load_font=font_select;
            load_addr=(font_select ? 21'h10BBB0 : 21'h10B300)+origin;
            load_len=words;load_req=1;
            wait(load_ack);@(negedge clk);load_req=0;
            wait(load_done);@(negedge clk);
        end
    endtask
    initial begin
        ready=0;
        for(k=0;k<5;k=k+1) begin remain[k]=0;amount[k]=0;end
        $readmemh("sim/typography_font.mem",font);$readmemh("sim/layout_five_lrc.mem",lrc);
        wait(rst_n);wait(init_done);
        for(upload=0;upload<964240;upload=upload+128)
            write_chunk(upload,(964240-upload>128)?128:964240-upload,1);
        for(upload=0;upload<1112;upload=upload+128)
            write_chunk(upload,(1112-upload>128)?128:1112-upload,0);
        ready=1;
    end
    always @(posedge clk) begin
        hs_d<=hs;
        if(rst_n && ready) begin
            for(k=0;k<5;k=k+1) if(k!=2) begin
                if(ca[k]) img_req[k]<=0;
                if(cd[k]) begin
                    remain[k]=remain[k]-amount[k];
                    amount[k]=remain[k]>128 ? 128 : remain[k];
                    if(remain[k]>0) img_req[k]<=1;
                end
            end
            if(raster_on && hs_d && !hs) begin
                for(k=0;k<5;k=k+1) if(k!=2 && remain[k]!=0) begin
                    $display("TEST_FAIL image client missed line %0d client %0d remain %0d",lines,k,remain[k]);$finish;
                end
                delay_left=contention_delay+1;lines=lines+1;
            end else if(delay_left>0) begin
                delay_left=delay_left-1;
                if(delay_left==0) for(k=0;k<5;k=k+1) if(k!=2) begin
                    remain[k]=(k==0 || k==3)?480:180;
                    amount[k]=128;img_req[k]<=1;
                end
            end
        end
    end
endmodule
`default_nettype wire
