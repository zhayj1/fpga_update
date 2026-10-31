`default_nettype none
// One-line-ahead, 1:1 RGB888. Request metadata stays stable until mailbox ACK.
// Completion tags reject expired rows. Missing rows remain transparent.
module layer_bg_reference #(
    parameter integer MAX_W=640, LAT=7, H_ACT_DLY=144,
    parameter integer V_ACT_DLY=35, V_ACT_LIN=480,
    parameter integer SHARED_RASTER=0,SHARED_WRITER=0,SCALE=0
)(
    input wire clk_pix, rst_pix_n, hs, vs, de, en,
    input wire [15:0] win_x,win_y,win_w,win_h,img_w,img_h,words_per_row,
    input wire [20:0] slot_base,
    output wire [23:0] dout,
    output wire dout_vld,
    output wire [31:0] underrun_cnt,stall_cnt,ferr_cnt,gap_cnt,
    output wire idle,
    input wire clk_sdr,rst_sdr_n,
    output wire px_req,
    output wire [20:0] px_addr,
    output wire [15:0] px_len,
    input wire px_ack,px_done,
    input wire [31:0] px_data,
    input wire px_valid,
    input wire [66:0] scan_state,
    output wire cmd_valid,slot_free,next_bank,
    output wire [20:0] cmd_addr,
    output wire [15:0] cmd_words,
    input wire cmd_ack,wr_take,wr_active,wr_done,wr_error,wr_en,wr_good,
    input wire [9:0] wr_addr
);
    wire [66:0] raster;
    wire hs_f,vs_f,frame_seen;
    wire [16:0] lcnt;
    wire [15:0] vln,xcnt;
    wire [14:0] frame_id;
    assign {hs_f,vs_f,frame_seen,lcnt,vln,xcnt,frame_id}=raster;
    generate if(SHARED_RASTER) begin: g_scan_shared
        assign raster=scan_state;
    end else begin: g_scan_local
        scene_raster u_scan(.clk_pix(clk_pix),.rst_pix_n(rst_pix_n),.hs(hs),.vs(vs),.de(de),.state(raster));
    end endgenerate
    wire [15:0] y=vln-V_ACT_DLY;
    wire active=(vln>=V_ACT_DLY && vln<V_ACT_DLY+V_ACT_LIN);
    wire geometry_ok=en && win_w!=0 && win_h!=0 && img_w!=0 && img_w<=MAX_W &&
                     words_per_row!=0 && frame_seen;
    wire line_ok=geometry_ok && active && y>=win_y && y<win_y+win_h &&
                 (SCALE || y-win_y<img_h);
    wire [16:0] go_at=H_ACT_DLY+{1'b0,win_x};
    wire go_now=line_ok && lcnt==go_at-LAT;
    wire [15:0] source_row=y-win_y;
    wire before_first=(vln==V_ACT_DLY+win_y-1) && win_y<V_ACT_LIN;
    wire next_ok=line_ok && y+16'd1<V_ACT_LIN && source_row+16'd1<win_h &&
                 (SCALE || source_row+16'd1<img_h);
    wire want_first=geometry_ok && before_first && lcnt>=17'd24;
    wire want_next=next_ok && lcnt>=go_at+17'd2;
    wire [8:0] target_row=want_first ? 9'd0 : source_row[8:0]+9'd1;
    reg [20:0] row_addr;
    reg [16:0] row_phase;
    wire [16:0] row_sum=row_phase+{1'b0,img_h};
    wire row_advance=!SCALE || row_sum>={1'b0,win_h};
    wire [20:0] next_addr=row_addr+(row_advance ? {5'd0,words_per_row} : 21'd0);
    reg sent;
    reg req_toggle;
    reg [20:0] req_addr;
    reg [15:0] req_words;
    reg [23:0] req_tag;
    reg [1:0] ack_sync,ready_sync;
    reg [1:0] req_sync;
    reg ack_toggle,fetch_pulse;
    wire fl_ready;
    wire mailbox_free=(req_toggle==ack_sync[1]);
    assign cmd_valid=SHARED_WRITER && req_sync[1]!=ack_toggle;
    assign cmd_addr=req_addr;
    assign cmd_words=req_words;
    assign slot_free=fl_ready;
    wire issue=(want_first || want_next) && !sent && mailbox_free && ready_sync[1];
    wire [23:0] expect_tag={frame_id,source_row[8:0]};
    wire [8:0] min_row=(active && y>=win_y) ?
                       source_row[8:0]+((lcnt>go_at) ? 9'd1 : 9'd0) : 9'd0;
    wire [23:0] fl_px;
    wire fl_vld,fl_err,line_done;
    reg stream_busy;
    reg [31:0] gap_c,ferr_c;
    reg err_toggle;
    reg [1:0] err_sync;
    reg err_seen;
    assign idle=mailbox_free && ready_sync[1] && !stream_busy && !issue;
    always @(posedge clk_pix) begin
        if (!rst_pix_n) begin
            row_addr<=0; row_phase<=0; sent<=0; req_toggle<=0; req_addr<=0; req_words<=0; req_tag<=0;
            ack_sync<=0; ready_sync<=0; stream_busy<=0; gap_c<=0; ferr_c<=0;
            err_sync<=0; err_seen<=0;
        end else begin
            ack_sync<={ack_sync[0],ack_toggle}; ready_sync<={ready_sync[0],fl_ready};
            err_sync<={err_sync[0],err_toggle};
            if (err_sync[1]!=err_seen) begin err_seen<=err_sync[1]; ferr_c<=ferr_c+1'b1; end
            if (hs_f || vs_f) sent<=0;
            // Initialize after the scene controller's frame-edge commit.
            if (vln==0 && lcnt==17'd16) begin row_addr<=slot_base; row_phase<=0; end
            else if (hs_f && line_ok) begin
                row_addr<=next_addr;
                if(SCALE) row_phase<=row_advance ? row_sum-{1'b0,win_h} : row_sum;
            end
            if (issue) begin
                req_addr<=want_first ? slot_base : next_addr;
                req_words<=words_per_row; req_tag<={frame_id,target_row};
                req_toggle<=~req_toggle; sent<=1;
            end
            if (go_now) stream_busy<=1;
            if (line_done) stream_busy<=0;
            if (de && line_ok && xcnt>=win_x && xcnt<win_x+win_w && !fl_vld) gap_c<=gap_c+1'b1;
        end
    end
    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin req_sync<=0; ack_toggle<=0; fetch_pulse<=0; err_toggle<=0; end
        else begin
            req_sync<={req_sync[0],req_toggle}; fetch_pulse<=0;
            if(SHARED_WRITER) begin
                if(cmd_ack) ack_toggle<=req_sync[1];
            end else begin
                if (req_sync[1]!=ack_toggle && fl_ready && !fetch_pulse) fetch_pulse<=1;
                if (fetch_pulse) ack_toggle<=req_sync[1];
            end
            if (fl_err) err_toggle<=~err_toggle;
        end
    end
    fetch_line_scene #(.MAX_W(MAX_W),.SHARED_WRITER(SHARED_WRITER),.SCALE(SCALE)) u_fl (
        .clk_sdr(clk_sdr),.rst_sdr_n(rst_sdr_n),.fetch_start(fetch_pulse),
        .row_base(req_addr),.words_per_row(req_words),.fetch_tag(req_tag),.fetch_ready(fl_ready),
        .fetch_busy(),.fetch_err(fl_err),.px_req(px_req),.px_addr(px_addr),.px_len(px_len),
        .px_ack(px_ack),.px_done(px_done),.px_data(px_data),.px_valid(px_valid),
        .clk_pix(clk_pix),.rst_pix_n(rst_pix_n),.px_go(go_now),.expect_tag(expect_tag),
        .frame_id(frame_id),.min_row(min_row),.discard_all(!en),.img_w(img_w),
        .out_w(win_w),.wr_pix(words_per_row),
        .px_out(fl_px),.px_out_vld(fl_vld),.px_line_done(line_done),
        .underrun_cnt(underrun_cnt),.stall_cnt(stall_cnt),.go_cnt(),
        .shared_take(wr_take),.shared_active(wr_active),.shared_done(wr_done),
        .shared_error(wr_error),.shared_we(wr_en),.shared_good(wr_good),
        .shared_addr(wr_addr),.next_bank(next_bank)
    );
    assign dout=fl_px;
    assign dout_vld=de && line_ok && xcnt>=win_x && xcnt<win_x+win_w && fl_vld;
    assign gap_cnt=gap_c;
    assign ferr_cnt=ferr_c;
endmodule
`default_nettype wire
