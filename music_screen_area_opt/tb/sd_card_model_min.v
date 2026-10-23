`timescale 1ns/1ps
//=============================================================================
// tb/sd_card_model_min.v —— 极简 SD 卡 SPI 从机模型（仿真专用）
//
//   支持命令：CMD0 / CMD8 / CMD55 / ACMD41 / CMD58 / CMD59 / CMD17
//   数据来源：$readmemh 载入的镜像（默认 sim/fat32_small.mem，由
//             scripts/mk_sim_image.py 生成）
//
//   时序（SPI mode 0，与 sd_spi_byte 一致）：
//     主机在 SCK 上升沿采样 MISO  -> 本模型在 SCK 下降沿更新 MISO
//     本模型在 SCK 上升沿采样 MOSI
//
//   响应节奏：命令帧收完后的那一个字节先回 0xFF（NCR），从下一个字节开始
//   依次输出 R1 / R7 / OCR / 数据令牌；这 1 字节延迟完全符合规范里
//   NCR（响应延迟）的定义，DUT 的 R1 搜索循环本就容忍最多 16 个 0xFF。
//
//   CMD17 的数据：先 0xFE，再该 LBA 的 512 字节，再 2 字节 CRC（发 0xFFFF，
//   因为 DUT 用 CHECK_CRC16=0，不校验）。
//=============================================================================
module sd_card_model_min #(
    parameter integer IMG_BYTES = 131072,
    parameter         MEM_FILE  = "sim/fat32_small.mem",
    parameter         DEBUG     = 0,
    // 故障注入：=1 时第一次 CMD0 不回合法 R1（模拟卡上电未就绪）
    parameter         FAIL_FIRST_CMD0 = 0,
    // Legal CMD17 token latency. Default keeps existing test behavior.
    parameter integer TOKEN_DELAY_BYTES = 0
)(
    input  wire sck,
    input  wire cs_n,
    input  wire mosi,
    output wire miso,
    // 收到过多少次 CMD0（单元 TB 用它证明"重试确实发生了"）
    output reg  [7:0] cmd0_cnt = 8'd0
);

    reg fail_first_cmd0;
    reg cmd0_seen = 1'b0;
    initial begin
        fail_first_cmd0 = FAIL_FIRST_CMD0;
        if ($test$plusargs("FAIL_FIRST_CMD0")) fail_first_cmd0 = 1'b1;
    end

    reg [7:0] img [0:IMG_BYTES-1];
    initial $readmemh(MEM_FILE, img);

    reg [7:0]  rx_sh;
    reg [3:0]  bit_cnt;
    reg [2:0]  frame_idx;          // 已收到的命令帧字节数 0..5
    reg [7:0]  frame [0:5];
    reg [7:0]  resp  [0:527+TOKEN_DELAY_BYTES];
    integer    resp_len;
    integer    resp_idx;
    reg        in_resp;
    reg        idle_state;         // 1 = 还在 idle（R1 bit0）
    reg [7:0]  poll_cnt;
    reg [7:0]  tx_byte;
    reg        miso_r;

    integer    i;

    assign miso = miso_r;

    // 下一个要发送的字节（组合）
    wire [7:0] next_byte = in_resp ? resp[resp_idx] : 8'hFF;

    // 命令字段
    wire [5:0]  cmd = frame[0][5:0];
    wire [31:0] arg = {frame[1], frame[2], frame[3], frame[4]};

    initial begin
        rx_sh     = 8'h00;
        bit_cnt   = 4'd0;
        frame_idx = 3'd0;
        in_resp   = 1'b0;
        resp_idx  = 0;
        resp_len  = 0;
        idle_state= 1'b1;
        poll_cnt  = 8'd0;
        tx_byte   = 8'hFF;
        miso_r    = 1'b1;
        for (i = 0; i < 6; i = i + 1)  frame[i] = 8'h00;
        for (i = 0; i < 528+TOKEN_DELAY_BYTES; i = i + 1) resp[i] = 8'hFF;
    end

    always @(negedge sck or posedge cs_n) begin
        if (cs_n) begin
            bit_cnt   <= 4'd0;
            rx_sh     <= 8'h00;
            frame_idx <= 3'd0;
            in_resp   <= 1'b0;
            resp_idx  <= 0;
            tx_byte   <= 8'hFF;
            miso_r    <= 1'b1;
        end else if (bit_cnt == 4'd8) begin
            //---------------- 一个完整字节收完（rx_sh 已含 8 位）----------------
            bit_cnt <= 4'd0;

            if (in_resp) begin
                // 响应推进
                if (resp_idx >= resp_len - 1) begin
                    in_resp   <= 1'b0;
                    resp_idx  <= 0;
                    frame_idx <= 3'd0;
                end else begin
                    resp_idx <= resp_idx + 1;
                end
            end else if (frame_idx == 3'd0) begin
                // 等命令起始字节（bit7:6 = 01）
                if (rx_sh[7:6] == 2'b01) begin
                    frame[0]  <= rx_sh;
                    frame_idx <= 3'd1;
                end
            end else begin
                frame[frame_idx] <= rx_sh;
                if (DEBUG) $display("[%0t] CARD rx byte%0d = %02X", $time, frame_idx, rx_sh);
                if (frame_idx == 3'd5) begin
                    //---------------- 命令帧完整，装载响应 ----------------
                    case (cmd)
                    6'd0: begin                                  // CMD0 -> idle
                        cmd0_cnt <= cmd0_cnt + 8'd1;
                        // 故障注入开关（跑仿真时加 +FAIL_FIRST_CMD0）：
                        //   实测板上开局第一条 CMD0 可能不应答（LIER=E_CMD0=1），
                        //   这里模拟"卡还没上电就绪"：第一次 CMD0 只回 0xFF（无响应），
                        //   用来逼出 board_top 的初始化重试分支。
                        if (fail_first_cmd0 && !cmd0_seen) begin
                            cmd0_seen <= 1'b1;
                            resp[0]   <= 8'hFF;                  // 无合法 R1
                            resp_len  <= 1;
                            $display("[%0t] CARD: inject no-R1 on first CMD0 (fault injection active)", $time);
                        end else begin
                            resp[0]   <= 8'h01;
                            resp_len  <= 1;
                            idle_state<= 1'b1;
                            poll_cnt  <= 8'd0;
                        end
                    end
                    6'd8: begin                                  // CMD8 -> R7
                        resp[0] <= 8'h01;
                        resp[1] <= 8'h00;
                        resp[2] <= 8'h00;
                        resp[3] <= 8'h01;                        // VCA 2.7-3.6V
                        resp[4] <= 8'hAA;                        // check pattern
                        resp_len<= 5;
                    end
                    6'd55: begin                                 // CMD55
                        resp[0] <= idle_state ? 8'h01 : 8'h00;
                        resp_len<= 1;
                    end
                    6'd41: begin                                 // ACMD41
                        if (poll_cnt >= 8'd2) begin
                            resp[0]    <= 8'h00;
                            idle_state <= 1'b0;
                        end else begin
                            resp[0] <= 8'h01;                    // 前两次故意 busy
                        end
                        poll_cnt <= poll_cnt + 8'd1;
                        resp_len <= 1;
                    end
                    6'd58: begin                                 // CMD58 -> OCR
                        resp[0] <= idle_state ? 8'h01 : 8'h00;
                        resp[1] <= 8'hC0;                        // bit31=1, CCS=1
                        resp[2] <= 8'hFF;                        // 电压窗口
                        resp[3] <= 8'h80;
                        resp[4] <= 8'h00;
                        resp_len<= 5;
                    end
                    6'd59: begin                                 // CMD59 -> CRC on
                        resp[0] <= idle_state ? 8'h01 : 8'h00;
                        resp_len<= 1;
                    end
                    6'd17: begin                                 // CMD17 -> 读单块
                        if (idle_state) begin
                            resp[0] <= 8'h01;
                            resp_len<= 1;
                        end else begin
                            resp[0] <= 8'h00;                    // R1 = ready
                            for (i = 0; i < TOKEN_DELAY_BYTES; i = i + 1)
                                resp[1+i] <= 8'hFF;
                            resp[1+TOKEN_DELAY_BYTES] <= 8'hFE;
                            for (i = 0; i < 512; i = i + 1) begin
                                resp[2 + TOKEN_DELAY_BYTES + i] <= img[arg * 512 + i];
                            end
                            resp[514+TOKEN_DELAY_BYTES] <= 8'hFF;
                            resp[515+TOKEN_DELAY_BYTES] <= 8'hFF;
                            resp_len  <= 516+TOKEN_DELAY_BYTES;
                        end
                    end
                    default: begin                               // 其他 -> 非法命令
                        resp[0] <= 8'h04;
                        resp_len<= 1;
                    end
                    endcase
                    in_resp   <= 1'b1;
                    resp_idx  <= 0;
                    if (DEBUG) $display("[%0t] CARD cmd=%0d arg=%08X resp_len=%0d idle=%b",
                                        $time, cmd, arg, (cmd == 6'd17 && !idle_state) ? 516 : 
                                        (cmd == 6'd8 || cmd == 6'd58) ? 5 : 1, idle_state);
                end else begin
                    frame_idx <= frame_idx + 3'd1;
                end
            end

            //---------------- 发送下一个字节（本边界先发旧的 next_byte）--------
            if (DEBUG) $display("[%0t] CARD tx=%02X in_resp=%b ridx=%0d rlen=%0d poll=%0d cs=%b",
                                $time, next_byte, in_resp, resp_idx, resp_len, poll_cnt, cs_n);
            tx_byte <= {next_byte[6:0], 1'b1};
            miso_r  <= next_byte[7];
        end else begin
            // 字节内：移位输出
            miso_r  <= tx_byte[7];
            tx_byte <= {tx_byte[6:0], 1'b1};
        end
    end

    // 采样 MOSI（上升沿）
    always @(posedge sck) begin
        if (!cs_n) begin
            rx_sh   <= {rx_sh[6:0], mosi};
            bit_cnt <= bit_cnt + 4'd1;
        end
    end

endmodule
