//=====================================================================
// sector_arbiter —— 扇区级交错读仲裁器（路径 1 的核心，见
//                   doc/design_interleaved_read.md §5 / §15）
//
// 职责（机制，不含任何"上层策略"）：
//   把"两条读流"对同一个 SD 扇区服务（sd_block_read）的请求，
//   按 (req, want) 授权给其中一条，并且——
//
//   ★ I1：**只在扇区边界换 owner**。
//     判据是 busy：busy=1 表示"一个扇区事务正在飞（CMD17..CS↑）"，
//     此时 owner 锁存不动；只有 busy=0（没有事务在飞）才重新评估。
//     ⇒ 永不打断数据块 ⇒ 卡不会被留在"吐半个块"状态、不需要冲块。
//
//   ★ 授权条件 = 该流"有挂起请求" **且** 上层给了 want。
//     没有 want 的流即使有请求也**安全停驻**（请求保持、不超时），
//     这就是"分块读/暂停续读"的实现点。
//     优先级：hi 高于 lo；两条都没有 want ⇒ 空闲（ow=NONE）。
//
//   ★ lo_stall：纯观测。lo"想要却拿不到"持续超过 LO_STALL_MS ⇒ 拉高。
//     want=0 的停驻**不算** stall（那是上层有意暂停）。
//     它不参与授权，不改变谁拿总线（与"RTL 不做防饿死"的决定一致）。
//
// 端口极性：全部高有效、电平信号；req/want 由外部保持。
// 本模块不产生任何时序例外：纯控制逻辑，建议综合后看 SWNS。
//=====================================================================
module sector_arbiter #(
    parameter integer CLK_HZ      = 50000000,
    // lo 流"想要却拿不到"多久算停滞（毫秒）
    parameter integer LO_STALL_MS  = 1000
)(
    input  wire        clk,
    input  wire        rst_n,        // 异步低有效（与项目其它模块一致）

    // 两条流的请求（电平，保持到被服务）
    input  wire        hi_req,       // hi 流有扇区/链请求待服务
    input  wire        lo_req,       // lo 流有扇区/链请求待服务
    // 上层给的"我现在需要这条流的数据"（电平；由上层水位/策略产生）
    input  wire        hi_want,
    input  wire        lo_want,
    // 扇区事务进行中（= sd_block_read 不在 R_IDLE）。busy=1 期间 owner 锁存
    input  wire        busy,

    // 授权（电平，二者不会同时为 1）
    output wire        hi_gnt,
    output wire        lo_gnt,
    // 当前 owner：0=无 1=hi 2=lo（供 storage_top 选通 sec_lba/sec_ready/…，并上报）
    output wire [1:0]  owner,

    // 观测：lo 停滞（超过 LO_STALL_MS）
    output reg         lo_stall
);
    localparam [1:0] OW_NONE = 2'd0,
                     OW_HI   = 2'd1,
                     OW_LO   = 2'd2;

    localparam [31:0] STALL_CYCLES = (CLK_HZ / 1000) * LO_STALL_MS;

    reg  [1:0]  ow;
    reg  [31:0] stall_cnt;

    // lo "想要却拿不到"：有请求 + 上层要 + 现在不是它拿总线
    wire lo_waiting = lo_req && lo_want && (ow != OW_LO);

    //-----------------------------------------------------------------
    // owner 决策：只在 busy=0 时评估（I1）
    //-----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ow <= OW_NONE;
        end else if (!busy) begin
            if (hi_req && hi_want)      ow <= OW_HI;   // hi 绝对优先
            else if (lo_req && lo_want) ow <= OW_LO;
            else                        ow <= OW_NONE; // 都没有 ⇒ 空闲（含"只 req 没 want"的停驻）
        end
        // busy=1：ow 保持不变 ⇒ 事务中途绝不换 owner
    end

    //-----------------------------------------------------------------
    // lo_stall：纯观测，不影响上面的授权
    //-----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stall_cnt <= 32'd0;
            lo_stall  <= 1'b0;
        end else if (!lo_waiting) begin
            stall_cnt <= 32'd0;                        // 被授权/请求消失/want 拉低 ⇒ 清零
            lo_stall  <= 1'b0;
        end else if (stall_cnt >= STALL_CYCLES) begin
            stall_cnt <= stall_cnt;                    // 到点后保持
            lo_stall  <= 1'b1;
        end else begin
            stall_cnt <= stall_cnt + 32'd1;
        end
    end

    assign hi_gnt = (ow == OW_HI);
    assign lo_gnt = (ow == OW_LO);
    assign owner  = ow;
endmodule
