`default_nettype none
// Five nonpreemptive clients: current BG/CV, text, previous BG/CV.
// Round robin bounds text/image starvation. Each owner persists through done.
module px_arb5(
    input wire clk_sdr,rst_sdr_n,
    input wire [4:0] c_req,
    input wire [104:0] c_addr,
    input wire [79:0] c_len,
    output wire [4:0] c_ack,c_done,c_valid,
    output reg arb_req,
    output reg [20:0] arb_addr,
    output reg [15:0] arb_len,
    input wire arb_ack,arb_done,arb_valid,
    output reg [31:0] grant_cnt,contend_cnt
);
    reg busy;
    reg [2:0] sel,rr,pick;
    reg found;
    integer i,k;
    always @* begin
        found=0; pick=0;
        for (i=0;i<5;i=i+1) begin
            k=rr+i;
            if (k>=5) k=k-5;
            if (!found && c_req[k]) begin pick=k; found=1; end
        end
    end
    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            busy<=0; sel<=0; rr<=0; arb_req<=0; arb_addr<=0; arb_len<=0;
            grant_cnt<=0; contend_cnt<=0;
        end else begin
            if ((c_req & (c_req-5'd1))!=0) contend_cnt<=contend_cnt+1'b1;
            if (!busy) begin
                arb_req<=found;
                if (found) begin
                    sel<=pick; busy<=1; arb_addr<=c_addr[pick*21+:21];
                    arb_len<=c_len[pick*16+:16]; grant_cnt<=grant_cnt+1'b1;
                end
            end else begin
                if (arb_ack) arb_req<=0;
                if (arb_done) begin
                    busy<=0; arb_req<=0; rr<=(sel==4) ? 3'd0 : sel+3'd1;
                end
            end
        end
    end
    assign c_ack=(busy && arb_ack) ? (5'b1<<sel) : 5'd0;
    assign c_done=(busy && arb_done) ? (5'b1<<sel) : 5'd0;
    assign c_valid=(busy && arb_valid) ? (5'b1<<sel) : 5'd0;
endmodule
`default_nettype wire
