`default_nettype none
// Exact round-to-nearest /15 using one signed color difference product.
// b + floor((a*(f-b)+7)/15) equals floor((b*(15-a)+f*a+7)/15).
// Shift/add only: no DSP and no loss of any of the 16 coverage levels.
module alpha_blend16 #(parameter integer USE_DSP=0)
                    (input wire [23:0] background, foreground,
                     input wire [3:0] alpha, output wire [23:0] rgb) /* synthesis dsp_style = yes */;
    function [7:0] channel;
        input [7:0] b,f;
        input [3:0] a;
        reg signed [8:0] delta;
        reg signed [12:0] x,p,s,q;
        begin
            delta=$signed({1'b0,f})-$signed({1'b0,b});
            x={{4{delta[8]}},delta};
            if (USE_DSP)
                p=x*$signed({1'b0,a});
            else
                p=(a[0]?x:13'sd0)+((a[1]?x:13'sd0)<<<1)+
                  ((a[2]?x:13'sd0)<<<2)+((a[3]?x:13'sd0)<<<3);
            s=p+13'sd7;
            // Arithmetic shifts implement floor division exactly over
            // s=-3818..3832. Both intermediate sums fit signed 13 bits.
            q=s+13'sd1+(s>>>4);
            q=q+(q>>>8);
            // The final value is 0..255; low eight quotient bits suffice.
            channel=b+q[11:4];
        end
    endfunction
    assign rgb={channel(background[23:16],foreground[23:16],alpha),
                channel(background[15:8],foreground[15:8],alpha),
                channel(background[7:0],foreground[7:0],alpha)};
endmodule
`default_nettype wire
