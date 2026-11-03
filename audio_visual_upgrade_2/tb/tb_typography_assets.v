`timescale 1ns/1ps
`default_nettype none
module tb_typography_assets;
    reg clk=0,rn=0,sd_ready=0,pl_done=0;
    always #5 clk=~clk;
    reg [31:0] font_size=3856960;
    reg [7:0] song=0;
    reg enable_preload=0,next_valid=0,song_switch=0,old_released=0,fail_font=0;
    wire select_start,task_start,task_raw,active,font_ok,asc_ok,lrc_ok,lrc_slot,lrc_prepared;
    wire [3:0] boot_state,task_tag;
    wire [7:0] task_index;
    wire [20:0] task_base;
    wire [31:0] task_bytes;
    wire [19:0] task_capacity;
    reg task_done=0;
    reg [3:0] done_tag=0;
    reg [7:0] task_error=0;
    integer fonts=0,ascs=0,lrcs=0,images=0,cycles=0;
    asset_manager #(.TYPOGRAPHY(1)) dut(.clk(clk),.rst_n(rn),.sd_ready(sd_ready),
        .pl_done(pl_done),.pl_busy(1'b0),.song(song),.current_images(48'h060504030201),
        .current_lrc_valid(1'b1),.current_lrc(8'd15),.next_valid(next_valid),.next_song(8'd1),
        .next_images(48'h161514131211),.next_lrc_valid(1'b1),.next_lrc(8'd31),
        .font_valid(1'b1),.asc_valid(1'b1),.font_size(font_size),.asc_size(32'd6144),
        .enable_preload(enable_preload),.song_switch(song_switch),.old_released(old_released),
        .rotation(2'd0),.pinned(4'd0),.probe_start(1'b0),.probe_index(8'd0),
        .select_start(select_start),.boot_state(boot_state),.task_start(task_start),
        .task_raw(task_raw),.task_index(task_index),.task_base(task_base),.task_bytes(task_bytes),
        .task_capacity(task_capacity),.task_tag(task_tag),.active(active),.probe_active(),
        .task_done(task_done),.done_tag(done_tag),.task_error(task_error),.image_w(16'd8),.image_h(16'd6),
        .bg_valid(),.cv_valid(),.shape_start(1'b0),.shape_pair(2'd0),.shape_done(),
        .shape_bw(),.shape_bh(),.shape_cw(),.shape_ch(),.ahead_ready(),.ahead_bg_ok(),.ahead_cv_ok(),
        .pre_busy(),.pre_step(),.pre_count(),.pre_error(),.font_ok(font_ok),.asc_ok(asc_ok),
        .lrc_ok(lrc_ok),.lrc_slot(lrc_slot),.lrc_prepared(lrc_prepared),.lrc_song(),.lrc_count());
    always @(negedge clk) begin
        task_done=0;
        if(!rn) begin fonts=0;ascs=0;lrcs=0;images=0;end
        else if(task_start) begin
            if(task_raw && task_index==136) begin
                fonts=fonts+1;
                if(task_base!==21'h10BBB0 || task_bytes!==font_size || task_capacity!==1000528) begin
                    $display("TEST_FAIL FONT allocation");$finish;
                end
            end else if(task_raw && task_index==137) ascs=ascs+1;
            else if(task_raw) begin
                lrcs=lrcs+1;
                if(task_bytes!==4448 || task_capacity!==1112 ||
                    task_base!==(lrc_slot ? 21'h10B300 : (boot_state==7 ? 21'h10B758 : 21'h10B300))) begin
                    $display("TEST_FAIL LRC allocation base=%h boot=%0d",task_base,boot_state);$finish;
                end
            end else begin
                images=images+1;
                case(task_base)
                21'h000000,21'h038400,21'h070800,21'h0A8C00:
                    if(task_capacity!==230400) begin $display("TEST_FAIL BG capacity");$finish;end
                21'h0E1000,21'h0EB8C0,21'h0F6180,21'h100A40:
                    if(task_capacity!==43200) begin $display("TEST_FAIL CV capacity");$finish;end
                default:begin $display("TEST_FAIL image map");$finish;end
                endcase
            end
            task_done=1;done_tag=task_tag;
            task_error=(fail_font && task_raw && task_index==136) ? 8'h04 : 8'h00;
        end
    end
    task boot;
        input [31:0] size;
        input expected_font,load_error;
        begin
            @(posedge clk);#1;rn=0;sd_ready=0;pl_done=0;enable_preload=0;next_valid=0;
            song_switch=0;old_released=0;song=0;font_size=size;fail_font=load_error;
            repeat(5) @(posedge clk);#1;rn=1;sd_ready=1;
            wait(select_start);@(posedge clk);#1;pl_done=1;
            @(posedge clk);#1;pl_done=0;
            cycles=0;
            while(boot_state!=7 && cycles<300) begin @(posedge clk);#1;cycles=cycles+1;end
            if(boot_state!=7 || fonts!=expected_font || ascs!=0 || images!=6 || lrcs!=1 ||
                font_ok!==(expected_font && !load_error) || asc_ok!==0 || lrc_ok!==1) begin
                $display("TEST_FAIL boot size=%0d fonts=%0d asc=%0d images=%0d lrc=%0d fontok=%b",size,fonts,ascs,images,lrcs,font_ok);$finish;
            end
        end
    endtask
    initial begin
        boot(33292,0,0);boot(1046788,0,0);boot(3856961,0,0);boot(3856944,0,0);
        boot(33296,0,0);boot(1046784,0,0);boot(82576,0,0);boot(3856960,1,1);boot(3856960,1,0);
        $display("SCENARIO_PASS TYP-06-font-loading");
        @(posedge clk);#1;enable_preload=1;next_valid=1;
        cycles=0;
        while(!lrc_prepared && cycles<300) begin @(posedge clk);#1;cycles=cycles+1;end
        if(!lrc_prepared || lrcs!=2 || fonts!=1 || ascs!=0) begin
            $display("TEST_FAIL preload typography");$finish;
        end
        @(posedge clk);#1;song_switch=1;song=1;
        @(posedge clk);#1;song_switch=0;old_released=1;
        @(posedge clk);#1;old_released=0;
        repeat(80) @(posedge clk);#1;
        if(lrc_slot!==1 || lrc_ok!==1 || font_ok!==1 || asc_ok!==0 || fonts!=1) begin
            $display("TEST_FAIL switch typography");$finish;
        end
        $display("SCENARIO_PASS TYP-06-song-assets");
        $display("TEST_PASS");$finish;
    end
    initial begin #100000;$display("TEST_FAIL assets timeout");$finish;end
endmodule
`default_nettype wire
