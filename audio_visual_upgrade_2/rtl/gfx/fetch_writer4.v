`default_nettype none
// One nonpreemptive SDRAM writer for four independent double-bank row caches.
// cmd_* is a bundled-data mailbox: metadata is captured on cmd_ack, never later.
// Each cache retains its tag/consumption CDC and cannot accept until slot_free.
// Only this engine owns SDRAM counts/addresses. RR advances even on bad commands.
module fetch_writer4 #(
    parameter integer MAX_W0=640,MAX_W1=320,MAX_W2=640,MAX_W3=320
)(
    input wire clk_sdr,rst_sdr_n,
    input wire [3:0] cmd_valid,slot_free,next_bank,
    input wire [83:0] cmd_addr,
    input wire [63:0] cmd_words,
    output wire [3:0] cmd_ack,wr_take,wr_active,wr_done,wr_error,wr_en,
    output wire [9:0] wr_addr,
    output wire wr_good,
    output reg px_req,
    output reg [20:0] px_addr,
    output reg [15:0] px_len,
    input wire px_ack,px_done,px_valid
);
    localparam integer W0=((MAX_W0*3+15)/16)*4,W1=((MAX_W1*3+15)/16)*4;
    localparam integer W2=((MAX_W2*3+15)/16)*4,W3=((MAX_W3*3+15)/16)*4;
    localparam [1:0] IDLE=0,SELECT=1,RUN=2,FIN=3;
    reg [1:0] st,owner,rr,pick;
    reg found;
    reg [8:0] max_words;
    reg [9:0] base;
    reg [8:0] idx,nwords;
    reg good;
    integer i,k;
    wire [15:0] selected_words=cmd_words[owner*16+:16];
    wire legal=selected_words!=0 && selected_words<={7'd0,max_words};
    // Reserve the owner before checking its payload. The request mailbox stays
    // valid and stable until SELECT acknowledges it; no other writer can claim
    // its free bank during this extra cycle. This breaks the RR-to-ACK path.
    wire take=rst_sdr_n && st==SELECT;
    wire [3:0] owner_mask=4'b0001<<owner;
    always @* begin
        found=0; pick=0;
        for(i=0;i<4;i=i+1) begin
            k=(rr+i)&3;
            if(!found && cmd_valid[k] && slot_free[k]) begin found=1; pick=k; end
        end
        case(owner)
            0:max_words=W0;
            1:max_words=W1;
            2:max_words=W2;
            default:max_words=W3;
        endcase
    end
    assign cmd_ack=take ? owner_mask : 4'd0;
    assign wr_take=take && legal ? owner_mask : 4'd0;
    assign wr_active=(st==RUN || st==FIN) ? owner_mask : 4'd0;
    assign wr_done=st==FIN ? owner_mask : 4'd0;
    assign wr_error=(take && !legal ? owner_mask : 4'd0) |
                    (st==FIN && !good ? owner_mask : 4'd0);
    assign wr_en=st==RUN && px_valid && idx<nwords ? owner_mask : 4'd0;
    assign wr_addr=base+{1'b0,idx};
    assign wr_good=good;
    always @(posedge clk_sdr) begin
        if(!rst_sdr_n) begin
            st<=IDLE; owner<=0; rr<=0; base<=0; idx<=0; nwords<=0; good<=0;
            px_req<=0; px_addr<=0; px_len<=0;
        end else case(st)
            IDLE: if(found) begin owner<=pick; st<=SELECT; end
            SELECT: begin
                rr<=owner+2'd1;
                if(legal) begin
                    idx<=0; nwords<=selected_words[8:0];
                    base<=next_bank[owner] ? {1'b0,max_words}+10'd1 : 10'd0;
                    px_addr<=cmd_addr[owner*21+:21]; px_len<=selected_words;
                    px_req<=1; good<=0; st<=RUN;
                end else st<=IDLE;
            end
            RUN: begin
                if(px_ack) px_req<=0;
                // Saturate one beyond the expected count: reject overlong bursts.
                if(px_valid && idx<=nwords) idx<=idx+1'b1;
                if(px_done) begin
                    px_req<=0; st<=FIN;
                    good<=({1'b0,idx}+{9'd0,px_valid}=={1'b0,nwords});
                end
            end
            FIN: st<=IDLE;
            default: begin st<=IDLE; px_req<=0; end
        endcase
    end
endmodule
`default_nettype wire
