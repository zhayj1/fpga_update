`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: anlgoic
// Author: 	xg 
// description:  top module
//////////////////////////////////////////////////////////////////////////////////

`define DEBUG

`include "global_def.v"

module sdram_top(
    `ifdef SIMULATION
	output					SDRAM_CLK,
	output					SDR_CKE,
	output					SDR_RAS,
	output					SDR_CAS,
	output					SDR_WE,
	output	[`BA_WIDTH-1:0]	SDR_BA,
	output	[`ROW_WIDTH-1:0]SDR_ADDR,
	output	[`DM_WIDTH-1:0]	SDR_DM,
	inout	[`DATA_WIDTH-1:0]	SDR_DQ,	
	`endif
    // ★★★ 2026-10-03（**我方新增 ✓**，仅供观测 ✗、不改任何功能 ✓）：
    //   把 DRAM 命令引脚**引出**给上层 ⇒ 上层可直接译码并计数 **REFRESH 命令**
    //   （REFRESH = RAS_n=0 且 CAS_n=0 且 WE_n=1 ✓ —— 与 NOP/ACT/READ/WRITE/PRECHARGE 都不同 ✓）
    //   ★ 为什么需要它：原来只有一个"旁证"——数厂商信号 `Sdr_init_ref_vld` 的边沿 ✓，
    //     而那两个信号的语义**我们文档里就写着"自相矛盾，实测为准"** ✗（`design_music_player.md:200` ✓）
    //     ⇒ 数引脚上的真命令**不依赖任何厂商语义** ✓✓，是无歧义的口径 ✓。
    output					SDR_RAS_MON,
    output					SDR_CAS_MON,
    output					SDR_WE_MON,
    input   					Clk,
    input						Clk_sft,
    input						Rst,
    
    output 						Sdr_init_done,
    output						Sdr_init_ref_vld,
    output						Sdr_busy,
    
    input						App_wr_en,
	input [`ADDR_WIDTH-1:0]		App_wr_addr,  	
	input [`DM_WIDTH-1:0]		App_wr_dm,
	input [`DATA_WIDTH-1:0]		App_wr_din,	//synthesis keep
    
    input 						App_rd_en,
	input [`ADDR_WIDTH-1:0]		App_rd_addr,
	output 						Sdr_rd_en,
	output [`DATA_WIDTH-1:0]	Sdr_rd_dout	//synthesis keep
    
    
    
);
`ifndef SIMULATION
wire  			SDRAM_CLK;
wire 			SDR_RAS;
wire  			SDR_CAS;
wire  			SDR_WE;
wire  [`BA_WIDTH-1:0]	SDR_BA; 
wire  [`ROW_WIDTH-1:0]	SDR_ADDR;
wire  [`DATA_WIDTH-1:0]	SDR_DQ ;
wire  [`DM_WIDTH-1:0]	SDR_DM; 
`endif

// ★★★ 2026-10-03（我方新增 ✓）：监视输出 —— 把命令引脚**原样**引给上层 ✓
//   （综合/simulation 两个分支里这三个信号都存在 ✓：综合是上面 `ifndef` 里的 wire ✓，
//     simulation 是端口表里的 output ✓ ⇒ 本 assign 两边都成立 ✓）
assign SDR_RAS_MON = SDR_RAS;
assign SDR_CAS_MON = SDR_CAS;
assign SDR_WE_MON  = SDR_WE;

// ★★★ 2026-10-03（**依据厂商文档 APUG011 §2.5** ✓，不是我猜的 ✗）：
//   `self_refresh_open` 的两个取值，厂商原文（本仓 `_apug011.txt` ✓）写得很明确 ✓：
//     · 传入 **1（默认）** ⇒ **控制器自动刷新** ✓（用 `global_def.v` 的 `SELF_REFRESH_INTERVAL` 自己刷 ✓）
//     · 传入 **0** ⇒ ★ **手动刷新模式** ✗ ⇒ "**此时用户自行控制 `app_ref_req` 信号**
//       （至少拉高 1 个时钟周期），发送刷新命令后，如果收到 `sdr_ref_ack`，则表示此次刷新有效" ✓
//   ⇒ ★ **所以 0 不能单独用** ✗（= 自动刷新关掉、手动又没做 ⇒ **谁都不刷** ✗）
//     ⇒ 本文件下方已按文档**加上 `App_ref_req` 定时脉冲** ✓（见 `ref_timer` ✓）。
//   【板上实测支撑（硬数 ✓）】
//     · 引脚译码计数 `SDR REF=0` ✗ —— DRAM 命令总线上**一条 REFRESH 都没有** ✓
//       （监视线接的是**真信号** ✓：`sdr_as_ram` 直接驱动 `SDR_RAS/CAS/WE` ✓，见下方例化 ✓）
//     · 用户实验 ✓：一直快切**不花** ✓；**停下等 3~5 分钟 ⇒ 再切 ⇒ 花** ✗ ⇒ 闲置槽漏电腐烂 ✓✓
//     · 且 `assign SDR_CKE = 1'b1;` ✗（见下 ✓）⇒ **芯片进不了自刷新** ⇒ "自刷新"这条并不可行 ✓
//   【验收】★ 同一把尺子 ✓：烧上后 `SDR REF` 应从 **0** 变成 **每窗上百** ✓
//     （100MHz、窗口 200,000 拍、每 15.625µs 一条 ⇒ 约 **128** 条/窗 ✓）。
// ★★★ 2026-10-03（我方新增 ✓，按厂商文档的手动刷新路径 ✓）：`App_ref_req` 定时脉冲
//   文档要求：64ms 内 **4096 次**刷新（= 每 **15.625µs** 一次 ✓，见 `sdr_init_ref.enc.v:26` 注释 ✓）
//   本板 `clk_sdr` = 100MHz ⇒ 15.625µs = **1562 拍** ✓
//   （`Sdr_ref_ack` 没引出来 ✗，由 `sdr_as_ram` 内部与 `sdr_init_ref` 自洽 ✓）
//
// ★★★ 2026-10-04 板上实测后的**重要修正** ✗✓：**只在总线安静时请求刷新** ✓
//   【现象】手动刷新一开 ⇒ `SDR REF=128` ✓（速率达标 ✓）、**彩点消失** ✓✓
//          但画面出现 **滚动条纹 + 亮线** ✗
//   【推导】请求脉冲**不看总线在干什么** ✗ ⇒ IP 在**一次读突发中途**拉高 `Sdr_init_ref_vld` ✗
//          ⇒ 仲裁器走 `sdram_arb.v:184` 的 `S_PAUSE`（撤使能、存现场、事后续发 ✓）
//          ⇒ ★ 可 ERAM 接口契约是"**使能连续给、地址每拍 +1**" ✓ ⇒ 中断一次 ⇒ IP 内部读流水**对不齐** ✗
//          ⇒ 读回数据**整行错位**（滚动条纹 ✓）+ 个别拍丢错（亮线 ✓）
//          ⇒ 错位位置逐帧漂移 ⇒ 视觉上就是"**条纹在滚动**" ✓✓
//   【为什么以前没有】`S_PAUSE` 在原浸泡里**触发 0 次** ✗ ⇒ 这条路径**从未被验证** ✓
//          ⇒ 现在刷新一开、每帧触发几十次 ⇒ 立刻暴露 ✓✓（**不是"刷太勤"** ✗：128/窗 = 15.625µs = 手册标准 ✓）
//   【修法】`RefReq` 只在"上层接口**连续安静** `QUIET_CYC` 拍"时才发出 ✓
//          （安静窗口覆盖读数据的返回期 ✓）；时间到了但总线不安静 ⇒ **保持待发、不丢刷新** ✓
//          ⇒ 上层空闲率本来 ~80% ✓ ⇒ 刷新速率几乎不受影响 ✓，但**再也不会截断突发** ✓✓
//   【验收】① `SDR REF` 仍应 ≈128/窗 ✓；② **滚动条纹与亮线消失** ✓；③ 彩点仍不出现 ✓（三者同时 ✓）。
localparam integer REF_PERIOD_CYC = 1562;   // 100MHz × 15.625µs ✓
localparam [6:0]   QUIET_CYC      = 7'd63;  // "安静"判据：连续 63 拍无使能 ✓（覆盖读返回期 ✓）
reg  [10:0] ref_timer;                      // 0..1561 ⇒ 11 位 ✓
reg  [6:0]  quiet_cnt;                      // 安静计数 0..63 ✓
reg         app_ref_pulse;
wire        app_en_any = App_rd_en | App_wr_en;      // 上层是否正在发起访问 ✓
always @(posedge Clk) begin
    if (Rst) quiet_cnt <= 7'd0;
    else if (app_en_any) quiet_cnt <= 7'd0;                       // 有访问 ⇒ 重新计安静 ✓
    else if (quiet_cnt < QUIET_CYC) quiet_cnt <= quiet_cnt + 7'd1;
end
wire app_quiet = (quiet_cnt >= QUIET_CYC);            // 连续安静够久 ⇒ 可以插刷新 ✓
always @(posedge Clk) begin
    // Do not issue manual refresh during the vendor power-up / initialization
    // sequence; banks have not yet received PRECHARGE ALL at that point.
    if (Rst || !Sdr_init_done) begin
        ref_timer     <= 11'd0;
        app_ref_pulse <= 1'b0;
    end else if (ref_timer >= REF_PERIOD_CYC - 1) begin
        if (app_quiet) begin
            ref_timer     <= 11'd0;                    // 到点且总线安静 ⇒ 发请求 ✓
            app_ref_pulse <= 1'b1;                     // 拉高 1 拍 ✓（文档："至少 1 个时钟周期" ✓）
        end else begin
            app_ref_pulse <= 1'b0;                     // 不安静 ⇒ **保持待发** ✓（计时到顶不动 ⇒ 不丢刷新 ✓）
        end
    end else begin
        ref_timer     <= ref_timer + 11'd1;
        app_ref_pulse <= 1'b0;
    end
end

sdr_as_ram  #( .self_refresh_open(1'b0))
	u2_ram( 
		.Sdr_clk(Clk),
		.Sdr_clk_sft(Clk_sft),
		.Rst(Rst),
			  			  
		.Sdr_init_done(Sdr_init_done),
		.Sdr_init_ref_vld(Sdr_init_ref_vld),
		.Sdr_busy(Sdr_busy),
		
		.App_ref_req(app_ref_pulse),   // ★ 2026-10-03：原为常数 1'b0 ✗ ⇒ 改接我们按 15.625µs 拉的脉冲 ✓
		
        .App_wr_en(App_wr_en), 
        .App_wr_addr(App_wr_addr),  	
		.App_wr_dm(App_wr_dm),
		.App_wr_din(App_wr_din),

		.App_rd_en(App_rd_en),
		.App_rd_addr(App_rd_addr),
		.Sdr_rd_en	(Sdr_rd_en),
		.Sdr_rd_dout(Sdr_rd_dout),
	
		.SDRAM_CLK(SDRAM_CLK),
		.SDR_RAS(SDR_RAS),
		.SDR_CAS(SDR_CAS),
		.SDR_WE(SDR_WE),
		.SDR_BA(SDR_BA),
		.SDR_ADDR(SDR_ADDR),
		.SDR_DM(SDR_DM),
		.SDR_DQ(SDR_DQ)	
	);


assign SDR_CKE=1'b1;

// 器件侧：仿真用厂商提供的 Micron 行为模型 IS42s32200（APUG011 的 sim.do 里就是编译这个），
// 综合用 TD 的 SIP 原语 EG_PHY_SDRAM_2M_32（`sim_release/eg4/eg_phy_sdram_2m_32.v` 只是个壳，
// 实测不驱动 DQ ⇒ 仿真必须走 IS42s32200；依据 2026-09-30 的 probe 结果）。
`ifdef SIM_DEVICE_MODEL
	// ★★ Step 0 判别实验（2026-10-09）：把器件模型的时序档位改成**真片的档位** ✓
	//   模型自带的是 **-7 档（`tRCD = 21.0`，见 `sim/vendor/IS42s32200.v:115`）**，
	//   而板上料号 **AEM638325TS-6IG 是 SDR-166 级 ⇒ tRCD ≤ 18ns**
	//   （依据：`rtl/mem/sdram_arb.v` **契约 6** 的实测与结论 ✓）。
	//   仿真里 IP 的 ACT→访问**固定 3 拍**（同上契约）；在 ~150MHz 下 3 拍 = **20ns** ⇒
	//     · 对 **-7 档模型**：20 < 21 ⇒ ★ **每一次访问都报 tRCD 违例**（实测两臂各约 2 万条 ✓）
	//     · 对 **真片 -6 档**：20 > 18 ⇒ ★ **合法** ✓
	//   ⇒ 改这两个数是**让仿真更贴近硬件** ✓，**不是放宽判据** ✗
	//   ★ 实验目的：区分"6 个坏点"到底是
	//       ① **模型在违例下返回了错数据**（⇒ 仿真假象，仿真回答不了这个问题，只能上板）
	//       ② **真实的并发数据完整性问题**（⇒ 按修正后的方案做抑制）
	//   ★ 只影响仿真（本 `ifdef` 分支 ✓）、**不影响综合** ✓；实验做完按结论决定是否保留。
	defparam sdram.tRCD = 18.0;
	defparam sdram.tRP  = 18.0;
	IS42s32200 sdram(
		.Dq     (SDR_DQ),
		.Addr   (SDR_ADDR[10:0]),
		.Ba     (SDR_BA),
		.Clk    (SDRAM_CLK),
		.Cke    (SDR_CKE),
		.Cs_n   (1'b0),
		.Ras_n  (SDR_RAS),
		.Cas_n  (SDR_CAS),
		.We_n   (SDR_WE),
		.Dqm    (SDR_DM)
		);
`else
	EG_PHY_SDRAM_2M_32 sdram(
		.clk(SDRAM_CLK),
		.ras_n(SDR_RAS),
		.cas_n(SDR_CAS),
		.we_n(SDR_WE),
		.addr(SDR_ADDR[10:0]),
		.ba(SDR_BA),
		.dq(SDR_DQ),
		.cs_n(1'b0),
		.dm0(SDR_DM[0]),
		.dm1(SDR_DM[1]),
		.dm2(SDR_DM[2]),
		.dm3(SDR_DM[3]),
		.cke(1'b1)
		);
`endif

endmodule 
