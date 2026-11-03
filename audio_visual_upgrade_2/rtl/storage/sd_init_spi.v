`default_nettype none
//=============================================================================
// sd_init_spi.v
//   SD 卡 SPI 模式初始化控制器（面向 SDHC / SD Physical Layer Spec v2.00+）
//
//   流程（全部依据 SD_Spec_Part1_Physical_Layer_v2.00_2006）：
//     PWR     : CS=1，发 10 字节 0xFF = 80 个时钟（规范要求 >=74 个时钟）
//               §6.4.1 P.92
//     CMD0    : CS=0 期间发 CMD0（CRC 固定 0x95）进入 SPI 模式，期望 R1=0x01
//               §7.2.1 P.94 / §7.2.2 P.98
//     CMD8    : VHS=0001b(2.7-3.6V)、check pattern=0xAA，期望 R1=0x01 且
//               返回的 32bit 回显 0x0000_01AA；回"非法命令"= V1.x 老卡
//               §4.2.2 P.14 / §4.3.13 P.40 / Table 7-5 P.108
//     CMD59   : 可选，打开卡侧 CRC 校验（参数 CRC_ON=1 时才发）
//     CMD55+ACMD41 : 轮询直到 R1 的 in_idle_state=0；ACMD41 参数只有
//               [31]=0 / [30]=HCS=1 / [29:0]=0（SPI 模式没有电压窗口字段）
//               §7.2.1 P.95 / Table 7-4 P.107
//     CMD58   : 读 OCR，判 CCS=OCR[30]，1=SDHC；要求卡接受了 CMD8 且
//               初始化已完成，CCS 才有效
//               §7.2.1 P.95 / Table 7-3 P.106
//
//   说明：
//     - 纯 SPI Mode 0（CPOL=0, CPHA=0），由 sd_spi_byte 保证上升沿采样、
//       下降沿更新；本模块负责 CS。
//     - 所有命令的 CRC7 由硬件生成（frame_of 函数），CMD0/CMD8 与规范给的
//       固定值一致（0x95 / 0x87）。
//     - 状态输出 init_done / init_fail 均为"保持"电平，只有复位才清除。
//=============================================================================
module sd_init_spi #(
    parameter integer CLK_HZ          = 50000000,  // 输入时钟频率
    parameter integer INIT_SCK_HZ     = 300000,    // 初始化 SCK 目标频率（<=400kHz）
    parameter integer POLL_TIMEOUT_MS = 1000,      // ACMD41 轮询总超时（规范 1s）
    parameter integer WATCHDOG_MS     = 2000,      // 全程看门狗
    parameter integer RESP_MAX_BYTES  = 16,        // 找 R1 时最多发多少个 0xFF
    // CMD0 之前先发的 0xFF 字节数（= PWR_BYTES*8 个时钟，CS 保持高）。
    //   规范只要求 >= 74 个时钟；默认 520 字节 ≈ 4160 个时钟（400kHz 下约 10ms），
    //   目的是**把上一次会话/一次被打断的数据块冲干净**（详见 §9.7 的实测记录）：
    //   数据块中途拉高 CS 中止后，卡会继续"吐这一块"，此后 CMD0 读到非法 R1
    //   （E_CMD0=1）或干脆无响应（E_NO_RESP=4）；每次重试只给约 256 个时钟不够用。
    //   仿真里 TB 会覆盖回 10，免得初始化太慢。
    parameter integer PWR_BYTES       = 520,
    parameter         REQUIRE_SDHC    = 1'b1,      // 1: CCS 必须为 1 才算成功
    parameter         AUTO_START      = 1'b1,      // 1: 复位释放后自动开始
    parameter         CRC_ON          = 1'b0       // 1: 发 CMD59 打开卡侧 CRC
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,        // AUTO_START=0 时的启动脉冲
    output reg         init_done,    // 初始化完成（保持）
    output reg         init_fail,    // 初始化失败（保持）
    output reg  [3:0]  err_code,     // 失败原因，见 E_* 编码
    output reg         card_sdhc,    // 1 = 高容量卡（CCS=1）
    output reg  [31:0] ocr,          // CMD58 读回的 OCR（调试用）
    output reg  [15:0] poll_count,   // 实际发出的 ACMD41 次数（调试用）
    output wire [7:0]  r1_dbg,       // 最近一次命令的 R1（调试用，供上板显示）
    output wire        busy,         // 初始化进行中
    output wire        sck,
    output wire        cs_n,
    output wire        mosi,
    input  wire        miso
);

    //-------------------------------------------------------------------------
    // 参数换算
    //-------------------------------------------------------------------------
    // HALF_PERIOD 向上取整，保证 SCK <= INIT_SCK_HZ
    localparam integer HALF_PERIOD        = (CLK_HZ + (2 * INIT_SCK_HZ) - 1) / (2 * INIT_SCK_HZ);
    localparam [31:0]  POLL_TIMEOUT_CYCLES = (CLK_HZ / 1000) * POLL_TIMEOUT_MS;
    localparam [31:0]  WATCHDOG_CYCLES     = (CLK_HZ / 1000) * WATCHDOG_MS;

    //-------------------------------------------------------------------------
    // 编码
    //-------------------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0, S_PWR  = 3'd1, S_CMD  = 3'd2,
                     S_RESP = 3'd3, S_EVAL = 3'd4, S_DONE = 3'd5, S_FAIL = 3'd6;

    localparam [2:0] ST_CMD0 = 3'd0, ST_CMD8 = 3'd1, ST_CMD59 = 3'd2,
                     ST_CMD55 = 3'd3, ST_ACMD41 = 3'd4, ST_CMD58 = 3'd5;

    localparam [3:0] E_NONE     = 4'h0,  // 无错误
                     E_CMD0     = 4'h1,  // CMD0 的 R1 != 0x01
                     E_LEGACY   = 4'h2,  // CMD8 回非法命令 -> V1.x 卡
                     E_CMD8_ECHO = 4'h3, // CMD8 电压/图案回显不符
                     E_NO_RESP  = 4'h4,  // 命令无响应或返回非法命令
                     E_POLL_TO  = 4'h5,  // ACMD41 轮询超时
                     E_CMD58    = 4'h6,  // OCR 无效（bit31=0 或电压窗口为空）
                     E_NOT_SDHC = 4'h7,  // CCS=0，不是高容量卡
                     E_WDOG     = 4'h8,  // 看门狗超时
                     E_CMD8_VCA = 4'hA,  // CMD8 R1=0x01 但 VCA=0：卡不接受所供电压
                     E_CMD8_PAT = 4'hB,  // CMD8 R1=0x01、VCA!=0，但 check pattern 未原样回显
                     E_CMD8_MISC= 4'hC;  // CMD8 R1=0x01、VCA 与 pattern 正常，其他位不符

    //-------------------------------------------------------------------------
    // CRC7 与命令帧生成
    //-------------------------------------------------------------------------
    function [6:0] crc7_step;
        input [6:0] crc_in;
        input [7:0] data_in;
        integer i;
        reg [6:0] c;
        reg       msb;
        begin
            c = crc_in;
            for (i = 7; i >= 0; i = i - 1) begin
                msb = c[6];
                c   = {c[5:0], 1'b0};
                if (msb ^ data_in[i]) c = c ^ 7'h09;
            end
            crc7_step = c;
        end
    endfunction

    function [39:0] head_of;
        input [2:0] s;
        begin
            case (s)
                ST_CMD0:   head_of = 40'h40_00_00_00_00;
                ST_CMD8:   head_of = 40'h48_00_00_01_AA;
                ST_CMD59:  head_of = 40'h7B_00_00_00_01;
                ST_CMD55:  head_of = 40'h77_00_00_00_00;
                ST_ACMD41: head_of = 40'h69_40_00_00_00;   // HCS=1
                ST_CMD58:  head_of = 40'h7A_00_00_00_00;
                default:   head_of = 40'h00_00_00_00_00;
            endcase
        end
    endfunction

    function [47:0] frame_of;
        input [39:0] h;
        reg [6:0] c0, c1, c2, c3, c4;
        begin
            c0 = crc7_step(7'd0, h[39:32]);
            c1 = crc7_step(c0,   h[31:24]);
            c2 = crc7_step(c1,   h[23:16]);
            c3 = crc7_step(c2,   h[15:8]);
            c4 = crc7_step(c3,   h[7:0]);
            frame_of = {h, c4, 1'b1};
        end
    endfunction

    //-------------------------------------------------------------------------
    // 状态
    //-------------------------------------------------------------------------
    reg [2:0]  state;
    reg [2:0]  step;
    reg [3:0]  err_r;

    reg [15:0] pwr_cnt;
    reg [3:0]  cmd_idx;
    reg [47:0] tx_shift;

    reg [7:0]  r1;
    reg [31:0] r3;
    reg        resp_phase;    // 0: 找 R1, 1: 收 R3/R7 的 4 个字节
    reg [2:0]  extra_left;
    reg [4:0]  resp_cnt;

    reg [31:0] timer;
    reg [31:0] wdog;

    reg        tx_active;
    reg        start_d;

    wire       start_pulse = start & ~start_d;

    // 本步响应在 R1 之后还要收几个字节
    wire [2:0] extra_total = (step == ST_CMD8 || step == ST_CMD58) ? 3'd4 : 3'd0;

    //-------------------------------------------------------------------------
    // 字节收发引擎
    //-------------------------------------------------------------------------
    wire       be_busy, be_done;
    wire [7:0] be_rx;
    wire [7:0] be_tx;

    wire byte_free = ~be_busy & ~be_done & ~tx_active;
    wire be_start  = ((state == S_PWR) || (state == S_CMD) || (state == S_RESP)) && byte_free;

    assign be_tx  = (state == S_CMD) ? tx_shift[47:40] : 8'hFF;
    assign cs_n   = (state == S_PWR || state == S_IDLE ||
                     state == S_DONE || state == S_FAIL) ? 1'b1 : 1'b0;
    assign busy   = (state != S_IDLE) && (state != S_DONE) && (state != S_FAIL);
    assign r1_dbg = r1;

    sd_spi_byte u_byte (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (be_start),
        .tx_data     (be_tx),
        .half_period (HALF_PERIOD[15:0]),
        .busy        (be_busy),
        .done        (be_done),
        .rx_data     (be_rx),
        .sck         (sck),
        .mosi        (mosi),
        .miso        (miso)
    );

    //-------------------------------------------------------------------------
    // 主状态机
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            step       <= ST_CMD0;
            err_r      <= E_NONE;
            pwr_cnt    <= 16'd0;
            cmd_idx    <= 4'd0;
            tx_shift   <= 48'd0;
            r1         <= 8'd0;
            r3         <= 32'd0;
            resp_phase <= 1'b0;
            extra_left <= 3'd0;
            resp_cnt   <= 5'd0;
            timer      <= 32'd0;
            wdog       <= 32'd0;
            tx_active  <= 1'b0;
            start_d    <= 1'b0;
            init_done  <= 1'b0;
            init_fail  <= 1'b0;
            err_code   <= E_NONE;
            card_sdhc  <= 1'b0;
            ocr        <= 32'd0;
            poll_count <= 16'd0;
        end else begin
            start_d <= start;

            // ---- 计时 ----
            if (wdog < WATCHDOG_CYCLES) wdog <= wdog + 32'd1;
            if (state == S_IDLE || state == S_DONE || state == S_FAIL) timer <= 32'd0;
            else if (timer <= POLL_TIMEOUT_CYCLES) timer <= timer + 32'd1;

            // ---- 字节引擎握手 ----
            if (be_start)      tx_active <= 1'b1;
            else if (be_done)  tx_active <= 1'b0;

            // ---- 看门狗优先于正常流程 ----
            if (busy && (wdog >= WATCHDOG_CYCLES)) begin
                err_r <= E_WDOG;
                state <= S_FAIL;
            end else begin
                case (state)
                //-------------------------------------------------------------
                S_IDLE: begin
                    if (AUTO_START || start_pulse) begin
                        wdog    <= 32'd0;
                        pwr_cnt <= 16'd0;
                        step    <= ST_CMD0;
                        err_r   <= E_NONE;
                        state   <= S_PWR;
                    end
                end
                //-------------------------------------------------------------
                // CS=1，发 80 个时钟
                S_PWR: begin
                    if (be_done) begin
                        if (pwr_cnt == PWR_BYTES - 1) begin
                            step       <= ST_CMD0;
                            tx_shift   <= frame_of(head_of(ST_CMD0));
                            cmd_idx    <= 4'd0;
                            resp_phase <= 1'b0;
                            resp_cnt   <= 5'd0;
                            state      <= S_CMD;
                        end else begin
                            pwr_cnt <= pwr_cnt + 16'd1;
                        end
                    end
                end
                //-------------------------------------------------------------
                // 发送当前 step 的 6 字节命令
                S_CMD: begin
                    if (be_done) begin
                        tx_shift <= {tx_shift[39:0], 8'hFF};
                        if (cmd_idx == 4'd5) begin
                            cmd_idx    <= 4'd0;
                            resp_phase <= 1'b0;
                            resp_cnt   <= 5'd0;
                            state      <= S_RESP;
                        end else begin
                            cmd_idx <= cmd_idx + 4'd1;
                        end
                    end
                end
                //-------------------------------------------------------------
                // 发 0xFF 收响应
                S_RESP: begin
                    if (be_done) begin
                        if (resp_phase == 1'b0) begin
                            if (be_rx[7] == 1'b0) begin
                                r1 <= be_rx;
                                if (extra_total == 3'd0) begin
                                    state <= S_EVAL;
                                end else begin
                                    resp_phase <= 1'b1;
                                    extra_left <= extra_total;
                                    r3         <= 32'd0;
                                end
                            end else begin
                                resp_cnt <= resp_cnt + 5'd1;
                                if (resp_cnt + 5'd1 >= RESP_MAX_BYTES) begin
                                    err_r <= E_NO_RESP;
                                    state <= S_FAIL;
                                end
                            end
                        end else begin
                            r3         <= {r3[23:0], be_rx};
                            extra_left <= extra_left - 3'd1;
                            if (extra_left == 3'd1) state <= S_EVAL;
                        end
                    end
                end
                //-------------------------------------------------------------
                // 按 step 判定并决定下一步
                S_EVAL: begin
                    case (step)
                    ST_CMD0: begin
                        if (r1 == 8'h01) begin
                            step       <= ST_CMD8;
                            tx_shift   <= frame_of(head_of(ST_CMD8));
                            cmd_idx    <= 4'd0;
                            resp_phase <= 1'b0;
                            resp_cnt   <= 5'd0;
                            state      <= S_CMD;
                        end else begin
                            err_r <= E_CMD0;
                            state <= S_FAIL;
                        end
                    end
                    ST_CMD8: begin
                        if (r1[2]) begin                 // 非法命令 -> V1.x
                            err_r <= E_LEGACY;
                            state <= S_FAIL;
                        end else if (r1 != 8'h01) begin  // 含 CRC 错等
                            err_r <= E_CMD8_ECHO;
                            state <= S_FAIL;
                        end else if (r3[11:8] == 4'h0) begin  // VCA=0：卡不接受所供电压
                            err_r <= E_CMD8_VCA;
                            state <= S_FAIL;
                        end else if (r3[7:0] != 8'hAA) begin  // check pattern 未原样回显
                            err_r <= E_CMD8_PAT;
                            state <= S_FAIL;
                        end else begin
                            // VCA 与 check pattern 都正确即通过：R7 = R1|Ver|Reserved|VCA|Pattern，
                            // 规范只要求回显供电压与 check pattern，[31:12] 的 Ver/Reserved 不参与判定
                            step       <= CRC_ON ? ST_CMD59 : ST_CMD55;
                            tx_shift   <= frame_of(head_of(CRC_ON ? ST_CMD59 : ST_CMD55));
                            cmd_idx    <= 4'd0;
                            resp_phase <= 1'b0;
                            resp_cnt   <= 5'd0;
                            state      <= S_CMD;
                        end
                    end
                    ST_CMD59: begin
                        if (r1[2]) begin
                            err_r <= E_NO_RESP;
                            state <= S_FAIL;
                        end else begin
                            step       <= ST_CMD55;
                            tx_shift   <= frame_of(head_of(ST_CMD55));
                            cmd_idx    <= 4'd0;
                            resp_phase <= 1'b0;
                            resp_cnt   <= 5'd0;
                            state      <= S_CMD;
                        end
                    end
                    ST_CMD55: begin
                        if (r1[2]) begin
                            err_r <= E_NO_RESP;
                            state <= S_FAIL;
                        end else begin
                            step       <= ST_ACMD41;
                            tx_shift   <= frame_of(head_of(ST_ACMD41));
                            cmd_idx    <= 4'd0;
                            resp_phase <= 1'b0;
                            resp_cnt   <= 5'd0;
                            state      <= S_CMD;
                        end
                    end
                    ST_ACMD41: begin
                        if (r1[2]) begin                 // 不认 ACMD41（如 MMC）
                            err_r <= E_NO_RESP;
                            state <= S_FAIL;
                        end else begin
                            poll_count <= poll_count + 16'd1;
                            if (r1[0]) begin             // 仍在初始化
                                if (timer >= POLL_TIMEOUT_CYCLES) begin
                                    err_r <= E_POLL_TO;
                                    state <= S_FAIL;
                                end else begin
                                    step       <= ST_CMD55;
                                    tx_shift   <= frame_of(head_of(ST_CMD55));
                                    cmd_idx    <= 4'd0;
                                    resp_phase <= 1'b0;
                                    resp_cnt   <= 5'd0;
                                    state      <= S_CMD;
                                end
                            end else begin               // 就绪 -> 读 OCR
                                step       <= ST_CMD58;
                                tx_shift   <= frame_of(head_of(ST_CMD58));
                                cmd_idx    <= 4'd0;
                                resp_phase <= 1'b0;
                                resp_cnt   <= 5'd0;
                                state      <= S_CMD;
                            end
                        end
                    end
                    ST_CMD58: begin
                        ocr       <= r3;
                        card_sdhc <= r3[30];
                        if (r3[31] == 1'b0 || r3[23:15] == 9'd0) begin
                            err_r <= E_CMD58;
                            state <= S_FAIL;
                        end else if (REQUIRE_SDHC && (r3[30] == 1'b0)) begin
                            err_r <= E_NOT_SDHC;
                            state <= S_FAIL;
                        end else begin
                            init_done <= 1'b1;
                            state     <= S_DONE;
                        end
                    end
                    default: begin
                        err_r <= E_WDOG;
                        state <= S_FAIL;
                    end
                    endcase
                end
                //-------------------------------------------------------------
                S_DONE: begin
                    state <= S_DONE;      // 保持，CS 已拉高
                end
                S_FAIL: begin
                    if (!init_fail) begin
                        init_fail <= 1'b1;
                        err_code  <= err_r;
                    end
                    state <= S_FAIL;      // 保持
                end
                default: state <= S_FAIL;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
