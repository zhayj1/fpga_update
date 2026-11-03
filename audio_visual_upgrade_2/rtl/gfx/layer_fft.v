`default_nettype none
// Thin white spectrum: 16 audio bands -> 64 tines and a connected envelope.
// All state is in clk_pix. Output describes the CURRENT raster pixel:
// no pixel pipeline delay, SDRAM client, bitmap, line RAM or reflection.
// Capture rotating spec_bands output ONLY on bars_stb; commit at vertical
// blank (frame_stb). Coincident strobes commit the newly completed set.
// rst_n also clears song history. See doc/spec/thin_spectrum.md.
//
// A short shift register walks the bands once per scan line, avoiding large
// indexed multiplexers and per-tine arithmetic. One signed multiply serves
// the whole raster and is suitable for DSP inference. DSP use is welcome;
// actual slice/BRAM/DSP mapping must be checked in the TD area report.
module layer_fft #(
    parameter integer BARS       = 16,
    parameter integer BAR_PITCH  = 20,
    parameter integer BAR_W      = 1,
    parameter integer H_SHIFT    = 2,
    parameter integer TINE_PITCH = 5
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              bars_stb,
    input  wire              frame_stb,
    input  wire              de,
    input  wire [15:0]       x,
    input  wire [15:0]       y,
    input  wire              en,
    input  wire [15:0]       base_x,
    input  wire [15:0]       base_y,
    input  wire [8*BARS-1:0] bars,
    output wire [23:0]       dout,
    output wire              dout_vld
);
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            clog2 = 0;
            while (v > 0) begin
                clog2 = clog2 + 1;
                v = v >> 1;
            end
            if (clog2 == 0) clog2 = 1;
        end
    endfunction

    localparam integer PW = clog2(BAR_PITCH);
    localparam integer BW = clog2(BARS);
    localparam integer HALF = BAR_PITCH / 2;
    localparam integer WIDTH = BARS * BAR_PITCH;
    reg [8*BARS-1:0] pending_bars, frame_bars, scan_bars;
    reg [PW-1:0] phase;
    reg [BW-1:0] band;
    reg [7:0] previous_band, previous_smooth, previous_height;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_bars <= {(8*BARS){1'b0}};
            frame_bars   <= {(8*BARS){1'b0}};
        end else begin
            if (bars_stb) pending_bars <= bars;
            if (frame_stb) frame_bars <= bars_stb ? bars : pending_bars;
        end
    end

    wire [15:0] dx = x - base_x;
    wire [15:0] dy = base_y - y;
    wire inside_x = (dx < WIDTH);
    wire last_band = (band == BARS - 1);
    wire [7:0] current_band = scan_bars[7:0];
    wire [7:0] next_band = scan_bars[15:8];
    // Shift-in zeros supply neighbours beyond the final band.
    wire [7:0] after_next = scan_bars[23:16];
    wire [9:0] smooth_sum = {2'b00, previous_band}
                          + {1'b0, current_band, 1'b0}
                          + {2'b00, next_band} + 10'd2;
    wire [9:0] next_sum = {2'b00, current_band}
                        + {1'b0, next_band, 1'b0}
                        + {2'b00, after_next} + 10'd2;
    wire [7:0] smooth = smooth_sum[9:2];
    wire [7:0] next_smooth = next_sum[9:2];

    // Tiny coefficient LUT. Every division has ELABORATION-CONSTANT
    // operands (i and parameters); there is no hardware divider.
    function [8:0] fraction;
        input [PW-1:0] pos;
        input first;
        input last;
        integer i;
        begin
            fraction = 9'd0;
            for (i = 0; i < BAR_PITCH; i = i + 1) begin
                if (pos == i) begin
                    if (i < HALF) begin
                        if (first)
                            fraction = (i * 256 + HALF / 2) / HALF;
                        else
                            fraction = ((i + HALF) * 256 + BAR_PITCH / 2) / BAR_PITCH;
                    end else begin
                        if (last)
                            fraction = ((i - HALF) * 256 + (HALF - 1) / 2) / (HALF - 1);
                        else
                            fraction = ((i - HALF) * 256 + BAR_PITCH / 2) / BAR_PITCH;
                    end
                end
            end
        end
    endfunction

    wire [7:0] left_level = (phase < HALF)
                           ? ((band == 0) ? 8'd0 : previous_smooth) : smooth;
    wire [7:0] right_level = (phase < HALF)
                            ? smooth : (last_band ? 8'd0 : next_smooth);
    wire [8:0] weight = fraction(phase, (band == 0), last_band);
    wire signed [8:0] delta = $signed({1'b0, right_level})
                              - $signed({1'b0, left_level});
    wire signed [18:0] product = delta * $signed({1'b0, weight});
    wire signed [18:0] interpolated = $signed({3'b000, left_level, 8'd0}) + product;
    wire [7:0] height = interpolated >> (8 + H_SHIFT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_bars       <= {(8*BARS){1'b0}};
            phase           <= {PW{1'b0}};
            band            <= {BW{1'b0}};
            previous_band   <= 8'd0;
            previous_smooth <= 8'd0;
            previous_height <= 8'd0;
        end else if (!de || !inside_x || !en) begin
            // Horizontal blank also restarts a line clipped by the screen.
            scan_bars       <= frame_bars;
            phase           <= {PW{1'b0}};
            band            <= {BW{1'b0}};
            previous_band   <= 8'd0;
            previous_smooth <= 8'd0;
            previous_height <= 8'd0;
        end else begin
            previous_height <= height;
            if (phase == BAR_PITCH - 1) begin
                phase           <= {PW{1'b0}};
                band            <= band + 1'b1;
                scan_bars       <= {8'd0, scan_bars[8*BARS-1:8]};
                previous_band   <= current_band;
                previous_smooth <= smooth;
            end else phase <= phase + 1'b1;
        end
    end

    integer t;
    reg tine;
    always @* begin
        tine = 1'b0;
        for (t = 0; t < BAR_PITCH; t = t + TINE_PITCH)
            if ((phase >= t) && (phase < t + BAR_W)) tine = 1'b1;
    end
    wire [7:0] low_height = (height < previous_height) ? height : previous_height;
    wire [7:0] high_height = (height > previous_height) ? height : previous_height;
    // Connect consecutive contour pixels vertically on steep slopes.
    wire envelope = (dy != 0) && (dy >= {8'd0, low_height})
                                 && (dy <= {8'd0, high_height});
    wire stick = tine && (dy != 0) && (dy <= {8'd0, height});
    wire baseline = (dy == 0);
    assign dout = 24'hffffff;
    assign dout_vld = rst_n && en && de && inside_x && (baseline || stick || envelope);

    // Invalid geometry must fail elaboration rather than silently misdraw.
    generate
        if ((BARS < 3) || (BAR_PITCH < 4) || (BAR_PITCH % 2 != 0)
            || (TINE_PITCH < 1) || (TINE_PITCH > BAR_PITCH)
            || (BAR_PITCH % TINE_PITCH != 0) || (BAR_W < 1)
            || (BAR_W > TINE_PITCH) || (H_SHIFT < 0) || (H_SHIFT > 7)) begin : g_invalid
            layer_fft_invalid_parameters u_guard ();
        end
    endgenerate
endmodule
`default_nettype wire
