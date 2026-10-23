`default_nettype none
//============================================================================
// rtl/mem/sdram_burst.v —— 厂商 SDRAM（虚拟 ERAM）IP 的**突发引擎**
//
// 依据（实测，见 doc/design_music_player.md §3.4.1、sim/vendor_probe_sdram.do）：
//   · App_rd_en → 第一个 Sdr_rd_en = 12~14 拍
//   · 地址只能在 4 字（128bit）边界跳，组内 IP 自增；地址每拍 +1 也可以（厂商示例如此）
//   · **地址与数据之间有固定相位差**：B1 探针"地址与数据同拍推进"时读回第一个字是 base+1
//     ⇒ 参数 ADDR_LEAD：1 = 第 i 拍给 base+i-1（读回才从 base 开始）；0 = 第 i 拍给 base+i
//   · 读写互斥；刷新期间（ref_vld=1）不得发起新突发
//
// 客户端接口（全在 SDRAM 时钟域）：
//   · req 必须是**电平**，保持到 busy 拉高为止（脉冲会在等刷新窗口时被丢掉）
//   · 写：客户端须提供**标准同步 FIFO**（wdata_rd 拉高后，下一拍 wdata 给出下一个字；
//         引擎在"给出 wdata_rd 的同一拍"采样 wdata，所以 FIFO 输出寄存器必须已在最前面）
//   · 读：rdata/rdata_valid 每拍一个字，顺序即 base, base+1, ...
//   · words 必须是 4 的倍数；base 必须 4 字对齐（本模块不检查，交由仲裁器保证）
//============================================================================
module sdram_burst #(
    parameter integer ADDR_LEAD = 1,
    parameter integer DRAIN_WR  = 32,
    parameter integer DRAIN_RD  = 8,
    parameter integer WD_TIMEOUT = 4096,      // 读突发看门狗（拍）
    parameter integer GROUP_GAP  = 0          // 每 4 拍使能后插入的空隙拍数（实验：吸收组边界气泡）      // 读突发看门狗（拍）
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req,
    input  wire        wr,
    input  wire [20:0] base,
    input  wire [15:0] words,
    output reg         busy,
    output reg         done,
    output reg         err_timeout,

    input  wire [31:0] wdata,
    output reg         wdata_rd,

    output reg  [31:0] rdata,
    output reg         rdata_valid,

    input  wire        ref_vld,
    output reg         app_wr_en,
    output reg  [20:0] app_wr_addr,
    output reg  [3:0]  app_wr_dm,
    output reg  [31:0] app_wr_din,
    output reg         app_rd_en,
    output reg  [20:0] app_rd_addr,
    input  wire        sdr_rd_en,
    input  wire [31:0] sdr_rd_dout
);

    localparam [2:0] S_IDLE   = 3'd0,
                     S_WRUN   = 3'd1,
                     S_WDRAIN = 3'd2,
                     S_RRUN   = 3'd3,
                     S_RDRAIN = 3'd4;

    reg [2:0]  st;
    reg [20:0] cmd_base;
    reg [15:0] cmd_words;
    reg [15:0] wcnt;        // 写：下一个要给出的字下标
    reg [15:0] acnt;        // 读：已给出的地址个数
    reg [15:0] rcnt;        // 读：已收到的字数
    reg [15:0] dly;
    reg [15:0] wdog;
    reg [20:0] rd_next;
    reg [3:0]  pc;          // 组内相位：0..(4+GROUP_GAP-1)

    wire [20:0] start_base = (ADDR_LEAD == 1) ? (base - 21'd1) : base;

    always @(posedge clk) begin
        if (!rst_n) begin
            st          <= S_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            err_timeout <= 1'b0;
            app_wr_en   <= 1'b0;
            app_rd_en   <= 1'b0;
            app_wr_addr <= 21'd0;
            app_rd_addr <= 21'd0;
            app_wr_dm   <= 4'd0;
            app_wr_din  <= 32'd0;
            wdata_rd    <= 1'b0;
            rdata_valid <= 1'b0;
            rdata       <= 32'd0;
            wcnt        <= 16'd0;
            acnt        <= 16'd0;
            rcnt        <= 16'd0;
            dly         <= 16'd0;
            pc          <= 4'd0;
            wdog        <= 16'd0;
            cmd_base    <= 21'd0;
            cmd_words   <= 16'd0;
            rd_next     <= 21'd0;
        end else begin
            done     <= 1'b0;
            wdata_rd <= 1'b0;

            case (st)
            // ---------------- 空闲 ----------------
            S_IDLE: begin
                busy        <= 1'b0;
                app_wr_en   <= 1'b0;
                app_rd_en   <= 1'b0;
                rdata_valid <= 1'b0;
                if (req && !ref_vld) begin
                    cmd_base  <= base;
                    cmd_words <= words;
                    dly       <= 16'd0;
                    wdog      <= 16'd0;
                    busy      <= 1'b1;
                    if (wr) begin
                        st          <= S_WRUN;
                        wcnt        <= 16'd0;
                        app_wr_addr <= base;
                        app_wr_dm   <= 4'd0;
                        wdata_rd    <= 1'b1;   // 标准同步 FIFO：本拍就要把首字放到 wdata
                    end else begin
                        st          <= S_RRUN;
                        acnt        <= 16'd1;
                        rcnt        <= 16'd0;
                        app_rd_addr <= start_base;
                        rd_next     <= start_base + 21'd1;
                        pc          <= 4'd0;
                        app_rd_en   <= 1'b1;
                    end
                end
            end

            // ---------------- 写突发 ----------------
            S_WRUN: begin
                app_wr_en   <= 1'b1;
                app_wr_addr <= cmd_base + {5'd0, wcnt};
                app_wr_din  <= wdata;
                app_wr_dm   <= 4'd0;
                wdata_rd    <= 1'b1;
                if (wcnt == (cmd_words - 16'd1)) begin
                    app_wr_en <= 1'b0;
                    st        <= S_WDRAIN;
                end else begin
                    wcnt <= wcnt + 16'd1;
                end
            end

            S_WDRAIN: begin
                app_wr_en <= 1'b0;
                if (dly == DRAIN_WR - 1) begin
                    dly  <= 16'd0;
                    done <= 1'b1;
                    st   <= S_IDLE;
                end else begin
                    dly <= dly + 16'd1;
                end
            end

            // ---------------- 读突发 ----------------
            S_RRUN: begin
                rdata_valid <= 1'b0;
                wdog        <= wdog + 16'd1;
                // 地址：只在**使能拍**推进；每 4 拍使能后按 GROUP_GAP 插空隙
                if (acnt < cmd_words) begin
                    if (pc < 4) begin
                        app_rd_addr <= rd_next;
                        rd_next     <= rd_next + 21'd1;
                        acnt        <= acnt + 16'd1;
                        app_rd_en   <= 1'b1;
                    end else begin
                        app_rd_en   <= 1'b0;      // 空隙拍：不推进地址
                    end
                    pc <= (pc == (4 + GROUP_GAP - 1)) ? 4'd0 : (pc + 4'd1);
                end else begin
                    app_rd_en <= 1'b0;
                end
                // 数据：与地址生成解耦，等 IP 的 14 拍延迟
                if (sdr_rd_en) begin
                    rdata       <= sdr_rd_dout;
                    rdata_valid <= 1'b1;
                    rcnt        <= rcnt + 16'd1;
                end
                if (rcnt == cmd_words) begin
                    app_rd_en <= 1'b0;
                    st        <= S_RDRAIN;
                end else if (wdog > WD_TIMEOUT) begin
                    app_rd_en   <= 1'b0;
                    err_timeout <= 1'b1;
                    st          <= S_RDRAIN;
                end
            end

            S_RDRAIN: begin
                app_rd_en <= 1'b0;
                if (dly == DRAIN_RD - 1) begin
                    dly  <= 16'd0;
                    done <= 1'b1;
                    st   <= S_IDLE;
                end else begin
                    dly <= dly + 16'd1;
                end
            end

            default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
