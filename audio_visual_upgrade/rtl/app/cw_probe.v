//=====================================================================
// cw_probe.v —— Step 0 装载并发探测（**单笔仪表**版，2026-10-09 重写）
//
// ★★ 为什么要重写（v1 的教训，逐条）：
//   v1 是"**周期发起**"（每 `GAP_MS` 给一个 `start` 脉冲），结果它**测不出目标** ✗：
//     · `GAP_MS=200` ⇒ **第一次间隔也要等 200ms** ⇒ 整段仿真里一次都没发起 ✗
//     · `GAP_MS=2`   ⇒ 发起时**开机那一笔还在飞**（`start` 被 `bmp_load` 忽略 ✗）
//                      ⇒ 台里"等一笔装载"挂到了**开机那一笔**上，测出 `wrote=0` ✗
//     · `GAP_MS=0`   ⇒ 装载器一空就发起 ⇒ **129 次连续重开** ✗
//                      ⇒ 写命令从 128 涨到 **600**、每笔只剩 26 字、画面坏 3 帧 ✗
//   ⇒ 根因有两条：**① 没有应答**（探针不知道上一笔成没成、写完没有 ✗）
//                 **② 周期发起**（吞掉 / 滥用重开，两种极端都出现 ✗）
//
// ★★ v2 的形态（**单笔、有应答**）：
//   · 只在 `en && boot_done && !busy` 时发起**一笔**（`N_LOAD` 笔为止，默认 1 笔 ✓）
//   · 发起后**死等 `done`**（或超时），把结果锁存下来：
//       `res_vld` / `res_err` / `res_cyc`（耗时拍数）/ `res_n`（累计完成笔数）
//   · 一笔未结束**绝不发第二笔** ⇒ 不会吞、不会滥用重开 ✓
//   ⇒ 台里只需等 `res_vld`，就能拿到"**成没成、错码几、用了多久**" ✓
//   ★ 写了多少字由**台**从 `u_load.wdone` 的峰值取（本模块不接 `wdone` ✗，
//     免得为它给 `bmp_load` 加端口、牵动 4 处例化 ✓）
//
// ★ 它**只在 `en_cwp=1` 时**接管 `bmp_load` 的 `start/index/slot` 三个输入 ✓
//   `en_cwp=0` ⇒ `active` 恒 0 ⇒ 顶层三选一 mux 全走原路 ⇒ **逐位不变** ✓
//
// 目标器件：EG4S20BG256（HX4S20）· Verilog-2001 · `default_nettype none`
//=====================================================================
`default_nettype none

module cw_probe #(
    parameter integer CLK_HZ = 50000000,
    // ★ 发起几笔为止（1 = 单笔仪表 ✓；扫剂量时可用 2/4/8）
    parameter integer N_LOAD = 1,
    // ★ 单笔超时（ms）：超过就锁存 `err=0xFF`（**台上一眼看出"没结束"** ✓）
    parameter integer TO_MS  = 300
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        en,             // 使能（顶层给 `en_cwp && lf_st==LF_DONE`）
    input  wire        boot_done,      // 开机装载结束
    input  wire [7:0]  file_index,     // 要装载的文件（播放表的 BG1）

    input  wire        busy,           // `bmp_load.busy`
    input  wire        done,           // `bmp_load.done`（单拍脉冲）
    input  wire [7:0]  err,            // `bmp_load.err`

    output reg         active,         // 本模块正在占用装载器（顶层 mux 选路用 ✓）
    output reg  [20:0] slot_base,      // 装载目标槽
    output reg  [7:0]  ld_idx,         // 装载文件索引
    output reg         ld_start,       // 单拍开始脉冲
    output reg         phase,          // 观测/LED：1 = 正在装载 ✓

    // ---------------- 结果（台读；板上 LED/上报也可用）----------------
    output reg         res_vld,        // 一笔完成、结果有效（保持到下一笔发起 ✓）
    output reg  [7:0]  res_err,        // 0 = 成功；0xFF = 本模块超时；其余 = bmp_load 的错误码
    output reg  [31:0] res_cyc,        // 该笔耗时（clk 拍数）
    output reg  [7:0]  res_n           // 累计完成笔数
);
    localparam [1:0] S_IDLE = 2'd0,   // 等条件
                     S_GO   = 2'd1,   // 已发 start，撤脉冲
                     S_WAIT = 2'd2,   // 死等 done / 超时
                     S_RES  = 2'd3;   // 结果有效，驻留

    // ★ 装载目标槽：**追加式**，紧接 CV_C 实占之后、`0x200000` 之前的一段无消费区 ✓
    localparam [20:0] SLOT_BASE = 21'h1C0800;

    localparam [31:0] TO_CYC = (CLK_HZ / 1000) * TO_MS;

    reg [1:0]  st;
    reg [31:0] cyc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; active <= 1'b0; slot_base <= SLOT_BASE; ld_idx <= 8'd0;
            ld_start <= 1'b0; phase <= 1'b0;
            res_vld <= 1'b0; res_err <= 8'h00; res_cyc <= 32'd0; res_n <= 8'd0;
            cyc <= 32'd0;
        end else begin
            case (st)
                //---------------------------------------------------------
                S_IDLE: begin
                    active   <= 1'b0;
                    ld_start <= 1'b0;
                    phase    <= 1'b0;
                    if (en && boot_done && !busy && (res_n < N_LOAD[7:0])) begin
                        ld_idx    <= file_index;
                        slot_base <= SLOT_BASE;
                        cyc       <= 32'd0;
                        res_vld   <= 1'b0;          // 新一笔开始 ⇒ 上一笔的结果作废 ✓
                        active    <= 1'b1;
                        ld_start  <= 1'b1;          // 单拍脉冲
                        phase     <= 1'b1;
                        st        <= S_GO;
                    end
                end
                //---------------------------------------------------------
                S_GO: begin
                    ld_start <= 1'b0;               // start 只保持一拍 ✓
                    st       <= S_WAIT;
                end
                //---------------------------------------------------------
                S_WAIT: begin
                    cyc <= cyc + 32'd1;
                    if (done) begin
                        res_err <= err;
                        res_cyc <= cyc;
                        res_n   <= res_n + 8'd1;
                        res_vld <= 1'b1;
                        active  <= 1'b0;
                        phase   <= 1'b0;
                        st      <= S_RES;
                    end else if (cyc >= TO_CYC) begin
                        // ★ 本模块自己的超时：锁存 0xFF ⇒ **台上立刻能分辨"没结束"**
                        //   （与 `bmp_load` 自己的 0x04 区分开 ✓）
                        res_err <= 8'hFF;
                        res_cyc <= cyc;
                        res_n   <= res_n + 8'd1;
                        res_vld <= 1'b1;
                        active  <= 1'b0;
                        phase   <= 1'b0;
                        st      <= S_RES;
                    end
                end
                //---------------------------------------------------------
                S_RES: begin
                    res_vld <= 1'b1;                // 驻留到下一笔发起（S_IDLE 里清 ✓）
                    active  <= 1'b0;
                    phase   <= 1'b0;
                    // 已发够笔数 ⇒ 永远驻留；否则回 IDLE 继续（等装载器空闲）
                    st <= (res_n >= N_LOAD[7:0]) ? S_RES : S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
