`default_nettype none
// A single outstanding task owns the file stream and writeback until completion.
// Image state belongs to eight physical assets (four BG/CV pairs). A two-bit
// song epoch hides old g2/g3 immediately on a song switch without copying tables.
module asset_manager (
    input wire clk, input wire rst_n, input wire sd_ready,
    input wire pl_done, input wire pl_busy, input wire [7:0] song,
    input wire [47:0] current_images, input wire current_lrc_valid,
    input wire [7:0] current_lrc,
    input wire next_valid, input wire [7:0] next_song,
    input wire [47:0] next_images, input wire next_lrc_valid,
    input wire [7:0] next_lrc,
    input wire font_valid, input wire asc_valid,
    input wire [31:0] font_size, input wire [31:0] asc_size,
    input wire enable_preload, input wire song_switch, input wire old_released,
    input wire [1:0] rotation, input wire [3:0] pinned,
    input wire probe_start, input wire [7:0] probe_index,
    output reg select_start, output wire [3:0] boot_state,
    output reg task_start, output reg task_raw,
    output reg [7:0] task_index, output reg [20:0] task_base,
    output reg [31:0] task_bytes, output reg [18:0] task_capacity,
    output reg [3:0] task_tag, output reg active, output wire probe_active,
    input wire task_done, input wire [3:0] done_tag,
    input wire [7:0] task_error, input wire [15:0] image_w, input wire [15:0] image_h,
    output wire [3:0] bg_valid, output wire [3:0] cv_valid,
    input wire shape_start, input wire [1:0] shape_pair,
    output reg shape_done, output reg [9:0] shape_bw, output reg [8:0] shape_bh,
    output reg [9:0] shape_cw, output reg [8:0] shape_ch,
    output reg ahead_ready, output wire ahead_bg_ok, output wire ahead_cv_ok,
    output wire pre_busy, output reg [2:0] pre_step,
    output reg [7:0] pre_count, output reg [7:0] pre_error,
    output wire font_ok, output wire asc_ok, output wire lrc_ok,
    output reg lrc_slot, output reg lrc_prepared,
    output reg [7:0] lrc_song, output reg [3:0] lrc_count
);
    localparam [2:0] WAIT_CARD=3'd0, SELECT=3'd1, BOOT=3'd2, LIVE=3'd3;
    reg [2:0] state;
    reg [3:0] boot_step;
    reg [1:0] epoch, task_epoch, ahead_physical;
    reg [47:0] round_images;
    reg [7:0] round_lrc;
    reg round_lrc_valid;
    reg [7:0] round_song, last_song;
    reg round_active, released, need_round, have_round;
    reg probe_pending;
    reg [7:0] probe_hold;
    reg [3:0] target;
    reg [11:0] valid, loading;
    reg [1:0] slot_epoch [0:7];
    wire complete = active && task_done && done_tag == task_tag;
    assign probe_active = active && target == 4'd12;
    wire [2:0] ahead_bg = {ahead_physical,1'b0};
    wire [2:0] ahead_cv = {ahead_physical,1'b1};
    assign ahead_bg_ok = valid[ahead_bg] && !loading[ahead_bg];
    assign ahead_cv_ok = valid[ahead_cv] && !loading[ahead_cv];
    assign font_ok = valid[8]; assign asc_ok = valid[9];
    assign lrc_ok = valid[lrc_slot ? 11 : 10];
    assign pre_busy = round_active && pre_step >= 3'd2 && released;
    assign boot_state = state == WAIT_CARD ? 4'd0 : state == SELECT ? 4'd8 :
                        state == LIVE ? 4'd7 : boot_step < 4'd6 ? 4'd2 :
                        boot_step < 4'd8 ? 4'd9 : 4'd10;
    genvar g;
    generate for (g=0;g<4;g=g+1) begin : g_slot_outputs
        assign bg_valid[g] = valid[2*g] && !loading[2*g] && slot_epoch[2*g] == epoch;
        assign cv_valid[g] = valid[2*g+1] && !loading[2*g+1] && slot_epoch[2*g+1] == epoch;
    end endgenerate
    // Two narrow words per physical image. No table reset and no asynchronous
    // reads: one 9K memory replaces all logical-group geometry copies/muxes.
    reg meta_tail;
    reg [2:0] meta_asset;
    reg [8:0] meta_height;
    reg [3:0] meta_addr;
    wire [15:0] meta_data;
    wire meta_first = complete && target < 4'd8;
    wire [3:0] meta_waddr = meta_tail ? {meta_asset,1'b1} : {target[2:0],1'b0};
    wire [15:0] meta_wdata = meta_tail ? {7'd0,meta_height} : image_w;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16), .ADDR_WIDTH_A(4), .ADDR_WIDTH_B(4),
        .DATA_DEPTH_A(16), .DATA_DEPTH_B(16), .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"), .RESETMODE("SYNC"),
        .DEBUGGABLE("NO"), .PACKABLE("NO"), .FORCE_KEEP("OFF"),
        .INIT_FILE("NONE"), .FILL_ALL("NONE"), .IMPLEMENT("9K")
    ) u_geometry (
        .clka(clk), .cea(1'b1), .ocea(1'b0), .wea(meta_first | meta_tail),
        .addra(meta_waddr), .dia(meta_wdata), .doa(), .rsta(1'b0), .bea(1'b0),
        .clkb(clk), .ceb(1'b1), .oceb(1'b1), .web(1'b0),
        .addrb(meta_addr), .dib(16'd0), .dob(meta_data), .rstb(1'b0), .beb(1'b0)
    );
    reg [2:0] shape_phase;
    always @(posedge clk) begin
        if (!rst_n) begin
            meta_tail<=1'b0; meta_asset<=3'd0; meta_height<=9'd0;
            shape_phase<=3'd0; meta_addr<=4'd0; shape_done<=1'b0;
            shape_bw<=10'd0; shape_bh<=9'd0; shape_cw<=10'd0; shape_ch<=9'd0;
        end else begin
            meta_tail<=meta_first;
            if (meta_first) begin meta_asset<=target[2:0]; meta_height<=image_h[8:0]; end
            shape_done<=1'b0;
            case(shape_phase)
            3'd0: if(shape_start) begin meta_addr<={shape_pair,2'b00}; shape_phase<=3'd1; end
            3'd1: begin meta_addr<=meta_addr+4'd1; shape_phase<=3'd2; end
            3'd2: begin shape_bw<=meta_data[9:0]; meta_addr<=meta_addr+4'd1; shape_phase<=3'd3; end
            3'd3: begin shape_bh<=meta_data[8:0]; meta_addr<=meta_addr+4'd1; shape_phase<=3'd4; end
            3'd4: begin shape_cw<=meta_data[9:0]; shape_phase<=3'd5; end
            3'd5: begin shape_ch<=meta_data[8:0]; shape_done<=1'b1; shape_phase<=3'd0; end
            default: shape_phase<=3'd0;
            endcase
        end
    end
    function [20:0] image_base;
        input [2:0] asset;
        begin
            case(asset)
            3'd0:image_base=21'h00000; 3'd1:image_base=21'h70800;
            3'd2:image_base=21'h38400; 3'd3:image_base=21'hA8C00;
            3'd4:image_base=21'h150000;3'd5:image_base=21'h1225A0;
            3'd6:image_base=21'h188400;3'd7:image_base=21'h1C0800;
            endcase
        end
    endfunction
    // One selector supplies the same task registers for boot, preload and raw files.
    reg candidate, raw_sel;
    reg [3:0] asset_sel;
    reg [7:0] index_sel;
    reg [20:0] base_sel;
    reg [31:0] bytes_sel;
    reg [18:0] capacity_sel;
    reg [1:0] epoch_sel, physical_sel;
    reg [2:0] image_sel;
    always @* begin
        candidate=1'b0; raw_sel=1'b0; asset_sel=4'd0; index_sel=8'd0;
        base_sel=21'd0; bytes_sel=32'd0; capacity_sel=19'd230400;
        epoch_sel=epoch; physical_sel=rotation; image_sel=3'd0;
        if (state == BOOT) begin
            if (boot_step < 4'd6) begin
                candidate=1'b1;
                physical_sel=rotation+boot_step[2:1];
                image_sel={physical_sel,boot_step[0]};
                asset_sel={1'b0,image_sel};
                index_sel=current_images[boot_step*8 +:8];
            end else begin
                raw_sel=1'b1;
                case (boot_step)
                4'd6: begin
                    candidate=font_valid; asset_sel=4'd8; index_sel=8'd136;
                    base_sel=21'hE1000; bytes_sel=font_size; capacity_sel=19'd261696;
                end
                4'd7: begin
                    candidate=asc_valid; asset_sel=4'd9; index_sel=8'd137;
                    base_sel=21'h120E40; bytes_sel=asc_size; capacity_sel=19'd1536;
                end
                4'd8: begin
                    candidate=current_lrc_valid; asset_sel=4'd10; index_sel=current_lrc;
                    base_sel=21'h121440; bytes_sel=32'd4448; capacity_sel=19'd1112;
                end
                default: candidate=1'b0;
                endcase
            end
        end else if (state == LIVE) begin
            if (probe_pending) begin
                candidate=1'b1; asset_sel=4'd12; index_sel=probe_hold;
                image_sel=3'd7;
            end else if (round_active && pre_step < 3'd6 &&
                        (pre_step < 3'd2 || released)) begin
                candidate=1'b1;
                physical_sel=pre_step < 3'd2 ? ahead_physical : rotation+{1'b0,pre_step[2:1]};
                image_sel={physical_sel,pre_step[0]}; asset_sel={1'b0,image_sel};
                index_sel=round_images[pre_step*8 +:8];
                epoch_sel=pre_step < 3'd2 ? epoch+2'd1 : epoch;
            end else if (round_active && pre_step == 3'd2 && !released && !lrc_prepared) begin
                candidate=round_lrc_valid && !pl_busy; raw_sel=1'b1;
                asset_sel=lrc_slot ? 4'd10 : 4'd11; index_sel=round_lrc;
                base_sel=lrc_slot ? 21'h121440 : 21'hD5C00;
                bytes_sel=32'd4448; capacity_sel=19'd1112;
            end
        end
        if (!raw_sel) begin
            base_sel=image_base(image_sel);
            capacity_sel=image_sel[0] ? 19'd184320 : 19'd230400;
            // Protect the currently displayed and the pending display pair.
            if (pinned[image_sel[2:1]]) candidate=1'b0;
        end
    end
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=WAIT_CARD; boot_step<=4'd0; epoch<=2'd0; task_epoch<=2'd0;
            select_start<=1'b0; task_start<=1'b0; task_raw<=1'b0;
            task_index<=8'd0; task_base<=21'd0; task_bytes<=32'd0;
            task_capacity<=19'd0; task_tag<=4'd0; active<=1'b0; target<=4'd0;
            valid<=12'd0; loading<=12'd0;
            ahead_physical<=2'd3; round_images<=48'd0; round_song<=8'd0; last_song<=8'd0;
            round_active<=1'b0; released<=1'b0; need_round<=1'b1; have_round<=1'b0;
            pre_step<=3'd0; pre_count<=8'd0; pre_error<=8'd0; ahead_ready<=1'b0;
            lrc_slot<=1'b0; lrc_prepared<=1'b0; lrc_song<=8'd0; lrc_count<=4'd0;
            probe_pending<=1'b0; probe_hold<=8'd0;
            round_lrc<=8'd0; round_lrc_valid<=1'b0;
            for(i=0;i<8;i=i+1) slot_epoch[i]<=2'd0;
        end else begin
            task_start<=1'b0; select_start<=1'b0;
            if (probe_start) begin probe_pending<=1'b1; probe_hold<=probe_index; end
            if (song_switch) begin
                epoch<=epoch+2'd1; lrc_slot<=~lrc_slot;
                ahead_ready<=1'b0; need_round<=1'b1;
            end
            if (old_released) released<=1'b1;
            case(state)
            WAIT_CARD: if(sd_ready) begin select_start<=1'b1; state<=SELECT; end
            SELECT: if(pl_done) begin state<=BOOT; boot_step<=4'd0; end
            BOOT: if(!active && !task_start && !candidate && boot_step >= 4'd6) begin
                if (boot_step < 4'd8) boot_step<=boot_step+4'd1;
                else state<=LIVE;
            end
            LIVE: begin
                if (!round_active && enable_preload && next_valid && !pl_busy && !song_switch &&
                    (!have_round || need_round || next_song != last_song)) begin
                    round_images<=next_images; round_song<=next_song;
                    round_lrc<=next_lrc; round_lrc_valid<=next_lrc_valid;
                    ahead_physical<=rotation+2'd3; pre_step<=3'd0;
                    round_active<=1'b1; released<=1'b0; need_round<=1'b0;
                    ahead_ready<=1'b0; lrc_prepared<=1'b0;
                end
                if (round_active && pre_step==3'd2 && !released && !lrc_prepared && !active && !pl_busy) begin
                    lrc_song<=round_song;
                    if (!round_lrc_valid) begin
                        lrc_prepared<=1'b1; valid[lrc_slot ? 10 : 11]<=1'b0;
                    end
                end
            end
            endcase
            if (!active && !task_start && !meta_tail && candidate && !song_switch) begin
                active<=1'b1; task_start<=1'b1; task_raw<=raw_sel;
                task_index<=index_sel; task_base<=base_sel; task_bytes<=bytes_sel;
                task_capacity<=capacity_sel; target<=asset_sel; task_epoch<=epoch_sel;
                task_tag<=task_tag+4'd1;
                if (asset_sel < 4'd12) begin
                    loading[asset_sel]<=1'b1; valid[asset_sel]<=1'b0;
                end
                // The diagnostic writer uses CV slot 3. Invalidate its normal
                // ownership; a diagnostic file must never masquerade as a cover.
                if (asset_sel == 4'd12) valid[7]<=1'b0;
                if (state==LIVE && asset_sel<4'd8) pre_count<=pre_count+8'd1;
                if (state==LIVE && raw_sel) lrc_count<=lrc_count+4'd1;
            end
            if (complete) begin
                active<=1'b0;
                if (target<4'd12) begin
                    loading[target]<=1'b0; valid[target]<=task_error==8'd0;
                    if (target<4'd8) begin
                        slot_epoch[target[2:0]]<=task_epoch;
                    end
                end
                if (state==BOOT) begin
                    if (boot_step<4'd8) boot_step<=boot_step+4'd1;
                    else state<=LIVE;
                end else if (target==4'd12) probe_pending<=1'b0;
                else if (task_raw) begin lrc_prepared<=1'b1; lrc_song<=round_song; end
                else begin
                    pre_error<=task_error;
                    if (pre_step==3'd1) ahead_ready<=1'b1;
                    if (pre_step==3'd5) begin
                        round_active<=1'b0; pre_step<=3'd0; last_song<=round_song; have_round<=1'b1;
                    end else pre_step<=pre_step+3'd1;
                end
            end
        end
    end
endmodule
`default_nettype wire
