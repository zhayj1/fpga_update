`default_nettype none
// Serial 18-band onset detector. One packed history word is read and updated
// per band; no second FFT or bin store is required.
module spec_attack18 (
    input wire clk, rst_n,
    input wire band_stb,
    input wire [4:0] band_idx,
    input wire [7:0] band_level,
    input wire [5:0] sensitivity,
    output reg analysis_stb,
    output reg hit,
    output reg [4:0] hit_band,
    output reg [12:0] flux,
    output reg [12:0] threshold,
    output reg [15:0] hit_count
);
    reg [31:0] history [0:17];
    reg [31:0] hist_read;
    reg pending, eval_pending;
    reg [4:0] pending_idx;
    reg [7:0] pending_mag;
    reg [2:0] history_frames;
    reg [12:0] flux_acc;
    reg [7:0] best_val;
    reg [4:0] best_idx;
    reg [17:0] base_q, sigma_q; // Q4
    reg base_valid;
    reg [3:0] cooldown;
    reg multiply_busy;
    reg [3:0] multiply_step;
    reg [28:0] multiply_acc, multiply_term;
    reg [10:0] multiply_bits;

    wire [31:0] old_hist=(history_frames==0)?32'd0:hist_read;
    wire [9:0] hist_sum={2'd0,old_hist[7:0]}+
                        {2'd0,old_hist[15:8]}+
                        {2'd0,old_hist[23:16]}+
                        {2'd0,old_hist[31:24]};
    wire [7:0] hist_mean=hist_sum[9:2];
    wire [7:0] positive=(pending_mag>hist_mean)?pending_mag-hist_mean:8'd0;
    wire [12:0] flux_next=(pending_idx==0)?{5'd0,positive}:
                            flux_acc+{5'd0,positive};

    wire [17:0] flux_q={1'b0,flux_acc,4'b0};
    wire signed [18:0] diff_q=$signed({1'b0,flux_q})-
                              $signed({1'b0,base_q});
    wire signed [22:0] base_diff_ext={{4{diff_q[18]}},diff_q};
    wire signed [22:0] base_step_product=
        (base_diff_ext<<<3)+(base_diff_ext<<<2)+base_diff_ext;
    wire signed [19:0] base_next_signed=
        $signed({1'b0,base_q})+(base_step_product>>>8);
    wire [17:0] base_next=base_next_signed[17:0];
    wire [18:0] abs_diff_q=diff_q[18] ? -diff_q : diff_q;
    wire signed [19:0] sigma_diff_q=
        $signed({1'b0,abs_diff_q})-$signed({1'b0,sigma_q});
    wire signed [23:0] sigma_diff_ext={{4{sigma_diff_q[19]}},sigma_diff_q};
    wire signed [23:0] sigma_step_product=(sigma_diff_ext<<<4)-sigma_diff_ext;
    wire signed [19:0] sigma_next_signed=
        $signed({1'b0,sigma_q})+(sigma_step_product>>>8);
    wire [17:0] sigma_next=sigma_next_signed[17:0];
    wire [5:0] sens_clamped=(sensitivity<6'd2)?6'd2:
                             ((sensitivity>6'd40)?6'd40:sensitivity);
    // Q8 approximation of 4.2 - sensitivity*3.1/40.
    wire [10:0] sens_x20=({5'd0,sens_clamped}<<4)+
                           ({5'd0,sens_clamped}<<2);
    wire [10:0] k_q8=11'd1075-sens_x20;
    wire [28:0] multiply_next=multiply_bits[0] ?
                               multiply_acc+multiply_term : multiply_acc;
    wire [20:0] threshold_q={3'd0,base_q}+
                             {1'b0,multiply_next[28:8]}+21'd40;
    wire [20:0] first_threshold_q={3'd0,flux_q}+21'd40;

    // No reset on the tiny RAM: the first complete frame overwrites every
    // word from a known zero history, including after a song change.
    always @(posedge clk) begin
        hist_read<=history[band_idx];
        if(pending) history[pending_idx]<={old_hist[23:0],pending_mag};
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pending<=0; eval_pending<=0; pending_idx<=0; pending_mag<=0;
            history_frames<=0; flux_acc<=0; best_val<=0; best_idx<=0;
            base_q<=0; sigma_q<=0; base_valid<=0; cooldown<=0;
            multiply_busy<=0; multiply_step<=0;
            multiply_acc<=0; multiply_term<=0; multiply_bits<=0;
            analysis_stb<=0; hit<=0; hit_band<=0;
            flux<=0; threshold<=0; hit_count<=0;
        end else begin
            analysis_stb<=0;
            hit<=0;
            pending<=band_stb;
            if(band_stb) begin
                pending_idx<=band_idx;
                pending_mag<=band_level;
            end
            if(pending) begin
                flux_acc<=flux_next;
                if(pending_idx==0) begin
                    best_val<=positive;
                    best_idx<=0;
                end else if(positive>best_val) begin
                    best_val<=positive;
                    best_idx<=pending_idx;
                end
                if(pending_idx==5'd17) eval_pending<=1;
            end
            if(eval_pending) begin
                eval_pending<=0;
                flux<=flux_acc;
                if(history_frames<3'd4) history_frames<=history_frames+3'd1;
                if(!base_valid) begin
                    analysis_stb<=1;
                    base_q<=flux_q;
                    sigma_q<=0;
                    threshold<=first_threshold_q[16:4];
                    base_valid<=1;
                end else begin
                    base_q<=base_next;
                    sigma_q<=sigma_next;
                    multiply_busy<=1;
                    multiply_step<=0;
                    multiply_acc<=0;
                    multiply_term<={11'd0,sigma_next};
                    multiply_bits<=k_q8;
                end
            end
            if(multiply_busy) begin
                multiply_acc<=multiply_next;
                multiply_term<=multiply_term<<1;
                multiply_bits<=multiply_bits>>1;
                multiply_step<=multiply_step+4'd1;
                if(multiply_step==4'd10) begin
                    multiply_busy<=0;
                    analysis_stb<=1;
                    threshold<=(threshold_q[20:17]!=0)?13'h1fff:
                               threshold_q[16:4];
                    if(cooldown!=0) cooldown<=cooldown-4'd1;
                    if(({3'd0,flux_q}>threshold_q) && cooldown==0) begin
                        hit<=1;
                        hit_band<=best_idx;
                        if(hit_count!=16'hffff) hit_count<=hit_count+16'd1;
                        cooldown<=4'd10; // next eligible analysis is 11 hops later
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
