`default_nettype none
//=============================================================================
// rtl/uart_tx.v
//   最简 UART 发送器（8N1，LSB first，空闲高电平）
//
//   只做发送：上板时只需把 FPGA 的这根线接到 USB-UART（CH340）的 RXD，
//   不需要知道 FPGA 侧 RX 的方向，避免手册"RXD=F12 / TXD=D12"方向待核对的坑。
//
//   波特率：DIV = CLK_HZ / BAUD（50MHz / 115200 = 434.03 -> 取 434，误差 0.007%）
//=============================================================================
module uart_tx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD   = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,     // 单周期脉冲
    input  wire [7:0] tx_data,
    output reg        tx_busy,      // 发完一字节前保持 1
    output reg        tx           // 空闲为高
);

    localparam integer DIV = (CLK_HZ / BAUD) > 1 ? (CLK_HZ / BAUD) : 2;

    reg [15:0] div_cnt;
    reg [3:0]  bit_idx;
    reg [9:0]  sh;                  // {stop, data[7:0], start}

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx      <= 1'b1;
            tx_busy <= 1'b0;
            div_cnt <= 16'd0;
            bit_idx <= 4'd0;
            sh      <= 10'h3FF;
        end else if (!tx_busy) begin
            tx <= 1'b1;
            if (tx_start) begin
                sh      <= {1'b1, tx_data, 1'b0};
                tx_busy <= 1'b1;
                div_cnt <= DIV[15:0] - 16'd1;
                bit_idx <= 4'd1;
                tx      <= 1'b0;                 // 起始位
            end
        end else if (div_cnt != 16'd0) begin
            div_cnt <= div_cnt - 16'd1;
        end else begin
            div_cnt <= DIV[15:0] - 16'd1;
            if (bit_idx >= 4'd10) begin
                tx_busy <= 1'b0;
                tx      <= 1'b1;
            end else begin
                tx      <= sh[bit_idx];
                bit_idx <= bit_idx + 4'd1;
            end
        end
    end

endmodule
`default_nettype wire
