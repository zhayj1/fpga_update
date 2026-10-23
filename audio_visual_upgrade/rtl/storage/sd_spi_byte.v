`default_nettype none
module sd_spi_byte (
    input wire clk, input wire rst_n,
    input wire start, input wire [7:0] tx_data,
    input wire [15:0] half_period,
    output reg busy, output reg done, output reg [7:0] rx_data,
    output reg sck, output reg mosi, input wire miso
);
    reg [15:0] tick, divider;
    reg [2:0] bit_number;
    reg [7:0] tx_shift, rx_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0; done <= 0; rx_data <= 0;
            sck <= 0; mosi <= 1; tick <= 0; divider <= 1;
            bit_number <= 7; tx_shift <= 8'hff; rx_shift <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                sck <= 0; mosi <= 1;
                if (start) begin
                    busy <= 1; bit_number <= 7;
                    divider <= half_period == 0 ? 16'd1 : half_period;
                    tick <= half_period == 0 ? 16'd0 : half_period - 1'b1;
                    tx_shift <= tx_data; rx_shift <= 0; mosi <= tx_data[7];
                end
            end else if (tick != 0) tick <= tick - 1'b1;
            else begin
                tick <= divider - 1'b1;
                if (!sck) begin
                    sck <= 1;
                    rx_shift <= {rx_shift[6:0], miso};
                end else begin
                    sck <= 0;
                    if (bit_number == 0) begin
                        rx_data <= rx_shift; busy <= 0; done <= 1; mosi <= 1;
                    end else begin
                        bit_number <= bit_number - 1'b1;
                        tx_shift <= {tx_shift[6:0],1'b1}; mosi <= tx_shift[6];
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
