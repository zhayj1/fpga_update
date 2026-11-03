`default_nettype none
// Continuously sample pre-gain PCM; copy the latest 1024 samples into the
// FFT every 800 input samples. A single read port is time-multiplexed.
module spec_window (
    input wire clk,
    input wire rst_n,
    input wire sample_valid,
    input wire signed [11:0] sample_data,
    input wire fft_ready,
    output wire fft_valid,
    output wire signed [11:0] fft_sample,
    output reg window_overrun
);
    reg signed [11:0] ring [0:1023];
    reg [9:0] wr_ptr, read_addr;
    reg signed [11:0] read_data;
    always @(posedge clk) begin
        if (sample_valid) ring[wr_ptr] <= sample_data;
        read_data <= ring[read_addr];
    end

    reg warmed;
    reg [9:0] fill_count, hop_count, window_start;
    reg pending;
    reg [9:0] copied;
    localparam [1:0] IDLE=2'd0, FETCH=2'd1, SEND=2'd2;
    reg [1:0] state;
    assign fft_valid = (state == SEND) && fft_ready;
    assign fft_sample = read_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 10'd0;
            read_addr <= 10'd0;
            fill_count <= 10'd0;
            hop_count <= 10'd0;
            warmed <= 1'b0;
            window_start <= 10'd0;
            pending <= 1'b0;
            copied <= 10'd0;
            state <= IDLE;
            window_overrun <= 1'b0;
        end else begin
            if (sample_valid) begin
                wr_ptr <= wr_ptr + 10'd1;
                if (!warmed) begin
                    if (fill_count == 10'd1023) begin
                        warmed <= 1'b1;
                        pending <= 1'b1;
                        window_start <= wr_ptr + 10'd1;
                        hop_count <= 10'd0;
                    end else fill_count <= fill_count + 10'd1;
                end else if (hop_count == 10'd799) begin
                    hop_count <= 10'd0;
                    if (pending) window_overrun <= 1'b1;
                    pending <= 1'b1;
                    window_start <= wr_ptr + 10'd1;
                end else hop_count <= hop_count + 10'd1;
            end
            case (state)
            IDLE: if (pending) begin
                read_addr <= window_start;
                copied <= 10'd0;
                pending <= 1'b0;
                state <= FETCH;
            end
            FETCH: state <= SEND;
            SEND: if (fft_ready) begin
                if (copied == 10'd1023) state <= IDLE;
                else begin
                    copied <= copied + 10'd1;
                    read_addr <= read_addr + 10'd1;
                    state <= FETCH;
                end
            end
            default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
