`default_nettype none
// Source mailbox is held until ack. Destination resolves all six colours
// during blanking, then atomically commits RGB and effect bits next frame.
module visual_settings(input wire clk,rst_n,input wire [46:0] settings,
    input wire clk_pix,rst_pix,frame_tick,
    input wire [6:0] swatch_index,output wire [23:0] swatch_rgb,
    output reg [23:0] spectrum,sung,other,title,singer,rings,
    output reg [4:0] effects,output reg [41:0] indices);
    reg [46:0] mailbox;
    reg request,ack;
    reg [1:0] ack_sync,req_sync;
    // Source holds this bundle until the frame commit is acknowledged.
    // The request synchronizer settles before any ROM address is consumed.
    wire [46:0] pending=mailbox;
    reg [2:0] step;
    reg ready;
    reg [23:0] c0,c1,c2,c3,c4;
    wire [6:0] ix=step==0?pending[6:0]:step==1?pending[13:7]:
        step==2?pending[20:14]:step==3?pending[27:21]:
        step==4?pending[34:28]:pending[41:35];
    // Index 70 selects the object's default, stored at 70+object.
    wire [6:0] rom_index=ix==70 ? 7'd70+{4'd0,step} : ix;
    wire [23:0] lookup;
    visual_palette u_palette(.clk(clk_pix),.index_a(rom_index),
        .index_b(swatch_index),.rgb_a(lookup),.rgb_b(swatch_rgb));
    always @(posedge clk) begin
        if(!rst_n) begin mailbox<=0;request<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};
            if(request==ack_sync[1] && settings!=mailbox) begin
                mailbox<=settings;request<=~request;
            end
        end
    end
    // ROM has a synchronous read. Two cycles per object avoid an address/data
    // ambiguity and keep the mailbox busy through the final frame commit.
    reg phase,busy;
    always @(posedge clk_pix) begin
        if(rst_pix) begin
            req_sync<=0;ack<=0;step<=0;phase<=0;busy<=0;ready<=0;
            spectrum<=24'hD97A26;sung<=24'hFF5FCB;other<=24'hE8E4FF;
            title<=24'hFFFFFF;singer<=24'hBCC4D2;rings<=24'h5EE8ED;
            effects<=5'b11111;indices<={6{7'd70}};
            c0<=0;c1<=0;c2<=0;c3<=0;c4<=0;
        end else begin
            req_sync<={req_sync[0],request};
            if(!busy && req_sync[1]!=ack) begin
                busy<=1;ready<=0;step<=0;phase<=0;
            end else if(busy && !ready) begin
                phase<=~phase;
                if(phase) begin
                    case(step)
                    0:c0<=lookup;1:c1<=lookup;2:c2<=lookup;
                    3:c3<=lookup;4:c4<=lookup;
                    endcase
                    if(step==5) ready<=1;else step<=step+3'd1;
                end
            end
            if(frame_tick && ready) begin
                // step remains five until commit, so the synchronous ROM
                // itself holds the sixth colour through this edge.
                spectrum<=c0;sung<=c1;other<=c2;title<=c3;singer<=c4;rings<=lookup;
                effects<=pending[46:42];indices<=pending[41:0];
                ack<=req_sync[1];busy<=0;ready<=0;
            end
        end
    end
endmodule
`default_nettype wire
