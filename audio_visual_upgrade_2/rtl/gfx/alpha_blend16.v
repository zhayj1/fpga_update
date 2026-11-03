`default_nettype none
// Exact round-to-nearest /15 using one signed color difference product.
// b + floor((a*(f-b)+7)/15) equals floor((b*(15-a)+f*a+7)/15).
// Radix-4 shift/add or selected DSP channels retain all 16 coverage levels.
module alpha_blend16 #(parameter integer USE_DSP=0, DSP_CHANNELS=7)
                    (input wire [23:0] background, foreground,
                     input wire [3:0] alpha, output wire [23:0] rgb) /* synthesis dsp_style = yes */;
    function [7:0] channel;
        input [7:0] b,f;
        input [3:0] a;
        input use_channel_dsp;
        reg signed [8:0] delta;
        reg signed [12:0] x,p,s,q;
        reg signed [10:0] triple,lo,hi;
        begin
            delta=$signed({1'b0,f})-$signed({1'b0,b});
            x={{4{delta[8]}},delta};
            if (USE_DSP && use_channel_dsp)
                p=x*$signed({1'b0,a});
            else begin
                triple=$signed({{2{delta[8]}},delta})+($signed({{2{delta[8]}},delta})<<<1);
                case(a[1:0])
                    0:lo=0;1:lo=delta;2:lo=$signed({delta,1'b0});3:lo=triple;
                endcase
                case(a[3:2])
                    0:hi=0;1:hi=delta;2:hi=$signed({delta,1'b0});3:hi=triple;
                endcase
                p=$signed({{2{lo[10]}},lo})+($signed({{2{hi[10]}},hi})<<<2);
            end
            s=p+13'sd7;
            // Arithmetic shifts implement floor division exactly over
            // s=-3818..3832. Both intermediate sums fit signed 13 bits.
            q=s+13'sd1+(s>>>4);
            q=q+(q>>>8);
            // The final value is 0..255; low eight quotient bits suffice.
            channel=b+q[11:4];
        end
    endfunction
    assign rgb={channel(background[23:16],foreground[23:16],alpha,DSP_CHANNELS[2]),
                channel(background[15:8],foreground[15:8],alpha,DSP_CHANNELS[1]),
                channel(background[7:0],foreground[7:0],alpha,DSP_CHANNELS[0])};
endmodule
`default_nettype wire
