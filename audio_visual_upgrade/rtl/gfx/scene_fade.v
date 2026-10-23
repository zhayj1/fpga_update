`default_nettype none
// Request payload is held by the source until ack_toggle. The ACK means old
// reads have drained, not merely that the new scene was accepted. Source-side
// pinned masks therefore protect BOTH scene slots for the whole transition.
module scene_fade #(
    parameter integer WIDTH=268,
    parameter [8:0] ALPHA_STEP=9'd8
)(
    input wire clk,rst,frame_tick,request_toggle,old_idle,
    input wire [WIDTH-1:0] next_scene,
    output reg [WIDTH-1:0] current_scene,previous_scene,
    output reg old_enable,busy,ack_toggle,
    output reg [8:0] alpha,
    output reg accepted
);
    localparam [1:0] IDLE=0,FADE=1,DRAIN=2;
    reg [1:0] state;
    reg [2:0] req_sync;
    reg have_scene,held_toggle;
    always @(posedge clk) begin
        if (rst) begin
            current_scene<=0; previous_scene<=0; old_enable<=0; busy<=0;
            ack_toggle<=0; alpha<=9'd256; accepted<=0;
            state<=IDLE; req_sync<=0; have_scene<=0; held_toggle<=0;
        end else begin
            req_sync<={req_sync[1:0],request_toggle}; accepted<=0;
            case (state)
                IDLE: if (frame_tick && req_sync[2]!=ack_toggle) begin
                    previous_scene<=current_scene; current_scene<=next_scene;
                    held_toggle<=req_sync[2]; accepted<=1; have_scene<=1;
                    if (!have_scene) begin ack_toggle<=req_sync[2]; alpha<=9'd256; end
                    else begin old_enable<=1; busy<=1; alpha<=0; state<=FADE; end
                end
                FADE: if (frame_tick) begin
                    if ({1'b0,alpha}+{1'b0,ALPHA_STEP}>=10'd256) begin
                        alpha<=9'd256; old_enable<=0; state<=DRAIN;
                    end else alpha<=alpha+ALPHA_STEP;
                end
                // At least one complete frame edge after disabling old fetches.
                DRAIN: if (frame_tick && old_idle) begin
                    ack_toggle<=held_toggle; busy<=0; state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
