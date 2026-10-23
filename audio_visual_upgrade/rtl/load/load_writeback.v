`default_nettype none
// A task owns this byte FIFO until END and the last SDRAM DONE agree.
// Internal counters use four-word (16-byte) units, the ERAM write granule.
module load_writeback (
    input wire clk, input wire rst_n,
    input wire clk_sdr, input wire rst_sdr_n,
    input wire flush, input wire byte_we, input wire [7:0] byte_data,
    output wire full,
    input wire cfg_valid, input wire [20:0] cfg_first,
    input wire [18:0] cfg_words, input wire [15:0] cfg_wpr,
    input wire cfg_rows, input wire cfg_down,
    input wire finish_valid, input wire [18:0] finish_words,
    output reg done,
    output reg ld_req, output reg [20:0] ld_addr,
    output reg [15:0] ld_len, output wire [31:0] ld_data,
    input wire ld_take, input wire ld_ack, input wire ld_done
);
    reg cfg_toggle, end_toggle, done_toggle;
    // Bundled-data mailbox: the selected format frontend already registers
    // CFG and END fields and holds them through backend DONE. Reuse those
    // registers; only the event toggles need independent synchronizers here.
    wire [20:0] first_hold=cfg_first;
    wire [16:0] words_hold=cfg_words[18:2], end_hold=finish_words[18:2];
    wire [13:0] wpr_hold=cfg_wpr[15:2];
    wire rows_hold=cfg_rows, down_hold=cfg_down;
    reg [1:0] done_sync;
    reg done_seen;
    always @(posedge clk) begin
        if (!rst_n) begin
            cfg_toggle<=0; end_toggle<=0; done_sync<=0; done_seen<=0; done<=0;
        end else begin
            done_sync<={done_sync[0],done_toggle};
            done<=done_sync[1]!=done_seen;
            done_seen<=done_sync[1];
            if(cfg_valid) begin
                cfg_toggle<=~cfg_toggle;
            end
            if(finish_valid) end_toggle<=~end_toggle;
        end
    end
    wire [7:0] usedw;
    afifo_8i_32o_bram #(
        .DATA_WIDTH_W(8),.DATA_WIDTH_R(32),.ADDR_WIDTH_W(10),.ADDR_WIDTH_R(8),
        .AL_FULL_NUM(1021),.AL_EMPTY_NUM(2),.SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")
    ) u_fifo (
        .rst((~rst_n)|(~rst_sdr_n)|flush),.clkw(clk),.clkr(clk_sdr),
        .we(byte_we),.di(byte_data),.re(ld_take),.dout(ld_data),.full_flag(full),
        .rdusedw(usedw),.valid(),.empty_flag(),.afull(),.aempty(),.wrusedw()
    );
    localparam [2:0] IDLE=0,REQ=1,RUN=2,ACCOUNT=3,ROWSTEP=4,
                     CALC=5,READY=6;
    reg [2:0] bst;
    reg [1:0] cfg_sync,end_sync;
    reg cfg_seen,end_seen,armed,ended,rows,down;
    reg [16:0] total_groups,done_groups;
    reg [13:0] row_groups,offset_groups;
    reg [16:0] remaining_r;
    reg [13:0] row_left_r;
    reg [5:0] want_r;
    reg [18:0] base_groups;
    reg [1:0] base_low;
    wire [16:0] limit_groups=total_groups;
    wire [13:0] row_left_groups=row_groups-offset_groups;
    wire [5:0] total_want=(|remaining_r[16:5]) ? 6'd32 : {1'b0,remaining_r[4:0]};
    wire [5:0] want=(rows && row_left_r<{8'd0,total_want}) ? row_left_r[5:0] : total_want;
    // END already supplies the exact complete-granule count. Waiting for the
    // entire next burst also handles short input without an available/min mux.
    wire enough=usedw[7:2]>=want_r;
    wire cfg_pending=cfg_sync[1]!=cfg_seen;
    wire end_pending=end_sync[1]!=end_seen;
    wire [5:0] burst_groups=ld_len[7:2];
    wire row_end=row_left_groups=={8'd0,burst_groups};
    // Address calculation and row stepping share this one add/sub datapath.
    wire step_row=bst==ROWSTEP;
    wire sub_row=step_row && rows && down;
    wire [13:0] address_step=rows ? row_groups : {8'd0,burst_groups};
    wire [18:0] add_operand={5'd0,(step_row ? address_step : offset_groups)};
    wire [18:0] address_sum=base_groups+(add_operand^{19{sub_row}})+sub_row;
    // Observation names retain word units for existing integration diagnostics.
    wire [18:0] c_words={total_groups,2'b00};
    wire [18:0] wdone={done_groups,2'b00};
    wire [18:0] stop_words={limit_groups,2'b00};
    wire [15:0] c_wpr={row_groups,2'b00};
    wire [15:0] roff={offset_groups,2'b00};
    wire [15:0] blen=ld_len;
    wire [20:0] cbase={base_groups,base_low};
    always @(posedge clk_sdr) begin
        if(!rst_sdr_n) begin
            bst<=IDLE;cfg_sync<=0;end_sync<=0;cfg_seen<=0;end_seen<=0;
            armed<=0;ended<=0;done_toggle<=0;total_groups<=0;done_groups<=0;
            row_groups<=0;offset_groups<=0;remaining_r<=0;row_left_r<=0;want_r<=0;
            base_groups<=0;base_low<=0;rows<=0;down<=0;
            ld_req<=0;ld_addr<=0;ld_len<=0;
        end else begin
            cfg_sync<={cfg_sync[0],cfg_toggle};end_sync<={end_sync[0],end_toggle};
            ld_req<=0;
            case(bst)
            IDLE:if(armed && !cfg_pending && !end_pending) begin
                if(ended && done_groups>=limit_groups) begin armed<=0;done_toggle<=~done_toggle;end
                else if(done_groups<limit_groups) begin
                    remaining_r<=limit_groups-done_groups;
                    row_left_r<=row_left_groups;
                    bst<=CALC;
                end
            end
            CALC:if(cfg_pending || end_pending) bst<=IDLE;
                 else begin want_r<=want;bst<=READY;end
            READY:if(cfg_pending || end_pending) bst<=IDLE;
                  else if(armed && want_r!=0 && enough) begin
                      ld_addr<={address_sum,base_low};ld_len<={8'd0,want_r,2'b00};bst<=REQ;
                  end
            REQ:begin ld_req<=1;if(ld_ack)begin ld_req<=0;bst<=ld_done ? ACCOUNT : RUN;end end
            RUN:if(ld_done)bst<=ACCOUNT;
            ACCOUNT:begin
                done_groups<=done_groups+{11'd0,burst_groups};
                if(!rows || row_end) begin offset_groups<=0;bst<=ROWSTEP;end
                else begin offset_groups<=offset_groups+{8'd0,burst_groups};bst<=IDLE;end
            end
            ROWSTEP:begin base_groups<=address_sum;bst<=IDLE;end
            default:bst<=IDLE;
            endcase
            if(cfg_sync[1]!=cfg_seen)begin
                cfg_seen<=cfg_sync[1];base_groups<=first_hold[20:2];base_low<=first_hold[1:0];
                total_groups<=words_hold;row_groups<=wpr_hold;rows<=rows_hold;down<=down_hold;
                offset_groups<=0;done_groups<=0;ended<=0;armed<=1;
            end
            if(end_sync[1]!=end_seen)begin end_seen<=end_sync[1];ended<=1;total_groups<=end_hold;end
        end
    end
endmodule
`default_nettype wire
