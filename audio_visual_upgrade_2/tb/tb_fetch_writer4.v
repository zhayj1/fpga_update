`timescale 1ns/1ps
`default_nettype none
// Four real EG4 row caches plus shared writer and the production text arbiter.
// Independent memory model checks captured address/length after mailbox release.
module tb_fetch_writer4;
    reg cs=0,cp=0,rn=0;
    always #5 cs=~cs;
    initial begin #3; forever #20 cp=~cp; end
    reg [3:0] commands=0,go=0,discard=0,monitor=0;
    reg [83:0] addresses=0;
    reg [63:0] lengths=0;
    reg [95:0] tags=0,expected_tags=0;
    reg [59:0] frames={4{15'd1}};
    reg [35:0] min_rows=0;
    reg [31:0] colors=0;
    wire [3:0] free_slot,bank,accepted,take,active,finished,errors,we,pv,ld;
    wire [95:0] pixels;
    wire [9:0] write_addr;
    wire good,ireq,iack,idone,ivalid;
    wire [20:0] iaddr;
    wire [15:0] ilen;
    wire [4:0] ca,cd,cv;
    wire mreq;
    wire [20:0] maddr;
    wire [15:0] mlen;
    reg mack=0,mdone=0,mvalid=0,text_req=0,pause_data=0;
    reg [31:0] mdata=0;
    integer expected_addr[0:3],expected_len[0:3],return_count[0:3];
    integer accepted_count[0:3],error_count[0:3],seen[0:3];
    integer total_images=0,text_jobs=0,transactions=0;
    integer mst=0,delay_count=0,returned=0,target_count=0,job=-1,tick=0;
    reg [20:0] held_addr=0;
    reg [15:0] held_len=0;
    reg [7:0] job_color=0;
    reg final_valid=0;
    reg [3:0] done_seen=0;
    integer a,b,n,prior,prior_jobs;

    fetch_writer4 dut(.clk_sdr(cs),.rst_sdr_n(rn),.cmd_valid(commands),.slot_free(free_slot),
        .next_bank(bank),.cmd_addr(addresses),.cmd_words(lengths),.cmd_ack(accepted),
        .wr_take(take),.wr_active(active),.wr_done(finished),.wr_error(errors),.wr_en(we),
        .wr_addr(write_addr),.wr_good(good),.px_req(ireq),.px_addr(iaddr),.px_len(ilen),
        .px_ack(iack),.px_done(idone),.px_valid(ivalid));
    px_arb5 arb(.clk_sdr(cs),.rst_sdr_n(rn),.c_req({2'd0,text_req,1'b0,ireq}),
        .c_addr({42'd0,21'h1f0000,21'd0,iaddr}),.c_len({32'd0,16'd2,16'd0,ilen}),
        .c_ack(ca),.c_done(cd),.c_valid(cv),.arb_req(mreq),.arb_addr(maddr),.arb_len(mlen),
        .arb_ack(mack),.arb_done(mdone),.arb_valid(mvalid),.grant_cnt(),.contend_cnt());
    assign iack=ca[0]; assign idone=cd[0]; assign ivalid=cv[0];

    genvar g;
    generate for(g=0;g<4;g=g+1) begin: caches
        localparam integer WIDTH=(g==0 || g==2) ? 640 : 320;
        localparam integer WORDS=(g==0 || g==2) ? 480 : 240;
        fetch_line_scene #(.MAX_W(WIDTH),.SHARED_WRITER(1)) cache(
            .clk_sdr(cs),.rst_sdr_n(rn),.fetch_start(1'b0),.row_base(21'd0),
            .words_per_row(16'd0),.fetch_tag(tags[g*24+:24]),.fetch_ready(free_slot[g]),
            .fetch_busy(),.fetch_err(),.px_req(),.px_addr(),.px_len(),
            .px_ack(1'b0),.px_done(1'b0),.px_data(mdata),.px_valid(1'b0),
            .clk_pix(cp),.rst_pix_n(rn),.px_go(go[g]),.expect_tag(expected_tags[g*24+:24]),
            .frame_id(frames[g*15+:15]),.min_row(min_rows[g*9+:9]),.discard_all(discard[g]),
            .img_w(WIDTH[15:0]),.wr_pix(16'd0),.px_out(pixels[g*24+:24]),
            .px_out_vld(pv[g]),.px_line_done(ld[g]),.underrun_cnt(),.go_cnt(),.stall_cnt(),
            .shared_take(take[g]),.shared_active(active[g]),.shared_done(finished[g]),
            .shared_error(errors[g]),.shared_we(we[g]),.shared_good(good),
            .shared_addr(write_addr),.next_bank(bank[g]));
        always @(posedge cs) if(rn && we[g]) begin
            if(cache.stream_on && cache.wr_buf_l==cache.rd_buf) begin
                $display("TEST_FAIL cache %0d writes bank currently displayed",g); $finish;
            end
            if(write_addr>2*WORDS ||
               (cache.wr_buf_l && write_addr<WORDS+1) ||
               (!cache.wr_buf_l && write_addr>=WORDS)) begin
                $display("TEST_FAIL cache %0d write address %0d outside selected bank",g,write_addr); $finish;
            end
        end
    end endgenerate

    // Release the bundled request immediately on ACK. The engine must use its
    // captured copy even when the downstream SDRAM ACK is delayed.
    always @(posedge cs) if(rn) begin
        if((we & (we-4'd1))!=0) begin $display("TEST_FAIL multiple cache write enables"); $finish; end
        for(a=0;a<4;a=a+1) begin
            if(accepted[a]) begin
                commands[a]<=0; addresses[a*21+:21]<=21'h1fffff; lengths[a*16+:16]<=16'hffff;
                accepted_count[a]=accepted_count[a]+1;
            end
            if(errors[a]) error_count[a]=error_count[a]+1;
        end
    end
    always @(negedge cp) begin
        if(rn) for(b=0;b<4;b=b+1) begin
            if(monitor[b] && pv[b]) begin
                seen[b]=seen[b]+1;
                if(pixels[b*24+:24]!=={colors[b*8+:8],colors[b*8+:8],colors[b*8+:8]}) begin
                    $display("TEST_FAIL cache %0d pixel %0d actual=%h",b,seen[b],pixels[b*24+:24]); $finish;
                end
            end
            if(ld[b]) done_seen[b]=1;
        end
    end
    // Memory traffic is gapped, ACK is delayed, and done can coincide with the
    // final valid word. Text competes continuously during the first scenario.
    always @(negedge cs) begin
        mack=0; mdone=0; mvalid=0;
        if(!rn) begin mst=0; returned=0; end
        else case(mst)
            0: if(mreq) begin
                held_addr=maddr; held_len=mlen; delay_count=5; returned=0; tick=0;
                transactions=transactions+1;
                if(maddr==21'h1f0000) begin
                    job=-1; target_count=2; job_color=8'hfe; final_valid=1; text_jobs=text_jobs+1;
                end else begin
                    job=(maddr>>16)-1;
                    if(job<0 || job>3) begin $display("TEST_FAIL unknown memory address %h",maddr); $finish; end
                    if(maddr!==expected_addr[job] || mlen!==expected_len[job]) begin
                        $display("TEST_FAIL metadata changed for %0d addr=%h len=%0d",job,maddr,mlen); $finish;
                    end
                    target_count=return_count[job]; job_color=colors[job*8+:8];
                    final_valid=(job==0 || job==2); total_images=total_images+1;
                end
                mst=1;
            end
            1: begin
                if(!mreq || maddr!==held_addr || mlen!==held_len) begin
                    $display("TEST_FAIL SDRAM request changed before ACK"); $finish;
                end
                if(delay_count==0) begin mack=1; mst=2; end
                else delay_count=delay_count-1;
            end
            2: if(!pause_data) begin
                tick=tick+1;
                if(returned<target_count && tick%4!=0) begin
                    mvalid=1; mdata={4{job_color}}; returned=returned+1;
                    if(returned==target_count && final_valid) begin mdone=1; mst=3; end
                end else if(returned==target_count) begin mdone=1; mst=3; end
            end
            3: mst=0;
        endcase
    end
    task queue_row;
        input integer id,row,words,count;
        input [7:0] color;
        begin
            wait(free_slot[id] && !commands[id]); @(negedge cs);
            expected_addr[id]=(id+1)*65536+row*512;
            expected_len[id]=words; return_count[id]=count;
            addresses[id*21+:21]=expected_addr[id]; lengths[id*16+:16]=words;
            tags[id*24+:24]={frames[id*15+:15],row[8:0]};
            colors[id*8+:8]=color; commands[id]=1;
        end
    endtask
    task read_row;
        input integer id,row,count;
        begin
            @(posedge cp); #1;
            expected_tags[id*24+:24]={frames[id*15+:15],row[8:0]};
            seen[id]=0; done_seen[id]=0; monitor[id]=1; go[id]=1;
            @(posedge cp); #1; go[id]=0;
            wait(done_seen[id]); @(posedge cp); #1; monitor[id]=0;
            if(seen[id]!=count) begin
                $display("TEST_FAIL cache %0d valid pixels=%0d expected=%0d",id,seen[id],count); $finish;
            end
        end
    endtask
    task await_row;
        input integer id;
        begin wait(finished[id]); repeat(8) @(posedge cp); end
    endtask
    initial begin
        for(n=0;n<4;n=n+1) begin
            accepted_count[n]=0; error_count[n]=0; seen[n]=0;
            expected_addr[n]=0; expected_len[n]=0; return_count[n]=0;
        end
        #213; rn=1;
        // Simultaneous full-width requests; each cache has different content.
        @(posedge cs); #1;
        for(n=0;n<4;n=n+1) begin
            expected_addr[n]=(n+1)*65536; expected_len[n]=(n%2==0)?480:240;
            return_count[n]=expected_len[n]; addresses[n*21+:21]=expected_addr[n];
            lengths[n*16+:16]=expected_len[n]; tags[n*24+:24]={15'd1,9'd0};
            colors[n*8+:8]=8'h31+n;
        end
        commands=15; text_req=1;
        wait(total_images==4); wait(mst==0); text_req=0;
        repeat(10) @(posedge cp);
        if(text_jobs==0 || transactions>9) begin $display("TEST_FAIL image/text starvation"); $finish; end
        for(n=0;n<4;n=n+1) begin
            if(accepted_count[n]!=1) begin $display("TEST_FAIL missing/duplicate request"); $finish; end
            read_row(n,0,(n%2==0)?640:320);
        end
        $display("SCENARIO_PASS fourway_fullwidth_and_text_fairness");

        queue_row(0,1,480,479,8'h51); await_row(0); read_row(0,1,0);
        queue_row(1,1,240,241,8'h52); await_row(1); read_row(1,1,0);
        if(error_count[0]!=1 || error_count[1]!=1) begin $display("TEST_FAIL burst length error missing"); $finish; end
        $display("SCENARIO_PASS short_and_overlong_bursts_rejected");

        prior=accepted_count[3]; prior_jobs=total_images;
        queue_row(3,1,0,0,8'h53); wait(accepted_count[3]==prior+1);
        queue_row(3,1,241,241,8'h53); wait(accepted_count[3]==prior+2);
        repeat(10) @(posedge cs);
        if(error_count[3]!=2 || total_images!=prior_jobs) begin $display("TEST_FAIL illegal command issued SDRAM request"); $finish; end
        $display("SCENARIO_PASS zero_and_oversized_commands");

        pause_data=1; queue_row(0,2,480,480,8'h61);
        wait(mst==2); read_row(0,2,0);
        min_rows[0+:9]=3; pause_data=0;
        wait(free_slot[0]);
        queue_row(0,3,480,480,8'h62); await_row(0); read_row(0,3,640);
        $display("SCENARIO_PASS late_row_discard_and_recovery");

        pause_data=1; queue_row(2,1,480,480,8'h71); wait(mst==2);
        frames[30+:15]=2; pause_data=0; wait(free_slot[2]);
        queue_row(2,0,480,480,8'h72); await_row(2); read_row(2,0,640);
        discard[3]=1; queue_row(3,1,240,240,8'h73);
        wait(finished[3]); wait(free_slot[3]); discard[3]=0;
        queue_row(3,2,240,240,8'h74); await_row(3); read_row(3,2,320);
        $display("SCENARIO_PASS old_frame_and_disabled_cache_discard");

        queue_row(0,4,480,480,8'h81); await_row(0);
        fork
            read_row(0,4,640);
            begin
                wait(pv[0]); wait(free_slot[0]);
                // Same color lets the concurrent pixel checker keep checking.
                queue_row(0,5,480,480,8'h81); wait(finished[0]);
                if(!monitor[0]) begin $display("TEST_FAIL overlap stimulus did not overlap"); $finish; end
            end
        join
        repeat(8) @(posedge cp); read_row(0,5,640);
        $display("SCENARIO_PASS double_bank_read_write_overlap");

        pause_data=1; queue_row(1,2,240,240,8'h91); wait(mst==2);
        repeat(8) @(posedge cs); @(posedge cp); #1; rn=0;
        commands=0; go=0; monitor=0; min_rows=0; frames={4{15'd1}};
        repeat(8) @(posedge cp); #1; rn=1; pause_data=0;
        read_row(1,0,0);
        queue_row(1,0,240,240,8'h92); await_row(1); read_row(1,0,320);
        $display("SCENARIO_PASS reset_during_burst_and_recovery");
        $display("TEST_PASS"); $finish;
    end
    initial begin #2000000; $display("TEST_FAIL watchdog st=%0d commands=%b free=%b",mst,commands,free_slot); $finish; end
endmodule
`default_nettype wire
