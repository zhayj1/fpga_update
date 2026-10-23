`timescale 1ns/1ps
`default_nettype none
module tb_fat32_sessions;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, lo_start=0, hi_start=0, lo_want=1, hi_want=1, urgent=1;
    reg [31:0] ls=0, hs=0;
    reg [3:0] shift=0;
    reg random_ready=0;
    reg [15:0] random_bits=16'hace1;
    wire lb,hb,ld,hd,lv,hv,sreq,sready,creq,idle,stall;
    wire [3:0] le,he;
    wire [7:0] ldata,hdata;
    wire [31:0] lba,cc;
    wire [1:0] owner;
    reg lr=1,hr=1,sbusy=0,sv=0,sdone=0,cbusy=0,cdone=0;
    reg [7:0] sdata=0;
    reg [3:0] serr=0,cerr=0;
    reg [31:0] cn=0;
    integer lc=0,hc=0,ldc=0,hdc=0,cycles=0,requests=0;
    integer pos=0,phase=0,delay_c=0,chain_fault=0,sector_fault=0;
    reg hang=0;
    reg [31:0] current_lba;
    reg [1:0] current_owner;
    fat32_sessions #(.CLK_HZ(1000000),.WATCHDOG_MS(2),.LO_STALL_MS(1)) dut(
        .clk(clk),.rst_n(rst_n),.lo_start(lo_start),.lo_cluster(32'd2),.lo_size(ls),
        .hi_start(hi_start),.hi_cluster(32'd3),.hi_size(hs),
        .lo_want(lo_want),.hi_want(hi_want),.hi_refill(urgent),
        .lo_busy(lb),.hi_busy(hb),.lo_done(ld),.hi_done(hd),.lo_err(le),.hi_err(he),
        .lo_valid(lv),.hi_valid(hv),.lo_data(ldata),.hi_data(hdata),.lo_ready(lr),.hi_ready(hr),
        .data_lba(32'd100),.total_clusters(32'd1000),.spc_shift(shift),
        .sec_req(sreq),.sec_lba(lba),.sec_busy(sbusy),.sec_valid(sv),.sec_data(sdata),
        .sec_done(sdone),.sec_err(serr),.sec_ready(sready),
        .chain_req(creq),.chain_cluster(cc),.chain_busy(cbusy),.chain_done(cdone),
        .chain_err(cerr),.chain_next(cn),.owner(owner),.safe_idle(idle),.lo_stall(stall)
    );
    function [7:0] pattern;
        input integer sector, byte_pos;
        begin pattern=(sector ^ 8'ha5)+byte_pos; end
    endfunction
    function [31:0] expected_lba;
        input integer first, byte_number;
        integer sectors_per_cluster, file_sector, current_cluster;
        begin
            sectors_per_cluster=1<<shift;
            file_sector=byte_number/512;
            current_cluster=first+5*(file_sector/sectors_per_cluster);
            expected_lba=100+(current_cluster-2)*sectors_per_cluster+
                file_sector%sectors_per_cluster;
        end
    endfunction
    task fail; input [600:0] msg; begin $display("TEST_FAIL %0s",msg); $finish; end endtask
    // Byte and FAT services are independent of the implementation state machine.
    always @(negedge clk) begin
        sv=0; sdone=0; cdone=0;
        if(!rst_n) begin sbusy=0; cbusy=0; pos=0; phase=0; delay_c=0; end
        else begin
            if(random_ready) begin
                random_bits={random_bits[14:0],random_bits[15]^random_bits[13]^random_bits[12]^random_bits[10]};
                lr=random_bits[0]; hr=random_bits[3];
            end
            if(sreq) begin
                if(sbusy || cbusy) fail("overlapping transaction");
                sbusy=1; current_lba=lba; current_owner=owner; pos=0; phase=0; requests=requests+1;
            end else if(sbusy && !hang) begin
                if(owner!=current_owner) fail("owner changed with SD in flight");
                phase=phase+1;
                if(phase%3==0) begin
                    if(pos<512) begin
                        if(!sready) fail("sector mailbox did not reserve capacity");
                        sv=1; sdata=pattern(current_lba,pos); pos=pos+1;
                    end else begin sbusy=0; sdone=1; serr=sector_fault; end
                end
            end
            if(creq) begin
                if(sbusy || cbusy) fail("overlapping FAT transaction");
                cbusy=1; delay_c=8; current_owner=owner;
                cn=chain_fault==1 ? 32'h0ffffff8 : chain_fault==2 ? 32'h0ffffff7 :
                   chain_fault==3 ? 32'd1 : chain_fault==4 ? 32'd1002 : cc+5;
                cerr=chain_fault==5 ? 4'd1 : 4'd0;
            end else if(cbusy) begin
                if(owner!=current_owner) fail("owner changed with FAT in flight");
                delay_c=delay_c-1;
                if(delay_c==0) begin cbusy=0; cdone=1; end
            end
        end
    end
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        if(lv && lr) begin
            if(ldata!==pattern(expected_lba(2,lc),lc%512)) fail("low stream byte/owner mismatch");
            lc=lc+1;
        end
        if(hv && hr) begin
            if(hdata!==pattern(expected_lba(3,hc),hc%512)) fail("audio stream byte/owner mismatch");
            hc=hc+1;
        end
        if(ld) ldc=ldc+1;
        if(hd) hdc=hdc+1;
        if(cycles>2000000) fail("bounded test timeout");
    end
    task reset_case;
        begin
            @(negedge clk); rst_n=0; lo_start=0; hi_start=0;
            repeat(4) @(negedge clk);
            lc=0; hc=0; ldc=0; hdc=0; requests=0; ls=0; hs=0;
            shift=0; random_ready=0; random_bits=16'hace1;
            lr=1; hr=1; urgent=1; chain_fault=0; sector_fault=0; hang=0;
            rst_n=1; repeat(2) @(negedge clk);
        end
    endtask
    task open_both;
        input integer low_size,high_size;
        begin
            @(negedge clk); ls=low_size; hs=high_size; lo_start=1; hi_start=1;
            @(negedge clk); lo_start=0; hi_start=0;
        end
    endtask
    integer k;
    initial begin
        reset_case; urgent=0; open_both(1100,800);
        wait(ldc==1 && hdc==1);
        if(lc!=1100 || hc!=800 || le!=0 || he!=0) fail("fragmented/partial file lengths");
        $display("SCENARIO_PASS FS01");
        reset_case; lr=0; open_both(600,900);
        wait(hdc==1); if(lc!=0 || !lb || hc!=900) fail("blocked material blocked audio");
        lr=1; wait(ldc==1); if(lc!=600) fail("material mailbox lost bytes");
        $display("SCENARIO_PASS FS02");
        reset_case; open_both(512,0); wait(lc==511);
        @(negedge clk); lr=0; repeat(20) @(negedge clk);
        if(!lb || ldc!=0) fail("EOF before final output byte consumed");
        hs=100; hi_start=1; @(negedge clk); hi_start=0;
        wait(hdc==2); if(hc!=100 || lc!=511) fail("held last byte changed owner");
        lr=1; wait(ldc==1); if(lc!=512) fail("held last byte missing");
        $display("SCENARIO_PASS FS03");
        for(k=1;k<=5;k=k+1) begin
            reset_case; chain_fault=k; open_both(600,100);
            wait(ldc==1 && hdc==1);
            if(le!=(k==5 ? 2 : 3) || he!=0 || lc!=512 || hc!=100) fail("FAT error isolation");
        end
        $display("SCENARIO_PASS FS04");
        reset_case; sector_fault=3; open_both(100,0); wait(ldc==1);
        if(le!=5 || lc!=0) fail("CRC error published bad sector");
        sector_fault=0; lc=0; ls=100; @(negedge clk); lo_start=1;
        @(negedge clk); lo_start=0; wait(ldc==2);
        if(le!=0 || lc!=100) fail("CRC recovery reopen");
        $display("SCENARIO_PASS FS05");
        reset_case; hang=1; open_both(100,100); wait(sbusy);
        repeat(2100) @(negedge clk);
        if(!sbusy || owner!=current_owner || requests!=1) fail("watchdog released live response");
        hang=0; wait(ldc==1 && hdc==1);
        if(he!=4 || le!=0 || lc!=100 || hc!=0) fail("timeout isolation/drain");
        $display("SCENARIO_PASS FS06");
        reset_case; open_both(0,0); wait(ldc==1 && hdc==1);
        if(requests!=0 || lc!=0 || hc!=0) fail("empty file issued sector");
        $display("SCENARIO_PASS FS07");
        for(k=0;k<=7;k=k+1) begin
            reset_case; shift=k; random_ready=1; urgent=0;
            open_both((512<<k)+1,(512<<k)+513);
            wait(ldc==1 && hdc==1);
            if(lc!=((512<<k)+1) || hc!=((512<<k)+513) || le!=0 || he!=0)
                fail("cluster geometry or random consumer stalls");
        end
        $display("SCENARIO_PASS FS08");
        $display("TEST_PASS"); $finish;
    end
endmodule
`default_nettype wire
