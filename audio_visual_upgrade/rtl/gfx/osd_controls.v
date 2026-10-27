`default_nettype none
// Button state is kept in the 50 MHz domain. Values change only on a debounced
// press, so the pixel domain can take a two-flop snapshot of each value.
module osd_controls #(
    parameter integer CLK_HZ = 50000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_MS = 600,
    parameter integer AUTO_HIDE_MS = 5000
)(
    input wire clk, rst_n,
    input wire key2, key3, key4,
    output reg visible,
    output reg [1:0] page,
    output reg [2:0] selected,
    output reg image_next,
    output reg [5:0] sensitivity,
    output reg [8:0] volume, sat_base, sat_max, con_base, con_max
);
    localparam integer MS_TICKS=(CLK_HZ/1000 < 1) ? 1 : CLK_HZ/1000;
    localparam integer MW=(MS_TICKS<2) ? 1 : $clog2(MS_TICKS);
    localparam integer DW=(DEBOUNCE_MS<2) ? 1 : $clog2(DEBOUNCE_MS+1);
    localparam integer LW=(LONG_MS<2) ? 1 : $clog2(LONG_MS+1);
    localparam integer AW=(AUTO_HIDE_MS<2) ? 1 : $clog2(AUTO_HIDE_MS+1);
    reg [MW-1:0] ms_div;
    wire ms_tick=ms_div==MS_TICKS-1;
    reg [1:0] k2_sync,k3_sync,k4_sync;
    reg k2_level,k3_level,key4_level;
    reg [DW-1:0] k2_stable,k3_stable,k4_stable;
    reg minus_press,plus_press,key4_press;
    reg [LW-1:0] held;
    reg [AW-1:0] idle_ms;
    reg was_down, long_done;
    wire minus = minus_press && !plus_press;
    wire plus = plus_press && !minus_press;

    always @(posedge clk) begin
        if (!rst_n) begin
            ms_div<=0;
            k2_sync<=2'b11; k3_sync<=2'b11; k4_sync<=2'b11;
            k2_level<=0; k3_level<=0; key4_level<=0;
            k2_stable<=0; k3_stable<=0; k4_stable<=0;
            minus_press<=0; plus_press<=0; key4_press<=0;
        end else begin
            k2_sync<={k2_sync[0],key2};
            k3_sync<={k3_sync[0],key3};
            k4_sync<={k4_sync[0],key4};
            ms_div<=ms_tick ? {MW{1'b0}} : ms_div+1'b1;
            minus_press<=0; plus_press<=0; key4_press<=0;
            if (ms_tick) begin
                if ((~k2_sync[1])==k2_level) k2_stable<=0;
                else if (k2_stable==DEBOUNCE_MS-1) begin
                    k2_stable<=0; k2_level<=~k2_sync[1];
                    minus_press<=~k2_sync[1];
                end else k2_stable<=k2_stable+1'b1;
                if ((~k3_sync[1])==k3_level) k3_stable<=0;
                else if (k3_stable==DEBOUNCE_MS-1) begin
                    k3_stable<=0; k3_level<=~k3_sync[1];
                    plus_press<=~k3_sync[1];
                end else k3_stable<=k3_stable+1'b1;
                if ((~k4_sync[1])==key4_level) k4_stable<=0;
                else if (k4_stable==DEBOUNCE_MS-1) begin
                    k4_stable<=0; key4_level<=~k4_sync[1];
                    key4_press<=~k4_sync[1];
                end else k4_stable<=k4_stable+1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            visible<=1'b0; page<=2'd0; selected<=3'd0;
            image_next<=1'b0; sensitivity<=6'd16;
            volume<=9'd100; sat_base<=9'd100; sat_max<=9'd180;
            con_base<=9'd100; con_max<=9'd135;
            held<=0; idle_ms<=0; was_down<=0; long_done<=0;
        end else begin
            image_next<=1'b0;
            was_down<=key4_level;
            if (key4_press || key4_level || minus || plus) idle_ms<=0;
            else if (ms_tick && visible) begin
                if (idle_ms==AUTO_HIDE_MS-1) begin
                    visible<=1'b0;
                    idle_ms<=0;
                end else idle_ms<=idle_ms+1'b1;
            end else if (!visible) idle_ms<=0;
            if (key4_press) begin
                held<=0;
                long_done<=0;
            end else if (ms_tick && key4_level && !long_done) begin
                if (held==LONG_MS[LW-1:0]) begin
                    visible<=~visible;
                    idle_ms<=0;
                    long_done<=1'b1;
                end else held<=held+1'b1;
            end
            if (was_down && !key4_level && !long_done) begin
                if (!visible) image_next<=1'b1;
                else if (page==2'd0) page<=2'd1;
                else if (page==2'd1) begin page<=2'd2; selected<=3'd0; end
                else if (selected==3'd4) begin page<=2'd0; selected<=3'd0; end
                else selected<=selected+3'd1;
                idle_ms<=0;
            end
            if (minus || plus) begin
                if (!visible) begin
                    visible<=1'b1;
                    page<=2'd2;
                    selected<=3'd0;
                    if (minus && volume>9'd0) volume<=volume-9'd1;
                    if (plus && volume<9'd100) volume<=volume+9'd1;
                end else if (page==2'd0) begin
                    if (minus && sensitivity>6'd2) sensitivity<=sensitivity-6'd1;
                    if (plus && sensitivity<6'd40) sensitivity<=sensitivity+6'd1;
                end else if (page==2'd2) begin
                    case (selected)
                    3'd0: begin
                        if (minus && volume>9'd0) volume<=volume-9'd1;
                        if (plus && volume<9'd100) volume<=volume+9'd1;
                    end
                    3'd1: begin
                        if (minus && sat_base>9'd60) sat_base<=sat_base-9'd1;
                        if (plus && sat_base<9'd150 && sat_base<sat_max)
                            sat_base<=sat_base+9'd1;
                    end
                    3'd2: begin
                        if (minus && sat_max>9'd100 && sat_max>sat_base)
                            sat_max<=sat_max-9'd1;
                        if (plus && sat_max<9'd260) sat_max<=sat_max+9'd1;
                    end
                    3'd3: begin
                        if (minus && con_base>9'd80) con_base<=con_base-9'd1;
                        if (plus && con_base<9'd130 && con_base<con_max)
                            con_base<=con_base+9'd1;
                    end
                    3'd4: begin
                        if (minus && con_max>9'd100 && con_max>con_base)
                            con_max<=con_max-9'd1;
                        if (plus && con_max<9'd170) con_max<=con_max+9'd1;
                    end
                    default: selected<=3'd0;
                    endcase
                end
            end
        end
    end
endmodule
`default_nettype wire
