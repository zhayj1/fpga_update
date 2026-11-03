`default_nettype none
//============================================================================
// rtl/mem/sdram_ctrl.v —— 自研 SDRAM 控制器
//
// ★ 状态（2026-09-30）：**WIP，功能验证进行中**
//   · 已做：ModelSim 语法编译通过；FSM 已重写为"命令与状态同拍、等待单独成状态"
//   · 待做：TB 五组场景（初始化/单拍读写/同行/换行/换 bank）、刷新穿插、行打开流式优化
//   · ⇒ 不计入任何验收
//
// 设计：BL=1 + 行打开。行命中时一次 ACT 可连着发多条 READ/WRITE；行不同才付 PRE+tRP+ACT+tRCD。
// 器件：EM638325（4 bank × 2048 行 × 256 列 × 32bit，2M×32）
// 地址：addr[20:19]=bank、addr[18:8]=row、addr[7:0]=col
//
// 客户端：req 电平（保持到 ready）→ 控制器锁存请求 → 忙完 done 一拍；
//         读：rdata_valid 脉冲时 rdata 有效（在 done 之前）
//============================================================================
module sdram_ctrl #(
    parameter integer CL      = 3,
    // 时序参数来源：sim/vendor/IS42s32200.v（安路改过的模型，模型自身的检查就用这些值）
    //   tRCD=21ns→3拍  tRP=21ns→3拍  tRAS=49ns→5拍  tRC=70ns→7拍  tMRD=2拍
    parameter integer T_RCD   = 3,
    parameter integer T_RP    = 3,
    parameter integer T_RAS   = 5,
    parameter integer T_RFC   = 7,
    parameter integer T_MRD   = 2,
    parameter integer T_INIT  = 20000,   // 上电等待 200us @100MHz（JEDEC，少了 MRS 会被拒）
    parameter integer REF_IVL = 1560,                 // 15.6us @100MHz
    parameter [11:0]  MRS_WORD = 12'b0000_0011_0000   // [6:4]=CL=3, [2:0]=BL=1
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        wr,
    input  wire [20:0] addr,
    input  wire [31:0] wdata,
    output wire        ready,
    output reg  [31:0] rdata,
    output reg         rdata_valid,
    output reg         done,
    output wire        sd_clk,
    output wire        sd_cke,
    output wire        sd_cs_n,
    output wire        sd_ras_n,
    output wire        sd_cas_n,
    output wire        sd_we_n,
    output wire [10:0] sd_addr,
    output wire [1:0]  sd_ba,
    output wire [3:0]  sd_dm,
    output wire [31:0] sd_dq_o,
    output wire        sd_dq_oe,
    input  wire [31:0] sd_dq_i
);

    // 命令编码（RAS_n,CAS_n,WE_n）—— 2026-09-30 踩过：ACT/PRE 与 READ/WRITE 写反，
    // 导致初始化把 PRE-all 当 ACT 发出、读操作实际在写。对照表：
    //   MRS 000 | REF 001 | PRE 011 | ACT 010 | READ 100 | WRITE 101 | NOP 111
    localparam [2:0] C_NOP = 3'b111, C_ACT = 3'b010, C_READ = 3'b100,
                     C_WRITE = 3'b101, C_PRE = 3'b011, C_REF = 3'b001, C_MRS = 3'b000;

    // 每个"要发命令"的状态只停 1 拍；等待单独成状态
    localparam [4:0] S_IWAIT= 5'd20, S_WRAS = 5'd21,
                     S_IPRE = 5'd0, S_IPREW = 5'd1, S_IREF = 5'd2, S_IREFW = 5'd3,
                     S_IREF2 = 5'd4, S_IREFW2 = 5'd5, S_IMRS = 5'd6, S_IMRSW = 5'd7,
                     S_RUN  = 5'd8, S_PRE = 5'd9, S_PREW = 5'd10,
                     S_ACT  = 5'd11, S_ACTW = 5'd12, S_COL = 5'd13, S_RDW = 5'd14,
                     S_RPRE = 5'd15, S_RPREW = 5'd16, S_REF = 5'd17, S_REFW = 5'd18,
                     S_FIN  = 5'd19;

    reg [4:0]  st;
    reg [3:0]  wc;                        // 等待计数
    reg        wr_r;                      // 锁存的请求
    reg [20:0] addr_r;
    reg [31:0] wdata_r;
    reg [1:0]  b_r;
    reg [10:0] rw_r;
    reg [7:0]  col_r;
    reg [15:0] ref_timer;
    reg [15:0] init_dly;
    reg [5:0]  act_age;      // ACT 之后的拍数（tRAS 用）
    reg        ref_pend;
    reg        row_v [0:3];
    reg [10:0] row_a [0:3];
    reg [31:0] rd_sr [0:CL-1];
    reg        rv_sr [0:CL-1];
    integer    i;

    // ---------------- 命令由状态直接组合给出（同拍，不留歧义）----------------
    reg [2:0]  cmd;
    reg [10:0] sa;
    reg [1:0]  ba;
    always @(*) begin
        cmd = C_NOP; sa = 11'd0; ba = 2'd0;
        case (st)
        S_IPRE, S_RPRE: begin cmd = C_PRE; sa = 11'h400; end    // A10=1：all banks
        S_PRE:          begin cmd = C_PRE; sa = 11'd0;  ba = b_r; end
        S_IREF, S_IREF2, S_REF: cmd = C_REF;
        S_IMRS:         begin cmd = C_MRS; sa = MRS_WORD[10:0]; end
        S_ACT:          begin cmd = C_ACT; sa = rw_r; ba = b_r; end
        S_COL:          begin cmd = wr_r ? C_WRITE : C_READ;
                               sa = {3'b000, col_r}; ba = b_r; end
        default: ;
        endcase
    end

    // ★ 输出级用**下降沿寄存**：命令线在周期中间才变化，器件在上升沿采样时是稳定的。
    //   不加这一级，命令会在器件采样沿上跳变 ⇒ 满屏 \ 违例（2026-09-30 踩过）。
    //   真实工程里等价做法是用 PLL 的相移输出驱动 SDRAM_CLK（厂商参考例程就是 ext_mem_clk_sft）。
    reg [2:0]  cmd_q;
    reg [10:0] sa_q;
    reg [1:0]  ba_q;
    reg [31:0] dq_q;
    reg        oe_q;
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_q <= C_NOP; sa_q <= 11'd0; ba_q <= 2'd0; dq_q <= 32'd0; oe_q <= 1'b0;
        end else begin
            cmd_q <= cmd; sa_q <= sa; ba_q <= ba; dq_q <= wdata_r; oe_q <= (cmd == C_WRITE);
        end
    end

    assign sd_clk   = clk;
    assign sd_cke   = 1'b1;
    assign sd_cs_n  = 1'b0;
    assign sd_ras_n = cmd_q[2];
    assign sd_cas_n = cmd_q[1];
    assign sd_we_n  = cmd_q[0];
    assign sd_addr  = sa_q;
    assign sd_ba    = ba_q;
    assign sd_dm    = 4'b0000;
    assign sd_dq_o  = dq_q;
    assign sd_dq_oe = oe_q;
    assign ready    = (st == S_RUN) && !ref_pend;

    // ---------------- FSM ----------------
    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IWAIT; wc <= 4'd0; init_dly <= 16'd0; act_age <= 6'd63; wr_r <= 1'b0; addr_r <= 21'd0; wdata_r <= 32'd0;
            b_r <= 2'd0; rw_r <= 11'd0; col_r <= 8'd0;
            ref_timer <= 16'd0; ref_pend <= 1'b0;
            done <= 1'b0; rdata <= 32'd0; rdata_valid <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin row_v[i] <= 1'b0; row_a[i] <= 11'd0; end
            for (i = 0; i < CL; i = i + 1) begin rd_sr[i] <= 32'd0; rv_sr[i] <= 1'b0; end
        end else begin
            done <= 1'b0;

            // 读数据流水：命令在引脚上的那一拍采 DQ，CL 拍后给 rdata_valid
            rd_sr[0] <= sd_dq_i;
            rv_sr[0] <= (cmd_q == C_READ);   // 采引脚上的读命令
            for (i = 1; i < CL; i = i + 1) begin
                rd_sr[i] <= rd_sr[i-1];
                rv_sr[i] <= rv_sr[i-1];
            end
            if (rv_sr[CL-1]) begin
                rdata <= rd_sr[CL-1];
                rdata_valid <= 1'b1;
            end else begin
                rdata_valid <= 1'b0;
            end

            // ACT 之后计拍数（tRAS 约束用）
            if (st == S_ACT) act_age <= 6'd0;
            else if (act_age < 6'd63) act_age <= act_age + 6'd1;

            // 刷新计时（只在运行态计时）
            if (st == S_RUN) begin
                if (ref_timer >= REF_IVL - 1) begin
                    ref_timer <= 16'd0;
                    ref_pend  <= 1'b1;
                end else begin
                    ref_timer <= ref_timer + 16'd1;
                end
            end

            case (st)
            // -------- 初始化：PRE all → REF → REF → MRS --------
            S_IWAIT: begin
                        if (init_dly >= T_INIT[15:0] - 16'd1) st <= S_IPRE;
                        else init_dly <= init_dly + 16'd1;
                     end
            S_WRAS:  begin
                        // 换行/刷新前必须满足 tRAS
                        if (act_age >= T_RAS[5:0]) st <= ref_pend ? S_RPRE : S_PRE;
                     end
            S_IPRE:  begin wc <= T_RP[3:0];  st <= S_IPREW;  end
            S_IPREW: begin if (wc == 0) st <= S_IREF; else wc <= wc - 4'd1; end
            S_IREF:  begin wc <= T_RFC[3:0]; st <= S_IREFW;  end
            S_IREFW: begin if (wc == 0) st <= S_IREF2; else wc <= wc - 4'd1; end
            S_IREF2: begin wc <= T_RFC[3:0]; st <= S_IREFW2; end
            S_IREFW2:begin if (wc == 0) st <= S_IMRS;  else wc <= wc - 4'd1; end
            S_IMRS:  begin wc <= T_MRD[3:0]; st <= S_IMRSW; end
            S_IMRSW: begin if (wc == 0) st <= S_RUN; else wc <= wc - 4'd1; end

            // -------- 运行 --------
            S_RUN: begin
                if (ref_pend) begin
                    st <= S_WRAS;                       // 先等 tRAS
                end else if (req) begin
                    wr_r   <= wr;
                    addr_r <= addr;
                    wdata_r<= wdata;
                    b_r    <= addr[20:19];
                    rw_r   <= addr[18:8];
                    col_r  <= addr[7:0];
                    if (row_v[addr[20:19]] && (row_a[addr[20:19]] == addr[18:8]))
                        st <= S_COL;                       // 行命中：直接发列命令
                    else if (row_v[addr[20:19]])
                        st <= S_WRAS;                      // 换行：先等 tRAS 再关旧行
                    else
                        st <= S_ACT;                       // 空 bank：直接开行
                end
            end

            S_PRE:  begin wc <= T_RP[3:0]; row_v[b_r] <= 1'b0; st <= S_PREW; end
            S_PREW: begin if (wc == 0) st <= S_ACT; else wc <= wc - 4'd1; end

            S_ACT:  begin wc <= T_RCD[3:0]; st <= S_ACTW; end
            S_ACTW: begin
                        if (wc == 0) begin
                            row_v[b_r] <= 1'b1;
                            row_a[b_r] <= rw_r;
                            st <= S_COL;
                        end else wc <= wc - 4'd1;
                    end

            S_COL:  begin
                        if (wr_r) st <= S_FIN;              // 写：数据已同拍给出
                        else begin wc <= CL[3:0] - 4'd1; st <= S_RDW; end
                    end
            S_RDW:  begin                                   // 等读数据落地
                        if (wc == 0) st <= S_FIN;
                        else wc <= wc - 4'd1;
                    end

            // -------- 刷新：PRE all → REF --------
            S_RPRE: begin wc <= T_RP[3:0];  st <= S_RPREW; end
            S_RPREW:begin
                        if (wc == 0) begin
                            row_v[0] <= 1'b0; row_v[1] <= 1'b0;
                            row_v[2] <= 1'b0; row_v[3] <= 1'b0;
                            st <= S_REF;
                        end else wc <= wc - 4'd1;
                    end
            S_REF:  begin wc <= T_RFC[3:0]; st <= S_REFW; end
            S_REFW: begin
                        if (wc == 0) begin
                            ref_pend <= 1'b0;
                            st <= S_RUN;
                        end else wc <= wc - 4'd1;
                    end

            S_FIN:  begin done <= 1'b1; st <= S_RUN; end
            default: st <= S_RUN;
            endcase
        end
    end

endmodule

`default_nettype wire
