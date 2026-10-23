# skeleton_top.sdc —— P0-2 骨架顶层时序约束（EG4S20BG256，TD 6.2.1）
#
# ★ `-name` 不能省：漏了 TD 会报 USR-8104 且约束**不生效**（只靠派生时钟兜着）。
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# 自动推导两个 PLL 的输出时钟（实例名与 rtl/top/skeleton_top.v 一致）
derive_clocks

# 给关键 PLL 输出命名（路径按本工程实例名写：u_pll_vid / u_pll_sdr，PLL 内部实例都是 pll_inst）
#   视频侧：clkc[0] = 25MHz 像素时钟；clkc[1] = 125MHz 5×串行时钟
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {u_pll_vid/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_pll_vid/pll_inst.clkc[1]}]
#   SDRAM 侧：clkc[1] = 150MHz(Clk)；clkc[2] = 150MHz 相移(Clk_sft)
rename_clock -name {sdr_clk}     -source [get_ports {clk}] -master_clock {clk} [get_pins {u_pll_sdr/pll_inst.clkc[1]}]
rename_clock -name {sdr_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_pll_sdr/pll_inst.clkc[2]}]

# 像素时钟与 5×串行时钟是同源但按"互斥"处理（照 APUG092 参考工程 timing.sdc 的做法）
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ============================================================================
# 5. 真实异步跨域 —— **看过布线后报告才加的**（先看报告，别一上来就开）
#
# 布线后 `route.qor`：54 → 64 条 setup 违例**全部**是 sdr_clk↔sdr_clk_sft（IP 固有，见下）；
# 而 32 条 hold 违例里 **30 条**落在 sdr_clk→clk(29) 与 video_clk→clk(1) ——
# 正是**我自己的跨域同步器**（见 rtl/top/skeleton_core.v）：
#   · sdr_clk(150M) → clk(50M)：快照握手 req_tgl/ack_tgl（多比特"稳定数据 + 握手"）
#   · clk_pix(25M)  → clk(50M)：O_video_locked 单比特 2 级同步
#   · clk(50M)      → sdr_clk  ：req_tgl 单比特 2 级同步
# 这几条本来就该按**异步**处理：STA 去算它们没有意义（正确性由同步器/握手保证）。
#
# ★ 这里用 `set_false_path` 而**不用 `set_clock_groups -asynchronous`**：后者的组语义
#   在"某些时钟未列进任何组"时各实现口径不一，有可能**顺带**把 sdr_clk 与 sdr_clk_sft
#   也变成异步——那正是下面第 6 条绝不允许的事。逐对写 false_path 最精确、不可能误伤。
set_false_path -from [get_clocks {sdr_clk}]   -to [get_clocks {clk}]
set_false_path -from [get_clocks {clk}]       -to [get_clocks {sdr_clk}]
set_false_path -from [get_clocks {video_clk}] -to [get_clocks {clk}]
set_false_path -from [get_clocks {clk}]       -to [get_clocks {video_clk}]

# ============================================================================
# 6. ★★ sdr_clk 与 sdr_clk_sft **绝不能**声明异步 / false_path
#
# 它们是 `sdr_as_ram` + `EG_PHY_SDRAM_2M_32` 内部**紧耦合的一对**（相移时钟）。
# 厂商自己的 APUG011 参考工程（**有可用 .bit**）也把它们当**同步**分析，并带着
# 32+32 条同样的违例出货 —— 布线后 Fmax **71.798 / 46.764MHz**，
# 与我的 **72.077 / 47.326MHz** 几乎相同（同一套无头流程、同器件、同 SDC 风格）。
# ⇒ 把这一对声明成异步 = **掩盖真实路径**，属于自欺，不做。
#    （对照数据与出处见 HANDOVER.md 的"时序对照"表。）
# ============================================================================
