`default_nettype none
//============================================================================
// rtl/load/wav_head.v —— WAV 头的**最小解析**（只认 48kHz / 16bit / stereo / PCM）
//
// ★ 它是什么：**吃一条字节流的前几十字节**，校验这是不是我们能播的 WAV ✓，
//   然后**停下**、把流原样交给流播放器 ✓（**不需要算 `data_lba`** ✗ ——
//   `storage_top` 的 `hi_*` 流是连续的 ✓，头解析完接着读就是 PCM 数据 ✓）。
//
// 【为什么只做"最小"解析（我定 ✓）】
//   · 卡里放**标准 WAV** ✓（`design` D2：48kHz/16bit/stereo ✓）⇒ 拷进去就能播 ✓；
//   · FPGA 只做**能拒**的最小校验 ⇒ 素材不合规时**如实报错误码** ✓ = A1"报告行如实" ✓；
//   · 约 100 行、7 个状态、**无乘法器/除法器** ✓（扇区数换算交给调用方用移位 ✓）。
//
// 【必须处理的"脏"情况（TB 逐项穷举 ✓）】
//   ① `fmt ` 块长度 **> 16**（`WAVE_FORMAT_EXTENSIBLE` 等 ✓）⇒ 多出的按 size 跳 ✓；
//   ② `data` **之前**有 `LIST`/`fact`/`bext` 等块 ⇒ **按 size 跳 chunk** ✓
//      （**不许写死 offset=44** ✗ —— 这是本模块存在的第一理由 ✓）；
//   ③ chunk 长度为**奇数** ⇒ 后面有 1 字节**填充** ✓；
//   ④ `data` 任意长度（含非 512 对齐 ✓）⇒ 只取长度、不搬运 ✓；
//   ⑤ 畸形头：非 RIFF / 非 WAVE / 非 PCM / 声道≠2 / 采样率≠48000 / 位深≠16 /
//      缺 `fmt ` / 缺 `data` / `data` 为空 / 头部超长 ✓ —— 各有**独立错误码** ✓。
//
// 【错误码（8 位，`{大类[7:4], 细码[3:0]}`，与 `storage_top.err_code` 同风格 ✓）】
//   0x10 非 RIFF ✓   0x11 非 WAVE ✓
//   0x20 走到 `data` 却没见过 fmt ✓   0x21 非 PCM ✓   0x22 声道数≠2 ✓
//   0x23 采样率≠48000 ✓   0x24 位深≠16 ✓   0x25 `fmt ` 块 < 16 字节 ✓
//   0x30 流结束仍无 `data` ✓   0x31 `data` 长度为 0 ✓   0x32 头部超过扫描上限 ✓
//
// ★ **错误"先到先得"** ✓：`err_set` 一旦置位，**后续检测一律不改写**错误码 ✗
//   （第一版我写成"谁最后写谁生效" ✗ ⇒ 一个非 RIFF 文件最终会报成"缺 data" ✗，
//     是 TB 抓不出来的那类错 ✗ —— 所以这里专门做了粘滞 ✓）。错误响应见文件末的**统一出口** ✓。
//
// 【与流接口的契约（重要 ✓）】
//   · 本模块是**从端**：`rd_valid/rd_data` 由上游给 ✓，`rd_ready` 由本模块给 ✓；
//   · ★ **成功时立刻撤 `rd_ready`** ✓ ⇒ **绝不吃掉 PCM 的第一个字节** ✓
//     （TB 核 `hdr_bytes` == 实际消耗 ✓）；
//   · `rd_eof`（上游已无更多字节 ✓）出现而尚未成功 ⇒ 报 `0x30` ✓，不挂死 ✓。
//============================================================================
module wav_head #(
    parameter [31:0] MAX_SCAN_BYTES = 32'd4096   // 头部扫描上限 ✓（防畸形文件把 FSM 拖死 ✗）
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          // 脉冲：开始解析（调用方已 open 该文件 ✓）
    output reg         busy,
    output reg         done,           // 脉冲：解析结束（成/败都发 ✓）
    input  wire        rd_valid,
    input  wire [7:0]  rd_data,
    output wire        rd_ready,
    input  wire        rd_eof,
    output reg  [31:0] data_bytes,     // `data` 块长度（= PCM 字节数 ✓）
    output reg  [7:0]  err_code,       // 0 = OK ✓
    output reg  [31:0] hdr_bytes       // 观测：本头实际消耗的字节数 ✓
);

    localparam [2:0] S_IDLE = 3'd0, S_RIFF = 3'd1, S_SZ1 = 3'd2, S_WAVE = 3'd3,
                     S_CID  = 3'd4, S_CSZ  = 3'd5, S_FMT = 3'd6, S_SKIP = 3'd7;

    // 错误码常量 ✓
    localparam [7:0] EC_RIFF = 8'h10, EC_WAVE = 8'h11,
                     EC_NOFMT = 8'h20, EC_NOPCM = 8'h21, EC_CH = 8'h22,
                     EC_RATE = 8'h23, EC_BITS = 8'h24, EC_FMTSHORT = 8'h25,
                     EC_NODATA = 8'h30, EC_EMPTY = 8'h31, EC_TOOLONG = 8'h32;

    reg [2:0]  st;
    reg [1:0]  k;              // 4 字节标签/长度里的字节序号 ✓
    reg [31:0] sh;             // 最近 4 字节（`{sh[23:0], b}` ⇒ 4 字节后正好原顺序 ✓）
    reg [31:0] n;              // 已消耗字节数 ✓
    reg [31:0] chunk_sz;       // 当前 chunk 的 size ✓
    reg [31:0] skip;           // 还要跳过的字节数 ✓
    reg        skip_pad;       // 跳完后是否再补 1 字节填充 ✓
    reg [3:0]  fi;             // `fmt ` 块内字节序号 0..15 ✓
    reg [31:0] acc;            // 字段累加器（**小端**：首字节是 LSB ✓）
    reg        fmt_seen;       // `fmt ` 已校验通过 ✓
    reg        err_set;        // 错误已定（粘滞 ✓）

    wire       ack = rd_valid & rd_ready;
    wire [7:0] b   = rd_data;

    // ★ "这一拍就是成功"（组合 ✓）—— 用来**保护成功路径** ✗：
    //   若不保护，成功那一拍若又恰好满足"头部超长/EOF"⇒ 统一出口会把错误码盖上去 ✗
    //   （尤其"`data` 之后文件就到头"的截断文件 ✓ —— 头是合法的 ✓ 该报成功 ✓）。
    wire ok_now = (st == S_CSZ) & ack & (sh == 32'h64617461) & fmt_seen &
                  ({b, acc[23:0]} != 32'd0);

    // 只在"要消费字节"的状态要数据 ✓；★ 一旦 err_set 就**不再索取** ✗（不再多吃字节 ✓）
    assign rd_ready = ((st == S_RIFF) | (st == S_SZ1) | (st == S_WAVE) |
                       (st == S_CID)  | (st == S_CSZ) | (st == S_FMT) | (st == S_SKIP))
                      & ~err_set & busy;

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; k <= 2'd0; sh <= 32'd0; n <= 32'd0;
            chunk_sz <= 32'd0; skip <= 32'd0; skip_pad <= 1'b0;
            fi <= 4'd0; acc <= 32'd0; fmt_seen <= 1'b0; err_set <= 1'b0;
            busy <= 1'b0; done <= 1'b0;
            data_bytes <= 32'd0; err_code <= 8'd0; hdr_bytes <= 32'd0;
        end else begin
            done <= 1'b0;

            if (ack) n <= n + 32'd1;

            case (st)
            S_IDLE: begin
                if (start) begin
                    busy <= 1'b1; k <= 2'd0; sh <= 32'd0; n <= 32'd0;
                    data_bytes <= 32'd0; err_code <= 8'd0; hdr_bytes <= 32'd0;
                    fmt_seen <= 1'b0; err_set <= 1'b0;
                    st <= S_RIFF;
                end
            end

            // "RIFF" ✓
            S_RIFF: if (ack) begin
                if (k == 2'd3) begin
                    if ({sh[23:0], b} != 32'h52494646) begin
                        err_code <= EC_RIFF; err_set <= 1'b1;
                    end else begin
                        k <= 2'd0; st <= S_SZ1;
                    end
                end else begin
                    sh <= {sh[23:0], b}; k <= k + 2'd1;
                end
            end

            // 文件长度（跳过，不校验 ✓）
            S_SZ1: if (ack) begin
                if (k == 2'd3) begin k <= 2'd0; st <= S_WAVE; end
                else           k <= k + 2'd1;
            end

            // "WAVE" ✓
            S_WAVE: if (ack) begin
                if (k == 2'd3) begin
                    if ({sh[23:0], b} != 32'h57415645) begin
                        err_code <= EC_WAVE; err_set <= 1'b1;
                    end else begin
                        k <= 2'd0; st <= S_CID;
                    end
                end else begin
                    sh <= {sh[23:0], b}; k <= k + 2'd1;
                end
            end

            // chunk id ✓
            S_CID: if (ack) begin
                sh <= {sh[23:0], b};
                if (k == 2'd3) begin k <= 2'd0; st <= S_CSZ; end
                else           k <= k + 2'd1;
            end

            // chunk size（4 字节小端 ✓）⇒ 分派 ✓
            S_CSZ: if (ack) begin
                if (k == 2'd3) begin
                    chunk_sz <= {b, acc[23:0]};
                    k <= 2'd0;
                    if (sh == 32'h666D7420) begin                    // "fmt "
                        fi <= 4'd0; st <= S_FMT;
                    end else if (sh == 32'h64617461) begin           // "data"
                        if (!fmt_seen) begin
                            err_code <= EC_NOFMT; err_set <= 1'b1;
                        end else if ({b, acc[23:0]} == 32'd0) begin
                            err_code <= EC_EMPTY; err_set <= 1'b1;
                        end else begin
                            data_bytes <= {b, acc[23:0]};            // ★ 成功 ✓
                            hdr_bytes  <= n + 32'd1;                 // 含本拍这一字节 ✓
                            busy <= 1'b0; done <= 1'b1;              // 立刻收工 ✓
                            err_set <= 1'b0;
                            st <= S_IDLE;
                        end
                    end else begin
                        skip <= {b, acc[23:0]};                      // 其它块 ⇒ 按 size 跳 ✓
                        // ★ 奇偶判据要取**值**的 bit0 = `acc[0]` ✓
                        //   （第一版写 `b[0]` ✗ —— `b` 是 size 的**第 4 个字节** ✗，
                        //    对 7(0x00000007) 它是 0x00 ⇒ 判成偶数 ⇒ **漏吃填充** ✗
                        //    ⇒ 后面全盘错位 ⇒ 最后报 0x30 ✗；WB-03 抓到的就是它 ✓）
                        skip_pad <= acc[0];
                        st <= S_SKIP;
                    end
                end else begin
                    // ★ 小端 4 字节累加：**按字节序号显式落位** ✓
                    //   （第一版写成 `{b, acc[23:0]}` ✗ —— 那是**左移** ✗ ⇒ 第二个字节
                    //    跑到 bit[31:24] ✗，48000(0x0000BB80) 被拼成 0xBB000080 ✗
                    //    ⇒ 采样率校验必错 ✗；被 WB-01..04/06/07 一起抓住 ✓）
                    case (k)
                    2'd0: acc <= {24'd0, b};
                    2'd1: acc <= {16'd0, b, acc[7:0]};
                    2'd2: acc <= {8'd0,  b, acc[15:0]};
                    default: acc <= {b, acc[23:0]};
                    endcase
                    k   <= k + 2'd1;
                end
            end

            // `fmt ` 前 16 字节逐字节校验 ✓（>16 的部分随后跳掉 ✓）
            S_FMT: if (ack) begin
                // ★ 小端累加：**按 fi 显式落位** ✓（与 S_CSZ 同一教训 ✗）
                case (fi)
                4'd0 : acc <= {24'd0, b};                 // fmt  LSB
                4'd1 : acc <= {16'd0, b, acc[7:0]};       // fmt  MSB
                4'd2 : acc <= {24'd0, b};                 // ch   LSB
                4'd3 : acc <= {16'd0, b, acc[7:0]};       // ch   MSB
                4'd4 : acc <= {24'd0, b};                 // rate b0
                4'd5 : acc <= {16'd0, b, acc[7:0]};       // rate b1
                4'd6 : acc <= {8'd0,  b, acc[15:0]};      // rate b2
                4'd7 : acc <= {b, acc[23:0]};             // rate b3
                4'd14: acc <= {24'd0, b};                 // bits LSB
                4'd15: acc <= {16'd0, b, acc[7:0]};       // bits MSB
                default: ;                                // 8..13 取值但不校验 ✓
                endcase

                if (fi == 4'd1) begin
                    if ({b, acc[7:0]} != 16'd1)     begin err_code <= EC_NOPCM; err_set <= 1'b1; end
                end else if (fi == 4'd3) begin
                    if ({b, acc[7:0]} != 16'd2)     begin err_code <= EC_CH;    err_set <= 1'b1; end
                end else if (fi == 4'd7) begin
                    if ({b, acc[23:0]} != 32'd48000) begin err_code <= EC_RATE; err_set <= 1'b1; end
                end else if (fi == 4'd15) begin
                    if ({b, acc[7:0]} != 16'd16)    begin err_code <= EC_BITS;  err_set <= 1'b1; end
                end

                if (fi == 4'd15) begin
                    fmt_seen <= 1'b1;
                    if (chunk_sz > 32'd16) begin
                        skip <= chunk_sz - 32'd16; skip_pad <= chunk_sz[0]; st <= S_SKIP;
                    end else if (chunk_sz < 32'd16) begin
                        err_code <= EC_FMTSHORT; err_set <= 1'b1;
                    end else begin
                        st <= S_CID;
                    end
                end else begin
                    fi <= fi + 4'd1;
                end
            end

            // 跳过 chunk 内容 + 奇数填充 ✓
            S_SKIP: if (ack) begin
                if (skip > 32'd1) begin
                    skip <= skip - 32'd1;
                end else if (skip == 32'd1) begin
                    skip <= 32'd0;
                    // ★ 若本块长度是**奇数** ⇒ 还差一个**填充字节** ✓
                    //   这里**不能**清 `skip_pad` ✗、也不能直接回 S_CID ✗ ——
                    //   否则那个 pad 会被当成下一个 chunk id ⇒ 后面全盘错位 ✗
                    //   （WB-03 抓到的就是这条 ✓：pad 没吃 ⇒ 最后报"没有 data" 0x30 ✗）
                    st   <= skip_pad ? S_SKIP : S_CID;
                end else if (skip_pad) begin
                    skip_pad <= 1'b0; st <= S_CID;
                end else begin
                    st <= S_CID;
                end
            end

            default: st <= S_IDLE;
            endcase

            // ------------------------------------------------------------------
            // ★ 统一出口（**放在 case 之后 ⇒ 它的赋值优先** ✓）
            //   ① 上限保护：头部超过 MAX_SCAN_BYTES ⇒ 0x32 ✓
            //   ② 上游没了而还没成功 ⇒ 0x30 ✓
            //   ③ 任何错误一旦定下 ⇒ 下一拍进"收工"（`done` 脉冲 + `busy` 拉低 ✓）
            // ------------------------------------------------------------------
            if (busy && !err_set && !ok_now && rd_eof && (st != S_IDLE)) begin
                err_code <= EC_NODATA; err_set <= 1'b1;
            end
            if (busy && !err_set && !ok_now && (n >= MAX_SCAN_BYTES)) begin
                err_code <= EC_TOOLONG; err_set <= 1'b1;      // 放最后 ⇒ 与 0x30 同拍时**它赢** ✓
            end
            if (err_set && (st != S_IDLE)) begin
                busy <= 1'b0;
                if (!done) done <= 1'b1;
                st <= S_IDLE;                 // 收工即回空闲 ⇒ 可再次 start ✓
            end
        end
    end

endmodule

`default_nettype wire
