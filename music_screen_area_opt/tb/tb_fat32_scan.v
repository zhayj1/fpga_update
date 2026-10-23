`timescale 1ns/1ps
`default_nettype none
module tb_fat32_scan;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    wire busy, done;
    wire [3:0] err;
    wire [8:0] file_total;
    wire chain_req, sec_req, sec_ready, ft_we;
    wire [31:0] chain_cluster, sec_lba, ft_size, ft_cluster;
    wire [8:0] ft_index;
    wire [87:0] ft_name;
    wire [1:0] ft_type;
    reg chain_done = 1'b0;
    reg [3:0] chain_err = 4'd0;
    reg [31:0] chain_next = 32'd9;
    reg sec_valid = 1'b0, sec_done = 1'b0;
    reg [7:0] sec_data = 8'd0;
    reg [3:0] sec_err = 4'd0;
    reg [7:0] sector0 [0:511];
    reg [7:0] sector1 [0:511];
    reg [31:0] expected_size [0:1];
    reg [31:0] expected_cluster [0:1];
    reg [87:0] expected_name [0:1];
    reg [1:0] expected_type [0:1];
    integer scenario = 0, writes = 0, sector_reads = 0, chain_reads = 0;
    integer sec_state = 0, byte_pos = 0, active_sector = 0;
    reg chain_pending = 1'b0, gap_done = 1'b0;
    reg inject_sec_error = 1'b0;
    integer i, wait_cycles;

    fat32_scan #(.FILE_MAX(240), .CLK_HZ(1000000), .WATCHDOG_MS(100)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
        .err(err), .file_total(file_total), .data_lba(32'd100),
        .spc_shift(4'd0), .root_cluster(32'd5), .total_clusters(32'd100),
        .chain_req(chain_req), .chain_cluster(chain_cluster),
        .chain_done(chain_done), .chain_err(chain_err), .chain_next(chain_next),
        .sec_req(sec_req), .sec_lba(sec_lba), .sec_valid(sec_valid),
        .sec_data(sec_data), .sec_done(sec_done), .sec_err(sec_err),
        .sec_ready(sec_ready), .ft_we(ft_we), .ft_index(ft_index),
        .ft_name(ft_name), .ft_type(ft_type), .ft_size(ft_size),
        .ft_cluster(ft_cluster)
    );

    task fail;
        input [8*120-1:0] reason;
        begin
            $display("TEST_FAIL %0s scenario=%0d time=%0t", reason, scenario, $time);
            $finish;
        end
    endtask

    task put_entry;
        input integer which_sector, slot;
        input [87:0] name;
        input [7:0] attr;
        input [31:0] cluster, size;
        integer offset, j;
        begin
            offset = slot * 32;
            for (j = 0; j < 11; j = j + 1) begin
                if (which_sector == 0) sector0[offset+j] = name[87-j*8 -: 8];
                else sector1[offset+j] = name[87-j*8 -: 8];
            end
            if (which_sector == 0) begin
                sector0[offset+11] = attr;
                sector0[offset+20] = cluster[23:16];
                sector0[offset+21] = cluster[31:24];
                sector0[offset+26] = cluster[7:0];
                sector0[offset+27] = cluster[15:8];
                sector0[offset+28] = size[7:0];
                sector0[offset+29] = size[15:8];
                sector0[offset+30] = size[23:16];
                sector0[offset+31] = size[31:24];
            end else begin
                sector1[offset+11] = attr;
                sector1[offset+20] = cluster[23:16];
                sector1[offset+21] = cluster[31:24];
                sector1[offset+26] = cluster[7:0];
                sector1[offset+27] = cluster[15:8];
                sector1[offset+28] = size[7:0];
                sector1[offset+29] = size[15:8];
                sector1[offset+30] = size[23:16];
                sector1[offset+31] = size[31:24];
            end
        end
    endtask

    // Independent sector/chain response model. It inserts valid gaps and
    // deliberately maps cluster 9 to a nonadjacent sector.
    always @(negedge clk) begin
        sec_valid = 1'b0;
        sec_done = 1'b0;
        sec_err = 4'd0;
        chain_done = 1'b0;
        if (!rst_n) begin
            sec_state = 0;
            byte_pos = 0;
            gap_done = 1'b0;
            chain_pending = 1'b0;
        end else begin
            if (sec_state == 0 && sec_req) begin
                if (sec_lba == 32'd103) active_sector = 0;
                else if (sec_lba == 32'd107) active_sector = 1;
                else fail("unexpected sector LBA");
                sector_reads = sector_reads + 1;
                byte_pos = 0;
                gap_done = 1'b0;
                sec_state = 1;
            end else if (sec_state == 1) begin
                if ((byte_pos % 7) != 3 || gap_done) begin
                    if (!sec_ready) fail("sector backpressure unsupported");
                    sec_valid = 1'b1;
                    if (active_sector == 0) sec_data = sector0[byte_pos];
                    else sec_data = sector1[byte_pos];
                    gap_done = 1'b0;
                    if (byte_pos == 511) sec_state = 2;
                    else byte_pos = byte_pos + 1;
                end else begin
                    // A single idle cycle at each gap; do not advance bpos.
                    gap_done = 1'b1;
                end
            end else if (sec_state == 2) begin
                sec_done = 1'b1;
                if (inject_sec_error) sec_err = 4'd2;
                sec_state = 0;
            end
            if (chain_pending) begin
                chain_done = 1'b1;
                chain_pending = 1'b0;
            end else if (chain_req) begin
                if (chain_cluster !== 32'd5) fail("unexpected chain cluster");
                chain_reads = chain_reads + 1;
                chain_pending = 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        #1;
        if (rst_n && ft_we) begin
            if (writes >= 2) fail("too many file entries");
            if (ft_index !== writes[8:0] || ft_name !== expected_name[writes] ||
                ft_type !== expected_type[writes] || ft_size !== expected_size[writes] ||
                ft_cluster !== expected_cluster[writes])
                fail("file table field mismatch");
            writes = writes + 1;
        end
    end

    task restart;
        begin
            @(posedge clk); #2; rst_n = 1'b0;
            repeat (3) @(posedge clk);
            #2; rst_n = 1'b1;
            @(posedge clk); #2; start = 1'b1;
            @(posedge clk); #2; start = 1'b0;
        end
    endtask

    task await_done;
        input integer want_files, want_sectors, want_chains, want_error;
        begin
            wait_cycles = 0;
            while (done !== 1'b1 && wait_cycles < 3000) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (wait_cycles == 3000) fail("scan timeout");
            if (err !== want_error[3:0] || file_total !== want_files || writes != want_files ||
                sector_reads != want_sectors || chain_reads != want_chains)
                fail("scan result/count mismatch");
        end
    endtask

    initial begin
        for (i = 0; i < 512; i = i + 1) begin
            sector0[i] = 8'hE5;
            sector1[i] = 8'hE5;
        end
        expected_name[0] = "S01     wav";
        expected_type[0] = 2'd1;
        expected_size[0] = 32'h89ABCDEF;
        expected_cluster[0] = 32'h02345678;
        expected_name[1] = "S01BG1  BMP";
        expected_type[1] = 2'd0;
        expected_size[1] = 32'h00112233;
        expected_cluster[1] = 32'h00000056;
        put_entry(0, 0, expected_name[0], 8'h20, expected_cluster[0], expected_size[0]);
        put_entry(0, 1, "LONGNAMEEXT", 8'h0F, 32'd11, 32'd22);
        put_entry(0, 2, "DELETE  WAV", 8'h20, 32'd12, 32'd23);
        sector0[64] = 8'hE5;
        put_entry(0, 3, "SUBDIR  BMP", 8'h10, 32'd13, 32'd24);
        put_entry(0, 4, "VOLUME  LRC", 8'h08, 32'd14, 32'd25);
        put_entry(0, 5, expected_name[1], 8'h20, expected_cluster[1], expected_size[1]);
        sector0[6*32] = 8'h00;
        put_entry(0, 7, "AFTER   WAV", 8'h20, 32'd15, 32'd26);
        scenario = 1;
        restart();
        await_done(2, 1, 0, 0);
        $display("SCENARIO_PASS scan_filter_fields");

        for (i = 0; i < 512; i = i + 1) sector0[i] = 8'hE5;
        put_entry(1, 0, "S01     LRC", 8'h20, 32'h00001234, 32'h01020304);
        sector1[32] = 8'h00;
        expected_name[0] = "S01     LRC";
        expected_type[0] = 2'd2;
        expected_size[0] = 32'h01020304;
        expected_cluster[0] = 32'h00001234;
        writes = 0; sector_reads = 0; chain_reads = 0;
        scenario = 2;
        restart();
        await_done(1, 2, 1, 0);
        $display("SCENARIO_PASS scan_fragmented_chain");

        writes = 0; sector_reads = 0; chain_reads = 0;
        inject_sec_error = 1'b1;
        scenario = 3;
        restart();
        await_done(0, 1, 0, 1);
        $display("SCENARIO_PASS scan_sector_error");

        writes = 0; sector_reads = 0; chain_reads = 0;
        inject_sec_error = 1'b0;
        chain_next = 32'h0FFFFFF7;
        scenario = 4;
        restart();
        await_done(0, 1, 1, 2);
        $display("SCENARIO_PASS scan_bad_chain");

        $display("TEST_PASS");
        $finish;
    end
    initial begin
        #100000;
        fail("global timeout");
    end
endmodule
`default_nettype wire
