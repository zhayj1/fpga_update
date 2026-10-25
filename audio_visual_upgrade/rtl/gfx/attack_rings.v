`default_nettype none
    // Four onset rings share one distance calculation and one boundary multiplier.
// Frame housekeeping prepares all annuli in 21 blank clocks, without a ROM
// or framebuffer. frame_tick must precede DE by at least 21 clocks.
// Raster contract: x starts at zero and advances once per DE clock; y is
// stable for at least two blank clocks before DE. Output has no pixel delay.
module attack_rings(
    input wire clk,rst,frame_tick,hit,de,
    input wire [9:0] x,y,
    output wire valid,
    output wire [23:0] rgb,
    output wire [7:0] alpha
);
    reg [3:0] alive;
    reg [1:0] insert_at;
    reg [5:0] age [0:3];
    reg [22:0] lower [0:3];
    reg [22:0] upper [0:3];
    reg [7:0] opacity [0:3];
    reg pending_hit;
    reg refresh_busy;
    reg [1:0] refresh_slot;
    reg [2:0] refresh_phase;
    reg [8:0] bound_radius;
    reg [8:0] upper_radius;
    reg [17:0] bound_square;
    wire [5:0] refresh_age=age[refresh_slot];
    // HTML advances radius 3.4 and multiplies opacity by .92 each frame.
    // The table contains integer pixel-center bounds and 8-bit opacity.
    function [25:0] ring_model;
        input [5:0] a;
        begin
            case(a)
                6'd0: ring_model={9'd130,9'd133,8'd188};
                6'd1: ring_model={9'd134,9'd136,8'd173};
                6'd2: ring_model={9'd137,9'd139,8'd159};
                6'd3: ring_model={9'd141,9'd143,8'd146};
                6'd4: ring_model={9'd144,9'd146,8'd134};
                6'd5: ring_model={9'd147,9'd149,8'd124};
                6'd6: ring_model={9'd151,9'd153,8'd114};
                6'd7: ring_model={9'd154,9'd156,8'd105};
                6'd8: ring_model={9'd158,9'd159,8'd96};
                6'd9: ring_model={9'd161,9'd163,8'd89};
                6'd10: ring_model={9'd165,9'd166,8'd82};
                6'd11: ring_model={9'd168,9'd170,8'd75};
                6'd12: ring_model={9'd171,9'd173,8'd69};
                6'd13: ring_model={9'd175,9'd176,8'd63};
                6'd14: ring_model={9'd178,9'd180,8'd58};
                6'd15: ring_model={9'd182,9'd183,8'd54};
                6'd16: ring_model={9'd185,9'd186,8'd49};
                6'd17: ring_model={9'd189,9'd190,8'd45};
                6'd18: ring_model={9'd192,9'd193,8'd42};
                6'd19: ring_model={9'd195,9'd197,8'd38};
                6'd20: ring_model={9'd199,9'd200,8'd35};
                6'd21: ring_model={9'd202,9'd203,8'd33};
                6'd22: ring_model={9'd206,9'd207,8'd30};
                6'd23: ring_model={9'd209,9'd210,8'd28};
                6'd24: ring_model={9'd212,9'd214,8'd25};
                6'd25: ring_model={9'd216,9'd217,8'd23};
                6'd26: ring_model={9'd219,9'd220,8'd21};
                6'd27: ring_model={9'd223,9'd224,8'd20};
                6'd28: ring_model={9'd226,9'd227,8'd18};
                6'd29: ring_model={9'd229,9'd231,8'd17};
                6'd30: ring_model={9'd233,9'd234,8'd15};
                6'd31: ring_model={9'd236,9'd237,8'd14};
                6'd32: ring_model={9'd240,9'd241,8'd13};
                6'd33: ring_model={9'd243,9'd244,8'd12};
                6'd34: ring_model={9'd246,9'd248,8'd11};
                6'd35: ring_model={9'd250,9'd251,8'd10};
                6'd36: ring_model={9'd253,9'd254,8'd9};
                6'd37: ring_model={9'd257,9'd258,8'd9};
                6'd38: ring_model={9'd260,9'd261,8'd8};
                default: ring_model=26'd0;
            endcase
        end
    endfunction
    wire [25:0] model=ring_model(refresh_age);
    integer i;
    wire [8:0] dy=(y>=10'd165) ? y-10'd165 : 10'd165-y;
    // (x+1-c)^2 = (x-c)^2 + 2*(x-c) + 1. The initial
    // value is prepared throughout horizontal blanking, so x=0 is exact.
    reg [17:0] dx2;
    reg [17:0] dy2;
    // x can reach 639, so use eleven bits for the doubled coordinate.
    wire [10:0] twice_x={x,1'b0};
    always @(posedge clk) begin
        if(rst) begin dx2<=18'd67600; dy2<=18'd27225; end
        else begin
            if(!de) begin
                dx2<=18'd67600;
                // y is stable for the horizontal blanking interval and for
                // the following active line, so calculate its square once.
                dy2<=dy*dy;
            end
            else if(x<10'd260) dx2<=dx2-(11'd519-twice_x);
            else dx2<=dx2+(twice_x-11'd519);
        end
    end
    // The monitor expands x by 6/5. Compare 36*dx^2+25*dy^2
    // against 25*r^2, so its physical ring remains circular.
    wire [22:0] dist=({5'd0,dx2}<<5)+({5'd0,dx2}<<2)+
                     ({5'd0,dy2}<<4)+({5'd0,dy2}<<3)+{5'd0,dy2};
    wire [3:0] match_ring;
    genvar k;
    generate for(k=0;k<4;k=k+1) begin: g_ring
        assign match_ring[k]=alive[k] &&
            (dist >= lower[k]) && (dist <= upper[k]);
    end endgenerate
    wire [3:0] show_ring=match_ring & alive;
    assign valid=de && (|show_ring);
    // Normal 180 ms hit spacing keeps rings apart; if two strokes meet,
    // the most opaque one wins without four parallel blending circuits.
    wire [7:0] a01=(show_ring[0] && opacity[0]>=opacity[1]) || !show_ring[1]
                   ? (show_ring[0] ? opacity[0] : 8'd0) : opacity[1];
    wire [7:0] a23=(show_ring[2] && opacity[2]>=opacity[3]) || !show_ring[3]
                   ? (show_ring[2] ? opacity[2] : 8'd0) : opacity[3];
    assign alpha=(a01>=a23) ? a01 : a23;
    assign rgb=24'h5EE8ED;
    always @(posedge clk) begin
        if(rst) begin
            alive<=0; insert_at<=0; pending_hit<=0;
            refresh_busy<=0; refresh_slot<=0; refresh_phase<=0;
            bound_radius<=0; upper_radius<=0; bound_square<=0;
            for(i=0;i<4;i=i+1) begin
                age[i]<=0; lower[i]<=0; upper[i]<=0; opacity[i]<=0;
            end
        end else begin
            if(hit) pending_hit<=1;
            // Only one slot is serviced at a time. All work finishes during
            // vertical blanking; the pixel path contains comparisons only.
            if(refresh_busy) begin
                if(refresh_phase==3'd1 || refresh_phase==3'd3)
                    bound_square<=bound_radius*bound_radius;
                case(refresh_phase)
                    3'd0: begin
                        bound_radius<=model[25:17]; upper_radius<=model[16:8];
                        opacity[refresh_slot]<=model[7:0]; refresh_phase<=1;
                    end
                    3'd1: refresh_phase<=2;
                    3'd2: begin
                        lower[refresh_slot]<=({5'd0,bound_square}<<4)+
                                             ({5'd0,bound_square}<<3)+{5'd0,bound_square};
                        bound_radius<=upper_radius; refresh_phase<=3;
                    end
                    3'd3: refresh_phase<=4;
                    3'd4: begin
                        upper[refresh_slot]<=({5'd0,bound_square}<<4)+
                                             ({5'd0,bound_square}<<3)+{5'd0,bound_square};
                        refresh_phase<=0;
                        if(refresh_slot==2'd3) refresh_busy<=0;
                        else refresh_slot<=refresh_slot+1'b1;
                    end
                    default: begin refresh_busy<=0; refresh_phase<=0; end
                endcase
            end
            if(frame_tick) begin
                refresh_busy<=1; refresh_slot<=0; refresh_phase<=0;
                for(i=0;i<4;i=i+1) if(alive[i]) begin
                    if(age[i]==6'd38) alive[i]<=0;
                    else age[i]<=age[i]+1'b1;
                end
                // Commit the event with the cover geometry at frame start.
                if(pending_hit || hit) begin
                    alive[insert_at]<=1;
                    age[insert_at]<=0;
                    insert_at<=insert_at+1'b1;
                    pending_hit<=0;
                end
            end
        end
    end
endmodule
`default_nettype wire
