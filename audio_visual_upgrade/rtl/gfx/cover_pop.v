`default_nettype none
module cover_pop(
    input wire clk,rst,frame_tick,hit,
    output reg [1:0] level
);
    reg pending_hit;
    reg [1:0] dwell;
    always @(posedge clk) begin
        if(rst) begin level<=0; dwell<=0; pending_hit<=0; end
        else begin
            if(hit) pending_hit<=1;
            if(frame_tick) begin
                if(pending_hit || hit) begin
                    level<=2'd3; dwell<=0; pending_hit<=0;
                end else if(level!=0) begin
                    if(dwell==1) begin level<=level-1'b1; dwell<=0; end
                    else dwell<=dwell+1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
