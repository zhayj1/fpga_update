`timescale 1ns/1ps
`default_nettype none
module tb_fat32_mount_pipeline;
    reg clk=0, rst_n=0, start=0;
    always #10 clk=~clk;
    wire busy,done,req,ready,old_busy,old_done,old_req,old_ready;
    wire [3:0] err,old_err,shift,old_shift;
    wire [31:0] part,fat,data,root,count,lba;
    wire [31:0] old_part,old_fat,old_data,old_root,old_count,old_lba;
    reg valid=0,sector_done=0;
    reg [7:0] din=0, image[0:1023];
    reg [3:0] sector_err=0;
    integer phase=0, offset=0, sector_base=0, requests=0, fault=0;
    integer i,j,test_count=0;
    reg mbr=0, seen_new=0,seen_old=0;
    reg [31:0] expected_part=2048;

    fat32_mount dut(.clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),.err(err),
        .part_lba(part),.fat_lba(fat),.data_lba(data),.spc_shift(shift),
        .root_cluster(root),.total_clusters(count),.sec_req(req),.sec_lba(lba),
        .sec_valid(valid),.sec_data(din),.sec_done(sector_done),.sec_err(sector_err),.sec_ready(ready));
    fat32_mount_before_pipeline ref_dut(.clk(clk),.rst_n(rst_n),.start(start),
        .busy(old_busy),.done(old_done),.err(old_err),.part_lba(old_part),
        .fat_lba(old_fat),.data_lba(old_data),.spc_shift(old_shift),
        .root_cluster(old_root),.total_clusters(old_count),.sec_req(old_req),.sec_lba(old_lba),
        .sec_valid(valid),.sec_data(din),.sec_done(sector_done),.sec_err(sector_err),.sec_ready(old_ready));

    always @(negedge clk) if(rst_n) begin
        valid=0; sector_done=0;
        if(req!==old_req || (req && lba!==old_lba)) begin
            $display("TEST_FAIL mount changed sector request"); $finish;
        end
        case(phase)
            0: if(req) begin
                requests=requests+1;
                if(lba==0) sector_base=0;
                else if(mbr && lba==expected_part) sector_base=512;
                else begin $display("TEST_FAIL unexpected mount LBA %0d",lba); $finish; end
                offset=0; phase=1;
            end
            1: begin
                if(!ready || !old_ready) begin $display("TEST_FAIL mount backpressure"); $finish; end
                valid=1; din=image[sector_base+offset];
                if(offset==511) phase=2; else offset=offset+1;
            end
            2: begin
                sector_err=((fault==1 && sector_base==0) ||
                            (fault==2 && sector_base==512)) ? 4'd4 : 4'd0;
                sector_done=1; phase=0;
            end
        endcase
    end
    always @(posedge clk) if(rst_n) begin
        if(done) begin
            if(seen_new || busy) begin $display("TEST_FAIL new done protocol"); $finish; end
            seen_new=1;
        end
        if(old_done) begin
            if(seen_old || old_busy) begin $display("TEST_FAIL old done protocol"); $finish; end
            seen_old=1;
        end
    end
    task put32;
        input integer addr;
        input [31:0] value;
        begin
            image[addr]=value[7:0]; image[addr+1]=value[15:8];
            image[addr+2]=value[23:16]; image[addr+3]=value[31:24];
        end
    endtask
    task setup;
        input integer is_mbr, spc, nfats;
        integer b;
        begin
            for(i=0;i<1024;i=i+1) image[i]=0;
            mbr=(is_mbr!=0); fault=0; expected_part=2048;
            b=mbr ? 512 : 0;
            image[b+11]=0; image[b+12]=2; image[b+13]=spc;
            image[b+14]=32; image[b+16]=nfats;
            put32(b+32,100000); put32(b+36,4); put32(b+44,2);
            image[b+82]="F"; image[b+83]="A"; image[b+84]="T";
            image[b+85]="3"; image[b+86]="2";
            image[b+510]=8'h55; image[b+511]=8'haa;
            if(mbr) begin
                image[510]=8'h55; image[511]=8'haa;
                image[450]=8'h0c; put32(454,2048);
            end
        end
    endtask
    task run_case;
        input [3:0] expected_error;
        integer ticks;
        reg [163:0] previous;
        reg [31:0] used,total;
        begin
            previous={part,fat,data,shift,root,count};
            seen_new=0; seen_old=0; requests=0;
            @(negedge clk); start=1;
            @(negedge clk); start=0;
            // A start during the sector transfer must be ignored by both.
            repeat(5) @(negedge clk);
            start=1; @(negedge clk); start=0;
            ticks=0;
            while((!seen_new || !seen_old) && ticks<2000) begin
                @(negedge clk); ticks=ticks+1;
            end
            if(ticks==2000 || err!==expected_error || err!==old_err ||
               {part,fat,data,shift,root,count}!=={old_part,old_fat,old_data,old_shift,old_root,old_count}) begin
                $display("TEST_FAIL mount case=%0d expected err=%0d got=%0d/%0d new=%h old=%h",
                    test_count,expected_error,err,old_err,{part,fat,data,shift,root,count},
                    {old_part,old_fat,old_data,old_shift,old_root,old_count}); $finish;
            end
            if(expected_error!=0 && {part,fat,data,shift,root,count}!==previous) begin
                $display("TEST_FAIL failed mount changed successful outputs"); $finish;
            end
            if(expected_error==0) begin
                used=32+image[(mbr?512:0)+16]*4;
                total=(100000-used)/image[(mbr?512:0)+13];
                if(part!==(mbr?expected_part:32'd0) || fat!==part+32 ||
                   data!==part+used || root!==2 || count!==total) begin
                    $display("TEST_FAIL mount independent geometry"); $finish;
                end
            end
            test_count=test_count+1;
            repeat(4) @(negedge clk);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        for(j=0;j<8;j=j+1) begin setup(0,1<<j,1); run_case(0); end
        setup(1,8,2); run_case(0);
        // Select the first valid partition, including a later table slot.
        setup(1,1,1); image[450]=0; image[482]=8'h0b; put32(486,2048); run_case(0);
        setup(1,1,1); image[466]=8'h0b; put32(470,4096); run_case(0);
        setup(0,1,1); fault=1; run_case(1);
        setup(0,1,1); image[510]=0; run_case(2);
        setup(1,1,1); image[450]=0; run_case(3);
        setup(1,1,1); fault=2; run_case(4);
        setup(1,1,1); image[594]=0; run_case(9);
        setup(1,1,1); image[1022]=0; run_case(9);
        setup(0,1,1); image[12]=4; image[13]=3; run_case(5);
        setup(0,3,1); image[14]=0; run_case(6);
        setup(0,1,1); image[14]=0; image[16]=3; run_case(11);
        setup(0,1,3); put32(36,0); run_case(10);
        setup(0,1,1); put32(36,0); run_case(7);
        setup(0,1,1); put32(32,35); run_case(7);
        setup(0,128,1); put32(32,36); run_case(7);
        setup(0,128,1); put32(32,163); run_case(7);
        setup(0,1,1); put32(44,1); run_case(8);
        setup(0,1,1); put32(44,99966); run_case(8);
        setup(0,1,2); put32(36,32'h80000000); put32(32,31); run_case(7);
        setup(1,1,1); expected_part=32'h10000; put32(454,expected_part); run_case(11);
        setup(0,1,1); run_case(0);
        if(test_count!=30) begin $display("TEST_FAIL mount case count %0d",test_count); $finish; end
        $display("MOUNT_EQ cases=%0d",test_count);
        $display("SCENARIO_PASS MOUNT01"); $display("TEST_PASS"); $finish;
    end
    initial begin #2000000; $display("TEST_FAIL mount simulation timeout"); $finish; end
endmodule
`default_nettype wire
