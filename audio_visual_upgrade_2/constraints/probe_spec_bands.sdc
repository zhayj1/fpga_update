# probe_spec_bands.sdc —— `prj/td_build/probe_spec_bands.v` 的单元探针约束 ✓
#
# 与 `probe_spec_fft.sdc` **同一口径**（同一个时钟域 ✓）：`clk` = **`clk_pix` = 25MHz（周期 40ns）** ✓
#   · 真机证据与"先前把 150MHz 当口径"的教训都写在 `probe_spec_fft.sdc` 与工单 §11.8 ✓
#   · `spec_bands` 与 `spec_fft`、像素/合成器**同域** ⇒ 全链无 CDC ✓
#
# 说明：本探针**故意不加** I/O 约束（顶层那几个脚是量面积用的假脚 ✓）
#   ⇒ 出脚路径不参与内部 hold/setup 判定 ✓，只看模块内部 ✓
#
# `-name` 不能省：漏了 TD 报 USR-8104 且约束**不生效** ✗（照 `skeleton_top.sdc` 的写法 ✓）
create_clock -name clk -period 40 -waveform {0 20} [get_ports {clk}]
