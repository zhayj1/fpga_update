`default_nettype none
// Shared proportional 4-bit text renderer. A tagged ping-pong row is prepared
// one scanline ahead; late jobs are cancelled during HS, before active video.
module layer_text_aa #(
    parameter integer V_ACT_DLY=35, WIN_Y0=396, WIN_H=72, ROW_Y0=404,
    parameter integer PITCH=32, BOX_X=32, BOX_W=160, TTL_Y0=16, SGR_Y0=48,
    parameter integer FIVE_LINES=0, LRC_X=296, LRC_W=336,
    parameter integer LAST_GAP_TRIM=0, DYNAMIC_COLORS=0,
    parameter integer SPP=1200, HOLD_N=24000, CLK_HZ=150000000,
    parameter [20:0] LRC_BASE=21'h10B300, FONT_BASE=21'h10BBB0,
    parameter [23:0] C_SUNG=24'hFF5FCB, C_UNSUNG=24'hE8E4FF,
        C_NEXT=24'hE8E4FF, C_TTL=24'hFFFFFF, C_SGR=24'hBCC4D2
)(
    input wire clk_pix,rst_pix_n,hs,vs,de,en,en_ttl,
    input wire [23:0] color_title,color_singer,color_sung,color_other,
    output wire [23:0] dout, output wire dout_vld,
    output wire [3:0] alpha,
    output reg [31:0] gap_cnt,on_cnt, output wire [11:0] ttl_off,
    input wire clk_sdr,rst_sdr_n, input wire [23:0] played,
    input wire [15:0] cur_fc,nxt_fc,n3_fc,cur_cnt,nxt_cnt,n3_cnt,
    input wire cur_vld,nxt_vld,n3_vld,
    input wire [15:0] prev2_fc,prev2_cnt,prev_fc,prev_cnt,n4_fc,n4_cnt,
    input wire prev2_vld,prev_vld,n4_vld,song_clear,
    input wire [5:0] off_px, input wire desc_tgl,samp_stb,
    input wire [15:0] ttl_fc,ttl_cnt,sgr_fc,sgr_cnt,
    input wire ttl_vld,sgr_vld,
    output wire px_req, output wire [20:0] px_addr, output wire [15:0] px_len,
    input wire px_ack,px_done, input wire [31:0] px_data, input wire px_valid
);
    // The five-line layout targets the fixed 640x480 raster (525 total lines).
    // Ten-bit blanking underflow remains above every visible text coordinate.
    localparam integer Y_W=FIVE_LINES ? 10 : 16;
    reg [1:0] hd,vd,ds,ack_sync,done_sync,req_sync,line_sync;
    reg req_toggle,ack_toggle,done_toggle,line_toggle;
    reg frame_id;
    reg [Y_W-1:0] vln;
    reg [9:0] xcnt;
    wire hs_f=hd[0] && !hs, vs_f=vd[0] && !vs;
    wire [Y_W-1:0] current_y=vln-V_ACT_DLY;
    wire [Y_W-1:0] new_line_y=vln+1'b1-V_ACT_DLY;
    wire [Y_W-1:0] target_y=vln+2'd2-V_ACT_DLY;
    reg [8:0] s_fc0,s_fc1,s_fc2,s_tfc,s_sfc;
    reg [4:0] s_cnt0,s_cnt1,s_cnt2,s_tcnt,s_scnt;
    reg [8:0] s_p2fc,s_pfc,s_f4fc;
    reg [4:0] s_p2cnt,s_pcnt,s_f4cnt;
    reg s_p2v,s_pv,s_f4v;
    reg s_v0,s_v1,s_v2,s_tv,s_sv;
    reg [5:0] s_off;
    reg want,sm,cur;
    reg [1:0] kind;
    reg [8:0] first;
    reg [4:0] count;
    reg [2:0] lyric_slot;
    reg [4:0] glyph_row;
    reg [Y_W-1:0] top0,top1,top2;
    // With the fixed 32px pitch, low bits select the glyph row and high bits
    // select the sentence. This replaces six separate range/subtract networks.
    wire [Y_W-1:0] lyric_y=target_y+s_off-(ROW_Y0-2*PITCH);
    reg [7:0] slot_base;
    reg [Y_W-1:0] slot_row;
    // A one-pixel shorter fourth gap fits five complete glyphs to the cover.
    // Its sentence moves PITCH-1 pixels; at full scroll every slot coincides
    // with the preceding slot, including the prefetched sixth sentence.
    wire [7:0] fifth_base=4*PITCH-LAST_GAP_TRIM+
        ((LAST_GAP_TRIM!=0 && s_off!=0) ? LAST_GAP_TRIM : 0);
    always @(*) begin
        top0=ROW_Y0-s_off; top1=ROW_Y0+PITCH-s_off; top2=ROW_Y0+2*PITCH-s_off;
        want=0; sm=0; cur=0; kind=0; first=0; count=0; glyph_row=0; lyric_slot=0;
        slot_base=0; slot_row=0;
        if(en_ttl && target_y>=TTL_Y0 && target_y<TTL_Y0+24) begin
            want=s_tv && s_tcnt!=0 && s_tcnt<=24; kind=1;
            first=s_tfc; count=s_tcnt; glyph_row=target_y-TTL_Y0;
        end else if(en_ttl && target_y>=SGR_Y0 && target_y<SGR_Y0+20) begin
            want=s_sv && s_scnt!=0 && s_scnt<=24; kind=2; sm=1;
            first=s_sfc; count=s_scnt; glyph_row=target_y-SGR_Y0;
        end else if(en && target_y>=WIN_Y0 && target_y<WIN_Y0+WIN_H) begin
            if(FIVE_LINES) begin
                if(PITCH==32 && LAST_GAP_TRIM==0) begin
                    glyph_row=lyric_y[4:0]; lyric_slot=lyric_y[7:5];
                    slot_row={5'd0,lyric_y[4:0]};
                end else begin
                    if(lyric_y< PITCH) begin lyric_slot=0; slot_base=0; end
                    else if(lyric_y<2*PITCH) begin lyric_slot=1; slot_base=PITCH; end
                    else if(lyric_y<3*PITCH) begin lyric_slot=2; slot_base=2*PITCH; end
                    else if(lyric_y<fifth_base) begin lyric_slot=3; slot_base=3*PITCH; end
                    else if(lyric_y<5*PITCH-LAST_GAP_TRIM) begin lyric_slot=4; slot_base=fifth_base; end
                    else begin lyric_slot=5; slot_base=5*PITCH-LAST_GAP_TRIM; end
                    slot_row=lyric_y-slot_base;
                    glyph_row=slot_row[4:0];
                end
                if(lyric_y<6*PITCH-LAST_GAP_TRIM && slot_row<24) begin
                    case(lyric_slot)
                    0:begin want=s_p2v; first=s_p2fc; count=s_p2cnt; end
                    1:begin want=s_pv; first=s_pfc; count=s_pcnt; end
                    2:begin want=s_v0; first=s_fc0; count=s_cnt0; cur=1; end
                    3:begin want=s_v1; first=s_fc1; count=s_cnt1; end
                    4:begin want=s_v2; first=s_fc2; count=s_cnt2; end
                    5:begin want=s_f4v; first=s_f4fc; count=s_f4cnt; end
                    default:begin want=0; first=0; count=0; end
                    endcase
                end
            end else if(FIVE_LINES && target_y>=top0-2*PITCH && target_y<top0-2*PITCH+24) begin
                want=s_p2v; first=s_p2fc; count=s_p2cnt;
                glyph_row=target_y-top0+2*PITCH; lyric_slot=0;
            end else if(FIVE_LINES && target_y>=top0-PITCH && target_y<top0-PITCH+24) begin
                want=s_pv; first=s_pfc; count=s_pcnt;
                glyph_row=target_y-top0+PITCH; lyric_slot=1;
            end else if(target_y>=top0 && target_y<top0+24) begin
                want=s_v0 && s_cnt0!=0 && s_cnt0<=19; cur=1;
                first=s_fc0; count=s_cnt0; glyph_row=target_y-top0; lyric_slot=2;
            end else if(target_y>=top1 && target_y<top1+24) begin
                want=s_v1 && s_cnt1!=0 && s_cnt1<=19;
                first=s_fc1; count=s_cnt1; glyph_row=target_y-top1; lyric_slot=3;
            end else if(target_y>=top2 && target_y<top2+24) begin
                want=s_v2 && s_cnt2!=0 && s_cnt2<=19;
                first=s_fc2; count=s_cnt2; glyph_row=target_y-top2; lyric_slot=4;
            end else if(FIVE_LINES && target_y>=top2+PITCH && target_y<top2+PITCH+24) begin
                want=s_f4v; first=s_f4fc; count=s_f4cnt;
                glyph_row=target_y-top2-PITCH; lyric_slot=5;
            end
        end
    end
    // Request mailbox remains stable until acknowledgement. The line mailbox
    // changes only once per HS (hundreds of SDR clocks between changes).
    reg [8:0] r_fc;
    reg [4:0] r_cnt;
    reg [Y_W-1:0] r_y,line_y;
    reg [4:0] r_row;
    reg r_small,r_frame,r_cur,line_frame;
    reg [1:0] r_kind;
    reg [9:0] r_scroll;
    reg [9:0] off_t,off_s,wt,ws,ot1,ot2,os1,os2;
    reg [bits_for(SPP)-1:0] div_count;
    reg [bits_for(HOLD_N+1)-1:0] hold_count;
    reg [15:0] last_tfc,last_sfc,last_tcnt,last_scnt;
    reg title_changed_q,singer_changed_q;
    assign ttl_off={2'd0,off_t};
    reg [Y_W-1:0] c_y,now_y;
    reg [8:0] c_fc;
    reg [4:0] c_cnt;
    reg [2:0] r_slot,c_slot,completed_slot;
    reg c_frame,c_cur,now_frame,working,launch;
    reg [1:0] lyric_epoch,r_epoch,c_epoch,completed_epoch;
    reg [1:0] c_kind;
    reg [9:0] c_scroll;
    reg [4:0] c_row;
    reg c_small;
    wire row_busy,row_done,wr_en;
    wire [7:0] row_error,wr_data;
    wire [9:0] row_width;
    wire [10:0] wr_addr;
    wire line_edge=line_sync[0]^line_sync[1];
    wire expired=(now_frame!=c_frame) || now_y>=c_y;
    wire incoming_expired=(now_frame!=r_frame) || now_y>=r_y;
    // Capture the stable line mailbox first. A 10 ns cancellation delay is
    // entirely inside horizontal blanking and keeps the compare/control in
    // the SDR domain instead of chaining it directly from pixel registers.
    wire cancel_job=working && expired;
    text_row_aa #(.LRC_BASE(LRC_BASE),.FONT_BASE(FONT_BASE),.CLK_HZ(CLK_HZ)) u_row(
        .clk_sdr(clk_sdr),.rst_sdr_n(rst_sdr_n),.start(launch),.cancel(cancel_job),
        .bank(c_y[0]),.small_font(c_small),.fc({7'd0,c_fc}),.cnt({11'd0,c_cnt}),.grow(c_row),.played(played),
        .busy(row_busy),.done(row_done),.err(row_error),.width(row_width),
        .wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),
        .px_req(px_req),.px_addr(px_addr),.px_len(px_len),
        .px_ack(px_ack),.px_done(px_done),.px_valid(px_valid),.px_data(px_data));
    reg [Y_W-1:0] completed_y;
    reg completed_frame,completed_cur;
    reg [1:0] completed_kind;
    reg [9:0] completed_width,completed_scroll;
    always @(posedge clk_sdr) begin
        if(!rst_sdr_n) begin
            req_sync<=0; line_sync<=0; ack_toggle<=0; done_toggle<=0;
            launch<=0; working<=0; c_y<=0; c_fc<=0; c_cnt<=0; c_row<=0;
            c_frame<=0; c_cur<=0; c_kind<=0; c_scroll<=0; c_small<=0;
            now_y<={Y_W{1'b1}}; now_frame<=0;
            completed_y<=0; completed_frame<=0; completed_cur<=0;
            completed_kind<=0; completed_width<=0; completed_scroll<=0;
            c_slot<=0; completed_slot<=0;
            c_epoch<=0; completed_epoch<=0;
            off_t<=0; off_s<=0; wt<=0; ws<=0; div_count<=0; hold_count<=0;
            last_tfc<=16'hFFFF; last_sfc<=16'hFFFF; last_tcnt<=0; last_scnt<=0;
            title_changed_q<=0;singer_changed_q<=0;
        end else begin
            title_changed_q<=ttl_fc!=last_tfc || ttl_cnt!=last_tcnt;
            singer_changed_q<=sgr_fc!=last_sfc || sgr_cnt!=last_scnt;
            last_tfc<=ttl_fc;last_tcnt<=ttl_cnt;
            last_sfc<=sgr_fc;last_scnt<=sgr_cnt;
            req_sync<={req_sync[0],req_toggle}; line_sync<={line_sync[0],line_toggle};
            launch<=0;
            if(line_edge) begin now_y<=line_y; now_frame<=line_frame; end
            if(req_sync[1]!=ack_toggle && !working && !row_busy) begin
                ack_toggle<=req_sync[1];
                if(!incoming_expired) begin
                    c_y<=r_y; c_frame<=r_frame; c_fc<=r_fc; c_cnt<=r_cnt;
                    c_row<=r_row; c_small<=r_small; c_cur<=r_cur;
                    c_kind<=r_kind; c_scroll<=r_scroll; working<=1; launch<=1;
                    c_slot<=r_slot;
                    c_epoch<=r_epoch;
                end
            end
            if(row_done && working) begin
                working<=0;
                if(row_error==0 && !cancel_job) begin
                    completed_y<=c_y; completed_frame<=c_frame;
                    completed_cur<=c_cur; completed_kind<=c_kind;
                    completed_width<=row_width; completed_scroll<=c_scroll;
                    completed_slot<=c_slot;
                    completed_epoch<=c_epoch;
                    done_toggle<=~done_toggle;
                    if(c_kind==1) wt<=row_width;
                    if(c_kind==2) ws<=row_width;
                end
            end
            if(samp_stb) begin
                if(hold_count!=0) hold_count<=hold_count-16'd1;
                else if(div_count<SPP-1) div_count<=div_count+16'd1;
                else begin
                    div_count<=0;
                    off_t<=wt>BOX_W ? (off_t>=wt+BOX_W-1 ? 10'd0 : off_t+10'd1) : 10'd0;
                    off_s<=ws>BOX_W ? (off_s>=ws+BOX_W-1 ? 10'd0 : off_s+10'd1) : 10'd0;
                    if((wt>BOX_W && off_t>=wt+BOX_W-1) ||
                       (ws>BOX_W && off_s>=ws+BOX_W-1)) hold_count<=HOLD_N;
                end
            end
            if(title_changed_q) begin
                off_t<=0; wt<=0;
            end
            if(singer_changed_q) begin
                off_s<=0; ws<=0;
            end
        end
    end
    reg [Y_W-1:0] tag_y0,tag_y1;
    reg tag_f0,tag_f1,tag_v0,tag_v1,tag_c0,tag_c1;
    reg [1:0] tag_k0,tag_k1;
    reg [9:0] tag_w0,tag_w1,tag_o0,tag_o1;
    reg active_ok,active_cur;
    reg [1:0] active_kind;
    reg [9:0] active_width,active_scroll;
    wire this_bank=current_y[0];
    wire tag_match=this_bank ? (tag_v1 && tag_y1==current_y && tag_f1==frame_id) :
                                              (tag_v0 && tag_y0==current_y && tag_f0==frame_id);
    function valid_desc;
        input [15:0] fc,cnt;
        input integer limit;
        begin valid_desc=fc[15:9]==0 && cnt[15:5]==0 && cnt[4:0]!=0 &&
            cnt[4:0]<=limit && ({1'b0,fc[8:0]}+{5'd0,cnt[4:0]}<=10'd488); end
    endfunction
    // Source-domain validation settles one SDR clock after descriptor
    // publication. The existing two-stage pixel toggle capture occurs later;
    // the descriptor bundle remains stable until that capture (same contract).
    reg cur_desc_ok,nxt_desc_ok,n3_desc_ok,ttl_desc_ok,sgr_desc_ok;
    reg prev2_desc_ok,prev_desc_ok,n4_desc_ok;
    always @(posedge clk_sdr) begin
        if(!rst_sdr_n) begin
            cur_desc_ok<=0;nxt_desc_ok<=0;n3_desc_ok<=0;ttl_desc_ok<=0;sgr_desc_ok<=0;
            prev2_desc_ok<=0;prev_desc_ok<=0;n4_desc_ok<=0;
        end else begin
            cur_desc_ok<=cur_vld && valid_desc(cur_fc,cur_cnt,19);
            nxt_desc_ok<=nxt_vld && valid_desc(nxt_fc,nxt_cnt,19);
            n3_desc_ok<=n3_vld && valid_desc(n3_fc,n3_cnt,19);
            ttl_desc_ok<=ttl_vld && valid_desc(ttl_fc,ttl_cnt,24);
            sgr_desc_ok<=sgr_vld && valid_desc(sgr_fc,sgr_cnt,24);
            prev2_desc_ok<=prev2_vld && valid_desc(prev2_fc,prev2_cnt,19);
            prev_desc_ok<=prev_vld && valid_desc(prev_fc,prev_cnt,19);
            n4_desc_ok<=n4_vld && valid_desc(n4_fc,n4_cnt,19);
        end
    end
    // Sample pulses cross as a toggle, at most one transition per 520 pixels.
    // Horizontal phases live in the pixel domain, so no six-wide multibit CDC.
    reg sample_toggle,clear_toggle;
    always @(posedge clk_sdr) begin
        if(!rst_sdr_n) begin sample_toggle<=0; clear_toggle<=0; end
        else begin
            if(samp_stb) sample_toggle<=~sample_toggle;
            if(song_clear && FIVE_LINES) clear_toggle<=~clear_toggle;
        end
    end
    reg [2:0] sample_sync,clear_sync;
    function integer bits_for;
        input integer n;
        integer v;
        begin bits_for=1; for(v=n-1;v>1;v=v>>1) bits_for=bits_for+1; end
    endfunction
    localparam integer STEP_W=bits_for(SPP);
    localparam [9:0] PAUSE_STEPS=(HOLD_N+SPP-1)/SPP;
    localparam [9:0] LYRIC_WINDOW=LRC_W;
    reg [STEP_W-1:0] lyric_div;
    reg [9:0] lyric_phase[0:5];
    reg [8:0] lyric_width[0:5];
    reg phase_busy;
    reg [2:0] phase_slot,phase_origin;
    function [2:0] phase_index;
        input [2:0] origin,slot;
        reg [3:0] sum;
        begin
            sum={1'b0,origin}+{1'b0,slot};
            phase_index=sum>=6 ? sum-4'd6 : sum[2:0];
        end
    endfunction
    wire [9:0] phase_now=lyric_phase[phase_slot];
    wire [8:0] phase_width=lyric_width[phase_slot];
    wire [9:0] phase_end={1'b0,phase_width}+LYRIC_WINDOW+PAUSE_STEPS-10'd1;
    integer li;
    wire desc_edge=ds[0]^ds[1];
    wire line_changed=cur_fc[8:0]!=s_fc0 || cur_cnt[4:0]!=s_cnt0 || cur_vld!=s_v0;
    wire next_is_current=s_v1 && cur_vld && cur_fc[8:0]==s_fc1 && cur_cnt[4:0]==s_cnt1;
    wire [2:0] selected_phase_index=phase_index(phase_origin,lyric_slot);
    wire [2:0] completed_phase_index=phase_index(phase_origin,completed_slot);
    reg line_changed_q,next_is_current_q;
    always @(posedge clk_pix) begin
        if(!rst_pix_n) begin line_changed_q<=0; next_is_current_q<=0; end
        else begin line_changed_q<=line_changed; next_is_current_q<=next_is_current; end
    end
    wire phase_rebase=desc_edge && line_changed_q;
    wire phase_clear=clear_sync[2]^clear_sync[1];
    wire [9:0] selected_phase=lyric_phase[selected_phase_index];
    wire [9:0] lyric_offset=selected_phase<PAUSE_STEPS ? 10'd0 : selected_phase-PAUSE_STEPS;
    always @(posedge clk_pix) begin
        if(!rst_pix_n) begin
            sample_sync<=0; clear_sync<=0; lyric_div<=0;
            phase_busy<=0;phase_slot<=0;phase_origin<=0;
            for(li=0;li<6;li=li+1) begin lyric_phase[li]<=0; lyric_width[li]<=0; end
        end else if(FIVE_LINES) begin
            sample_sync<={sample_sync[1:0],sample_toggle};
            clear_sync<={clear_sync[1:0],clear_toggle};
            if(sample_sync[2]^sample_sync[1]) begin
                if(lyric_div==SPP-1) begin
                    lyric_div<=0;
                    phase_busy<=1;phase_slot<=0;
                end else lyric_div<=lyric_div+1'b1;
            end
            // Six updates share one adder/comparator, completing in 240 ns.
            if(phase_busy && !phase_rebase && !phase_clear) begin
                lyric_phase[phase_slot]<=phase_width>LRC_W ?
                    (phase_now>=phase_end ? 10'd0 : phase_now+10'd1) : 10'd0;
                if(phase_slot==5) phase_busy<=0;
                else phase_slot<=phase_slot+3'd1;
            end
            if((done_sync[0]^done_sync[1]) && !phase_rebase && !phase_clear)
                if(completed_kind==0 && completed_epoch==lyric_epoch)
                    lyric_width[completed_phase_index]<=completed_width[8:0];
            // Advance a circular origin instead of moving 114 register bits.
            // The departing first sentence's storage becomes the new sixth.
            if(phase_rebase) begin
                phase_busy<=0;
                if(next_is_current_q) begin
                    phase_origin<=phase_origin==5 ? 3'd0 : phase_origin+3'd1;
                    lyric_phase[phase_origin]<=0; lyric_width[phase_origin]<=0;
                end else begin
                    phase_origin<=0;
                    for(li=0;li<6;li=li+1) begin lyric_phase[li]<=0; lyric_width[li]<=0; end
                end
            end
            if(phase_clear) begin
                phase_busy<=0;
                lyric_div<=0;phase_origin<=0;
                for(li=0;li<6;li=li+1) begin lyric_phase[li]<=0; lyric_width[li]<=0; end
            end
        end
    end
    always @(posedge clk_pix) begin
        if(!rst_pix_n) begin
            hd<=0; vd<=0; ds<=0; ack_sync<=0; done_sync<=0; req_toggle<=0; line_toggle<=0;
            frame_id<=0; vln<=0; xcnt<=0; line_y<=0; line_frame<=0;
            s_fc0<=0; s_fc1<=0; s_fc2<=0; s_cnt0<=0; s_cnt1<=0; s_cnt2<=0;
            s_tfc<=0; s_sfc<=0; s_tcnt<=0; s_scnt<=0;
            s_v0<=0; s_v1<=0; s_v2<=0; s_tv<=0; s_sv<=0; s_off<=0;
            s_p2fc<=0; s_pfc<=0; s_f4fc<=0; s_p2cnt<=0; s_pcnt<=0; s_f4cnt<=0;
            s_p2v<=0; s_pv<=0; s_f4v<=0; r_slot<=0;
            lyric_epoch<=0; r_epoch<=0;
            r_fc<=0; r_cnt<=0; r_y<=0; r_row<=0; r_small<=0; r_frame<=0;
            r_cur<=0; r_kind<=0; r_scroll<=0; ot1<=0; ot2<=0; os1<=0; os2<=0;
            tag_y0<=0; tag_y1<=0; tag_f0<=0; tag_f1<=0; tag_v0<=0; tag_v1<=0;
            tag_c0<=0; tag_c1<=0; tag_k0<=0; tag_k1<=0;
            tag_w0<=0; tag_w1<=0; tag_o0<=0; tag_o1<=0;
            active_ok<=0; active_cur<=0; active_kind<=0; active_width<=0; active_scroll<=0;
            gap_cnt<=0; on_cnt<=0;
        end else begin
            hd<={hd[0],hs}; vd<={vd[0],vs}; ds<={ds[0],desc_tgl};
            ack_sync<={ack_sync[0],ack_toggle}; done_sync<={done_sync[0],done_toggle};
            ot1<=off_t; ot2<=ot1; os1<=off_s; os2<=os1;
            if(de) xcnt<=xcnt+10'd1; else xcnt<=0;
            if(FIVE_LINES && (phase_rebase || (clear_sync[2]^clear_sync[1])))
                lyric_epoch<=lyric_epoch+2'd1;
            if(vs_f) begin vln<=0; frame_id<=~frame_id; tag_v0<=0; tag_v1<=0; end
            else if(hs_f) vln<=vln+1'b1;
            if(ds[0]^ds[1]) begin
                s_fc0<=cur_fc[8:0]; s_fc1<=nxt_fc[8:0]; s_fc2<=n3_fc[8:0];
                s_cnt0<=cur_cnt[4:0]; s_cnt1<=nxt_cnt[4:0]; s_cnt2<=n3_cnt[4:0];
                s_v0<=cur_desc_ok;
                s_v1<=nxt_desc_ok;
                s_v2<=n3_desc_ok; s_off<=off_px;
                s_tfc<=ttl_fc[8:0]; s_tcnt<=ttl_cnt[4:0]; s_tv<=ttl_desc_ok;
                s_sfc<=sgr_fc[8:0]; s_scnt<=sgr_cnt[4:0]; s_sv<=sgr_desc_ok;
                s_p2fc<=prev2_fc[8:0]; s_p2cnt<=prev2_cnt[4:0];
                s_pfc<=prev_fc[8:0]; s_pcnt<=prev_cnt[4:0];
                s_f4fc<=n4_fc[8:0]; s_f4cnt<=n4_cnt[4:0];
                s_p2v<=FIVE_LINES && prev2_desc_ok;
                s_pv<=FIVE_LINES && prev_desc_ok;
                s_f4v<=FIVE_LINES && n4_desc_ok;
            end
            if(hs_f && !vs_f) begin
                line_y<=new_line_y; line_frame<=frame_id; line_toggle<=~line_toggle;
                if(want && req_toggle==ack_sync[1]) begin
                    r_fc<=first; r_cnt<=count; r_row<=glyph_row; r_small<=sm;
                    r_y<=target_y; r_frame<=frame_id; r_cur<=cur; r_kind<=kind;
                    r_scroll<=kind==1 ? ot2 : (kind==2 ? os2 : (FIVE_LINES ? lyric_offset : 10'd0));
                    r_slot<=lyric_slot;
                    r_epoch<=lyric_epoch;
                    req_toggle<=~req_toggle;
                end
            end
            if(done_sync[0]^done_sync[1]) begin
                if(completed_y[0]) begin
                    tag_y1<=completed_y; tag_f1<=completed_frame; tag_v1<=1;
                    tag_w1<=completed_width; tag_o1<=completed_scroll;
                    tag_c1<=completed_cur; tag_k1<=completed_kind;
                end else begin
                    tag_y0<=completed_y; tag_f0<=completed_frame; tag_v0<=1;
                    tag_w0<=completed_width; tag_o0<=completed_scroll;
                    tag_c0<=completed_cur; tag_k0<=completed_kind;
                end
            end
            // Metadata is frozen throughout DE, even if another job completes.
            if(!de) begin
                active_ok<=tag_match;
                active_width<=this_bank ? tag_w1 : tag_w0;
                active_scroll<=this_bank ? tag_o1 : tag_o0;
                active_cur<=this_bank ? tag_c1 : tag_c0;
                active_kind<=this_bank ? tag_k1 : tag_k0;
            end
            if(de && dout_vld) on_cnt<=on_cnt+32'd1;
            if(hs_f && req_toggle!=ack_sync[1]) gap_cnt<=gap_cnt+32'd1;
        end
    end
    // The synchronous RAM receives the next pixel's address. During blanking
    // pixel zero is prefetched, matching the established raster convention.
    wire [9:0] read_x=de ? xcnt+10'd1 : 10'd0;
    wire lyric_long=active_width>LRC_W;
    wire [9:0] left=FIVE_LINES ? LRC_X+((LRC_W-active_width)>>1) : (10'd640-active_width)>>1;
    wire [9:0] window_x=(active_kind==0 && FIVE_LINES) ? LRC_X : BOX_X;
    wire [9:0] window_w=(active_kind==0 && FIVE_LINES) ? LRC_W : BOX_W;
    wire scrolling=active_kind!=0 || (FIVE_LINES && lyric_long);
    wire [10:0] relative_x={1'b0,read_x}-{1'b0,window_x};
    wire [10:0] scroll_x=relative_x+{1'b0,active_scroll};
    wire [10:0] wrapped=scroll_x>=active_width+window_w ? scroll_x-active_width-window_w : scroll_x;
    wire [10:0] source_x=scrolling ? wrapped : {1'b0,read_x}-{1'b0,left};
    wire [9:0] read_index=source_x[9:0];
    // Prefetch the geometric mask with the synchronous RAM pixel. Sharing the
    // source coordinate removes a second complete wrap/subtract datapath.
    wire next_inside=source_x<{1'b0,active_width} && (!scrolling ||
        (read_x>=window_x && read_x<window_x+window_w));
    reg pixel_inside;
    always @(posedge clk_pix) begin
        if(!rst_pix_n) pixel_inside<=0;
        else pixel_inside<=next_inside;
    end
    wire [10:0] read_addr={this_bank,read_index};
    wire [7:0] memory_pixel;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),.IMPLEMENT("32K")
    ) u_line(.clka(clk_sdr),.cea(1'b1),.ocea(1'b0),.wea(wr_en),
        .addra(wr_addr),.dia(wr_data),.doa(),.rsta(1'b0),.bea(1'b0),
        .clkb(clk_pix),.ceb(1'b1),.oceb(1'b1),.web(1'b0),
        .addrb(read_addr),.dib(8'd0),.dob(memory_pixel),.rstb(1'b0),.beb(1'b0));
    wire inside=(active_kind==0 ? en : en_ttl) && pixel_inside;
    assign alpha=(de && active_ok && inside) ? memory_pixel[3:0] : 4'd0;
    assign dout_vld=|alpha;
    wire [23:0] legacy_rgb;
    assign legacy_rgb=active_kind==1 ? C_TTL : active_kind==2 ? C_SGR :
                active_cur ? (memory_pixel[4] ? C_SUNG : C_UNSUNG) : C_NEXT;
    assign dout=DYNAMIC_COLORS ?
        (active_kind==1?color_title:active_kind==2?color_singer:
         (active_cur && memory_pixel[4])?color_sung:color_other) : legacy_rgb;
endmodule
`default_nettype wire
