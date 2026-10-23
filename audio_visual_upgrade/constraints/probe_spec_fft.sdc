# probe_spec_fft.sdc —— `prj/td_build/probe_spec_fft.v` 的单元探针约束 ✓
#
# ★ 时钟口径（**先前写错过一次，这里改对并留证** ✓）：
#   本探针第一版把 `clk` 约束成 **150MHz（6.666ns）** ✗ —— 那是我**自己猜的** ✗，不是设计里的口径。
#   真机证据（`rtl/top/skeleton_core.v`）：
#     · `:1154` `audio_sample_tick #(.CLK_HZ(25000000))` ⇒ **48kHz 音频时基在 `clk_pix` = 25MHz** ✓
#     · `:1572` `samp_stb_sdr = sst_sync[2]^sst_sync[1]` ⇒ 48kHz 节拍**跨到 150MHz**只是给播放计数用 ✓
#     · 频谱要"**音量前**同一份样本"（design `:680` ✓）⇒ 它跟音频样本走 = **`clk_pix` 域** ✓
#     · 而柱高最终进**合成器**画在像素域 ✓ —— `clk_pix` **同时**是像素时钟 ⇒ **同域、不用跨时钟** ✓
#   ⇒ 所以正确约束是 **25MHz（周期 40ns）** ✓（见下）
#   ★ 拿 150MHz 去卡这个模块是不对的 ✗：那样量出来的是"**在错误的时钟域下**能不能跑"✗，
#     不是"真机能不能跑" ✓。修正后的数见 `doc/workitem_p3_lean.md` §11.8 ✓。
#
# 说明：本探针**故意不加** I/O 约束（顶层那几个脚是量面积用的假脚 ✓）
#   ⇒ 出脚路径不参与内部 hold/setup 判定 ✓，这正是我们要的"只看模块内部" ✓
#
# `-name` 不能省：漏了 TD 报 USR-8104 且约束**不生效** ✗（照 `skeleton_top.sdc` 的写法 ✓）
create_clock -name clk -period 40 -waveform {0 20} [get_ports {clk}]
