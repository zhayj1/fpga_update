`default_nettype none
// One completed row mailbox; two banks. Completed metadata stays stable until
// pixel retirement returns through two flops. Tags reject late/old-frame rows.
// Both domains reset together. The RAM itself is deliberately not reset.
module fetch_line_scene #(parameter integer MAX_W=640,SHARED_WRITER=0)(
    input wire clk_sdr,rst_sdr_n,fetch_start,
    input wire [20:0] row_base,
    input wire [15:0] words_per_row,
    input wire [23:0] fetch_tag,
    output wire fetch_ready,
    output reg fetch_busy,fetch_err,px_req,
    output reg [20:0] px_addr,
    output reg [15:0] px_len,
    input wire px_ack,px_done,
    input wire [31:0] px_data,
    input wire px_valid,
    input wire clk_pix,rst_pix_n,px_go,
    input wire [23:0] expect_tag,
    input wire [14:0] frame_id,
    input wire [8:0] min_row,
    input wire discard_all,
    input wire [15:0] img_w,wr_pix,
    output reg [23:0] px_out,
    output reg px_out_vld,px_line_done,
    output reg [31:0] underrun_cnt,go_cnt,
    output wire [31:0] stall_cnt,
    input wire shared_take,shared_active,shared_done,shared_error,shared_we,shared_good,
    input wire [9:0] shared_addr,
    output wire next_bank
);
    function integer clog2f;
        input integer n;
        integer v;
        begin clog2f=0; for(v=n-1;v>0;v=v>>1) clog2f=clog2f+1; end
    endfunction
    localparam integer WORDS=((MAX_W*3+15)/16)*4,STRIDE=WORDS+1;
    localparam integer AW=clog2f(2*STRIDE),CW=clog2f(WORDS+1),XW=clog2f(MAX_W+1);
    localparam [1:0] F_IDLE=0,F_RUN=1,F_FIN=2;
    reg [1:0] fst;
    reg [CW-1:0] wr_idx,nw_l;
    reg [AW-1:0] wr_base;
    reg wr_buf_l,cur_rd_buf,rdy_buf,rdy_valid,rdy_tgl,cons_tgl,cons_seen;
    reg [1:0] cons_s;
    reg [23:0] tag_l,rdy_tag;
    reg row_good,rdy_good;
    wire param_ok=words_per_row!=0 && words_per_row<=WORDS;
    assign fetch_ready=SHARED_WRITER ? (!shared_active && !rdy_valid) :
                                      ((fst==F_IDLE) && !fetch_busy && !rdy_valid);
    assign next_bank=~cur_rd_buf;
    wire mem_we=SHARED_WRITER ? shared_we : ((fst==F_RUN) && px_valid && wr_idx<nw_l);
    wire [AW-1:0] mem_addra=SHARED_WRITER ? shared_addr : wr_base+wr_idx;
    wire [AW-1:0] mem_addrb;
    wire [31:0] mem_dob;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
        .DATA_DEPTH_A(1<<AW),.DATA_DEPTH_B(1<<AW),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),.IMPLEMENT("9K")
    ) u_linebuf(
        .dia(px_data),.addra(mem_addra),.cea(1'b1),.ocea(1'b0),.clka(clk_sdr),
        .wea(mem_we),.rsta(1'b0),.bea(1'b0),.doa(),
        .dib(32'd0),.addrb(mem_addrb),.ceb(1'b1),.oceb(1'b1),.clkb(clk_pix),
        .web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(mem_dob));
    generate if(SHARED_WRITER) begin: g_shared
        always @* begin
            fetch_busy=shared_active; fetch_err=shared_error;
            px_req=0; px_addr=0; px_len=0;
        end
        always @(posedge clk_sdr) begin
            if(!rst_sdr_n) begin
                wr_buf_l<=0; cur_rd_buf<=0; rdy_buf<=0; rdy_valid<=0; rdy_tgl<=0;
                cons_seen<=0; cons_s<=0; rdy_tag<=0; rdy_good<=0;
            end else begin
                cons_s<={cons_s[0],cons_tgl};
                if(cons_s[1]!=cons_seen) begin
                    cons_seen<=cons_s[1]; rdy_valid<=0; cur_rd_buf<=~cur_rd_buf;
                end
                if(shared_take) begin
                    wr_buf_l<=~cur_rd_buf; rdy_buf<=~cur_rd_buf; rdy_tag<=fetch_tag;
                end
                if(shared_done) begin
                    rdy_good<=shared_good; rdy_tgl<=~rdy_tgl; rdy_valid<=1;
                end
            end
        end
    end else begin: g_local
    always @(posedge clk_sdr) begin
        if(!rst_sdr_n) begin
            fst<=F_IDLE; wr_idx<=0; nw_l<=0; wr_base<=0; wr_buf_l<=0; cur_rd_buf<=0;
            rdy_buf<=0; rdy_valid<=0; rdy_tgl<=0; cons_seen<=0; cons_s<=0;
            tag_l<=0; rdy_tag<=0; row_good<=0; rdy_good<=0;
            fetch_busy<=0; fetch_err<=0; px_req<=0; px_addr<=0; px_len<=0;
        end else begin
            fetch_err<=0; cons_s<={cons_s[0],cons_tgl};
            if(cons_s[1]!=cons_seen) begin
                cons_seen<=cons_s[1]; rdy_valid<=0; cur_rd_buf<=~cur_rd_buf;
            end
            case(fst)
                F_IDLE: if(fetch_start) begin
                    if(fetch_ready && param_ok) begin
                        wr_idx<=0; nw_l<=words_per_row[CW-1:0]; wr_buf_l<=~cur_rd_buf;
                        wr_base<=(~cur_rd_buf)?STRIDE:0;
                        tag_l<=fetch_tag; row_good<=0; px_addr<=row_base;
                        px_len<=words_per_row; px_req<=1; fetch_busy<=1; fst<=F_RUN;
                    end else fetch_err<=1;
                end
                F_RUN: begin
                    if(px_ack) px_req<=0;
                    if(px_valid && wr_idx<nw_l) wr_idx<=wr_idx+1'b1;
                    if(px_done) begin
                        px_req<=0; fst<=F_FIN;
                        row_good<=({1'b0,wr_idx}+(px_valid?1'b1:1'b0)=={1'b0,nw_l});
                        if({1'b0,wr_idx}+(px_valid?1'b1:1'b0)!={1'b0,nw_l}) fetch_err<=1;
                    end
                end
                F_FIN: begin
                    rdy_buf<=wr_buf_l; rdy_tag<=tag_l; rdy_good<=row_good;
                    rdy_tgl<=~rdy_tgl; rdy_valid<=1; fetch_busy<=0; fst<=F_IDLE;
                end
                default: fst<=F_IDLE;
            endcase
        end
    end
    end endgenerate
    // RGB888 byte lanes repeat 0,3,2,1. Read word indices repeat 0,1,2,2,
    // 3,4,5,5,... . At lanes 3/2 the preceding word supplies the low bytes;
    // lanes 0/1 fit within the current BRAM output. No FIFO or barrel shifter.
    localparam [1:0] P_IDLE=0,P_PRIME=1,P_RUN=2;
    reg [1:0] pst,rdy_s,rdy_buf_s,lane;
    reg rdy_seen,rd_buf,stream_on,line_ok;
    reg [2:0] prime;
    reg [XW-1:0] x,width_l;
    reg [CW-1:0] rd_ptr;
    reg [31:0] previous_word;
    reg [23:0] selected_pixel;
    assign mem_addrb=(rd_buf?STRIDE:0)+rd_ptr;
    assign stall_cnt=32'd0; // Fixed-rate RAM schedule has no variable queue.
    always @* begin
        case(lane)
            0:selected_pixel={mem_dob[7:0],mem_dob[15:8],mem_dob[23:16]};
            3:selected_pixel={previous_word[31:24],mem_dob[7:0],mem_dob[15:8]};
            2:selected_pixel={previous_word[23:16],previous_word[31:24],mem_dob[7:0]};
            1:selected_pixel={mem_dob[15:8],mem_dob[23:16],mem_dob[31:24]};
        endcase
    end
    always @(posedge clk_pix) begin
        if(!rst_pix_n) begin
            pst<=P_IDLE; rdy_s<=0; rdy_buf_s<=0; lane<=0; rdy_seen<=0; rd_buf<=0;
            stream_on<=0; line_ok<=0; prime<=0; x<=0; width_l<=0; rd_ptr<=0;
            previous_word<=0; cons_tgl<=0; px_out<=0; px_out_vld<=0;
            px_line_done<=0; underrun_cnt<=0; go_cnt<=0;
        end else begin
            rdy_s<={rdy_s[0],rdy_tgl}; rdy_buf_s<={rdy_buf_s[0],rdy_buf};
            px_line_done<=0; px_out_vld<=0;
            case(pst)
                P_IDLE: begin
                    if(!px_go && rdy_s[1]!=rdy_seen &&
                       (discard_all || rdy_tag[23:9]!=frame_id || rdy_tag[8:0]<min_row)) begin
                        rdy_seen<=rdy_s[1]; rd_buf<=rdy_buf_s[1]; cons_tgl<=~cons_tgl;
                    end
                    if(px_go) begin
                        go_cnt<=go_cnt+1'b1; x<=0; lane<=0; rd_ptr<=0; prime<=4;
                        width_l<=img_w[XW-1:0]; line_ok<=0; previous_word<=0;
                        if(rdy_s[1]!=rdy_seen) begin
                            rdy_seen<=rdy_s[1]; rd_buf<=rdy_buf_s[1]; cons_tgl<=~cons_tgl;
                            line_ok<=rdy_good && rdy_tag==expect_tag;
                        end
                        if(rdy_s[1]==rdy_seen || !rdy_good || rdy_tag!=expect_tag)
                            underrun_cnt<=underrun_cnt+1'b1;
                        if(img_w==0 || img_w>MAX_W) px_line_done<=1;
                        else begin stream_on<=1; pst<=P_PRIME; end
                    end
                end
                P_PRIME: begin
                    prime<=prime-1'b1;
                    if(prime==1) begin pst<=P_RUN; rd_ptr<=1; end
                end
                P_RUN: begin
                    previous_word<=mem_dob; px_out<=selected_pixel; px_out_vld<=line_ok;
                    if(lane!=3) rd_ptr<=rd_ptr+1'b1;
                    lane<=lane-1'b1; x<=x+1'b1;
                    if(x+1'b1>=width_l) begin
                        pst<=P_IDLE; stream_on<=0; px_line_done<=1;
                    end
                end
                default: pst<=P_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
