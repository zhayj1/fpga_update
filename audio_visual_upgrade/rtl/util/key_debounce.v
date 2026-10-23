`default_nettype none
//============================================================================
// rtl/util/key_debounce.v —— 按键去抖（P1 A1：KEY4 → 组切换）
//
// 用途：把机械按键的抖动整形成"一次按下 = 一个单拍 press 脉冲"。
//   板上按键是**低有效**（与 rst_n 同一套上拉，见 skeleton_top 头注释）⇒ 默认 KEY_ACTIVE_LOW=1。
//
// 做法（三级）：
//   ① 2FF 同步：异步按键进 clk 域（单比特，标准做法）；
//   ② 稳定计数：电平保持 STABLE_CNT 拍不变才算"变"，否则重新计时 ⇒ 抖动被吸收；
//   ③ 边沿：去抖后的电平**由松开变按下**那一拍输出一个 `press` 脉冲（每次按下只一个）。
//
// 参数：
//   CLK_HZ        —— clk 频率（默认 50MHz，与 skeleton_core 的 clk 一致）
//   DEBOUNCE_MS   —— 去抖时间（默认 20ms ⇒ 50MHz 下 1,000,000 拍）
//   KEY_ACTIVE_LOW —— 1=按下为低（板上默认），0=按下为高
//
// 复位：rst_n 低有效；复位期间不产生 press。
//============================================================================
module key_debounce #(
    parameter integer CLK_HZ         = 50000000,
    parameter integer DEBOUNCE_MS    = 20,
    parameter         KEY_ACTIVE_LOW = 1
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,        // 异步按键输入
    output reg  press,         // 单拍脉冲：一次"按下"一个
    output reg  level          // 去抖后的"按下"电平（1=按下）
);
    localparam integer CNT_MAX = (CLK_HZ / 1000) * DEBOUNCE_MS;   // 需要的稳定拍数
    localparam integer CW      = (CNT_MAX < 2) ? 1 : $clog2(CNT_MAX + 1);

    // ---- ① 2FF 同步 ----
    reg [1:0] ksync;
    always @(posedge clk) begin
        if (!rst_n) ksync <= 2'b00;
        else        ksync <= {ksync[0], key_in};
    end
    // 同步后的原始电平（按极性换算成"按下=1"）
    wire raw_press = KEY_ACTIVE_LOW ? ~ksync[1] : ksync[1];

    // ---- ② 稳定计数 + ③ 边沿 ----
    reg [CW-1:0] cnt;
    reg          raw_d;
    always @(posedge clk) begin
        if (!rst_n) begin
            cnt   <= {CW{1'b0}};
            raw_d <= 1'b0;
            level <= 1'b0;
            press <= 1'b0;
        end else begin
            press <= 1'b0;                       // 默认：无脉冲
            raw_d <= raw_press;
            if (raw_press == raw_d) begin        // 与上一拍相同 ⇒ 继续计时
                if (cnt != CNT_MAX[CW-1:0]) cnt <= cnt + 1'b1;
            end else begin
                cnt <= {CW{1'b0}};               // 变了 ⇒ 重新计时（抖动的尖峰被吃掉）
            end
            // 稳定满 ⇒ 更新去抖电平；"由松开变按下"那一拍给 press
            //   ★ 必须同时要求 `raw_press == raw_d`（本拍电平已与上一拍相同、即在稳定期内）：
            //     否则"长时间松开"期间 cnt 会停在饱和值 CNT_MAX，按下第一拍就会用这个旧值
            //     立刻误发脉冲（单元 TB 的 K-03 抓到的正是这条）。
            if ((raw_press == raw_d) && (cnt == CNT_MAX[CW-1:0]) && (raw_press != level)) begin
                level <= raw_press;
                if (raw_press) press <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
