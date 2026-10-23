`timescale 1ns/1ps
`default_nettype none
module tb_scan_capacity;
    reg clk=0, rst_n=0, start=0;
    always #5 clk=~clk;
    reg [31:0] base=32'hf0000100, root=32'h02345678;
    reg [3:0] shift=0;
    wire busy,done,sec_req,sec_ready,chain_req,ft_we;
    wire [3:0] err;
    wire [8:0] total,ft_index;
    wire [31:0] sec_lba,chain_cluster,ft_size,ft_cluster;
    wire [87:0] ft_name;
    wire [1:0] ft_type;
    reg sec_valid=0,sec_done=0,chain_done=0;
    reg [7:0] sec_data=0;
    reg [31:0] next_cluster=0;
    reg [7:0] image[0:1023];
    reg [87:0] names[0:31];
    reg [31:0] sizes[0:31],clusters[0:31];
    integer mode=0,reads=0,chains=0,writes=0;
    integer phase=0,pos=0,active=0,delay_count=0;
    integer n,j,k,ticks;
    reg chain_pending=0;
    reg [31:0] expected_lba;
    fat32_scan #(.FILE_MAX(19),.CLK_HZ(1000000),.WATCHDOG_MS(1)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),.err(err),
        .file_total(total),.data_lba(base),.spc_shift(shift),.root_cluster(root),
        .total_clusters(32'h10000000),.chain_req(chain_req),.chain_cluster(chain_cluster),
        .chain_done(chain_done),.chain_err(4'd0),.chain_next(next_cluster),
        .sec_req(sec_req),.sec_lba(sec_lba),.sec_valid(sec_valid),.sec_data(sec_data),
        .sec_done(sec_done),.sec_err(4'd0),.sec_ready(sec_ready),.ft_we(ft_we),
        .ft_index(ft_index),.ft_name(ft_name),.ft_type(ft_type),.ft_size(ft_size),
        .ft_cluster(ft_cluster)
    );
    task fail;
        input [8*100-1:0] why;
        begin
            $display("TEST_FAIL %0s mode=%0d shift=%0d writes=%0d reads=%0d t=%0t",
                     why,mode,shift,writes,reads,$time);
            $finish;
        end
    endtask

    // A stream model, including idle cycles before bytes 0/31 of each entry.
    always @(negedge clk) begin
        sec_valid=0;sec_done=0;chain_done=0;
        if(!rst_n) begin phase=0;chain_pending=0;delay_count=0;end
        else begin
            if(chain_pending) begin
                chain_done=1;chain_pending=0;next_cluster=root+32'd4;
            end else if(chain_req) begin
                if(chain_cluster !== root || chains!=0 || shift!=0)
                    fail("unexpected chain request");
                chains=chains+1;chain_pending=1;
            end
            if(mode!=2 && mode!=3) begin
                case(phase)
                    0: if(sec_req) begin
                        if(reads>1) fail("capacity limit requested another sector");
                        expected_lba=base+(root-32'd2)*(32'd1<<shift);
                        if(reads==1) begin
                            if(shift==0) expected_lba=base+(root+32'd4-32'd2);
                            else expected_lba=expected_lba+32'd1;
                        end
                        if(sec_lba !== expected_lba) fail("sector address mismatch");
                        active=reads;reads=reads+1;pos=0;phase=1;delay_count=0;
                    end
                    1: begin
                        if(delay_count==0 && ((pos%32)==0 || (pos%32)==31))
                            delay_count=1;
                        else begin
                            if(!sec_ready) fail("unexpected sector backpressure");
                            sec_valid=1;sec_data=image[active*512+pos];delay_count=0;
                            if(pos==511) phase=2;else pos=pos+1;
                        end
                    end
                    2: begin sec_done=1;phase=0;end
                    default: fail("invalid stream model state");
                endcase
            end
        end
    end
    always @(posedge clk) begin
        #1;
        if(rst_n && ft_we) begin
            if(mode!=0 || writes>=19) fail("unexpected table write");
            if(ft_index !== writes[8:0] || ft_name !== names[writes] ||
               ft_size !== sizes[writes] || ft_cluster !== clusters[writes] ||
               ft_type !== (writes%4)) fail("table data mismatch");
            writes=writes+1;
        end
    end
    task launch;
        begin
            @(negedge clk);start=1;
            @(negedge clk);start=0;
        end
    endtask
    task await_done;
        input integer count,requests,chain_count,error_code;
        begin
            ticks=0;
            while(done!==1 && ticks<4000) begin @(negedge clk);#1;ticks=ticks+1;end
            if(ticks==4000) fail("completion timeout");
            if(total!==count || err!==error_code[3:0] || writes!=count ||
               reads!=requests || chains!=chain_count || busy!==0)
                fail("completion result mismatch");
            @(negedge clk);#1;
            if(done!==0) fail("done is not a pulse");
        end
    endtask
    initial begin
        // Fill every ignored field with a different value; required fields
        // contain nonzero high bytes and mixed-case/unknown extensions.
        for(n=0;n<1024;n=n+1) image[n]=(n*37+91)&255;
        for(n=0;n<32;n=n+1) begin
            case(n%4)
                0:names[n]="S00BG1  BMP";
                1:names[n]="S00     wAv";
                2:names[n]="S00     LrC";
                3:names[n]="S00     dat";
            endcase
            names[n][79:72]=8'h30+n/10;
            names[n][71:64]=8'h30+n%10;
            sizes[n]=32'h89abcdef ^ (n*32'h07050301);
            clusters[n]=32'h02345678 ^ (n*32'h01020408);
            for(j=0;j<11;j=j+1) image[n*32+j]=names[n][87-j*8 -:8];
            image[n*32+11]=8'h20;
            image[n*32+20]=clusters[n][23:16];image[n*32+21]=clusters[n][31:24];
            image[n*32+26]=clusters[n][7:0];image[n*32+27]=clusters[n][15:8];
            image[n*32+28]=sizes[n][7:0];image[n*32+29]=sizes[n][15:8];
            image[n*32+30]=sizes[n][23:16];image[n*32+31]=sizes[n][31:24];
        end
        repeat(3) @(negedge clk);rst_n=1;
        // Restart without reset: no entry data from a previous scan may leak.
        for(k=0;k<8;k=k+1) begin
            shift=k;reads=0;writes=0;chains=0;
            launch();await_done(19,2,(k==0)?1:0,0);
        end
        $display("SCENARIO_PASS scan-capacity-all-cluster-sizes");
        mode=1;image[0]=0;reads=0;writes=0;chains=0;
        launch();await_done(0,1,0,0);
        $display("SCENARIO_PASS scan-end-marker-after-restart");
        mode=2;reads=0;writes=0;chains=0;
        launch();await_done(0,0,0,3);
        $display("SCENARIO_PASS scan-no-progress-watchdog");
        mode=3;reads=0;writes=0;chains=0;
        launch();repeat(20) @(negedge clk);
        rst_n=0;repeat(3) @(negedge clk);rst_n=1;
        repeat(1100) begin
            @(negedge clk);#1;
            if(done!==0 || busy!==0 || ft_we!==0 || sec_req!==0 || chain_req!==0)
                fail("reset did not cancel scan");
        end
        $display("SCENARIO_PASS scan-reset-cancels-wait");
        $display("TEST_PASS");$finish;
    end
    initial begin #250000;fail("global timeout");end
endmodule
`default_nettype wire
